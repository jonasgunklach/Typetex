//  TeXTypesetter.swift — Converts [TexBlock] AST to TypesetDocument (pages + frames)
import Foundation
import CoreText
import CoreGraphics
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// Import parser types (same module)
// TexBlock, TexInline defined in LaTeXParser.swift

final class TeXTypesetter {

    // MARK: - Configuration

    var geometry: DocumentGeometry = .article
    var fonts:    TeXFontConfig    = .palatino

    private var counters = TeXCounters()
    private var pendingTitle:    String?
    private var pendingAuthors:  [String] = []
    private var pendingAbstract: String?

    // MARK: - Main typeset entry point

    func typeset(_ blocks: [TexBlock]) -> TypesetDocument {
        counters = TeXCounters()
        pendingTitle    = nil
        pendingAuthors  = []
        pendingAbstract = nil

        // Pre-scan for document class / preamble metadata
        scanPreamble(blocks)

        var pages:         [TypesetPage] = [TypesetPage(pageNumber: 1)]
        var columnIndex:   Int     = 0  // 0 = left, 1 = right
        var cursorY:       CGFloat = geometry.marginTop  // top-of-content y (from paper top)

        // Column rect in normal coordinates (y from top)
        func colRect(forColumn col: Int) -> CGRect {
            geometry.columnRect(index: col)
        }

        // Accumulated attributed string being built for current paragraph stream
        var pendingAttrParts = [NSAttributedString]()
        var pendingHeight: CGFloat = 0

        func flushPending() {
            guard !pendingAttrParts.isEmpty else { return }
            let combined = NSMutableAttributedString()
            for p in pendingAttrParts { combined.append(p) }
            pendingAttrParts = []
            let w = geometry.columnWidth
            let h = measureAttrStringHeight(combined, width: w)
            appendTextBlock(combined,
                            pages: &pages,
                            col: &columnIndex,
                            cursorY: &cursorY,
                            geometry: geometry)
            pendingHeight = 0
        }

        for block in blocks {
            switch block {

            case .documentMetadata(let title, let authors, let date):
                pendingTitle   = title
                pendingAuthors = authors
                // date unused for now

            case .abstract(let innerBlocks):
                flushPending()
                let text = extractPlainText(innerBlocks)
                pendingAbstract = text

            case .titleBlock:
                // Emit title + authors + abstract
                flushPending()
                if let title = pendingTitle {
                    emitTitleBlock(title: title, authors: pendingAuthors,
                                   abstract: pendingAbstract,
                                   pages: &pages, col: &columnIndex,
                                   cursorY: &cursorY, geometry: geometry, fonts: fonts)
                }

            case .heading(let level, let numbered, let inlines):
                flushPending()
                let numStr: String
                switch level {
                case 1: numStr = numbered ? counters.incrementSection() + "\u{2002}" : ""
                case 2: numStr = numbered ? counters.incrementSubsection() + "\u{2002}" : ""
                case 3: numStr = numbered ? counters.incrementSubsubsection() + "\u{2002}" : ""
                default: numStr = ""
                }
                let headingText = numStr + inlinesToPlain(inlines)
                let attrStr = makeHeadingAttrStr(headingText, level: level, fonts: fonts)
                let spaceAbove: CGFloat = level == 1 ? fonts.bodySize * 1.0 : fonts.bodySize * 0.6
                addVerticalSpace(spaceAbove, pages: &pages, col: &columnIndex, cursorY: &cursorY, geometry: geometry)
                appendTextBlock(attrStr, pages: &pages, col: &columnIndex, cursorY: &cursorY, geometry: geometry)
                let spaceBelow = fonts.bodySize * 0.25
                addVerticalSpace(spaceBelow, pages: &pages, col: &columnIndex, cursorY: &cursorY, geometry: geometry)

            case .paragraph(let inlines):
                let attrStr = makeParaAttrStr(inlines, fonts: fonts)
                pendingAttrParts.append(attrStr)
                let sep = NSAttributedString(string: "\n\n", attributes: parasepAttrs(fonts))
                pendingAttrParts.append(sep)

            case .mathDisplay(let src):
                flushPending()
                let mathNode = MathParser.parse(src)
                let boxSize  = MathRenderer.shared.size(of: mathNode, style: .display, baseFontSize: fonts.bodySize * 1.1)
                let colW     = geometry.columnWidth
                let mathH    = boxSize.totalHeight + fonts.bodySize * 0.8

                if !fitsInColumn(height: mathH, cursorY: cursorY, geometry: geometry) {
                    advanceColumn(pages: &pages, col: &columnIndex, cursorY: &cursorY, geometry: geometry)
                }

                let mathX = geometry.columnRect(index: columnIndex).minX + (colW - boxSize.width) / 2
                let mathRect = CGRect(x: mathX,
                                      y: cursorY + fonts.bodySize * 0.3,
                                      width: boxSize.width,
                                      height: boxSize.totalHeight)
                pages[pages.count - 1].blocks.append(.mathDisplay(mathNode, mathRect))
                cursorY += mathH

            case .codeBlock(let src):
                flushPending()
                let attrStr = makeCodeAttrStr(src, fonts: fonts)
                let spaceAbove = fonts.bodySize * 0.4
                addVerticalSpace(spaceAbove, pages: &pages, col: &columnIndex, cursorY: &cursorY, geometry: geometry)
                appendTextBlock(attrStr, pages: &pages, col: &columnIndex, cursorY: &cursorY, geometry: geometry)
                let spaceBelow = fonts.bodySize * 0.4
                addVerticalSpace(spaceBelow, pages: &pages, col: &columnIndex, cursorY: &cursorY, geometry: geometry)

            case .bulletList(let items):
                flushPending()
                for item in items {
                    let inlines = extractInlinesFromBlocks(item)
                    let attrStr = makeListItemAttrStr(inlines, bullet: "•", fonts: fonts)
                    appendTextBlock(attrStr, pages: &pages, col: &columnIndex, cursorY: &cursorY, geometry: geometry)
                }

            case .numberedList(let items):
                flushPending()
                for (i, item) in items.enumerated() {
                    let inlines = extractInlinesFromBlocks(item)
                    let attrStr = makeListItemAttrStr(inlines, bullet: "\(i+1).", fonts: fonts)
                    appendTextBlock(attrStr, pages: &pages, col: &columnIndex, cursorY: &cursorY, geometry: geometry)
                }

            case .blockQuote(let innerBlocks):
                flushPending()
                for inner in innerBlocks {
                    if case .paragraph(let inlines) = inner {
                        let attrStr = makeBlockQuoteAttrStr(inlines, fonts: fonts)
                        appendTextBlock(attrStr, pages: &pages, col: &columnIndex, cursorY: &cursorY, geometry: geometry)
                    }
                }

            case .thematicBreak:
                flushPending()
                let ruleH: CGFloat = 0.5
                if !fitsInColumn(height: ruleH + 4, cursorY: cursorY, geometry: geometry) {
                    advanceColumn(pages: &pages, col: &columnIndex, cursorY: &cursorY, geometry: geometry)
                }
                let colR = geometry.columnRect(index: columnIndex)
                let ruleRect = CGRect(x: colR.minX, y: cursorY + 2, width: colR.width, height: ruleH)
                pages[pages.count - 1].blocks.append(.rule(ruleRect))
                cursorY += ruleH + 4

            case .table(let header, let rows, _):
                flushPending()
                let attrStr = makeTableAttrStr(header: header, rows: rows, fonts: fonts,
                                               width: geometry.columnWidth)
                let spaceAbove = fonts.bodySize * 0.6
                addVerticalSpace(spaceAbove, pages: &pages, col: &columnIndex, cursorY: &cursorY, geometry: geometry)
                appendTextBlock(attrStr, pages: &pages, col: &columnIndex, cursorY: &cursorY, geometry: geometry)
                let spaceBelow = fonts.bodySize * 0.6
                addVerticalSpace(spaceBelow, pages: &pages, col: &columnIndex, cursorY: &cursorY, geometry: geometry)

            default:
                break
            }
        }

        flushPending()
        return TypesetDocument(pages: pages, geometry: geometry, fonts: fonts)
    }

