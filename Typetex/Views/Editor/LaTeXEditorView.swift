//
//  LaTeXEditorView.swift
//  Typetex
//
//  VS Code-style LaTeX editor:
//  • Plain NSTextView — no custom NSTextStorage (avoids layout-manager notification bug)
//  • Proper scroll-view setup with real initial frame so content is always visible
//  • Syntax highlighting via textStorage.setAttributes — correct and debuggable
//  • Debounced incremental highlight (120 ms after last keystroke, ±300 chars)
//  • Non-contiguous layout (allowsNonContiguousLayout) for fast large-file load
//  • Line-number gutter with current-line bright highlight
//  • Current-line background tint (VS Code style)
//  • Auto-close { [ ( $   |   ⌘/ comment toggle   |   Tab / ⇧Tab indent
//  • NSTextFinder find/replace   |   Jump to line   |   Snippet insert
//

import SwiftUI

// ─────────────────────────────────────────────────────────────────
// MARK: - Shared constants
// ─────────────────────────────────────────────────────────────────

extension Notification.Name {
    static let insertSnippet = Notification.Name("typetex.insertSnippet")
    static let jumpToLine    = Notification.Name("typetex.jumpToLine")
    static let toggleFind    = Notification.Name("typetex.toggleFind")
}

enum EditorAppearance {
    static let fontFamilyKey  = "editorFontFamily"
    static let fontSizeKey    = "editorFontSize"
    static let lineNumbersKey = "showLineNumbers"
    static let wordWrapKey    = "wordWrap"
    static let themeKey       = "editorTheme"
}

