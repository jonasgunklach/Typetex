//  TeXTypes.swift — Shared types for the TeX rendering pipeline
import Foundation
import CoreGraphics
import CoreText

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
        marginTop: 72, marginBottom: 72,
        marginLeft: 72, marginRight: 72,
        columnCount: 2, columnSep: 18)

    static let acmTwoColumnLetter = DocumentGeometry(
        paperWidth: 612, paperHeight: 792,
        marginTop: 72, marginBottom: 72,
        marginLeft: 54, marginRight: 54,
        columnCount: 2, columnSep: 18)
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

    static let georgia = TeXFontConfig(
        bodyFace: "Georgia", boldFace: "Georgia-Bold",
        italicFace: "Georgia-Italic", boldItalicFace: "Georgia-BoldItalic",
        monoFace: "Menlo-Regular", mathFace: "Georgia-Italic",
        bodySize: 11)
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
    case ctFrame(CTFrame, CGRect)            // CoreText laid-out text
    case mathDisplay(MathNode, CGRect)       // display math
    case rule(CGRect)                        // horizontal rule
    case verticalSpace(CGFloat)              // blank space
    case titleBlock(TypesetTitleBlock)
    case columnBreak                         // force next column
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
}