    // MARK: - Column / page management

    private func fitsInColumn(height: CGFloat, cursorY: CGFloat, geometry: DocumentGeometry) -> Bool {
        cursorY + height <= geometry.paperHeight - geometry.marginBottom
    }

    private func advanceColumn(pages: inout [TypesetPage], col: inout Int,
                                cursorY: inout CGFloat, geometry: DocumentGeometry) {
        if geometry.columnCount > 1 && col == 0 {
            col = 1
            cursorY = geometry.marginTop
        } else {
            col = 0
            cursorY = geometry.marginTop
            pages.append(TypesetPage(pageNumber: pages.count + 1))
        }
    }

    private func addVerticalSpace(_ h: CGFloat, pages: inout [TypesetPage],
                                   col: inout Int, cursorY: inout CGFloat,
                                   geometry: DocumentGeometry) {
        cursorY += h
    }

    // MARK: - Text block emission

    private func appendTextBlock(_ attrStr: NSAttributedString,
                                  pages: inout [TypesetPage],
                                  col: inout Int,
                                  cursorY: inout CGFloat,
                                  geometry: DocumentGeometry) {
        let colW = geometry.columnWidth
        let maxH = geometry.paperHeight - geometry.marginBottom - cursorY
        let totalH = measureAttrStringHeight(attrStr, width: colW)

        // If it doesn't fit at all in current column, advance
        if totalH > maxH + 2 && maxH < geometry.textHeight * 0.3 {
            advanceColumn(pages: &pages, col: &col, cursorY: &cursorY, geometry: geometry)
        }

        // Flow text across columns/pages
        var remaining: NSAttributedString = attrStr
        while !remaining.string.isEmpty {
            let availH = geometry.paperHeight - geometry.marginBottom - cursorY
            guard availH > geometry.bodyFontSize * 2 else {
                advanceColumn(pages: &pages, col: &col, cursorY: &cursorY, geometry: geometry)
                continue
            }

            let colRect = geometry.columnRect(index: col)
            // Adjust rect for current cursor
            let textRect = CGRect(x: colRect.minX,
                                  y: cursorY,
                                  width: colRect.width,
                                  height: min(availH, measureAttrStringHeight(remaining, width: colRect.width)))

            let path = CGPath(rect: toFlippedRect(textRect, paperH: geometry.paperHeight), transform: nil)
            let fs   = CTFramesetterCreateWithAttributedString(remaining as CFAttributedString)
            let frame = CTFramesetterCreateFrame(fs, CFRangeMake(0, 0), path, nil)

            // How much text was consumed
            let visRange = CTFrameGetVisibleStringRange(frame)
            let consumed = visRange.length

            pages[pages.count - 1].blocks.append(.ctFrame(frame, textRect))

            let actualH = measureAttrStringHeight(
                remaining.attributedSubstring(from: NSRange(location: 0, length: consumed)),
                width: colRect.width)
            cursorY += actualH

            if consumed >= remaining.length {
                break
            }
            remaining = remaining.attributedSubstring(
                from: NSRange(location: consumed, length: remaining.length - consumed))
            advanceColumn(pages: &pages, col: &col, cursorY: &cursorY, geometry: geometry)
        }
    }

