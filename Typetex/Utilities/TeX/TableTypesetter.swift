// TableTypesetter.swift — Converts TableRowData AST into a rendered TableGridData
// with CoreText frames per cell, correct column widths, and rule geometry.
import Foundation
import AppKit
import CoreText
import CoreGraphics

enum TableTypesetter {

    // MARK: - Build TableGridData from parsed rows

    static func build(rows: [TableRowData], spec: String, booktabs: Bool,
                      availableWidth: CGFloat, fonts: TeXFontConfig) -> TableGridData {

        let bodyFont = CTFontCreateWithName(fonts.bodyFace as CFString, fonts.bodySize, nil)
        let boldFont = CTFontCreateWithName(fonts.boldFace as CFString, fonts.bodySize, nil)
        let monoFont = CTFontCreateWithName(fonts.monoFace as CFString, fonts.bodySize * 0.9, nil)

        // 1. Parse column spec (e.g. "lrrc", "@{}lXlr@{}")
        let colSpecs = parseColumnSpec(spec)
        let numCols = colSpecs.isEmpty ? estimateColumnCount(rows) : colSpecs.count

        // 2. Compute column widths
        let dataRows = rows.filter { !$0.cells.isEmpty }
        let colWidths = computeColumnWidths(
            rows: dataRows, numCols: numCols, spec: colSpecs,
            totalWidth: availableWidth, fonts: fonts, bodyFont: bodyFont)

        // 3. Build NSAttributedString cells + measure row heights
        var tableRows: [TableRow] = []
        var rowIdx = 0
        for rowData in rows {
            let ruleAbove = toRowRule(rowData.kind)
            if rowData.cells.isEmpty {
                // Pure rule row
                tableRows.append(TableRow(cells: [], ruleAbove: ruleAbove, ruleBelow: .none, height: 0))
                continue
            }
            var cells: [TableCell] = []
            var maxH: CGFloat = fonts.bodySize * 1.4
            let isHeader = tableRows.allSatisfy { $0.cells.isEmpty }  // first data row = header
            for (ci, cellInlines) in rowData.cells.enumerated() {
                let font: CTFont = isHeader ? boldFont : bodyFont
                let w = ci < colWidths.count ? colWidths[ci] : (colWidths.last ?? 60)
                let cellPad: CGFloat = fonts.bodySize * 0.3
                let effectiveW = max(w - cellPad * 2, 10)

                let alignment: NSTextAlignment
                if ci < colSpecs.count {
                    switch colSpecs[ci] {
                    case "r": alignment = .right
                    case "c": alignment = .center
                    default:  alignment = .left
                    }
                } else { alignment = .left }

                let attrStr = makeAttrStr(cellInlines, font: font, monoFont: monoFont,
                                          boldFont: boldFont,
                                          alignment: alignment, lineHeight: fonts.bodySize * 1.3)
                let cellH = measureHeight(attrStr, width: effectiveW)
                maxH = max(maxH, cellH + cellPad * 2)
                cells.append(TableCell(content: attrStr, alignment: alignment,
                                        colspan: 1, rowspan: 1, background: nil))
            }
            // Pad to numCols
            while cells.count < numCols {
                cells.append(TableCell(content: NSAttributedString(string: ""),
                                        alignment: .left, colspan: 1, rowspan: 1, background: nil))
            }
            tableRows.append(TableRow(cells: cells, ruleAbove: ruleAbove, ruleBelow: .none, height: maxH))
        }

        // 4. Compute total rect size
        let totalH = tableRows.reduce(0) { $0 + $1.height }
            + ruleHeight(tableRows) + fonts.bodySize * 0.5  // extra padding
        let totalW = colWidths.reduce(0, +)

        let borders: TableBorders = booktabs ? .booktabs : .ruled

        // 5. Convert to TableGridData
        var gridCells: [[TableCell]] = []
        for row in tableRows where !row.cells.isEmpty {
            gridCells.append(row.cells)
        }

        return TableGridData(
            rect: CGRect(x: 0, y: 0, width: totalW, height: totalH),
            columnWidths: colWidths,
            rowHeights: tableRows.filter { !$0.cells.isEmpty }.map { $0.height },
            cells: gridCells,
            borders: borders,
            caption: nil,
            isBooktabs: booktabs
        )
    }

    // MARK: - Column spec parser

