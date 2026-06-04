//  TeXTypes.swift — Shared types for the TeX rendering pipeline
import Foundation
import CoreGraphics
import CoreText
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - TeXColor (model-independent color representation)

struct TeXColor: Hashable {
    let r: CGFloat
    let g: CGFloat
    let b: CGFloat
    let a: CGFloat

    var cgColor: CGColor { CGColor(red: r, green: g, blue: b, alpha: a) }
    #if os(macOS)
    var nsColor: NSColor { NSColor(red: r, green: g, blue: b, alpha: a) }
    #else
    var uiColor: UIColor { UIColor(red: r, green: g, blue: b, alpha: a) }
    #endif

    static let black   = TeXColor(r: 0,    g: 0,    b: 0,    a: 1)
    static let white   = TeXColor(r: 1,    g: 1,    b: 1,    a: 1)
    static let red     = TeXColor(r: 1,    g: 0,    b: 0,    a: 1)
    static let green   = TeXColor(r: 0,    g: 0.6,  b: 0,    a: 1)
    static let blue    = TeXColor(r: 0,    g: 0,    b: 1,    a: 1)
    static let cyan    = TeXColor(r: 0,    g: 1,    b: 1,    a: 1)
    static let magenta = TeXColor(r: 1,    g: 0,    b: 1,    a: 1)
    static let yellow  = TeXColor(r: 1,    g: 1,    b: 0,    a: 1)
    static let orange  = TeXColor(r: 1,    g: 0.5,  b: 0,    a: 1)
    static let violet  = TeXColor(r: 0.5,  g: 0,    b: 0.5,  a: 1)
    static let purple  = TeXColor(r: 0.5,  g: 0,    b: 0.5,  a: 1)
    static let gray    = TeXColor(r: 0.5,  g: 0.5,  b: 0.5,  a: 1)
    static let brown   = TeXColor(r: 0.6,  g: 0.3,  b: 0.1,  a: 1)
    static let darkgray = TeXColor(r: 0.25, g: 0.25, b: 0.25, a: 1)
    static let lightgray = TeXColor(r: 0.75, g: 0.75, b: 0.75, a: 1)
    static let teal    = TeXColor(r: 0,    g: 0.5,  b: 0.5,  a: 1)
    static let lime    = TeXColor(r: 0.75, g: 1,    b: 0,    a: 1)
    static let pink    = TeXColor(r: 1,    g: 0.75, b: 0.8,  a: 1)