    // Convert a rect from "y from top" to CoreText's "y from bottom" coordinate system
    private func toFlippedRect(_ rect: CGRect, paperH: CGFloat) -> CGRect {
        CGRect(x: rect.minX,
               y: paperH - rect.maxY,
               width: rect.width,
               height: rect.height)
    }

    // MARK: - Title block

    private func emitTitleBlock(title: String, authors: [String], abstract: String?,
                                 pages: inout [TypesetPage], col: inout Int,
                                 cursorY: inout CGFloat,
                                 geometry: DocumentGeometry, fonts: TeXFontConfig) {
        let titleAttr = makeTitleAttrStr(title, fonts: fonts)
        let authorAttr = makeAuthorAttrStr(authors.joined(separator: "  ·  "), fonts: fonts)

        let colW = geometry.columnCount == 1 ? geometry.textWidth : geometry.textWidth  // full width for title
        let titleH = measureAttrStringHeight(titleAttr, width: colW)
        let authorH = measureAttrStringHeight(authorAttr, width: colW)

        // Save column, use full width for title area
        let savedCol = col
        col = 0

        let titleBlock = TypesetTitleBlock(
            title: title,
            authors: authors,
            abstract: abstract,
            rect: CGRect(x: geometry.marginLeft, y: cursorY,
                         width: geometry.textWidth, height: titleH + authorH + fonts.bodySize * 2))
        pages[pages.count - 1].blocks.append(.titleBlock(titleBlock))
        cursorY += titleH + authorH + fonts.bodySize * 2

        if let abs = abstract, !abs.isEmpty {
            let absAttr = makeAbstractAttrStr(abs, fonts: fonts)
            let absW = geometry.columnCount == 1 ? geometry.textWidth : geometry.textWidth
            let absH = measureAttrStringHeight(absAttr, width: absW)
            let absRect = CGRect(x: geometry.marginLeft + 20, y: cursorY,
                                 width: geometry.textWidth - 40, height: absH + fonts.bodySize)
            let path = CGPath(rect: toFlippedRect(absRect, paperH: geometry.paperHeight), transform: nil)
            let fs    = CTFramesetterCreateWithAttributedString(absAttr as CFAttributedString)
            let frame = CTFramesetterCreateFrame(fs, CFRangeMake(0, 0), path, nil)
            pages[pages.count - 1].blocks.append(.ctFrame(frame, absRect))
            cursorY += absH + fonts.bodySize * 1.5
        }

        col = savedCol
    }