    private static func parseColumnSpec(_ spec: String) -> [String] {
        var cols: [String] = []
        var i = spec.startIndex
        while i < spec.endIndex {
            let c = spec[i]
            switch c {
            case "l", "r", "c":
                cols.append(String(c))
                i = spec.index(after: i)
            case "p", "m", "b":
                // Skip fixed-width column specification
                let next = spec.index(after: i)
                if next < spec.endIndex && spec[next] == "{" {
                    var depth = 1; var j = spec.index(after: next)
                    while j < spec.endIndex && depth > 0 {
                        if spec[j] == "{" { depth += 1 } else if spec[j] == "}" { depth -= 1 }
                        j = spec.index(after: j)
                    }
                    i = j
                } else { i = spec.index(after: i) }
                cols.append("l")
            case "X":  // tabularx auto-width column
                cols.append("l")
                i = spec.index(after: i)
            case "@":  // column separator spec — skip
                if spec.index(after: i) < spec.endIndex && spec[spec.index(after: i)] == "{" {
                    var depth = 1; var j = spec.index(i, offsetBy: 2)
                    while j < spec.endIndex && depth > 0 {
                        if spec[j] == "{" { depth += 1 } else if spec[j] == "}" { depth -= 1 }
                        j = spec.index(after: j)
                    }
                    i = j
                } else { i = spec.index(after: i) }
            case "|", " ":
                i = spec.index(after: i)  // skip rules and spaces
            default:
                i = spec.index(after: i)
            }
        }
        return cols
    }

    private static func estimateColumnCount(_ rows: [TableRowData]) -> Int {
        rows.compactMap { $0.cells.isEmpty ? nil : $0.cells.count }.max() ?? 1
    }

    // MARK: - Column width calculation

    private static func computeColumnWidths(rows: [TableRowData], numCols: Int,
                                             spec: [String], totalWidth: CGFloat,
                                             fonts: TeXFontConfig, bodyFont: CTFont) -> [CGFloat] {
        guard numCols > 0 else { return [] }
        let cellPad: CGFloat = fonts.bodySize * 0.6

        // Measure natural widths
        var naturalWidths = [CGFloat](repeating: 0, count: numCols)
        for row in rows where !row.cells.isEmpty {
            for (ci, cellInlines) in row.cells.prefix(numCols).enumerated() {
                let text = inlinesToPlain(cellInlines)
                let w = measureWord(text, font: bodyFont) + cellPad * 2
                naturalWidths[ci] = max(naturalWidths[ci], w)
            }
        }

        let minColWidth: CGFloat = 20
        var widths = naturalWidths.map { max($0, minColWidth) }
        let total = widths.reduce(0, +)
        if total > totalWidth {
            // Scale down proportionally
            let scale = totalWidth / total
            widths = widths.map { $0 * scale }
        } else if total < totalWidth * 0.7 {
            // Distribute extra space
            let extra = (totalWidth - total) / CGFloat(numCols)
            widths = widths.map { $0 + extra }
        }
        return widths
    }

    // MARK: - AttributedString builder for a cell

    private static func makeAttrStr(_ inlines: [TexInline], font: CTFont, monoFont: CTFont,
                                    boldFont: CTFont, alignment: NSTextAlignment,
                                    lineHeight: CGFloat) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.alignment = alignment
        para.minimumLineHeight = lineHeight
        para.maximumLineHeight = lineHeight * 1.05
        para.lineBreakMode = .byWordWrapping

