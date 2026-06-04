//
//  LaTeXParser.swift
//  Typetex
//

import Foundation
import SwiftUI

// MARK: - Outline item

struct OutlineItem: Identifiable {
    let id = UUID()
    let title: String
    let level: Level
    let lineNumber: Int

    enum Level: Int, Comparable {
        case chapter = 0, section, subsection, subsubsection, paragraph

        static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }

        var indentWidth: CGFloat { CGFloat(rawValue) * 14 }

        var systemImage: String {
            switch self {
            case .chapter:       return "book.closed.fill"
            case .section:       return "1.circle.fill"
            case .subsection:    return "2.circle"
            case .subsubsection: return "3.circle"
            case .paragraph:     return "text.alignleft"
            }
        }
    }
}

// MARK: - TODO item

struct TodoItem: Identifiable {
    let id = UUID()
    let text: String
    let lineNumber: Int
}

// MARK: - Compile message

struct CompileMessage: Identifiable {
    let id = UUID()
    let message: String
    let lineNumber: Int?
    let severity: Severity
    let context: String?

    enum Severity {
        case error, warning, info

        var systemImage: String {
            switch self {
            case .error:   return "xmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .info:    return "info.circle.fill"
            }
        }
    }
}

// MARK: - AST types

/// Options for list environments (enumitem-style)
struct ListOptions {
    var label: String?         // e.g. "\\alph*", "\\Roman*", "\\faCheck"
    var noitemsep: Bool = false
    var leftmargin: CGFloat?
    var start: Int?            // starting counter for enumerate
    var topsep: CGFloat?

    static let `default` = ListOptions()

    init(label: String? = nil, noitemsep: Bool = false,
         leftmargin: CGFloat? = nil, start: Int? = nil, topsep: CGFloat? = nil) {
        self.label = label; self.noitemsep = noitemsep
        self.leftmargin = leftmargin; self.start = start; self.topsep = topsep
    }

    init(parsing optStr: String) {
        let pairs = optStr.components(separatedBy: ",")
        for pair in pairs {
            let kv = pair.components(separatedBy: "=").map { $0.trimmingCharacters(in: .whitespaces) }
            if kv.count == 2 {
                switch kv[0] {
                case "label":       label = kv[1]
                case "leftmargin":  leftmargin = CGFloat(Double(kv[1]) ?? 0)
                case "start":       start = Int(kv[1])
                case "topsep":      topsep = CGFloat(Double(kv[1]) ?? 0)
                default: break
                }
            } else if kv.count == 1 {
                if kv[0] == "noitemsep" || kv[0] == "nosep" { noitemsep = true }
            }
        }
    }
}

/// Tcolorbox render options
struct TcolorboxOptions {
    var colback: TeXColor = .white
    var colframe: TeXColor = TeXColor(r: 0.3, g: 0.3, b: 0.8, a: 1)
    var coltitle: TeXColor = .white
    var colbacktitle: TeXColor = TeXColor(r: 0.3, g: 0.3, b: 0.8, a: 1)
    var title: String = ""
    var cornerRadius: CGFloat = 2
    var borderWidth: CGFloat = 0.8

    init(parsing optStr: String) {
        let pairs = optStr.components(separatedBy: ",")
        for pair in pairs {
            let kv = pair.components(separatedBy: "=").map { $0.trimmingCharacters(in: .whitespaces) }
            if kv.count >= 2 {
                switch kv[0] {
                case "colback":      colback = TeXColor.parse(kv[1])
                case "colframe":     colframe = TeXColor.parse(kv[1])
                case "coltitle":     coltitle = TeXColor.parse(kv[1])
                case "colbacktitle": colbacktitle = TeXColor.parse(kv[1])
                case "title":        title = kv[1]
                case "arc":
                    let s = kv[1].replacingOccurrences(of: "mm", with: "").replacingOccurrences(of: "pt", with: "")
                    cornerRadius = CGFloat(Double(s) ?? 2)
                default: break
                }
            } else if kv.count == 1 {
                let v = kv[0]
                if v.hasPrefix("title=") { title = String(v.dropFirst(6)) }
            }
        }
    }
}

/// Listings options
struct ListingsOptions {
    var language: String = ""
    var caption: String = ""
    var label: String = ""
    var basicstyle: String = ""
    var numbers: String = "none"
    var frame: String = "none"
    var backgroundcolor: TeXColor?

    init(parsing optStr: String) {
        let pairs = optStr.components(separatedBy: ",")
        for pair in pairs {
            let kv = pair.components(separatedBy: "=").map { $0.trimmingCharacters(in: .whitespaces) }
            if kv.count >= 2 {
                switch kv[0].lowercased() {
                case "language":    language = kv[1]
                case "caption":     caption = kv[1]
                case "label":       label = kv[1]
                case "numbers":     numbers = kv[1]
                case "frame":       frame = kv[1]
                default: break
                }
            }
        }
    }
}

indirect enum TexBlock {
    // Core blocks
    case heading(level: Int, numbered: Bool, inlines: [TexInline])
    case paragraph([TexInline])
    case mathDisplay(String)
    case codeBlock(String)
    case verbatimBlock(code: String, options: ListingsOptions)
    case bulletList(items: [[TexBlock]], options: ListOptions)
    case numberedList(items: [[TexBlock]], options: ListOptions)
    case descriptionList(items: [(label: [TexInline], body: [TexBlock])])
    case blockQuote([TexBlock])
    case thematicBreak
    // Document structure
    case documentMetadata(title: String, authors: [String], date: String?)
    case abstract([TexBlock])
    case titleBlock
    // Rich content
    case table(header: [[TexInline]], rows: [[[TexInline]]], spec: String)
    case tableDetailed(rows: [TableRowData], spec: String, booktabs: Bool)
    case figure(src: String?, caption: [TexInline])
    case figureDetailed(src: String?, options: GraphicxOptions, caption: [TexInline], label: String?)
    // Color & boxes
    case coloredBlock(color: TeXColor, content: [TexBlock])
    case tcolorboxBlock(options: TcolorboxOptions, content: [TexBlock])
    // Spacing
    case vspace(CGFloat)
    case hspace(CGFloat)
    case pageBreak
    case newPage
    // Other
    case comment        // stripped content
}

/// Detailed table row for full grid rendering
struct TableRowData {
    enum RowKind: Equatable { case none, data, hline, toprule, midrule, bottomrule, cmidrule(Int, Int) }
    var cells: [[TexInline]]
    var kind: RowKind
    var cellAlignments: [String]
}

/// graphicx \includegraphics options
struct GraphicxOptions {
    var width: GraphicxDim?
    var height: GraphicxDim?
    var scale: CGFloat?
    var angle: CGFloat?
    var keepAspectRatio: Bool = true

    enum GraphicxDim {
        case points(CGFloat)
        case textwidthFraction(CGFloat)  // e.g. 0.8\textwidth
    }