// Pre-compiled regex patterns
private enum HP {
    static let command   = try! NSRegularExpression(pattern: #"\\[a-zA-Z]+\*?"#)
    static let beginEnd  = try! NSRegularExpression(pattern: #"\\(?:begin|end)\{[^}]*\}"#)
    static let doubleDol = try! NSRegularExpression(pattern: #"\$\$[\s\S]*?\$\$"#,
                                                     options: .dotMatchesLineSeparators)
    static let singleDol = try! NSRegularExpression(pattern: #"(?<!\$)\$(?!\$)[^$\n]*\$"#)
    static let comment   = try! NSRegularExpression(pattern: #"%[^\n]*"#)
}

// ─────────────────────────────────────────────────────────────────
// MARK: - macOS
// ─────────────────────────────────────────────────────────────────

#if os(macOS)
import AppKit

// MARK: Theme

struct EditorTheme {
    let background:  NSColor
    let foreground:  NSColor
    let gutter:      NSColor
    let gutterText:  NSColor
    let command:     NSColor
    let beginEnd:    NSColor
    let math:        NSColor
    let comment:     NSColor

    static func resolve(_ name: String) -> EditorTheme {
        switch name {
        case "solarized":
            return EditorTheme(
                background: NSColor(hex: "#002B36"), foreground: NSColor(hex: "#839496"),
                gutter:     NSColor(hex: "#073642"), gutterText: NSColor(hex: "#586E75"),
                command:    NSColor(hex: "#268BD2"), beginEnd:   NSColor(hex: "#6C71C4"),
                math:       NSColor(hex: "#CB4B16"), comment:    NSColor(hex: "#586E75"))
        case "monokai":
            return EditorTheme(
                background: NSColor(hex: "#272822"), foreground: NSColor(hex: "#F8F8F2"),
                gutter:     NSColor(hex: "#1E1F1C"), gutterText: NSColor(hex: "#75715E"),
                command:    NSColor(hex: "#66D9E8"), beginEnd:   NSColor(hex: "#AE81FF"),
                math:       NSColor(hex: "#FD971F"), comment:    NSColor(hex: "#75715E"))
        default:
            return EditorTheme(
                background: .textBackgroundColor,    foreground: .labelColor,
                gutter:     .windowBackgroundColor,  gutterText: .tertiaryLabelColor,
                command:    .systemBlue,             beginEnd:   .systemPurple,
                math:       .systemOrange,           comment:    .secondaryLabelColor)
        }
    }
}

// MARK: Font helper

private func monoFont(_ size: Double, _ family: String) -> NSFont {
    if !family.isEmpty, let f = NSFont(name: family, size: size) { return f }
    return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
}

// MARK: Highlighting

/// Apply LaTeX syntax colours to `storage` in `range`.
/// Always call this from the main thread; `storage` must NOT be inside a
/// beginEditing/endEditing block when this is called.
private func applyHighlight(to storage: NSTextStorage,
                             in range: NSRange,
                             theme: EditorTheme,
                             font: NSFont) {
    guard storage.length > 0 else { return }
    let lo  = max(0, range.location)
    let len = min(range.length, storage.length - lo)
    guard len > 0 else { return }
    let r    = NSRange(location: lo, length: len)
    let text = storage.string   // snapshot before editing

    storage.beginEditing()
    storage.setAttributes([.font: font, .foregroundColor: theme.foreground], range: r)

    let runs: [(NSRegularExpression, NSColor)] = [
        (HP.command,   theme.command),
        (HP.beginEnd,  theme.beginEnd),
        (HP.doubleDol, theme.math),
        (HP.singleDol, theme.math),
        (HP.comment,   theme.comment),
    ]
    for (rx, color) in runs {
        rx.enumerateMatches(in: text, range: r) { m, _, _ in
            guard let m else { return }
            storage.addAttributes([.foregroundColor: color], range: m.range)
        }
    }
    storage.endEditing()
}

// ─────────────────────────────────────────────────────────────────
// MARK: - Line-number ruler
// ─────────────────────────────────────────────────────────────────

final class LineNumberRulerView: NSRulerView {
    weak var textView: NSTextView?
    var theme: EditorTheme = EditorTheme.resolve("default") { didSet { needsDisplay = true } }
    var fontSize: Double = 13 { didSet { needsDisplay = true } }

    // CRITICAL: must match NSTextView's flipped coordinate system (y grows downward)
    override var isFlipped: Bool { true }

    override init(scrollView: NSScrollView?, orientation: NSRulerView.Orientation) {
        super.init(scrollView: scrollView, orientation: orientation)
        ruleThickness = 52
    }
    required init(coder: NSCoder) { fatalError() }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        // Background
        theme.gutter.setFill()
        bounds.fill()

        // Right-edge separator
        NSColor.separatorColor.withAlphaComponent(0.4).setFill()
        NSRect(x: bounds.width - 1, y: rect.minY, width: 1, height: rect.height).fill()

        guard let tv  = textView,
              let lm  = tv.layoutManager,
              let tc  = tv.textContainer,
              lm.numberOfGlyphs > 0 else { return }

        let docVisRect  = scrollView?.documentVisibleRect ?? .zero
        let glyphRange  = lm.glyphRange(forBoundingRect: docVisRect, in: tc)
        guard glyphRange.length > 0 else { return }

        // Count lines before the visible area
        let visCharStart = lm.characterRange(
            forGlyphRange: glyphRange, actualGlyphRange: nil).location
        let nsText = tv.string as NSString
        var firstLine = 1
        for i in 0..<min(visCharStart, nsText.length) {
            if nsText.character(at: i) == 10 { firstLine += 1 }
        }

        let labelFont  = NSFont.monospacedSystemFont(
            ofSize: max(fontSize * 0.82, 10), weight: .regular)
        let cursorLine = currentLine(in: tv)
        let inset      = tv.textContainerInset.height
        let scrollOffY = docVisRect.minY   // document scroll offset (flipped: 0 = top)

        var lineNum = firstLine
        lm.enumerateLineFragments(forGlyphRange: glyphRange) { [weak self]
            _, usedRect, _, glyphRange, _ in
            guard let self else { return }

            let charRange = lm.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            let isLineStart = charRange.location == 0 ||
                (charRange.location > 0 && nsText.character(at: charRange.location - 1) == 10)
            guard isLineStart else { return }

            let isCurrent = lineNum == cursorLine
            let color     = isCurrent ? self.theme.foreground : self.theme.gutterText
            let attrs: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: color]
            let label = "\(lineNum)" as NSString
            let sz    = label.size(withAttributes: attrs)

            // Convert from document coords to ruler coords:
            // - usedRect.minY is in layout manager space (from top of text view content)
            // - add textContainerInset.height to get text view document coords
            // - subtract scroll offset to get ruler-local y (flipped, 0=top)
            let y = usedRect.minY + inset - scrollOffY
            label.draw(at: NSPoint(
                x: self.bounds.width - sz.width - 8,
                y: y + (usedRect.height - sz.height) / 2
            ), withAttributes: attrs)
            lineNum += 1
        }
    }

    private func currentLine(in tv: NSTextView) -> Int {
        let loc  = tv.selectedRange().location
        let text = tv.string as NSString
        var n    = 1
        for i in 0..<min(loc, text.length) {
            if text.character(at: i) == 10 { n += 1 }
        }
        return n
    }

    override func mouseDown(with event: NSEvent) {
        guard let tv = textView, let lm = tv.layoutManager,
              let tc = tv.textContainer else { return }
        let pt      = convert(event.locationInWindow, from: nil)
        let scrollY = scrollView?.documentVisibleRect.minY ?? 0
        // Convert ruler (flipped) y to document coord
        let yInDoc  = pt.y + scrollY - tv.textContainerInset.height
        let gi = lm.glyphIndex(
            for: NSPoint(x: tv.textContainerInset.width + 4, y: yInDoc), in: tc)
        let ci = lm.characterIndexForGlyph(at: gi)
        let lr = (tv.string as NSString).lineRange(for: NSRange(location: ci, length: 0))
        tv.setSelectedRange(lr)
        tv.scrollRangeToVisible(lr)
    }
}

// ─────────────────────────────────────────────────────────────────
// MARK: - LaTeXEditorView
// ─────────────────────────────────────────────────────────────────

struct LaTeXEditorView: NSViewRepresentable {
    @Bindable var document: LaTeXDocument
    @Binding  var sidebarTab: SidebarTab
    @Environment(EditorViewModel.self) private var vm

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        // ── Scroll view ────────────────────────────────────────────
        // Give a real frame so contentSize is non-zero at construction time.
        // SwiftUI will resize this scroll view to fill its column — we must NOT
        // set autoresizingMask on the scroll view itself (SwiftUI controls its frame).
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800))
        scroll.borderType          = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers  = true
        // Do NOT set autoresizingMask here — SwiftUI sets the frame directly.
        // autoresizingMask on the root NSViewRepresentable view is ignored by SwiftUI
        // but can cause the view to over-expand into toolbar/titlebar territory.