    /// Parse a color expression like "red", "blue!40!white", "0.1,0.2,0.8", "FF0000"
    static func parse(_ expr: String, model: String = "named") -> TeXColor {
        let e = expr.trimmingCharacters(in: .whitespaces)

        // hex #RRGGBB or RRGGBB
        let hex = e.hasPrefix("#") ? String(e.dropFirst()) : e
        if hex.count == 6, let rgb = UInt32(hex, radix: 16) {
            let r = CGFloat((rgb >> 16) & 0xFF) / 255
            let g = CGFloat((rgb >> 8)  & 0xFF) / 255
            let b = CGFloat(rgb & 0xFF) / 255
            return TeXColor(r: r, g: g, b: b, a: 1)
        }

        // "red!40!white" — xcolor mixing
        if e.contains("!") {
            return parseXColorMix(e)
        }

        // "0.1,0.2,0.8" — RGB values
        let parts = e.components(separatedBy: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        if parts.count == 3 {
            return TeXColor(r: CGFloat(parts[0]), g: CGFloat(parts[1]), b: CGFloat(parts[2]), a: 1)
        }

        // named color
        return namedColor(e) ?? .black
    }

    private static func parseXColorMix(_ expr: String) -> TeXColor {
        // e.g. "blue!70!black" means 70% blue + 30% black
        // "blue!40" means 40% blue + 60% white (implicit)
        let parts = expr.components(separatedBy: "!")
        guard parts.count >= 2 else { return namedColor(expr) ?? .black }
        let color1 = namedColor(parts[0]) ?? .black
        let pct    = CGFloat(Double(parts[1]) ?? 50) / 100.0
        let color2 = parts.count >= 3 ? (namedColor(parts[2]) ?? .white) : .white
        return TeXColor(
            r: color1.r * pct + color2.r * (1 - pct),
            g: color1.g * pct + color2.g * (1 - pct),
            b: color1.b * pct + color2.b * (1 - pct),
            a: 1)
    }

    private static func namedColor(_ name: String) -> TeXColor? {
        switch name.lowercased() {
        case "black":     return .black
        case "white":     return .white
        case "red":       return .red
        case "green":     return .green
        case "blue":      return .blue
        case "cyan":      return .cyan
        case "magenta":   return .magenta
        case "yellow":    return .yellow
        case "orange":    return .orange
        case "violet":    return .violet
        case "purple":    return .purple
        case "gray", "grey": return .gray
        case "darkgray", "darkgrey": return .darkgray
        case "lightgray", "lightgrey": return .lightgray
        case "brown":     return .brown
        case "teal":      return .teal
        case "lime":      return .lime
        case "pink":      return .pink
        // SVG / CSS colors
        case "navy":      return TeXColor(r: 0,    g: 0,    b: 0.5,  a: 1)
        case "maroon":    return TeXColor(r: 0.5,  g: 0,    b: 0,    a: 1)
        case "olive":     return TeXColor(r: 0.5,  g: 0.5,  b: 0,    a: 1)
        case "aqua":      return TeXColor(r: 0,    g: 1,    b: 1,    a: 1)
        case "fuchsia":   return TeXColor(r: 1,    g: 0,    b: 1,    a: 1)
        case "silver":    return TeXColor(r: 0.75, g: 0.75, b: 0.75, a: 1)
        case "coral":     return TeXColor(r: 1,    g: 0.5,  b: 0.31, a: 1)
        case "salmon":    return TeXColor(r: 0.98, g: 0.5,  b: 0.45, a: 1)
        case "turquoise": return TeXColor(r: 0.25, g: 0.88, b: 0.82, a: 1)
        case "gold":      return TeXColor(r: 1,    g: 0.84, b: 0,    a: 1)
        case "indigo":    return TeXColor(r: 0.29, g: 0,    b: 0.51, a: 1)
        case "crimson":   return TeXColor(r: 0.86, g: 0.08, b: 0.24, a: 1)
        case "forestgreen": return TeXColor(r: 0.13, g: 0.55, b: 0.13, a: 1)
        case "royalblue": return TeXColor(r: 0.25, g: 0.41, b: 0.88, a: 1)
        case "steelblue": return TeXColor(r: 0.27, g: 0.51, b: 0.71, a: 1)
        case "skyblue":   return TeXColor(r: 0.53, g: 0.81, b: 0.98, a: 1)
        case "midnightblue": return TeXColor(r: 0.10, g: 0.10, b: 0.44, a: 1)
        default:          return nil
        }
    }

    // User-defined colors registered by \definecolor
    static var userColors: [String: TeXColor] = [:]

    static func resolve(_ name: String) -> TeXColor {
        if let c = userColors[name.lowercased()] { return c }
        return parse(name)
    }
}

// MARK: - Table grid model

struct TableGridData {
    var rect: CGRect
    var columnWidths: [CGFloat]
    var rowHeights: [CGFloat]
    var cells: [[TableCell]]
    var borders: TableBorders
    var caption: NSAttributedString?
    var isBooktabs: Bool
}

struct TableCell {
    var content: NSAttributedString
    var alignment: NSTextAlignment
    var colspan: Int
    var rowspan: Int
    var background: CGColor?
}

struct TableBorders {
    var outerLineWidth: CGFloat    // \hline or surrounding border
    var innerLineWidth: CGFloat    // inner cell borders
    var topruleWidth: CGFloat      // booktabs \toprule  (1.5pt)
    var midruleWidth: CGFloat      // booktabs \midrule  (0.75pt)
    var bottomruleWidth: CGFloat   // booktabs \bottomrule (1.25pt)
    var hasTopBorder: Bool
    var hasBottomBorder: Bool
    var hasLeftBorder: Bool
    var hasRightBorder: Bool
    var innerHorizontal: Bool
    var innerVertical: Bool