    init(parsing optStr: String) {
        let pairs = optStr.components(separatedBy: ",")
        for pair in pairs {
            let kv = pair.components(separatedBy: "=").map { $0.trimmingCharacters(in: .whitespaces) }
            guard kv.count == 2 else { continue }
            switch kv[0] {
            case "width":
                width = parseDim(kv[1])
            case "height":
                height = parseDim(kv[1])
            case "scale":
                scale = CGFloat(Double(kv[1]) ?? 1)
            case "angle":
                angle = CGFloat(Double(kv[1]) ?? 0)
            case "keepaspectratio":
                keepAspectRatio = kv[1] != "false"
            default:
                break
            }
        }
    }

    private func parseDim(_ s: String) -> GraphicxDim? {
        if s.hasSuffix("\\textwidth"),
           let frac = Double(s.replacingOccurrences(of: "\\textwidth", with: "").trimmingCharacters(in: .whitespaces)) {
            return .textwidthFraction(CGFloat(frac))
        }
        if s.hasSuffix("\\linewidth"),
           let frac = Double(s.replacingOccurrences(of: "\\linewidth", with: "").trimmingCharacters(in: .whitespaces)) {
            return .textwidthFraction(CGFloat(frac))
        }
        let ptPerCm = 28.3465; let ptPerIn = 72.0
        if s.hasSuffix("cm"), let v = Double(s.dropLast(2)) { return .points(CGFloat(v * ptPerCm)) }
        if s.hasSuffix("in"), let v = Double(s.dropLast(2)) { return .points(CGFloat(v * ptPerIn)) }
        if s.hasSuffix("mm"), let v = Double(s.dropLast(2)) { return .points(CGFloat(v * ptPerCm / 10)) }
        if s.hasSuffix("pt"), let v = Double(s.dropLast(2)) { return .points(CGFloat(v)) }
        if let v = Double(s) { return .points(CGFloat(v)) }
        return nil
    }
}

indirect enum TexInline {
    case text(String)
    case bold([TexInline])
    case italic([TexInline])
    case boldItalic([TexInline])
    case underline([TexInline])
    case strikethrough([TexInline])
    case smallcaps([TexInline])
    case code(String)
    case mathInline(String)
    case lineBreak
    case link(_ label: String, url: String)
    case footnote([TexInline])
    // New rich inlines
    case colored(color: TeXColor, content: [TexInline])
    case coloredBackground(color: TeXColor, content: [TexInline])
    case sized(size: CGFloat, content: [TexInline])
    case ref(label: String)            // \ref{label} — resolved at typeset time
    case eqref(label: String)          // \eqref{label}
    case cite(keys: [String])          // \cite{key1,key2}
    case icon(name: String)            // fontawesome icon
}


// MARK: - Parser

enum LaTeXParser {

    // MARK: - Outline (used by sidebar)