        let cs = scroll.contentSize   // valid because frame is set above

        // ── Text view ──────────────────────────────────────────────
        let tv = EditorTextView(frame: NSRect(origin: .zero, size: cs))
        // minSize.height = cs.height: text view fills the scroll view even for short files.
        // Without this it collapses to zero and text is invisible.
        tv.minSize                = NSSize(width: 0, height: cs.height)
        tv.maxSize                = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                           height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable  = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask       = [.width]   // resize with clip view width
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize =
            NSSize(width: cs.width, height: CGFloat.greatestFiniteMagnitude)
        tv.layoutManager?.allowsNonContiguousLayout = true   // lazy: only layout visible glyphs

        tv.delegate                              = context.coordinator
        tv.isEditable                            = true
        tv.isRichText                            = false
        tv.usesFindBar                           = true
        tv.isIncrementalSearchingEnabled         = true
        tv.isAutomaticSpellingCorrectionEnabled  = false
        tv.isAutomaticQuoteSubstitutionEnabled   = false
        tv.isAutomaticDashSubstitutionEnabled    = false
        tv.isAutomaticTextReplacementEnabled     = false
        tv.isContinuousSpellCheckingEnabled      = false
        tv.textContainerInset = NSSize(width: 8, height: 12)

        let theme = EditorTheme.resolve(vm.themeName)
        let font  = monoFont(vm.fontSize, vm.fontFamily)