    static let none = TableBorders(
        outerLineWidth: 0, innerLineWidth: 0,
        topruleWidth: 1.5, midruleWidth: 0.75, bottomruleWidth: 1.25,
        hasTopBorder: false, hasBottomBorder: false,
        hasLeftBorder: false, hasRightBorder: false,
        innerHorizontal: false, innerVertical: false)

    static let booktabs = TableBorders(
        outerLineWidth: 0, innerLineWidth: 0,
        topruleWidth: 1.5, midruleWidth: 0.75, bottomruleWidth: 1.25,
        hasTopBorder: false, hasBottomBorder: false,
        hasLeftBorder: false, hasRightBorder: false,
        innerHorizontal: false, innerVertical: false)

    static let ruled = TableBorders(
        outerLineWidth: 0.4, innerLineWidth: 0.4,
        topruleWidth: 1.5, midruleWidth: 0.75, bottomruleWidth: 1.25,
        hasTopBorder: true, hasBottomBorder: true,
        hasLeftBorder: false, hasRightBorder: false,
        innerHorizontal: true, innerVertical: false)
}

// Row separator kind (determines which rule to draw above a row)
enum RowRule {
    case none
    case hline
    case toprule
    case midrule
    case bottomrule
    case cmidrule(from: Int, to: Int)
}

struct TableRow {
    var cells: [TableCell]
    var ruleAbove: RowRule  // rule drawn above this row
    var ruleBelow: RowRule  // rule drawn below this row (used for \bottomrule)
    var height: CGFloat
}

// MARK: - Tcolorbox data

struct TcolorboxData {
    var rect: CGRect
    var title: NSAttributedString?
    var contentBlocks: [TypesetBlock]
    var background: CGColor
    var borderColor: CGColor
    var titleBackground: CGColor
    var borderWidth: CGFloat
    var cornerRadius: CGFloat
}

// MARK: - Image block data

struct ImageBlockData {
    var rect: CGRect
    var cgImage: CGImage?     // nil = image not found / not loaded
    var aspectRatio: CGFloat  // width/height, or 1.0 as fallback
    var caption: NSAttributedString?
}

// MARK: - Footnote data

struct FootnoteData {
    var number: Int
    var content: NSAttributedString
    var rect: CGRect
}

// MARK: - Document geometry

struct DocumentGeometry {
    let paperWidth:   CGFloat
    let paperHeight:  CGFloat
    let marginTop:    CGFloat
    let marginBottom: CGFloat
    let marginLeft:   CGFloat
    let marginRight:  CGFloat
    let columnCount:  Int
    let columnSep:    CGFloat

    var textWidth:  CGFloat { paperWidth  - marginLeft - marginRight }
    var textHeight: CGFloat { paperHeight - marginTop  - marginBottom }

    var columnWidth: CGFloat {
        columnCount == 1
            ? textWidth
            : (textWidth - CGFloat(columnCount - 1) * columnSep) / CGFloat(columnCount)
    }

    /// CGRect of a column on a page, y from TOP of paper
    func columnRect(index: Int) -> CGRect {
        let x = marginLeft + CGFloat(index) * (columnWidth + columnSep)
        return CGRect(x: x, y: marginTop, width: columnWidth, height: textHeight)
    }

    // Named presets
    static let article = DocumentGeometry(
        paperWidth: 612, paperHeight: 792,
        marginTop: 90, marginBottom: 90,
        marginLeft: 80, marginRight: 80,
        columnCount: 1, columnSep: 0)

    static let acmSigConf = DocumentGeometry(
        paperWidth: 612, paperHeight: 792,
        marginTop: 57, marginBottom: 57,
        marginLeft: 54, marginRight: 54,
        columnCount: 2, columnSep: 17)

    static let acmTwoColumnLetter = DocumentGeometry(
        paperWidth: 612, paperHeight: 792,
        marginTop: 72, marginBottom: 72,
        marginLeft: 54, marginRight: 54,
        columnCount: 2, columnSep: 18)