    static func parseOutline(from text: String) -> [OutlineItem] {
        let lines = text.components(separatedBy: "\n")
        var items: [OutlineItem] = []

        let patterns: [(String, OutlineItem.Level)] = [
            (#"\\chapter\*?\{([^}]+)\}"#,        .chapter),
            (#"\\section\*?\{([^}]+)\}"#,         .section),
            (#"\\subsection\*?\{([^}]+)\}"#,      .subsection),
            (#"\\subsubsection\*?\{([^}]+)\}"#,   .subsubsection),
            (#"\\paragraph\*?\{([^}]+)\}"#,       .paragraph),
        ]

        for (idx, line) in lines.enumerated() {
            guard !line.trimmingCharacters(in: .whitespaces).hasPrefix("%") else { continue }
            for (pattern, level) in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern),
                      let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                      match.numberOfRanges > 1,
                      let r = Range(match.range(at: 1), in: line) else { continue }
                items.append(OutlineItem(title: String(line[r]), level: level, lineNumber: idx + 1))
                break
            }
        }
        return items
    }

    // MARK: - TODOs (used by sidebar)

    static func parseTodos(from text: String) -> [TodoItem] {
        let lines = text.components(separatedBy: "\n")
        var todos: [TodoItem] = []
        let pattern = #"%\s*TODO:?\s*(.+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }

        for (idx, line) in lines.enumerated() {
            let ns = line as NSString
            let range = NSRange(location: 0, length: ns.length)
            guard let match = regex.firstMatch(in: line, range: range),
                  match.numberOfRanges > 1,
                  let r = Range(match.range(at: 1), in: line) else { continue }
            todos.append(TodoItem(text: String(line[r]).trimmingCharacters(in: .whitespaces), lineNumber: idx + 1))
        }
        return todos
    }

    // MARK: - Syntax check

    static func syntaxCheck(_ text: String) -> [CompileMessage] {
        var messages: [CompileMessage] = []
        let lines = text.components(separatedBy: "\n")

        var depth = 0
        for (idx, line) in lines.enumerated() {
            guard !line.trimmingCharacters(in: .whitespaces).hasPrefix("%") else { continue }
            for ch in line {
                if ch == "{" { depth += 1 }
                if ch == "}" {
                    depth -= 1
                    if depth < 0 {
                        messages.append(CompileMessage(
                            message: "Unexpected closing brace `}`",
                            lineNumber: idx + 1, severity: .error,
                            context: line.trimmingCharacters(in: .whitespaces)))
                        depth = 0
                    }
                }
            }
        }
        if depth > 0 {
            messages.append(CompileMessage(
                message: "Unmatched opening brace `{` (\(depth) unclosed)",
                lineNumber: nil, severity: .warning, context: nil))
        }

        let beginRx   = try? NSRegularExpression(pattern: #"\\begin\{([^}]+)\}"#)
        let endRx     = try? NSRegularExpression(pattern: #"\\end\{([^}]+)\}"#)
        let fullRange = NSRange(location: 0, length: (text as NSString).length)

        func envCounts(_ regex: NSRegularExpression?) -> [String: Int] {
            var counts = [String: Int]()
            regex?.matches(in: text, range: fullRange).forEach { m in
                if m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: text) {
                    counts[String(text[r]), default: 0] += 1
                }
            }
            return counts
        }

        let begins = envCounts(beginRx)
        let ends   = envCounts(endRx)
        for (env, count) in begins where env != "document" {
            if (ends[env] ?? 0) < count {
                messages.append(CompileMessage(
                    message: "\\begin{\(env)} without matching \\end{\(env)}",
                    lineNumber: nil, severity: .error, context: nil))
            }
        }

        if !text.contains("\\documentclass") {
            messages.append(CompileMessage(
                message: "Missing \\documentclass", lineNumber: nil, severity: .warning, context: nil))
        }
        if !text.contains("\\begin{document}") {
            messages.append(CompileMessage(
                message: "Missing \\begin{document}", lineNumber: nil, severity: .error, context: nil))
        }
        return messages
    }

    // MARK: - Document parsing → AST (with macro expansion)

    static func parseDocument(_ source: String, expander: TeXExpander? = nil) -> [TexBlock] {
        let exp = expander ?? TeXExpander()
        let (expanded, preamble) = exp.expand(source)

        // Wire packages so they can inject macros
        var mutableExp = exp
        PackageRegistry.shared.loadPackages(from: preamble, expander: &mutableExp)

        // Re-expand with package macros
        let (finalExpanded, _) = mutableExp.expand(source)

        // Split preamble / body
        let preambText: String
        let body: String
        if let s = finalExpanded.range(of: "\\begin{document}"),
           let e = finalExpanded.range(of: "\\end{document}") {
            preambText = String(finalExpanded[..<s.lowerBound])
            body = String(finalExpanded[s.upperBound..<e.lowerBound])
        } else {
            preambText = ""
            body = finalExpanded
        }

        var blocks: [TexBlock] = []

        // Metadata from expander preamble
        let title   = preamble.title.isEmpty ? (extractCommand("title",  from: preambText) ?? "") : preamble.title
        let authors = preamble.authors.isEmpty ? [extractCommand("author", from: preambText) ?? ""].filter { !$0.isEmpty } : preamble.authors
        let date    = preamble.date.isEmpty ? extractCommand("date", from: preambText) : preamble.date

        if !title.isEmpty || !authors.isEmpty {
            blocks.append(.documentMetadata(title: title, authors: authors, date: date))
        }

        // Parse body
        let bodyBlocks = parseBlocks(Substring(stripComments(body)))

        // Inject title block only when there is NO explicit \maketitle in the body.
        // If \maketitle is present, parseBlocks() will emit it at the right position.
        if !title.isEmpty && !body.contains("\\maketitle") {
            blocks.append(.titleBlock)
        }

        blocks.append(contentsOf: bodyBlocks)
        return blocks
    }

    static func extractCommand(_ cmd: String, from text: String) -> String? {
        let search = "\\\(cmd){"
        guard let r = text.range(of: search) else { return nil }
        let after = text[r.upperBound...]
        var depth = 1; var result = ""
        for ch in after {
            if ch == "{" { depth += 1; result.append(ch) }
            else if ch == "}" { depth -= 1; if depth == 0 { break } else { result.append(ch) } }
            else { result.append(ch) }
        }
        let stripped = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? nil : stripped
    }

    /// Strip all \label{...} occurrences from math content.
    static func stripMathLabels(_ input: String) -> String {
        var s = input
        while let start = s.range(of: "\\label{", options: .literal) {
            var idx = start.upperBound
            var depth = 1
            while idx < s.endIndex, depth > 0 {
                if s[idx] == "{" { depth += 1 }
                else if s[idx] == "}" { depth -= 1 }
                if depth > 0 { idx = s.index(after: idx) }
            }
            let end = depth == 0 ? s.index(after: idx) : s.endIndex
            s.removeSubrange(start.lowerBound..<end)
        }
        return s
    }

    // MARK: - Private: comment stripping

    private static func stripComments(_ text: String) -> String {
        text.components(separatedBy: "\n").map { line -> String in
            var out = ""
            var escaped = false
            for ch in line {
                if escaped { out.append(ch); escaped = false; continue }
                if ch == "\\" { escaped = true; out.append(ch); continue }
                if ch == "%" { break }
                out.append(ch)
            }
            return out
        }.joined(separator: "\n")
    }

    // MARK: - Private: block parsing

    private static let headingMap: [(String, Int)] = [
        ("\\chapter",       0),
        ("\\section",       1),
        ("\\subsection",    2),
        ("\\subsubsection", 3),
        ("\\paragraph",     4),
    ]

    private static func isBlockStart(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        for (cmd, _) in headingMap {
            if t.hasPrefix(cmd + "{") || t.hasPrefix(cmd + "*{") || t.hasPrefix(cmd + " ") { return true }
        }
        return t.hasPrefix("\\begin{") || t.hasPrefix("\\[") || t.hasPrefix("$$")
            || t.hasPrefix("\\hline") || t.hasPrefix("\\hrule") || t.hasPrefix("\\newpage")
            || t.hasPrefix("\\clearpage") || t.hasPrefix("\\vspace") || t.hasPrefix("\\pagebreak")
    }

    static func parseBlocks(_ input: Substring) -> [TexBlock] {
        var blocks: [TexBlock] = []
        var sc = input

        while !sc.isEmpty {
            sc = sc.drop(while: { $0 == "\n" })
            if sc.isEmpty { break }

            // Display math \[...\]
            if sc.hasPrefix("\\[") {
                let body = sc.dropFirst(2)
                if let r = body.range(of: "\\]") {
                    let raw = String(body[..<r.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    blocks.append(.mathDisplay(LaTeXParser.stripMathLabels(raw)))
                    sc = body[r.upperBound...]
                    continue
                }
            }

            // Display math $$...$$
            if sc.hasPrefix("$$") {
                let body = sc.dropFirst(2)
                if let r = body.range(of: "$$") {
                    let raw = String(body[..<r.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    blocks.append(.mathDisplay(LaTeXParser.stripMathLabels(raw)))
                    sc = body[r.upperBound...]
                    continue
                }
            }

            // Environments
            if sc.hasPrefix("\\begin{") {
                if let (block, rest) = parseEnvBlock(sc) {
                    if let b = block { blocks.append(b) }
                    sc = rest
                    continue
                }
            }

            // Thematic breaks
            if sc.hasPrefix("\\hline") || sc.hasPrefix("\\hrule") {
                blocks.append(.thematicBreak)
                sc = sc.drop(while: { $0 != "\n" })
                continue
            }

            if sc.hasPrefix("\\newpage") || sc.hasPrefix("\\clearpage") {
                blocks.append(.newPage)
                sc = sc.drop(while: { $0 != "\n" })
                continue
            }

            if sc.hasPrefix("\\pagebreak") {
                blocks.append(.pageBreak)
                sc = sc.dropFirst("\\pagebreak".count)
                continue
            }

            // vspace/hspace
            if sc.hasPrefix("\\vspace") || sc.hasPrefix("\\vspace*") {
                let starred = sc.hasPrefix("\\vspace*")
                let cmd = starred ? "\\vspace*" : "\\vspace"
                let rest = sc.dropFirst(cmd.count)
                if let (dimStr, after) = extractBrace(rest) {
                    let pts = parseDimension(dimStr)
                    blocks.append(.vspace(pts))
                    sc = after
                } else {
                    sc = rest
                }
                continue
            }

            if sc.hasPrefix("\\maketitle") {
                blocks.append(.titleBlock)
                sc = sc.dropFirst("\\maketitle".count)
                continue
            }

            // Headings
            var foundHeading = false
            for (cmd, level) in headingMap {
                let star = cmd + "*"
                if sc.hasPrefix(star + "{") || sc.hasPrefix(cmd + "{") ||
                   sc.hasPrefix(star + " ") || sc.hasPrefix(cmd + " ") {
                    let numbered = !(sc.hasPrefix(star + "{") || sc.hasPrefix(star + " "))
                    let skipLen = (sc.hasPrefix(star + "{") || sc.hasPrefix(star + " ")) ? star.count : cmd.count
                    let rest = sc.dropFirst(skipLen)
                    // optional short title [...]
                    var afterOpt = rest
                    if afterOpt.first == "[" {
                        afterOpt = afterOpt.drop(while: { $0 != "]" }).dropFirst()
                    }
                    if let (title, after) = extractBrace(afterOpt) {
                        blocks.append(.heading(level: level, numbered: numbered,
                                               inlines: parseInlines(Substring(title))))
                        sc = after
                        foundHeading = true
                        break
                    }
                }
            }
            if foundHeading { continue }

            // Skip isolated block commands with no visible output
            let skipCmds = [
                "\\tableofcontents", "\\listoffigures", "\\listoftables",
                "\\printbibliography", "\\bibliographystyle", "\\bibliography",
                "\\pagestyle", "\\thispagestyle", "\\setcounter", "\\addtocounter",
                "\\pagenumbering", "\\setlength", "\\addtolength", "\\settowidth",
                "\\columnsep", "\\columnseprule", "\\parindent", "\\parskip",
                "\\baselineskip", "\\linespread", "\\frenchspacing",
                "\\makeatletter", "\\makeatother",
                // Document-metadata commands that may appear in the body (LNCS, beamer, etc.)
                // They are already captured by TeXExpander and should not render as text.
                "\\title", "\\author", "\\authorrunning", "\\institute",
                "\\date", "\\thanks", "\\subtitle", "\\keywords",
                "\\affiliation", "\\email", "\\orcidID",
            ]
            var skipped = false
            for cmd in skipCmds {
                if sc.hasPrefix(cmd) {
                    // Also skip optional [arg] and required {arg}
                    var rest = sc.dropFirst(cmd.count)
                    if rest.first == "[" { rest = rest.drop(while: { $0 != "]" }).dropFirst() }
                    if rest.first == "{" { if let (_, r) = extractBrace(rest) { rest = r } }
                    sc = rest
                    skipped = true
                    break
                }
            }
            if skipped { continue }

            // Paragraph
            let paraText = collectParagraph(&sc)
            if !paraText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let inlines = parseInlines(Substring(paraText))
                if !inlines.isEmpty { blocks.append(.paragraph(inlines)) }
            }
        }
        return blocks
    }

    private static func collectParagraph(_ sc: inout Substring) -> String {
        var lines: [String] = []
        while !sc.isEmpty {
            let lineEnd = sc.firstIndex(of: "\n") ?? sc.endIndex
            let line    = String(sc[..<lineEnd])

            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                sc = lineEnd < sc.endIndex ? sc[sc.index(after: lineEnd)...] : Substring("")
                break
            }
            if isBlockStart(line) { break }

            lines.append(line)
            sc = lineEnd < sc.endIndex ? sc[sc.index(after: lineEnd)...] : Substring("")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Private: environment parsing

    /// Returns (block?, rest). block=nil means silently consumed (comment, abstract handled elsewhere)
    private static func parseEnvBlock(_ sc: Substring) -> (TexBlock?, Substring)? {
        guard sc.hasPrefix("\\begin{") else { return nil }
        let nameStart = sc.dropFirst("\\begin{".count)
        guard let nameEnd = nameStart.firstIndex(of: "}") else { return nil }
        let name = String(nameStart[..<nameEnd])
        let afterOpen = nameStart[nameStart.index(after: nameEnd)...]

        guard let (body, rest) = findMatchingEnd(afterOpen, name: name) else { return nil }

        // tcolorbox — parse options from opening line
        if name == "tcolorbox" {
            // Options may be in [...] right after \begin{tcolorbox}
            var opts = TcolorboxOptions(parsing: "")
            var innerBody = afterOpen
            if afterOpen.first == "[" {
                let afterBracket = afterOpen.dropFirst()
                var bracketContent = ""
                var d = 1
                var idx = afterBracket.startIndex
                while idx < afterBracket.endIndex {
                    let c = afterBracket[idx]
                    if c == "[" { d += 1 } else if c == "]" { d -= 1; if d == 0 { break } }
                    bracketContent.append(c)
                    idx = afterBracket.index(after: idx)
                }
                opts = TcolorboxOptions(parsing: bracketContent)
                if let restBody = findMatchingEnd(afterBracket[afterBracket.index(after: idx)...], name: name) {
                    let content = parseBlocks(restBody.0)
                    return (.tcolorboxBlock(options: opts, content: content), restBody.1)
                }
            }
            let content = parseBlocks(body)
            return (.tcolorboxBlock(options: opts, content: content), rest)
        }

        let block: TexBlock?
        switch name {
        case "verbatim", "lstlisting", "minted", "Verbatim", "alltt":
            // Extract optional lstlisting options
            var optsStr = ""
            var trueBody = body
            if name == "lstlisting" || name == "minted" {
                let afterBegin = afterOpen
                if afterBegin.first == "[" {
                    let ab = afterBegin.dropFirst()
                    optsStr = String(ab.prefix(while: { $0 != "]" }))
                    if let nb = findMatchingEnd(ab.drop(while: { $0 != "}" }).dropFirst(), name: name) {
                        trueBody = nb.0
                    }
                }
            }
            let opts = ListingsOptions(parsing: optsStr)
            block = .verbatimBlock(code: String(trueBody).trimmingCharacters(in: CharacterSet(charactersIn: "\n")),
                                   options: opts)
        case "lstlisting":
            block = .verbatimBlock(code: String(body).trimmingCharacters(in: CharacterSet(charactersIn: "\n")),
                                   options: ListingsOptions(parsing: ""))
        case "equation", "equation*", "align", "align*", "gather", "gather*",
             "multline", "multline*", "eqnarray", "eqnarray*", "math", "displaymath",
             "flalign", "flalign*", "alignat", "alignat*":
            let mathRaw = String(body).trimmingCharacters(in: .whitespacesAndNewlines)
            block = .mathDisplay(LaTeXParser.stripMathLabels(mathRaw).trimmingCharacters(in: .whitespacesAndNewlines))
        case "itemize":
            let (items, opts) = parseItemsWithOptions(body, defaultLabel: "•")
            block = .bulletList(items: items, options: opts)
        case "enumerate":
            let (items, opts) = parseItemsWithOptions(body, defaultLabel: nil)
            block = .numberedList(items: items, options: opts)
        case "description":
            block = .descriptionList(items: parseDescriptionItems(body))
        case "abstract":
            block = .abstract(parseBlocks(body))
        case "quote", "quotation":
            block = .blockQuote(parseBlocks(body))
        case "figure", "figure*":
            block = parseFigureEnv(body: body)
        case "table", "table*", "wraptable":
            block = parseTableEnv(body: body)
        case "tabular", "tabular*", "tabulary", "tabularx", "longtable":
            block = parseTabularDetailed(body: body, afterOpen: afterOpen, name: name)
        case "center":
            let inner = parseBlocks(body)
            block = inner.isEmpty ? nil : (inner.count == 1 ? inner[0] : .blockQuote(inner))
        case "minipage", "boxminipage", "framed", "shaded", "mdframed":
            let inner = parseBlocks(body)
            block = inner.isEmpty ? nil : (inner.count == 1 ? inner[0] : .blockQuote(inner))
        case "comment":
            block = nil  // silently drop comment environments
        case "multicols", "twocolumn":
            block = .blockQuote(parseBlocks(body))
        case "theorem", "lemma", "corollary", "definition", "proof", "remark",
             "proposition", "example", "exercise", "solution", "notation":
            // Extract optional [title] from start of body
            var envBody = body
            var optTitle: String? = nil
            let bodyTrimmed = envBody.drop(while: { $0.isWhitespace || $0.isNewline })
            if bodyTrimmed.first == "[" {
                var title = ""; var depth = 0
                var idx = bodyTrimmed.index(after: bodyTrimmed.startIndex)
                while idx < bodyTrimmed.endIndex {
                    let c = bodyTrimmed[idx]
                    if c == "[" { depth += 1; title.append(c) }
                    else if c == "]" {
                        if depth == 0 {
                            envBody = bodyTrimmed[bodyTrimmed.index(after: idx)...]
                            break
                        }
                        depth -= 1; title.append(c)
                    } else { title.append(c) }
                    idx = bodyTrimmed.index(after: idx)
                }
                optTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let envNameCapitalized = name.prefix(1).uppercased() + name.dropFirst()
            var headerInlines: [TexInline] = [.bold([.text(envNameCapitalized)])]
            if let t = optTitle, !t.isEmpty {
                headerInlines += [.text(" ("), .italic([.text(t)]), .text(")")]
            }
            headerInlines.append(.text("."))
            let headerPara = TexBlock.paragraph(headerInlines)
            let innerBlocks = parseBlocks(envBody)
            block = .blockQuote([headerPara] + innerBlocks)
        case "IEEEkeywords", "keywords":
            let kw = parseInlines(body)
            block = .paragraph([.bold([.text("Keywords: ")]), .italic(kw)])

        case "teaserfigure":
            // Same as figure — contains \includegraphics + \caption
            block = parseFigureEnv(body: body)

        case "acks", "ACK":
            // Acknowledgments section
            let inner = parseBlocks(body)
            let heading = TexBlock.heading(level: 1, numbered: false,
                                           inlines: [.text("Acknowledgments")])
            block = .blockQuote([heading] + inner)

        case "thebibliography":
            // Parse \bibitem entries into a numbered list
            block = parseBibliographyEnv(body: body)

        case "CCSXML":
            // Machine-readable CCS metadata — silently drop
            block = nil

        case "algorithm", "algorithm2e", "algorithmic", "algorithmicx", "pseudocode":
            // Render as verbatim-ish code block
            let cleaned = String(body).trimmingCharacters(in: .whitespacesAndNewlines)
            block = .verbatimBlock(code: cleaned, options: ListingsOptions(parsing: ""))

        default:
            let inner = parseBlocks(body)
            if inner.isEmpty { return (nil, rest) }
            block = inner.count == 1 ? inner[0] : .blockQuote(inner)
        }
        return (block, rest)
    }

    // MARK: - Bibliography

    /// Parse \begin{thebibliography}{N} … \end{thebibliography}
    /// Each entry: \bibitem[label]{key} <text>
    private static func parseBibliographyEnv(body: Substring) -> TexBlock {
        let src = String(body)
        var entries: [[TexBlock]] = []
        var remaining = src[...]

        while let bibRange = remaining.range(of: "\\bibitem") {
            remaining = remaining[bibRange.upperBound...]
            // Optional [label]
            if remaining.first == "[" {
                remaining = remaining.dropFirst()
                remaining = remaining.drop(while: { $0 != "]" }).dropFirst()
            }
            // {key}
            if let (_, afterKey) = extractBrace(Substring(remaining)) {
                remaining = afterKey
            }
            // Text until next \bibitem or end
            let nextBib = remaining.range(of: "\\bibitem")
            let entryText: Substring
            if let nb = nextBib {
                entryText = remaining[..<nb.lowerBound]
            } else {
                entryText = remaining
                remaining = remaining[remaining.endIndex...]
            }
            let cleaned = String(entryText).trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                entries.append([.paragraph(parseInlines(Substring(cleaned)))])
            }
        }

        if entries.isEmpty { return .comment }
        return .numberedList(items: entries, options: ListOptions(label: nil))
    }

    private static func parseFigureEnv(body: Substring) -> TexBlock {
        let bodyStr = String(body)
        // Look for \includegraphics[opts]{path}
        var src: String? = nil
        var gfxOpts = GraphicxOptions(parsing: "")
        if let igRange = bodyStr.range(of: "\\includegraphics") {
            let afterIG = bodyStr[igRange.upperBound...]
            var optsStr = ""
            var rest2 = afterIG
            if rest2.first == "[" {
                let afterBr = rest2.dropFirst()
                optsStr = String(afterBr.prefix(while: { $0 != "]" }))
                rest2 = afterBr.drop(while: { $0 != "]" }).dropFirst()
                gfxOpts = GraphicxOptions(parsing: optsStr)
            }
            if let (path, _) = extractBrace(Substring(rest2)) { src = path }
        }
        let captionText = extractCommand("caption", from: bodyStr) ?? ""
        let labelText   = extractCommand("label",   from: bodyStr)
        let captionInlines: [TexInline] = captionText.isEmpty ? [] : parseInlines(Substring(captionText))
        return .figureDetailed(src: src, options: gfxOpts, caption: captionInlines, label: labelText)
    }

    private static func parseTableEnv(body: Substring) -> TexBlock {
        let bodyStr = String(body)
        let captionText = extractCommand("caption", from: bodyStr) ?? ""
        let labelText   = extractCommand("label",   from: bodyStr)

        // Find nested tabular
        if let tabularRange = bodyStr.range(of: "\\begin{tabular") {
            let tabBody = Substring(bodyStr[tabularRange.lowerBound...])
            if let (inner, _) = parseEnvBlock(tabBody) {
                let captionInlines: [TexInline] = captionText.isEmpty ? [] : parseInlines(Substring(captionText))
                if let innerBlock = inner {
                    // Wrap in a blockquote so we can add caption
                    return .blockQuote([
                        innerBlock,
                        captionText.isEmpty ? .thematicBreak : .paragraph([.italic([.text("Table: " + captionText)])])
                    ])
                }
            }
        }
        return .blockQuote(parseBlocks(body))
    }

    private static func parseTabularDetailed(body: Substring, afterOpen: Substring, name: String) -> TexBlock {
        // Consume optional size args (tabular*, tabulary, tabularx)
        var scanAfter = afterOpen
        var spec = ""
        if name == "tabular*" || name == "tabulary" || name == "tabularx" {
            if let (_, a2) = extractBrace(scanAfter) { scanAfter = a2 }
        }
        if let (s, _) = extractBrace(scanAfter) { spec = s }

        let bodyStr = String(body)
        let isBooktabs = bodyStr.contains("\\toprule") || bodyStr.contains("\\midrule") || bodyStr.contains("\\bottomrule")

        // Parse rows
        var rows: [TableRowData] = []
        var currentRow: [String] = []
        var pendingRule: TableRowData.RowKind = .none
        var lines = bodyStr.components(separatedBy: "\\\\")
        // Handle \hline between rows
        var allParts: [String] = []
        for line in lines {
            let parts = line.components(separatedBy: "\n")
            allParts.append(contentsOf: parts)
        }

        // Re-parse properly: split by \\ first
        let rowStrings = bodyStr.components(separatedBy: "\\\\")
        for rowStr in rowStrings {
            let trimmed = rowStr.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            // Check for rule markers
            var remaining = trimmed
            var rule: TableRowData.RowKind = .none
            if remaining.hasPrefix("\\toprule") { rule = .toprule; remaining = String(remaining.dropFirst("\\toprule".count)) }
            else if remaining.hasPrefix("\\bottomrule") { rule = .bottomrule; remaining = String(remaining.dropFirst("\\bottomrule".count)) }
            else if remaining.hasPrefix("\\midrule") { rule = .midrule; remaining = String(remaining.dropFirst("\\midrule".count)) }
            else if remaining.hasPrefix("\\hline") { rule = .hline; remaining = String(remaining.dropFirst("\\hline".count)) }
            remaining = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
            if remaining.isEmpty {
                // Just a rule row
                rows.append(TableRowData(cells: [], kind: rule, cellAlignments: []))
                continue
            }
            // Also strip trailing rules
            var trailingRule: TableRowData.RowKind = .none
            if remaining.hasSuffix("\\toprule") { trailingRule = .toprule; remaining = String(remaining.dropLast("\\toprule".count)) }
            else if remaining.hasSuffix("\\bottomrule") { trailingRule = .bottomrule; remaining = String(remaining.dropLast("\\bottomrule".count)) }
            else if remaining.hasSuffix("\\midrule") { trailingRule = .midrule; remaining = String(remaining.dropLast("\\midrule".count)) }
            else if remaining.hasSuffix("\\hline") { trailingRule = .hline; remaining = String(remaining.dropLast("\\hline".count)) }

            // Also handle \hline at start of remaining
            if remaining.hasPrefix("\\toprule") { if rule == .none { rule = .toprule }; remaining = String(remaining.dropFirst("\\toprule".count)) }
            else if remaining.hasPrefix("\\bottomrule") { if rule == .none { rule = .bottomrule }; remaining = String(remaining.dropFirst("\\bottomrule".count)) }
            else if remaining.hasPrefix("\\midrule") { if rule == .none { rule = .midrule }; remaining = String(remaining.dropFirst("\\midrule".count)) }
            else if remaining.hasPrefix("\\hline") { if rule == .none { rule = .hline }; remaining = String(remaining.dropFirst("\\hline".count)) }
            remaining = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
            if remaining.isEmpty {
                rows.append(TableRowData(cells: [], kind: rule, cellAlignments: []))
                if trailingRule != .none { rows.append(TableRowData(cells: [], kind: trailingRule, cellAlignments: [])) }
                continue
            }
            let cells = remaining.components(separatedBy: "&").map { $0.trimmingCharacters(in: .whitespaces) }
            let cellInlines = cells.map { parseInlines(Substring($0)) }
            rows.append(TableRowData(cells: cellInlines, kind: rule, cellAlignments: []))
            if trailingRule != .none { rows.append(TableRowData(cells: [], kind: trailingRule, cellAlignments: [])) }
        }

        return .tableDetailed(rows: rows, spec: spec, booktabs: isBooktabs)
    }

    static func findMatchingEnd(_ input: Substring, name: String) -> (Substring, Substring)? {
        let beginTag = "\\begin{\(name)}"
        let endTag   = "\\end{\(name)}"
        var sc    = input
        var depth = 1

        while !sc.isEmpty {
            if sc.hasPrefix(endTag) {
                depth -= 1
                if depth == 0 {
                    let body = input[input.startIndex..<sc.startIndex]
                    let rest = sc.dropFirst(endTag.count)
                    return (body, rest)
                }
                sc = sc.dropFirst(endTag.count)
            } else if sc.hasPrefix(beginTag) {
                depth += 1
                sc = sc.dropFirst(beginTag.count)
            } else {
                sc = sc.dropFirst()
            }
        }
        return nil
    }

    private static func parseItemsWithOptions(_ content: Substring,
                                               defaultLabel: String?) -> ([[TexBlock]], ListOptions) {
        let str = String(content)
        var opts = ListOptions()
        var bodyStr = str

        // Extract options from \begin{itemize}[...] — already consumed by caller, but sometimes inline
        // Check if content starts with optional arg
        let trimmed = str.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("[") {
            let afterBr = trimmed.dropFirst()
            let optsStr = String(afterBr.prefix(while: { $0 != "]" }))
            opts = ListOptions(parsing: optsStr)
            if let idx = trimmed.firstIndex(of: "]") {
                bodyStr = String(trimmed[trimmed.index(after: idx)...])
            }
        }

        let items = bodyStr.components(separatedBy: "\\item")
            .dropFirst()
            .compactMap { part -> [TexBlock]? in
                var t = part.trimmingCharacters(in: .whitespacesAndNewlines)
                // Strip per-item optional [label]
                if t.hasPrefix("[") { t = String(t.drop(while: { $0 != "]" }).dropFirst()) }
                guard !t.isEmpty else { return nil }
                return parseBlocks(Substring(t))
            }
        return (items, opts)
    }

    private static func parseDescriptionItems(_ content: Substring) -> [(label: [TexInline], body: [TexBlock])] {
        let parts = String(content).components(separatedBy: "\\item")
        return parts.dropFirst().compactMap { part -> (label: [TexInline], body: [TexBlock])? in
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("[") {
                let afterBr = trimmed.dropFirst()
                let labelStr = String(afterBr.prefix(while: { $0 != "]" }))
                let afterLabel = afterBr.drop(while: { $0 != "]" }).dropFirst()
                let label = parseInlines(Substring(labelStr))
                let body  = parseBlocks(Substring(afterLabel.trimmingCharacters(in: .whitespacesAndNewlines)))
                return (label: label, body: body)
            }
            let body = parseBlocks(Substring(trimmed))
            return body.isEmpty ? nil : (label: [], body: body)
        }
    }

    // MARK: - Private: inline parsing

    static func parseInlines(_ input: Substring) -> [TexInline] {
        var result: [TexInline] = []
        var sc  = input
        var buf = ""

        func flush() { if !buf.isEmpty { result.append(.text(buf)); buf = "" } }

        while !sc.isEmpty {
            // Line break \\
            if sc.hasPrefix("\\\\") { flush(); result.append(.lineBreak); sc = sc.dropFirst(2); continue }

            // Escaped specials
            if sc.hasPrefix("\\%") { buf += "%"; sc = sc.dropFirst(2); continue }
            if sc.hasPrefix("\\&") { buf += "&"; sc = sc.dropFirst(2); continue }
            if sc.hasPrefix("\\$") { buf += "$"; sc = sc.dropFirst(2); continue }
            if sc.hasPrefix("\\#") { buf += "#"; sc = sc.dropFirst(2); continue }
            if sc.hasPrefix("\\{") { buf += "{"; sc = sc.dropFirst(2); continue }
            if sc.hasPrefix("\\}") { buf += "}"; sc = sc.dropFirst(2); continue }
            if sc.hasPrefix("\\_") { buf += "_"; sc = sc.dropFirst(2); continue }
            if sc.hasPrefix("\\^") { buf += "^"; sc = sc.dropFirst(2); continue }
            if sc.hasPrefix("\\~") { buf += "~"; sc = sc.dropFirst(2); continue }
            if sc.hasPrefix("\\`") { buf += "`"; sc = sc.dropFirst(2); continue }
            if sc.hasPrefix("\\'") { buf += "'"; sc = sc.dropFirst(2); continue }

            // Em/en dashes
            if sc.hasPrefix("---") { buf += "\u{2014}"; sc = sc.dropFirst(3); continue }
            if sc.hasPrefix("--")  { buf += "\u{2013}"; sc = sc.dropFirst(2); continue }

            // Opening/closing quotes
            if sc.hasPrefix("``") { buf += "\u{201C}"; sc = sc.dropFirst(2); continue }
            if sc.hasPrefix("''") { buf += "\u{201D}"; sc = sc.dropFirst(2); continue }
            if sc.hasPrefix("`")  { buf += "\u{2018}"; sc = sc.dropFirst(1); continue }
            if sc.hasPrefix("'")  { buf += "\u{2019}"; sc = sc.dropFirst(1); continue }

            // Non-breaking space
            if sc.first == "~" { buf += "\u{00A0}"; sc = sc.dropFirst(); continue }

            // Inline math $...$
            if sc.first == "$" && !sc.hasPrefix("$$") {
                let body = sc.dropFirst()
                if let idx = body.firstIndex(of: "$") {
                    flush()
                    result.append(.mathInline(String(body[..<idx])))
                    sc = body[body.index(after: idx)...]
                    continue
                }
            }

            // Commands
            if sc.first == "\\" {
                let nameStart = sc.dropFirst()
                let nameEnd   = nameStart.firstIndex(where: { !$0.isLetter }) ?? nameStart.endIndex
                let cmdName   = String(nameStart[..<nameEnd])
                let afterName = nameStart[nameEnd...]

                switch cmdName {
                case "textbf", "mathbf", "bm":
                    if let (a, r) = extractBrace(afterName) {
                        flush(); result.append(.bold(parseInlines(Substring(a)))); sc = r; continue
                    }
                case "textit", "mathit", "emph", "textsl":
                    if let (a, r) = extractBrace(afterName) {
                        flush(); result.append(.italic(parseInlines(Substring(a)))); sc = r; continue
                    }
                case "textbfit", "textitbf":
                    if let (a, r) = extractBrace(afterName) {
                        flush(); result.append(.boldItalic(parseInlines(Substring(a)))); sc = r; continue
                    }
                case "underline":
                    if let (a, r) = extractBrace(afterName) {
                        flush(); result.append(.underline(parseInlines(Substring(a)))); sc = r; continue
                    }
                case "sout", "st", "cancel", "xcancel":
                    if let (a, r) = extractBrace(afterName) {
                        flush(); result.append(.strikethrough(parseInlines(Substring(a)))); sc = r; continue
                    }
                case "textsc", "textsmallcaps":
                    if let (a, r) = extractBrace(afterName) {
                        flush(); result.append(.smallcaps(parseInlines(Substring(a)))); sc = r; continue
                    }
                case "texttt", "texttt":
                    if let (a, r) = extractBrace(afterName) {
                        flush(); result.append(.code(a)); sc = r; continue
                    }
                case "verb":
                    if let delim = afterName.first {
                        let body = afterName.dropFirst()
                        if let end = body.firstIndex(of: delim) {
                            flush(); result.append(.code(String(body[..<end])))
                            sc = body[body.index(after: end)...]; continue
                        }
                    }
                case "href":
                    if let (url, a2) = extractBrace(afterName), let (lbl, r) = extractBrace(a2) {
                        flush(); result.append(.link(lbl, url: url))
                        sc = r; continue
                    }
                case "url":
                    if let (url, r) = extractBrace(afterName) {
                        flush(); result.append(.link(url, url: url)); sc = r; continue
                    }
                case "footnote":
                    if let (a, r) = extractBrace(afterName) {
                        flush(); result.append(.footnote(parseInlines(Substring(a)))); sc = r; continue
                    }
                case "textcolor", "color":
                    // \textcolor{color_name}{text} or \textcolor[model]{spec}{text}
                    var colorSpec = ""
                    var rest = afterName
                    if rest.first == "[" {
                        // [model] — skip model for now
                        rest = rest.drop(while: { $0 != "]" }).dropFirst()
                    }
                    if let (cname, a2) = extractBrace(rest),
                       let (txt, r) = extractBrace(a2) {
                        flush()
                        let color = TeXColor.resolve(cname)
                        result.append(.colored(color: color, content: parseInlines(Substring(txt))))
                        sc = r; continue
                    }
                case "colorbox":
                    if let (cname, a2) = extractBrace(afterName),
                       let (txt, r) = extractBrace(a2) {
                        flush()
                        let color = TeXColor.resolve(cname)
                        result.append(.coloredBackground(color: color, content: parseInlines(Substring(txt))))
                        sc = r; continue
                    }
                case "fcolorbox":
                    // \fcolorbox{frame}{bg}{text}
                    if let (_, a2) = extractBrace(afterName),
                       let (bgName, a3) = extractBrace(a2),
                       let (txt, r) = extractBrace(a3) {
                        flush()
                        let color = TeXColor.resolve(bgName)
                        result.append(.coloredBackground(color: color, content: parseInlines(Substring(txt))))
                        sc = r; continue
                    }
                case "ref", "pageref":
                    if let (a, r) = extractBrace(afterName) {
                        flush(); result.append(.ref(label: a)); sc = r; continue
                    }
                case "eqref":
                    if let (a, r) = extractBrace(afterName) {
                        flush(); result.append(.eqref(label: a)); sc = r; continue
                    }
                case "cite", "citep", "citet", "citealp", "parencite", "textcite",
                     "autocite", "citealt", "citenum":
                    // skip optional args
                    var rest = afterName
                    if rest.first == "[" { rest = rest.drop(while: { $0 != "]" }).dropFirst() }
                    if rest.first == "[" { rest = rest.drop(while: { $0 != "]" }).dropFirst() }
                    if let (keys, r) = extractBrace(rest) {
                        flush()
                        let keyList = keys.components(separatedBy: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                        result.append(.cite(keys: keyList))
                        sc = r; continue
                    }
                case "label":
                    // Labels are consumed but not rendered inline
                    if let (_, r) = extractBrace(afterName) { sc = r; continue }
                case "mbox", "hbox", "text", "textrm", "textnormal", "textup", "textsf", "textmd":
                    if let (a, r) = extractBrace(afterName) {
                        flush(); result.append(contentsOf: parseInlines(Substring(a))); sc = r; continue
                    }
                case "noindent":
                    flush(); sc = afterName; continue
                case "newline", "par", "break":
                    flush(); result.append(.lineBreak); sc = afterName; continue
                case "LaTeX":
                    buf += "LaTeX"; sc = afterName; continue
                case "TeX":
                    buf += "TeX"; sc = afterName; continue
                case "ldots", "dots", "cdots", "hdots", "vdots", "ddots":
                    buf += "…"; sc = afterName; continue
                case "mdash": buf += "—"; sc = afterName; continue
                case "ndash": buf += "–"; sc = afterName; continue
                case "quad":  buf += "  "; sc = afterName; continue
                case "qquad": buf += "    "; sc = afterName; continue
                case "thinspace", ",": buf += "\u{2009}"; sc = afterName; continue
                case "enspace": buf += "\u{2002}"; sc = afterName; continue
                case "!": sc = afterName; continue  // negative thin space
                case "copyright": buf += "©"; sc = afterName; continue
                case "registered": buf += "®"; sc = afterName; continue
                case "trademark": buf += "™"; sc = afterName; continue
                case "S", "S": buf += "§"; sc = afterName; continue
                case "P": buf += "¶"; sc = afterName; continue
                case "dagger": buf += "†"; sc = afterName; continue
                case "ddagger": buf += "‡"; sc = afterName; continue
                case "bullet": buf += "•"; sc = afterName; continue
                case "textbackslash": buf += "\\"; sc = afterName; continue
                case "textasciitilde": buf += "~"; sc = afterName; continue
                case "textasciicircum": buf += "^"; sc = afterName; continue
                case "texttimes": buf += "×"; sc = afterName; continue
                case "textpm": buf += "±"; sc = afterName; continue
                case "textdegree": buf += "°"; sc = afterName; continue
                case "textmu": buf += "μ"; sc = afterName; continue
                case "today": buf += TeXExpander.todayString(); sc = afterName; continue
                // Size commands
                case "tiny", "scriptsize", "footnotesize", "small", "normalsize",
                     "large", "Large", "LARGE", "huge", "Huge":
                    let sizes: [String: CGFloat] = [
                        "tiny": 5, "scriptsize": 7, "footnotesize": 8, "small": 9,
                        "normalsize": 10, "large": 12, "Large": 14, "LARGE": 17,
                        "huge": 20, "Huge": 25
                    ]
                    let sz = sizes[cmdName] ?? 10
                    if let (a, r) = extractBrace(afterName) {
                        flush(); result.append(.sized(size: sz, content: parseInlines(Substring(a))))
                        sc = r; continue
                    } else {
                        // Declaration form — affects rest of group
                        sc = afterName; continue
                    }
                case "textsuperscript":
                    if let (a, r) = extractBrace(afterName) {
                        flush(); result.append(.mathInline("^{\\text{\(a)}}")); sc = r; continue
                    }
                case "textsubscript":
                    if let (a, r) = extractBrace(afterName) {
                        flush(); result.append(.mathInline("_{\\text{\(a)}}")); sc = r; continue
                    }
                case "":
                    break
                default:
                    // Unknown command: skip optional args silently, keep braced content
                    var rest = afterName
                    if rest.first == "[" { rest = rest.drop(while: { $0 != "]" }).dropFirst() }
                    if rest.first == "{" {
                        if let (content, r) = extractBrace(rest) {
                            // Show content for unknown commands that wrap text
                            let trimContent = content.trimmingCharacters(in: .whitespaces)
                            if !trimContent.isEmpty && !trimContent.hasPrefix("\\") {
                                flush()
                                result.append(contentsOf: parseInlines(Substring(content)))
                            }
                            rest = r
                        }
                    }
                    sc = rest; continue
                }
            }

            buf.append(sc.first!)
            sc = sc.dropFirst()
        }

        flush()
        return result
    }

    // MARK: - Private: brace extraction

    static func extractBrace(_ input: Substring) -> (String, Substring)? {
        var sc = input
        sc = sc.drop(while: { $0 == " " || $0 == "\t" })
        guard sc.first == "{" else { return nil }
        sc = sc.dropFirst()
        var out   = ""
        var depth = 1
        while !sc.isEmpty {
            let ch = sc.first!
            if ch == "\\" {
                let next = sc.dropFirst()
                out.append(ch)
                if let c2 = next.first { out.append(c2); sc = next.dropFirst() } else { sc = next }
                continue
            }
            if ch == "{" { depth += 1; out.append(ch); sc = sc.dropFirst(); continue }
            if ch == "}" {
                depth -= 1
                if depth == 0 { return (out, sc.dropFirst()) }
                out.append(ch); sc = sc.dropFirst(); continue
            }
            out.append(ch); sc = sc.dropFirst()
        }
        return nil
    }

    // MARK: - Private: dimension parsing

    static func parseDimension(_ s: String) -> CGFloat {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        let ptPerCm = 28.3465; let ptPerIn = 72.0
        if trimmed.hasSuffix("cm"), let v = Double(trimmed.dropLast(2)) { return CGFloat(v * ptPerCm) }
        if trimmed.hasSuffix("in"), let v = Double(trimmed.dropLast(2)) { return CGFloat(v * ptPerIn) }
        if trimmed.hasSuffix("mm"), let v = Double(trimmed.dropLast(2)) { return CGFloat(v * ptPerCm / 10) }
        if trimmed.hasSuffix("pt"), let v = Double(trimmed.dropLast(2)) { return CGFloat(v) }
        if trimmed.hasSuffix("em"), let v = Double(trimmed.dropLast(2)) { return CGFloat(v * 10) }
        if trimmed.hasSuffix("ex"), let v = Double(trimmed.dropLast(2)) { return CGFloat(v * 6) }
        if let v = Double(trimmed) { return CGFloat(v) }
        return 0
    }

}