    // MARK: - Measurement

    private func measureAttrStringHeight(_ attrStr: NSAttributedString, width: CGFloat) -> CGFloat {
        guard !attrStr.string.isEmpty else { return 0 }
        let fs = CTFramesetterCreateWithAttributedString(attrStr as CFAttributedString)
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            fs, CFRangeMake(0, 0), nil,
            CGSize(width: width, height: CGFloat.greatestFiniteMagnitude), nil)
        return ceil(size.height) + 1
    }

    // MARK: - Attributed string builders

    private func makeHeadingAttrStr(_ text: String, level: Int, fonts: TeXFontConfig) -> NSAttributedString {
        let sizes = fonts.headingSizes
        let sz = level <= sizes.count ? sizes[level - 1] : fonts.bodySize
        let isBold = level <= 3
        let faceName = isBold ? fonts.boldFace : fonts.bodyFace
        let font = CTFontCreateWithName(faceName as CFString, sz, nil)
        let para = NSMutableParagraphStyle()
        para.alignment = level == 1 ? .left : .left
        para.lineSpacing = sz * 0.1
        para.paragraphSpacingBefore = sz * 0.4
        return NSAttributedString(string: text, attributes: [
            kCTFontAttributeName as NSAttributedString.Key: font,
            NSAttributedString.Key.paragraphStyle: para,
            kCTForegroundColorFromContextAttributeName as NSAttributedString.Key: true
        ])
    }

    private func makeParaAttrStr(_ inlines: [TexInline], fonts: TeXFontConfig) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let bodyFont = CTFontCreateWithName(fonts.bodyFace as CFString, fonts.bodySize, nil)
        let boldFont = CTFontCreateWithName(fonts.boldFace as CFString, fonts.bodySize, nil)
        let itFont   = CTFontCreateWithName(fonts.italicFace as CFString, fonts.bodySize, nil)
        let ttFont   = CTFontCreateWithName(fonts.monoFace as CFString, fonts.bodySize * 0.9, nil)
        let mathFont = CTFontCreateWithName(fonts.mathFace as CFString, fonts.bodySize, nil)
        let para     = justifiedParagraphStyle(lineHeight: fonts.bodySize * 1.3)

        func append(_ s: String, font f: CTFont) {
            result.append(NSAttributedString(string: s, attributes: [
                kCTFontAttributeName as NSAttributedString.Key: f,
                NSAttributedString.Key.paragraphStyle: para,
                kCTForegroundColorFromContextAttributeName as NSAttributedString.Key: true
            ]))
        }

        for inline in inlines {
            switch inline {
            case .text(let s):     append(s, font: bodyFont)
            case .bold(let inner): append(inlinesToPlain(inner), font: boldFont)
            case .italic(let inner): append(inlinesToPlain(inner), font: itFont)
            case .code(let s):     append(s, font: ttFont)
            case .mathInline(let s):
                append(mathInlineUnicode(s), font: mathFont)
            case .lineBreak:       append("\n", font: bodyFont)
            case .link(let text, _): append(text, font: bodyFont)
            case .footnote(let s): append("[\(s)]", font: ttFont)
            default: append(inlineToPlain(inline), font: bodyFont)
            }
        }
        return result
    }

    private func makeCodeAttrStr(_ src: String, fonts: TeXFontConfig) -> NSAttributedString {
        let ttFont = CTFontCreateWithName(fonts.monoFace as CFString, fonts.bodySize * 0.87, nil)
        let para   = NSMutableParagraphStyle()
        para.alignment = .left
        para.lineSpacing = fonts.bodySize * 0.15
        para.firstLineHeadIndent = 0
        para.headIndent = 0
        return NSAttributedString(string: src, attributes: [
            kCTFontAttributeName as NSAttributedString.Key: ttFont,
            NSAttributedString.Key.paragraphStyle: para,
            kCTForegroundColorFromContextAttributeName as NSAttributedString.Key: true
        ])
    }

    private func makeListItemAttrStr(_ item: [TexInline], bullet: String,
                                      fonts: TeXFontConfig) -> NSAttributedString {
        let indent: CGFloat = fonts.bodySize * 1.5
        let bodyFont = CTFontCreateWithName(fonts.bodyFace as CFString, fonts.bodySize, nil)
        let para = NSMutableParagraphStyle()
        para.alignment = .left
        para.firstLineHeadIndent = indent / 2
        para.headIndent = indent
        para.lineSpacing = fonts.bodySize * 0.1

        let result = NSMutableAttributedString()
        result.append(NSAttributedString(string: bullet + "\u{2002}", attributes: [
            kCTFontAttributeName as NSAttributedString.Key: bodyFont,
            NSAttributedString.Key.paragraphStyle: para,
            kCTForegroundColorFromContextAttributeName as NSAttributedString.Key: true
        ]))
        let rest = makeParaAttrStr(item, fonts: fonts)
        result.append(rest)
        return result
    }

    private func makeBlockQuoteAttrStr(_ inlines: [TexInline], fonts: TeXFontConfig) -> NSAttributedString {
        let sz = fonts.bodySize * 0.95
        let itFont = CTFontCreateWithName(fonts.italicFace as CFString, sz, nil)
        let para   = NSMutableParagraphStyle()
        para.alignment = .left
        para.firstLineHeadIndent = fonts.bodySize * 2
        para.headIndent = fonts.bodySize * 2
        para.tailIndent = -fonts.bodySize * 2
        para.lineSpacing = sz * 0.1
        return NSAttributedString(string: inlinesToPlain(inlines), attributes: [
            kCTFontAttributeName as NSAttributedString.Key: itFont,
            NSAttributedString.Key.paragraphStyle: para,
            kCTForegroundColorFromContextAttributeName as NSAttributedString.Key: true
        ])
    }

    private func makeTableAttrStr(header: [[TexInline]], rows: [[[TexInline]]],
                                   fonts: TeXFontConfig, width: CGFloat) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let bodyFont = CTFontCreateWithName(fonts.bodyFace as CFString, fonts.bodySize, nil)
        let boldFont = CTFontCreateWithName(fonts.boldFace as CFString, fonts.bodySize, nil)
        let para = NSMutableParagraphStyle()
        para.alignment = .left

        func addRow(_ cells: [[TexInline]], isHeader: Bool) {
            let font = isHeader ? boldFont : bodyFont
            let line = cells.map { inlinesToPlain($0) }.joined(separator: "\t")
            result.append(NSAttributedString(string: line + "\n", attributes: [
                kCTFontAttributeName as NSAttributedString.Key: font,
                NSAttributedString.Key.paragraphStyle: para,
                kCTForegroundColorFromContextAttributeName as NSAttributedString.Key: true
            ]))
        }

        if !header.isEmpty { addRow(header, isHeader: true) }
        for row in rows { addRow(row, isHeader: false) }
        return result
    }

    private func makeTitleAttrStr(_ title: String, fonts: TeXFontConfig) -> NSAttributedString {
        let sz   = fonts.bodySize * 1.9
        let font = CTFontCreateWithName(fonts.boldFace as CFString, sz, nil)
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineSpacing = sz * 0.1
        return NSAttributedString(string: title, attributes: [
            kCTFontAttributeName as NSAttributedString.Key: font,
            NSAttributedString.Key.paragraphStyle: para,
            kCTForegroundColorFromContextAttributeName as NSAttributedString.Key: true
        ])
    }

    private func makeAuthorAttrStr(_ authors: String, fonts: TeXFontConfig) -> NSAttributedString {
        let sz   = fonts.bodySize * 1.05
        let font = CTFontCreateWithName(fonts.italicFace as CFString, sz, nil)
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        return NSAttributedString(string: authors, attributes: [
            kCTFontAttributeName as NSAttributedString.Key: font,
            NSAttributedString.Key.paragraphStyle: para,
            kCTForegroundColorFromContextAttributeName as NSAttributedString.Key: true
        ])
    }

    private func makeAbstractAttrStr(_ text: String, fonts: TeXFontConfig) -> NSAttributedString {
        let sz   = fonts.bodySize * 0.9
        let font = CTFontCreateWithName(fonts.bodyFace as CFString, sz, nil)
        let para = justifiedParagraphStyle(lineHeight: sz * 1.3)
        return NSAttributedString(string: text, attributes: [
            kCTFontAttributeName as NSAttributedString.Key: font,
            NSAttributedString.Key.paragraphStyle: para,
            kCTForegroundColorFromContextAttributeName as NSAttributedString.Key: true
        ])
    }

    private func parasepAttrs(_ fonts: TeXFontConfig) -> [NSAttributedString.Key: Any] {
        let bodyFont = CTFontCreateWithName(fonts.bodyFace as CFString, fonts.bodySize, nil)
        let para = NSMutableParagraphStyle()
        para.paragraphSpacing = fonts.bodySize * 0.4
        return [
            kCTFontAttributeName as NSAttributedString.Key: bodyFont,
            NSAttributedString.Key.paragraphStyle: para
        ]
    }

    private func justifiedParagraphStyle(lineHeight: CGFloat) -> NSMutableParagraphStyle {
        let para = NSMutableParagraphStyle()
        para.alignment = .justified
        para.lineSpacing = 0
        para.minimumLineHeight = lineHeight
        para.maximumLineHeight = lineHeight * 1.05
        para.hyphenationFactor = 0.9
        para.lineBreakMode = .byWordWrapping
        return para
    }

    // MARK: - Inline → plain text

    private func inlinesToPlain(_ inlines: [TexInline]) -> String {
        inlines.map { inlineToPlain($0) }.joined()
    }

    private func inlineToPlain(_ inline: TexInline) -> String {
        switch inline {
        case .text(let s): return s
        case .bold(let inner): return inlinesToPlain(inner)
        case .italic(let inner): return inlinesToPlain(inner)
        case .underline(let inner): return inlinesToPlain(inner)
        case .strikethrough(let inner): return inlinesToPlain(inner)
        case .code(let s): return s
        case .mathInline(let s): return mathInlineUnicode(s)
        case .lineBreak: return "\n"
        case .link(let t, _): return t
        case .footnote(let s): return "[\(s)]"
        default: return ""
        }
    }

    private func mathInlineUnicode(_ src: String) -> String {
        // Quick unicode substitution for inline math display
        let node = MathParser.parse(src)
        return mathNodeToUnicode(node)
    }

    private func mathNodeToUnicode(_ node: MathNode) -> String {
        switch node {
        case .atom(let s, _, _): return s
        case .group(let ns): return ns.map { mathNodeToUnicode($0) }.joined()
        case .text(let s): return s
        case .space: return " "
        case .fraction(let n, let d, _):
            return "(\(mathNodeToUnicode(n)))/(\(mathNodeToUnicode(d)))"
        case .radical(_, let b): return "√(\(mathNodeToUnicode(b)))"
        case .script(let b, let sup, let sub):
            var r = mathNodeToUnicode(b)
            if let s = sup { r += superscriptStr(mathNodeToUnicode(s)) }
            if let s = sub { r += subscriptStr(mathNodeToUnicode(s)) }
            return r
        case .largeOp(let n, _, _, _): return n
        case .fence(let o, let body, let c):
            return o + body.map { mathNodeToUnicode($0) }.joined() + c
        case .matrix: return "[matrix]"
        }
    }

    private func superscriptStr(_ s: String) -> String {
        let sup: [Character: String] = ["0":"⁰","1":"¹","2":"²","3":"³","4":"⁴","5":"⁵",
                                         "6":"⁶","7":"⁷","8":"⁸","9":"⁹",
                                         "n":"ⁿ","i":"ⁱ","+":"⁺","-":"⁻","=":"⁼"]
        return "^{" + s + "}"  // fallback; real superscripts only work for digits
    }

    private func subscriptStr(_ s: String) -> String { "_{\(s)}" }

    // MARK: - Preamble scanner

    private func scanPreamble(_ blocks: [TexBlock]) {
        for block in blocks {
            if case .documentMetadata(let t, let a, _) = block {
                pendingTitle = t; pendingAuthors = a
            }
            if case .abstract(let inner) = block {
                pendingAbstract = extractPlainText(inner)
            }
        }
    }

    private func extractPlainText(_ blocks: [TexBlock]) -> String {
        blocks.compactMap { block -> String? in
            if case .paragraph(let inlines) = block { return inlinesToPlain(inlines) }
            return nil
        }.joined(separator: " ")
    }

    private func extractInlinesFromBlocks(_ blocks: [TexBlock]) -> [TexInline] {
        var result = [TexInline]()
        for block in blocks {
            switch block {
            case .paragraph(let inlines): result.append(contentsOf: inlines)
            default: result.append(.text(extractPlainText([block])))
            }
        }
        return result
    }
}

// MARK: - DocumentGeometry + bodyFontSize helper

extension DocumentGeometry {
    var bodyFontSize: CGFloat {
        // Approximate: smaller column => smaller font
        columnWidth < 250 ? 9 : (columnWidth < 350 ? 10 : 11)
    }
}