    static let ieeeConference = DocumentGeometry(
        paperWidth: 612, paperHeight: 792,
        marginTop: 54, marginBottom: 72,   // 0.75 in top, 1.0 in bottom
        marginLeft: 46, marginRight: 46,   // ~0.64 in → col width ≈ 251 pt ≈ 3.49 in
        columnCount: 2, columnSep: 18)

    static let ieeeDouble = DocumentGeometry(  // alias kept for compatibility
        paperWidth: 612, paperHeight: 792,
        marginTop: 54, marginBottom: 72,
        marginLeft: 46, marginRight: 46,
        columnCount: 2, columnSep: 18)

    static let lncs = DocumentGeometry(
        paperWidth: 595.28, paperHeight: 841.89,  // A4
        marginTop: 74, marginBottom: 220,          // text height ≈ 547.89 pt ≈ 19.3 cm
        marginLeft: 125, marginRight: 125,         // text width  ≈ 345.28 pt ≈ 12.2 cm
        columnCount: 1, columnSep: 0)

    static let a4Article = DocumentGeometry(
        paperWidth: 595.28, paperHeight: 841.89,
        marginTop: 71, marginBottom: 71,
        marginLeft: 71, marginRight: 71,
        columnCount: 1, columnSep: 0)

    /// Build geometry from LaTeXPreamble (geometry package options override)
    static func from(preamble: LaTeXPreamble) -> DocumentGeometry {
        var base: DocumentGeometry
        let cls = preamble.documentClass.lowercased()
        let opts = preamble.documentClassOptions

        if cls.hasPrefix("acmart") {
            let isTwoCol = opts.contains("sigconf") || opts.contains("sigplan") || preamble.isTwoColumn
            base = isTwoCol ? .acmSigConf : .article
        } else if cls.hasPrefix("ieee") {
            base = .ieeeConference
        } else if cls == "llncs" {
            base = .lncs
        } else if opts.contains("a4paper") {
            base = .a4Article
        } else if preamble.isTwoColumn {
            base = .acmTwoColumnLetter
        } else {
            base = .article
        }

        // Apply geometry package overrides
        if let mT = preamble.marginTop    { base = DocumentGeometry(paperWidth: base.paperWidth, paperHeight: base.paperHeight, marginTop: CGFloat(mT), marginBottom: base.marginBottom, marginLeft: base.marginLeft, marginRight: base.marginRight, columnCount: base.columnCount, columnSep: base.columnSep) }
        if let mB = preamble.marginBottom { base = DocumentGeometry(paperWidth: base.paperWidth, paperHeight: base.paperHeight, marginTop: base.marginTop, marginBottom: CGFloat(mB), marginLeft: base.marginLeft, marginRight: base.marginRight, columnCount: base.columnCount, columnSep: base.columnSep) }
        if let mL = preamble.marginLeft   { base = DocumentGeometry(paperWidth: base.paperWidth, paperHeight: base.paperHeight, marginTop: base.marginTop, marginBottom: base.marginBottom, marginLeft: CGFloat(mL), marginRight: base.marginRight, columnCount: base.columnCount, columnSep: base.columnSep) }
        if let mR = preamble.marginRight  { base = DocumentGeometry(paperWidth: base.paperWidth, paperHeight: base.paperHeight, marginTop: base.marginTop, marginBottom: base.marginBottom, marginLeft: base.marginLeft, marginRight: CGFloat(mR), columnCount: base.columnCount, columnSep: base.columnSep) }
        if let pW = preamble.paperWidth   { base = DocumentGeometry(paperWidth: CGFloat(pW), paperHeight: base.paperHeight, marginTop: base.marginTop, marginBottom: base.marginBottom, marginLeft: base.marginLeft, marginRight: base.marginRight, columnCount: base.columnCount, columnSep: base.columnSep) }
        if let pH = preamble.paperHeight  { base = DocumentGeometry(paperWidth: base.paperWidth, paperHeight: CGFloat(pH), marginTop: base.marginTop, marginBottom: base.marginBottom, marginLeft: base.marginLeft, marginRight: base.marginRight, columnCount: base.columnCount, columnSep: base.columnSep) }

        return base
    }
}

// MARK: - Font configuration

struct TeXFontConfig {
    let bodyFace:   String  // e.g. "Palatino-Roman"
    let boldFace:   String
    let italicFace: String
    let boldItalicFace: String
    let monoFace:   String
    let mathFace:   String  // for variables
    let bodySize:   CGFloat