        // Set ALL three colour properties so text is always visible regardless
        // of which path sets the initial attributes on the text storage.
        tv.backgroundColor     = theme.background
        tv.textColor           = theme.foreground   // default text colour for tv.string=
        tv.insertionPointColor = theme.foreground
        // typingAttributes: used for characters typed AND for tv.string= initial attrs
        tv.typingAttributes    = [.font: font, .foregroundColor: theme.foreground]

        scroll.documentView = tv

        // Load content. typingAttributes is already set so the string gets correct colour.
        tv.string = document.content
        // Apply syntax colours on top.
        if let s = tv.textStorage, s.length > 0 {
            applyHighlight(to: s, in: NSRange(location: 0, length: s.length),
                           theme: theme, font: font)
        }

        // ── Ruler ──────────────────────────────────────────────────
        let ruler = LineNumberRulerView(scrollView: scroll, orientation: .verticalRuler)
        ruler.textView = tv
        ruler.theme    = theme
        ruler.fontSize = vm.fontSize
        scroll.verticalRulerView = ruler
        scroll.hasVerticalRuler  = true
        scroll.rulersVisible     = vm.showLineNumbers

        context.coordinator.textView     = tv
        context.coordinator.currentDocID = document.id
        context.coordinator.lastTheme    = vm.themeName
        context.coordinator.lastSize     = vm.fontSize
        context.coordinator.lastFamily   = vm.fontFamily

        let nc = NotificationCenter.default
        nc.addObserver(context.coordinator, selector: #selector(Coordinator.onSnippet(_:)),
                       name: .insertSnippet, object: nil)
        nc.addObserver(context.coordinator, selector: #selector(Coordinator.onJumpToLine(_:)),
                       name: .jumpToLine, object: nil)
        nc.addObserver(context.coordinator, selector: #selector(Coordinator.onToggleFind(_:)),
                       name: .toggleFind, object: nil)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = scroll.documentView as? EditorTextView else { return }

        let theme = EditorTheme.resolve(vm.themeName)
        let font  = monoFont(vm.fontSize, vm.fontFamily)

        // Keep minSize.height in sync — scroll view grows when window resizes
        let cs = scroll.contentSize
        if cs.height > 0, tv.minSize.height < cs.height {
            tv.minSize = NSSize(width: 0, height: cs.height)
        }

        // Appearance
        tv.backgroundColor     = theme.background
        tv.textColor           = theme.foreground
        tv.insertionPointColor = theme.foreground

        var needsHighlight = false
        if context.coordinator.lastTheme  != vm.themeName  ||
           context.coordinator.lastSize   != vm.fontSize   ||
           context.coordinator.lastFamily != vm.fontFamily {
            context.coordinator.lastTheme  = vm.themeName
            context.coordinator.lastSize   = vm.fontSize
            context.coordinator.lastFamily = vm.fontFamily
            tv.font = font
            tv.typingAttributes = [.font: font, .foregroundColor: theme.foreground]
            needsHighlight = true
        }

        scroll.rulersVisible = vm.showLineNumbers
        if let ruler = scroll.verticalRulerView as? LineNumberRulerView {
            ruler.theme    = theme
            ruler.fontSize = vm.fontSize
        }

        // Document switch
        if context.coordinator.currentDocID != vm.document?.id {
            context.coordinator.currentDocID = vm.document?.id
            tv.typingAttributes = [.font: font, .foregroundColor: theme.foreground]
            tv.textColor        = theme.foreground
            tv.string           = document.content
            if let s = tv.textStorage, s.length > 0 {
                applyHighlight(to: s, in: NSRange(location: 0, length: s.length),
                               theme: theme, font: font)
            }
            tv.setSelectedRange(NSRange(location: 0, length: 0))
            tv.scrollRangeToVisible(NSRange(location: 0, length: 0))
            needsHighlight = false
        }