        let result = NSMutableAttributedString()
        for inline in inlines {
            switch inline {
            case .text(let s):
                result.append(NSAttributedString(string: s, attributes: [
                    kCTFontAttributeName as NSAttributedString.Key: font,
                    NSAttributedString.Key.paragraphStyle: para,
                    kCTForegroundColorFromContextAttributeName as NSAttributedString.Key: true
                ]))
            case .bold(let inner):
                result.append(NSAttributedString(string: inlinesToPlain(inner), attributes: [
                    kCTFontAttributeName as NSAttributedString.Key: boldFont,
                    NSAttributedString.Key.paragraphStyle: para,
                    kCTForegroundColorFromContextAttributeName as NSAttributedString.Key: true
                ]))
            case .italic(let inner):
                let itFont = CTFontCreateCopyWithSymbolicTraits(font, CTFontGetSize(font), nil,
                    [.traitItalic], [.traitItalic]) ?? font
                result.append(NSAttributedString(string: inlinesToPlain(inner), attributes: [
                    kCTFontAttributeName as NSAttributedString.Key: itFont,
                    NSAttributedString.Key.paragraphStyle: para,
                    kCTForegroundColorFromContextAttributeName as NSAttributedString.Key: true
                ]))
            case .code(let s):
                result.append(NSAttributedString(string: s, attributes: [
                    kCTFontAttributeName as NSAttributedString.Key: monoFont,
                    NSAttributedString.Key.paragraphStyle: para,
                    kCTForegroundColorFromContextAttributeName as NSAttributedString.Key: true
                ]))
            case .mathInline(let src):
                result.append(NSAttributedString(string: mathToUnicode(src), attributes: [
                    kCTFontAttributeName as NSAttributedString.Key: font,
                    NSAttributedString.Key.paragraphStyle: para,
                    kCTForegroundColorFromContextAttributeName as NSAttributedString.Key: true
                ]))
            case .colored(let color, let inner):
                result.append(NSAttributedString(string: inlinesToPlain(inner), attributes: [
                    kCTFontAttributeName as NSAttributedString.Key: font,
                    NSAttributedString.Key.paragraphStyle: para,
                    kCTForegroundColorAttributeName as NSAttributedString.Key: color.cgColor
                ]))
            default:
                result.append(NSAttributedString(string: inlineToPlain(inline), attributes: [
                    kCTFontAttributeName as NSAttributedString.Key: font,
                    NSAttributedString.Key.paragraphStyle: para,
                    kCTForegroundColorFromContextAttributeName as NSAttributedString.Key: true
                ]))
            }
        }
        return result
    }

    // MARK: - Helpers

    private static func toRowRule(_ kind: TableRowData.RowKind) -> RowRule {
        switch kind {
        case .none, .data: return .none
        case .hline:      return .hline
        case .toprule:    return .toprule
        case .midrule:    return .midrule
        case .bottomrule: return .bottomrule
        case .cmidrule(let f, let t): return .cmidrule(from: f, to: t)
        }
    }

    private static func ruleHeight(_ rows: [TableRow]) -> CGFloat {
        rows.reduce(0) { acc, row in
            var h: CGFloat = 0
            switch row.ruleAbove {
            case .toprule, .bottomrule: h += 2.5
            case .midrule, .hline: h += 1.5
            default: break
            }
            return acc + h
        }
    }

    private static func measureHeight(_ attrStr: NSAttributedString, width: CGFloat) -> CGFloat {
        guard !attrStr.string.isEmpty else { return 0 }
        let fs = CTFramesetterCreateWithAttributedString(attrStr as CFAttributedString)
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            fs, CFRangeMake(0, 0), nil,
            CGSize(width: max(width, 1), height: CGFloat.greatestFiniteMagnitude), nil)
        return ceil(size.height) + 1
    }

    private static func measureWord(_ s: String, font: CTFont) -> CGFloat {
        guard !s.isEmpty else { return 0 }
        let attr = NSAttributedString(string: s,
            attributes: [kCTFontAttributeName as NSAttributedString.Key: font])
        let line = CTLineCreateWithAttributedString(attr as CFAttributedString)
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    private static func inlinesToPlain(_ inlines: [TexInline]) -> String {
        inlines.map { inlineToPlain($0) }.joined()
    }

    private static func inlineToPlain(_ inline: TexInline) -> String {
        switch inline {
        case .text(let s): return s
        case .bold(let i), .italic(let i), .underline(let i),
             .strikethrough(let i), .smallcaps(let i), .boldItalic(let i): return inlinesToPlain(i)
        case .colored(_, let i), .coloredBackground(_, let i), .sized(_, let i): return inlinesToPlain(i)
        case .code(let s): return s
        case .mathInline(let s): return mathToUnicode(s)
        case .lineBreak: return "\n"
        case .link(let t, _): return t
        case .footnote(let i): return "[\(inlinesToPlain(i))]"
        case .ref(let l): return "[\(l)]"
        case .eqref(let l): return "(\(l))"
        case .cite(let keys): return "[\(keys.joined(separator: ","))]"
        case .icon(let n): return n
        }
    }

    private static func mathToUnicode(_ s: String) -> String {
        // Quick substitutions for table cells
        var r = s
        let subs: [(String, String)] = [
            ("\\uparrow", "↑"), ("\\downarrow", "↓"), ("\\pm", "±"),
            ("\\times", "×"), ("\\div", "÷"), ("\\leq", "≤"), ("\\geq", "≥"),
            ("\\neq", "≠"), ("\\approx", "≈"), ("\\infty", "∞"),
        ]
        for (from, to) in subs { r = r.replacingOccurrences(of: from, with: to) }
        return r.replacingOccurrences(of: "\\", with: "")
    }
}