    var headingSizes: [CGFloat] { [bodySize * 1.8, bodySize * 1.4, bodySize * 1.2, bodySize * 1.1, bodySize * 1.0] }

    static let palatino = TeXFontConfig(
        bodyFace: "Palatino-Roman", boldFace: "Palatino-Bold",
        italicFace: "Palatino-Italic", boldItalicFace: "Palatino-BoldItalic",
        monoFace: "Menlo-Regular", mathFace: "Palatino-Italic",
        bodySize: 11)

    static let timesACM = TeXFontConfig(
        bodyFace: "TimesNewRomanPSMT", boldFace: "TimesNewRomanPS-BoldMT",
        italicFace: "TimesNewRomanPS-ItalicMT", boldItalicFace: "TimesNewRomanPS-BoldItalicMT",
        monoFace: "Menlo-Regular", mathFace: "TimesNewRomanPS-ItalicMT",
        bodySize: 9)

    static let timesIEEE = TeXFontConfig(
        bodyFace: "TimesNewRomanPSMT", boldFace: "TimesNewRomanPS-BoldMT",
        italicFace: "TimesNewRomanPS-ItalicMT", boldItalicFace: "TimesNewRomanPS-BoldItalicMT",
        monoFace: "Menlo-Regular", mathFace: "TimesNewRomanPS-ItalicMT",
        bodySize: 10)

    static let times = TeXFontConfig(
        bodyFace: "TimesNewRomanPSMT", boldFace: "TimesNewRomanPS-BoldMT",
        italicFace: "TimesNewRomanPS-ItalicMT", boldItalicFace: "TimesNewRomanPS-BoldItalicMT",
        monoFace: "Menlo-Regular", mathFace: "TimesNewRomanPS-ItalicMT",
        bodySize: 11)

    static let timesLNCS = TeXFontConfig(
        bodyFace: "TimesNewRomanPSMT", boldFace: "TimesNewRomanPS-BoldMT",
        italicFace: "TimesNewRomanPS-ItalicMT", boldItalicFace: "TimesNewRomanPS-BoldItalicMT",
        monoFace: "CourierNewPSMT", mathFace: "TimesNewRomanPS-ItalicMT",
        bodySize: 10)

    static let georgia = TeXFontConfig(
        bodyFace: "Georgia", boldFace: "Georgia-Bold",
        italicFace: "Georgia-Italic", boldItalicFace: "Georgia-BoldItalic",
        monoFace: "Menlo-Regular", mathFace: "Georgia-Italic",
        bodySize: 11)