        if needsHighlight, let s = tv.textStorage, s.length > 0 {
            applyHighlight(to: s, in: NSRange(location: 0, length: s.length),
                           theme: theme, font: font)
        }
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: Coordinator
    // ─────────────────────────────────────────────────────────────

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: LaTeXEditorView
        weak var textView: NSTextView?
        var currentDocID: UUID?
        var lastTheme:  String = "default"
        var lastSize:   Double = 15
        var lastFamily: String = ""
        private var highlightTask: Task<Void, Never>?

        init(_ p: LaTeXEditorView) { self.parent = p }

        func textDidChange(_ note: Notification) {
            guard let tv = note.object as? NSTextView else { return }
            parent.vm.contentChanged(tv.string)
            tv.enclosingScrollView?.verticalRulerView?.needsDisplay = true

            // Debounced incremental highlight — paragraph ± 300 chars, 120 ms delay
            let sel = tv.selectedRange()
            highlightTask?.cancel()
            highlightTask = Task { @MainActor [weak self, weak tv] in
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard !Task.isCancelled, let self, let tv,
                      let storage = tv.textStorage else { return }
                let text  = tv.string as NSString
                let loc   = max(0, sel.location > 0 ? sel.location - 1 : 0)
                let para  = text.paragraphRange(for: NSRange(location: loc, length: 0))
                let lo    = max(0, para.location - 300)
                let hi    = min(text.length, para.location + para.length + 300)
                let theme = EditorTheme.resolve(self.parent.vm.themeName)
                let font  = monoFont(self.parent.vm.fontSize, self.parent.vm.fontFamily)
                applyHighlight(to: storage,
                               in: NSRange(location: lo, length: hi - lo),
                               theme: theme, font: font)
                tv.typingAttributes = [.font: font, .foregroundColor: theme.foreground]
            }
        }

        func textViewDidChangeSelection(_ note: Notification) {
            guard let tv = note.object as? NSTextView else { return }
            tv.enclosingScrollView?.verticalRulerView?.needsDisplay = true
            tv.setNeedsDisplay(tv.visibleRect)
        }

        // Auto-close: { → {}   [ → []   ( → ()   $ → $$
        func textView(_ tv: NSTextView, shouldChangeTextIn range: NSRange,
                      replacementString str: String?) -> Bool {
            guard let str, str.count == 1,
                  tv.selectedRange().length == 0 else { return true }
            let pairs: [String: String] = ["{": "}", "[": "]", "(": ")", "$": "$"]
            guard let close = pairs[str] else { return true }
            tv.insertText(str + close, replacementRange: range)
            tv.setSelectedRange(NSRange(location: range.location + 1, length: 0))
            return false
        }

        @objc func onSnippet(_ note: Notification) {
            guard let code = note.userInfo?["code"] as? String,
                  let tv   = textView else { return }
            tv.insertText(code, replacementRange: tv.selectedRange())
        }

        @objc func onJumpToLine(_ note: Notification) {
            guard let line = note.userInfo?["line"] as? Int,
                  let tv   = textView else { return }
            let text = tv.string as NSString
            var n = 1, idx = 0
            while idx < text.length && n < line {
                let r = text.lineRange(for: NSRange(location: idx, length: 0))
                idx = r.location + r.length; n += 1
            }
            let r = NSRange(location: min(idx, text.length), length: 0)
            tv.setSelectedRange(r)
            tv.scrollRangeToVisible(r)
            tv.window?.makeFirstResponder(tv)
        }

        @objc func onToggleFind(_ note: Notification) {
            guard let tv = textView else { return }
            tv.window?.makeFirstResponder(tv)
            let item = NSMenuItem()
            item.tag = NSTextFinder.Action.showFindInterface.rawValue
            tv.performTextFinderAction(item)
        }
    }
}

// ─────────────────────────────────────────────────────────────────
// MARK: - EditorTextView
// ─────────────────────────────────────────────────────────────────

final class EditorTextView: NSTextView {
    override var acceptsFirstResponder: Bool { true }