    static func from(preamble: LaTeXPreamble) -> TeXFontConfig {
        let cls = preamble.documentClass.lowercased()
        if cls.hasPrefix("acmart") { return .timesACM }
        if cls.hasPrefix("ieee")   { return .timesIEEE }
        if cls == "llncs"          { return .timesLNCS }
        // Default: 12pt article uses Palatino; with explicit 12pt option
        if preamble.documentClassOptions.contains("12pt") {
            return TeXFontConfig(bodyFace: "Palatino-Roman", boldFace: "Palatino-Bold",
                italicFace: "Palatino-Italic", boldItalicFace: "Palatino-BoldItalic",
                monoFace: "Menlo-Regular", mathFace: "Palatino-Italic", bodySize: 12)
        }
        if preamble.documentClassOptions.contains("11pt") {
            return .palatino  // default
        }
        return .palatino
    }
}

// MARK: - Math style

enum MathStyle {
    case display, text, script, scriptScript
    var isCramped: Bool { false }
    var subscriptStyle: MathStyle {
        switch self {
        case .display, .text: return .script
        default: return .scriptScript
        }
    }
    var numeratorStyle: MathStyle {
        switch self {
        case .display: return .text
        case .text: return .script
        default: return .scriptScript
        }
    }
    var denominatorStyle: MathStyle { subscriptStyle }
    func fontSize(base: CGFloat) -> CGFloat {
        switch self {
        case .display, .text: return base
        case .script: return max(base * 0.71, 5)
        case .scriptScript: return max(base * 0.5, 4)
        }
    }
}

// MARK: - Math atom types

enum MathAtomType { case ord, op, bin, rel, open, close, punct, inner }

// MARK: - Math nodes (AST)

indirect enum MathNode {
    case atom(String, MathAtomType, font: MathFont)
    case group([MathNode])
    case script(base: MathNode, sup: MathNode?, sub: MathNode?)
    case fraction(num: MathNode, denom: MathNode, rule: Bool)
    case radical(degree: MathNode?, body: MathNode)
    case largeOp(name: String, sub: MathNode?, sup: MathNode?, limits: Bool)
    case fence(open: String, body: [MathNode], close: String)
    case matrix(rows: [[MathNode]], env: String)
    case space(CGFloat)
    case text(String)
}

enum MathFont { case rm, it, bf, tt, cal, bb }

// MARK: - Typeset block (output of typesetter)

struct TypesetPage {
    var blocks: [TypesetBlock] = []
    var pageNumber: Int = 1
}

enum TypesetBlock {
    case ctFrame(CTFrame, CGRect)                      // CoreText laid-out text
    case coloredFrame(color: CGColor, frame: CTFrame, rect: CGRect)  // colored text frame
    case mathDisplay(MathNode, CGRect)                 // display math
    case rule(CGRect)                                  // horizontal rule
    case colorRule(color: CGColor, rect: CGRect)       // colored rule
    case verticalSpace(CGFloat)                        // blank space
    case titleBlock(TypesetTitleBlock)
    case columnBreak                                   // force next column
    case tableGrid(TableGridData)                      // full table with grid lines
    case imageBlock(ImageBlockData)                    // \includegraphics
    case tcolorboxBlock(TcolorboxData)                 // tcolorbox environment
    case footnoteRule(CGRect)                          // footnote separator
    case footnoteBlock(FootnoteData)                   // numbered footnote
    case pageNumberBlock(number: Int, rect: CGRect)    // page number
}

struct TypesetTitleBlock {
    var title:    String
    var authors:  [String]
    var abstract: String?
    var rect:     CGRect
}

// MARK: - Typeset document

struct TypesetDocument {
    var pages:    [TypesetPage]
    var geometry: DocumentGeometry
    var fonts:    TeXFontConfig

    static let empty = TypesetDocument(pages: [], geometry: .article, fonts: .palatino)
}

// MARK: - Counter state

struct TeXCounters {
    var section    = 0
    var subsection = 0
    var subsubsection = 0
    var equation   = 0
    var figure     = 0
    var table      = 0

    mutating func incrementSection() -> String {
        section += 1; subsection = 0; subsubsection = 0
        return "\(section)"
    }
    mutating func incrementSubsection() -> String {
        subsection += 1; subsubsection = 0
        return "\(section).\(subsection)"
    }
    mutating func incrementSubsubsection() -> String {
        subsubsection += 1
        return "\(section).\(subsection).\(subsubsection)"
    }
    mutating func incrementEquation() -> String { equation += 1; return "(\(equation))" }

    // Raw integer increments for document-class-aware numbering (e.g. IEEE Roman numerals)
    mutating func incrementSectionRaw() -> Int {
        section += 1; subsection = 0; subsubsection = 0; return section
    }
    mutating func incrementSubsectionRaw() -> Int {
        subsection += 1; subsubsection = 0; return subsection
    }
    mutating func incrementSubsubsectionRaw() -> Int {
        subsubsection += 1; return subsubsection
    }
}