    // VS Code-style current-line tint
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let lm  = layoutManager, let tc = textContainer else { return }
        let sel = selectedRange()
        guard sel.length == 0, lm.numberOfGlyphs > 0 else { return }
        let glyphIdx = lm.glyphRange(
            forCharacterRange: NSRange(location: sel.location, length: 0),
            actualCharacterRange: nil).location
        guard glyphIdx < lm.numberOfGlyphs else { return }
        var frag = lm.lineFragmentRect(
            forGlyphAt: glyphIdx, effectiveRange: nil, withoutAdditionalLayout: true)
        guard frag != .zero else { return }
        frag.origin.x  = 0
        frag.origin.y += textContainerInset.height
        frag.size.width = bounds.width
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        NSColor.white.withAlphaComponent(dark ? 0.06 : 0.04).setFill()
        frag.fill()
    }

    // Tab: 4-space indent or indent block
    override func insertTab(_ sender: Any?) {
        let sel  = selectedRange()
        let text = string as NSString
        if sel.length == 0 {
            insertText("    ", replacementRange: sel)
        } else {
            let lr = text.lineRange(for: sel)
            let out = text.substring(with: lr)
                .components(separatedBy: "\n")
                .map { $0.isEmpty ? $0 : "    " + $0 }
                .joined(separator: "\n")
            insertText(out, replacementRange: lr)
            setSelectedRange(NSRange(location: lr.location, length: (out as NSString).length))
        }
    }

    // ⇧Tab: dedent
    override func insertBacktab(_ sender: Any?) {
        let text = string as NSString
        let lr   = text.lineRange(for: selectedRange())
        let out  = text.substring(with: lr)
            .components(separatedBy: "\n")
            .map { line -> String in
                if line.hasPrefix("    ") { return String(line.dropFirst(4)) }
                if line.hasPrefix("\t")   { return String(line.dropFirst()) }
                return line
            }.joined(separator: "\n")
        insertText(out, replacementRange: lr)
        setSelectedRange(NSRange(location: lr.location, length: (out as NSString).length))
    }

    // ⌘/: toggle % comment
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) && event.characters == "/" {
            toggleComment(); return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private func toggleComment() {
        let text  = string as NSString
        let lr    = text.lineRange(for: selectedRange())
        let lines = text.substring(with: lr).components(separatedBy: "\n")
        let allCommented = lines
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .allSatisfy { $0.trimmingCharacters(in: .whitespaces).hasPrefix("%") }
        let out = lines.map { line -> String in
            if allCommented {
                if let r = line.range(of: "%") { var l = line; l.removeSubrange(r); return l }
                return line
            }
            return line.isEmpty ? line : "%" + line
        }.joined(separator: "\n")
        insertText(out, replacementRange: lr)
        setSelectedRange(NSRange(location: lr.location, length: (out as NSString).length))
    }
}
// ─────────────────────────────────────────────────────────────────
// MARK: - iOS
// ─────────────────────────────────────────────────────────────────

#elseif os(iOS)
import UIKit

private func monoFont(_ size: Double, _ family: String) -> UIFont {
    if !family.isEmpty, let f = UIFont(name: family, size: size) { return f }
    return UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
}

struct LaTeXEditorView: UIViewRepresentable {
    @Bindable var document: LaTeXDocument
    @Binding  var sidebarTab: SidebarTab
    @Environment(EditorViewModel.self) private var vm

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate               = context.coordinator
        tv.isScrollEnabled        = true
        tv.isEditable             = true
        tv.autocorrectionType     = .no
        tv.autocapitalizationType = .none
        tv.spellCheckingType      = .no
        tv.smartQuotesType        = .no
        tv.smartDashesType        = .no
        tv.keyboardType           = .asciiCapable
        tv.backgroundColor        = .systemBackground
        tv.textContainerInset     = UIEdgeInsets(top: 16, left: 12, bottom: 80, right: 12)
        tv.inputAccessoryView     = makeAccessoryBar(for: tv)

        let font = monoFont(vm.fontSize, vm.fontFamily)
        tv.font  = font
        tv.textStorage.setAttributes(
            [.font: font, .foregroundColor: UIColor.label],
            range: NSRange(location: 0, length: tv.textStorage.length))
        tv.text = document.content

        context.coordinator.textView     = tv
        context.coordinator.currentDocID = document.id

        for (name, sel) in [
            (Notification.Name.insertSnippet, #selector(Coordinator.onSnippet(_:))),
            (.jumpToLine,                     #selector(Coordinator.onJumpToLine(_:))),
        ] {
            NotificationCenter.default.addObserver(
                context.coordinator, selector: sel, name: name, object: nil)
        }
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        context.coordinator.parent = self
        let font = monoFont(vm.fontSize, vm.fontFamily)
        if tv.font != font { tv.font = font }

        if context.coordinator.currentDocID != vm.document?.id {
            context.coordinator.currentDocID = vm.document?.id
            tv.text = document.content
            tv.selectedRange = NSRange(location: 0, length: 0)
        }
    }

    private func makeAccessoryBar(for tv: UITextView) -> UIView {
        let bar = UIScrollView(frame: CGRect(x: 0, y: 0, width: 300, height: 44))
        bar.showsHorizontalScrollIndicator = false
        bar.backgroundColor = UIColor.systemGroupedBackground

        let stack = UIStackView()
        stack.axis    = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor  .constraint(equalTo: bar.contentLayoutGuide.leadingAnchor,  constant: 8),
            stack.trailingAnchor .constraint(equalTo: bar.contentLayoutGuide.trailingAnchor, constant: -8),
            stack.topAnchor      .constraint(equalTo: bar.topAnchor,    constant: 5),
            stack.bottomAnchor   .constraint(equalTo: bar.bottomAnchor, constant: -5),
            stack.heightAnchor   .constraint(equalToConstant: 34),
        ])
        for (label, insert) in [("\\","\\"), ("{}","{}"), ("[]","[]"), ("$","$"),
                                 ("^","^"), ("_","_"), ("&","&"), ("%","%")] {
            let btn = UIButton(type: .system)
            btn.setTitle(label, for: .normal)
            btn.titleLabel?.font = .monospacedSystemFont(ofSize: 15, weight: .medium)
            btn.backgroundColor  = .secondarySystemGroupedBackground
            btn.layer.cornerRadius = 7
            btn.contentEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
            let str = insert
            btn.addAction(UIAction { [weak tv] _ in
                guard let tv, let r = tv.selectedTextRange else { return }
                tv.replace(r, withText: str)
            }, for: .touchUpInside)
            stack.addArrangedSubview(btn)
        }
        return bar
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: LaTeXEditorView
        weak var textView: UITextView?
        var currentDocID: UUID?
        init(_ p: LaTeXEditorView) { self.parent = p }

        func textViewDidChange(_ tv: UITextView) {
            parent.vm.contentChanged(tv.text)
        }

        @objc func onSnippet(_ note: Notification) {
            guard let code = note.userInfo?["code"] as? String,
                  let tv   = textView,
                  let r    = tv.selectedTextRange else { return }
            tv.replace(r, withText: code)
        }

        @objc func onJumpToLine(_ note: Notification) {
            guard let line = note.userInfo?["line"] as? Int,
                  let tv   = textView else { return }
            let text = tv.text as NSString
            var n = 1, idx = 0
            while idx < text.length && n < line {
                let r = text.lineRange(for: NSRange(location: idx, length: 0))
                idx = r.location + r.length; n += 1
            }
            tv.selectedRange = NSRange(location: min(idx, text.length), length: 0)
            tv.scrollRangeToVisible(tv.selectedRange)
        }
    }
}

#endif

// ─────────────────────────────────────────────────────────────────
// MARK: - NSColor hex helper
// ─────────────────────────────────────────────────────────────────

#if os(macOS)
extension NSColor {
    convenience init(hex: String) {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var rgb: UInt64 = 0
        Scanner(string: h).scanHexInt64(&rgb)
        self.init(red:   CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >>  8) & 0xFF) / 255,
                  blue:  CGFloat( rgb        & 0xFF) / 255,
                  alpha: 1)
    }
}
#endif
