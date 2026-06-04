// PackageRegistry.swift — Central registry for LaTeX package implementations.
// Each package registers command and environment handlers that the parser
// and typesetter consult when encountering unknown commands/environments.
import Foundation
import CoreGraphics

// MARK: - Protocol

protocol LaTeXPackage {
    var name: String { get }
    /// Called once when the package is loaded. Returns new macros to add.
    func load(options: String, expander: inout TeXExpander) -> [String: MacroDef]
}

// MARK: - Registry

final class PackageRegistry {

    static let shared = PackageRegistry()

    private var registered: [String: LaTeXPackage] = [:]

    private init() {
        // Register all built-in packages
        let packages: [LaTeXPackage] = [
            GeometryPackage(),
            XColorPackage(),
            GraphicxPackage(),
            AmsmathPackage(),
            BooktabsPackage(),
            TabularxPackage(),
            EnumitemPackage(),
            HyperrefPackage(),
            CaptionPackage(),
            ListingsPackage(),
            TcolorboxPackage(),
            CommentPackage(),
            FontawesomePackage(),
            MiscPackage(),          // fancyhdr, microtype, fontenc, inputenc, …
        ]
        for pkg in packages { registered[pkg.name] = pkg }
        // Aliases
        let aliases: [(String, String)] = [
            ("amsfonts", "amsmath"), ("amssymb", "amsmath"), ("mathtools", "amsmath"),
            ("color", "xcolor"), ("colortbl", "xcolor"),
            ("tabulary", "tabularx"), ("longtable", "tabularx"),
            ("multirow", "tabularx"), ("array", "tabularx"),
            ("subcaption", "caption"), ("subfig", "caption"),
            ("wrapfig", "graphicx"), ("float", "graphicx"),
            ("minted", "listings"), ("algorithm", "misc"), ("algorithmic", "misc"),
            ("siunitx", "misc"), ("cleveref", "hyperref"),
            ("natbib", "misc"), ("biblatex", "misc"),
            ("fontawesome", "fontawesome5"),
            ("tcolorbox", "tcolorbox"),
        ]
        for (alias, target) in aliases {
            if let pkg = registered[target] { registered[alias] = pkg }
        }
    }

    /// Load packages declared in the preamble and collect additional macros.
    func loadPackages(from preamble: LaTeXPreamble, expander: inout TeXExpander) {
        for (pkgName, options) in preamble.packages {
            guard let pkg = registered[pkgName] else { continue }
            let newMacros = pkg.load(options: options, expander: &expander)
            for (k, v) in newMacros { expander.registerMacro(k, def: v) }
        }
    }
}

// MARK: - GeometryPackage

struct GeometryPackage: LaTeXPackage {
    var name: String { "geometry" }
    func load(options: String, expander: inout TeXExpander) -> [String: MacroDef] {
        // Geometry options already parsed by TeXExpander.extractPackages
        return [:]
    }
}

// MARK: - XColorPackage

struct XColorPackage: LaTeXPackage {
    var name: String { "xcolor" }
    func load(options: String, expander: inout TeXExpander) -> [String: MacroDef] {
        // \textcolor and \colorbox handled inline by parser
        // \definecolor{name}{model}{spec} — register as a custom named color
        return [:]
    }
}

// MARK: - GraphicxPackage

struct GraphicxPackage: LaTeXPackage {
    var name: String { "graphicx" }
    func load(options: String, expander: inout TeXExpander) -> [String: MacroDef] {
        // \includegraphics handled inline
        return [
            "scalebox": MacroDef(arity: 2, optDefault: nil, body: "#2"),
            "resizebox": MacroDef(arity: 3, optDefault: nil, body: "#3"),
            "rotatebox": MacroDef(arity: 2, optDefault: nil, body: "#2"),
            "reflectbox": MacroDef(arity: 1, optDefault: nil, body: "#1"),
        ]
    }
}

// MARK: - AmsmathPackage

struct AmsmathPackage: LaTeXPackage {
    var name: String { "amsmath" }
    func load(options: String, expander: inout TeXExpander) -> [String: MacroDef] {
        return [
            // Text in math
            "text": MacroDef(arity: 1, optDefault: nil, body: "\\text{#1}"),
            // Math operators
            "operatorname": MacroDef(arity: 1, optDefault: nil, body: "\\mathrm{#1}"),
            "DeclareMathOperator": MacroDef(arity: 2, optDefault: nil, body: ""),
            // Number sets (if not user-defined)
            "mathbb": MacroDef(arity: 1, optDefault: nil, body: "\\mathbb{#1}"),
            "mathcal": MacroDef(arity: 1, optDefault: nil, body: "\\mathcal{#1}"),
            "mathbf": MacroDef(arity: 1, optDefault: nil, body: "\\mathbf{#1}"),
            "boldsymbol": MacroDef(arity: 1, optDefault: nil, body: "\\boldsymbol{#1}"),
            // Equation numbering helpers
            "tag": MacroDef(arity: 1, optDefault: nil, body: ""),
            "notag": MacroDef(arity: 0, optDefault: nil, body: ""),
            "nonumber": MacroDef(arity: 0, optDefault: nil, body: ""),
            // Spacing
            "mspace": MacroDef(arity: 1, optDefault: nil, body: ""),
            "negmedspace": MacroDef(arity: 0, optDefault: nil, body: ""),
            // Delimiters
            "lvert": MacroDef(arity: 0, optDefault: nil, body: "|"),
            "rvert": MacroDef(arity: 0, optDefault: nil, body: "|"),
            "lVert": MacroDef(arity: 0, optDefault: nil, body: "‖"),
            "rVert": MacroDef(arity: 0, optDefault: nil, body: "‖"),
            // Common named operators
            "ker": MacroDef(arity: 0, optDefault: nil, body: "ker"),
            "dim": MacroDef(arity: 0, optDefault: nil, body: "dim"),
            "hom": MacroDef(arity: 0, optDefault: nil, body: "hom"),
            "Pr": MacroDef(arity: 0, optDefault: nil, body: "Pr"),
            "gcd": MacroDef(arity: 0, optDefault: nil, body: "gcd"),
            "lcm": MacroDef(arity: 0, optDefault: nil, body: "lcm"),
            "intertext": MacroDef(arity: 1, optDefault: nil, body: "#1"),
            "shortintertext": MacroDef(arity: 1, optDefault: nil, body: "#1"),
        ]
    }
}

// MARK: - BooktabsPackage

struct BooktabsPackage: LaTeXPackage {
    var name: String { "booktabs" }
    func load(options: String, expander: inout TeXExpander) -> [String: MacroDef] {
        // \toprule, \midrule, \bottomrule, \cmidrule — handled by parser
        return [
            "addlinespace": MacroDef(arity: 0, optDefault: nil, body: ""),
            "specialrule": MacroDef(arity: 3, optDefault: nil, body: ""),
            "morecmidrules": MacroDef(arity: 0, optDefault: nil, body: ""),
        ]
    }
}

// MARK: - TabularxPackage

struct TabularxPackage: LaTeXPackage {
    var name: String { "tabularx" }
    func load(options: String, expander: inout TeXExpander) -> [String: MacroDef] {
        return [
            "multicolumn": MacroDef(arity: 3, optDefault: nil, body: "#3"),
            "multirow": MacroDef(arity: 3, optDefault: nil, body: "#3"),
            "cline": MacroDef(arity: 1, optDefault: nil, body: ""),
            "hhline": MacroDef(arity: 1, optDefault: nil, body: ""),
            "arrayrulewidth": MacroDef(arity: 0, optDefault: nil, body: ""),
        ]
    }
}

// MARK: - EnumitemPackage

struct EnumitemPackage: LaTeXPackage {
    var name: String { "enumitem" }
    func load(options: String, expander: inout TeXExpander) -> [String: MacroDef] {
        return [
            "setlist": MacroDef(arity: 2, optDefault: nil, body: ""),
            "setitemize": MacroDef(arity: 2, optDefault: nil, body: ""),
            "setenumerate": MacroDef(arity: 2, optDefault: nil, body: ""),
            "newlist": MacroDef(arity: 3, optDefault: nil, body: ""),
        ]
    }
}

// MARK: - HyperrefPackage

struct HyperrefPackage: LaTeXPackage {
    var name: String { "hyperref" }
    func load(options: String, expander: inout TeXExpander) -> [String: MacroDef] {
        return [
            "autoref": MacroDef(arity: 1, optDefault: nil, body: "\\ref{#1}"),
            "nameref": MacroDef(arity: 1, optDefault: nil, body: "\\ref{#1}"),
            "cref": MacroDef(arity: 1, optDefault: nil, body: "\\ref{#1}"),
            "Cref": MacroDef(arity: 1, optDefault: nil, body: "\\ref{#1}"),
            "hypersetup": MacroDef(arity: 1, optDefault: nil, body: ""),
            "hypertarget": MacroDef(arity: 2, optDefault: nil, body: "#2"),
            "hyperlink": MacroDef(arity: 2, optDefault: nil, body: "#2"),
            "urlstyle": MacroDef(arity: 1, optDefault: nil, body: ""),
            "pdfbookmark": MacroDef(arity: 3, optDefault: nil, body: ""),
        ]
    }
}

// MARK: - CaptionPackage

struct CaptionPackage: LaTeXPackage {
    var name: String { "caption" }
    func load(options: String, expander: inout TeXExpander) -> [String: MacroDef] {
        return [
            "captionsetup": MacroDef(arity: 1, optDefault: "figure", body: ""),
            "captionof": MacroDef(arity: 2, optDefault: nil, body: ""),
            "subcaptionbox": MacroDef(arity: 2, optDefault: nil, body: "#2"),
        ]
    }
}

// MARK: - ListingsPackage

struct ListingsPackage: LaTeXPackage {
    var name: String { "listings" }
    func load(options: String, expander: inout TeXExpander) -> [String: MacroDef] {
        return [
            "lstset": MacroDef(arity: 1, optDefault: nil, body: ""),
            "lstdefinelanguage": MacroDef(arity: 2, optDefault: nil, body: ""),
            "lstdefinestyle": MacroDef(arity: 2, optDefault: nil, body: ""),
            "lstinputlisting": MacroDef(arity: 1, optDefault: "", body: ""),
            "lstinline": MacroDef(arity: 1, optDefault: nil, body: "\\texttt{#1}"),
        ]
    }
}

// MARK: - TcolorboxPackage

struct TcolorboxPackage: LaTeXPackage {
    var name: String { "tcolorbox" }
    func load(options: String, expander: inout TeXExpander) -> [String: MacroDef] {
        return [
            "tcbset": MacroDef(arity: 1, optDefault: nil, body: ""),
            "tcbsetforeverylayer": MacroDef(arity: 1, optDefault: nil, body: ""),
            "newtcolorbox": MacroDef(arity: 3, optDefault: nil, body: ""),
            "newtcbox": MacroDef(arity: 2, optDefault: nil, body: ""),
        ]
    }
}

// MARK: - CommentPackage

struct CommentPackage: LaTeXPackage {
    var name: String { "comment" }
    func load(options: String, expander: inout TeXExpander) -> [String: MacroDef] {
        // \begin{comment}...\end{comment} handled by parser
        return [
            "excludecomment": MacroDef(arity: 1, optDefault: nil, body: ""),
            "includecomment": MacroDef(arity: 1, optDefault: nil, body: ""),
            "specialcomment": MacroDef(arity: 4, optDefault: nil, body: ""),
        ]
    }
}

// MARK: - FontawesomePackage

struct FontawesomePackage: LaTeXPackage {
    var name: String { "fontawesome5" }
    func load(options: String, expander: inout TeXExpander) -> [String: MacroDef] {
        // Map common \fa commands to Unicode equivalents
        var defs: [String: MacroDef] = [:]
        let icons: [(String, String)] = [
            ("faCheck",     "✓"), ("faTimes",     "✗"), ("faPlus",      "+"),
            ("faMinus",     "−"), ("faSearch",    "🔍"), ("faHome",     "⌂"),
            ("faUser",      "👤"), ("faUsers",    "👥"), ("faEnvelope", "✉"),
            ("faPhone",     "☎"), ("faStar",      "★"), ("faHeart",    "♥"),
            ("faArrowRight","→"), ("faArrowLeft", "←"), ("faArrowUp",  "↑"),
            ("faArrowDown", "↓"), ("faBars",      "≡"), ("faCog",     "⚙"),
            ("faExclamationTriangle", "⚠"), ("faInfoCircle", "ℹ"),
            ("faCheckCircle", "✓"), ("faTimesCircle", "✗"),
            ("faGithub",    ""), ("faTwitter",   ""), ("faLinkedin",  ""),
            ("faCode",      "⟨⟩"), ("faFileCode", "📄"), ("faTerminal", "$"),
        ]
        for (cmd, unicode) in icons {
            defs[cmd] = MacroDef(arity: 0, optDefault: nil, body: unicode)
            // starred form
            defs[cmd + "*"] = MacroDef(arity: 0, optDefault: nil, body: unicode)
        }
        // Generic fallback: \faXxx -> [Xxx]
        return defs
    }
}

// MARK: - MiscPackage (catch-all for no-op packages)

struct MiscPackage: LaTeXPackage {
    var name: String { "misc" }
    func load(options: String, expander: inout TeXExpander) -> [String: MacroDef] {
        return [
            // fancyhdr
            "fancyhf":  MacroDef(arity: 1, optDefault: nil, body: ""),
            "fancyhead": MacroDef(arity: 1, optDefault: nil, body: ""),
            "fancyfoot": MacroDef(arity: 1, optDefault: nil, body: ""),
            "lhead": MacroDef(arity: 1, optDefault: nil, body: ""),
            "rhead": MacroDef(arity: 1, optDefault: nil, body: ""),
            "lfoot": MacroDef(arity: 1, optDefault: nil, body: ""),
            "rfoot": MacroDef(arity: 1, optDefault: nil, body: ""),
            "cfoot": MacroDef(arity: 1, optDefault: nil, body: ""),
            "pagestyle": MacroDef(arity: 1, optDefault: nil, body: ""),
            "thispagestyle": MacroDef(arity: 1, optDefault: nil, body: ""),
            // microtype
            "microtypesetup": MacroDef(arity: 1, optDefault: nil, body: ""),
            // fontenc / inputenc
            "selectfont": MacroDef(arity: 0, optDefault: nil, body: ""),
            // natbib
            "citep": MacroDef(arity: 1, optDefault: nil, body: "[\\cite{#1}]"),
            "citet": MacroDef(arity: 1, optDefault: nil, body: "\\cite{#1}"),
            "citealp": MacroDef(arity: 1, optDefault: nil, body: "\\cite{#1}"),
            // biblatex
            "addbibresource": MacroDef(arity: 1, optDefault: nil, body: ""),
            "printbibliography": MacroDef(arity: 0, optDefault: nil, body: ""),
            "parencite": MacroDef(arity: 1, optDefault: nil, body: "[\\cite{#1}]"),
            "textcite": MacroDef(arity: 1, optDefault: nil, body: "\\cite{#1}"),
            "autocite": MacroDef(arity: 1, optDefault: nil, body: "[\\cite{#1}]"),
            // siunitx
            "SI": MacroDef(arity: 2, optDefault: nil, body: "#1\\,#2"),
            "si": MacroDef(arity: 1, optDefault: nil, body: "#1"),
            "num": MacroDef(arity: 1, optDefault: nil, body: "#1"),
            "ang": MacroDef(arity: 1, optDefault: nil, body: "#1°"),
            // algorithmicx
            "State": MacroDef(arity: 0, optDefault: nil, body: ""),
            "Procedure": MacroDef(arity: 0, optDefault: nil, body: ""),
            "Function": MacroDef(arity: 0, optDefault: nil, body: ""),
            "If": MacroDef(arity: 1, optDefault: nil, body: "if #1 then"),
            "ElsIf": MacroDef(arity: 1, optDefault: nil, body: "else if #1 then"),
            "Else": MacroDef(arity: 0, optDefault: nil, body: "else"),
            "EndIf": MacroDef(arity: 0, optDefault: nil, body: "end if"),
            "For": MacroDef(arity: 1, optDefault: nil, body: "for #1 do"),
            "EndFor": MacroDef(arity: 0, optDefault: nil, body: "end for"),
            "While": MacroDef(arity: 1, optDefault: nil, body: "while #1 do"),
            "EndWhile": MacroDef(arity: 0, optDefault: nil, body: "end while"),
            "Return": MacroDef(arity: 1, optDefault: nil, body: "return #1"),
            // Generic layout helpers (no-op)
            "vspace": MacroDef(arity: 1, optDefault: nil, body: ""),
            "hspace": MacroDef(arity: 1, optDefault: nil, body: ""),
            "vspace*": MacroDef(arity: 1, optDefault: nil, body: ""),
            "hspace*": MacroDef(arity: 1, optDefault: nil, body: ""),
            "bigskip": MacroDef(arity: 0, optDefault: nil, body: "\n\n"),
            "medskip": MacroDef(arity: 0, optDefault: nil, body: "\n"),
            "smallskip": MacroDef(arity: 0, optDefault: nil, body: ""),
            "noindent": MacroDef(arity: 0, optDefault: nil, body: ""),
            "newpage": MacroDef(arity: 0, optDefault: nil, body: "\n"),
            "clearpage": MacroDef(arity: 0, optDefault: nil, body: "\n"),
            "linebreak": MacroDef(arity: 0, optDefault: nil, body: "\n"),
            "pagebreak": MacroDef(arity: 0, optDefault: nil, body: ""),
            "centering": MacroDef(arity: 0, optDefault: nil, body: ""),
            "raggedright": MacroDef(arity: 0, optDefault: nil, body: ""),
            "raggedleft": MacroDef(arity: 0, optDefault: nil, body: ""),
            "flushleft": MacroDef(arity: 0, optDefault: nil, body: ""),
            "flushright": MacroDef(arity: 0, optDefault: nil, body: ""),
            // ACM-specific
            "acmDOI": MacroDef(arity: 1, optDefault: nil, body: ""),
            "acmISBN": MacroDef(arity: 1, optDefault: nil, body: ""),
            "acmConference": MacroDef(arity: 3, optDefault: nil, body: ""),
            "acmYear": MacroDef(arity: 1, optDefault: nil, body: ""),
            "acmBooktitle": MacroDef(arity: 1, optDefault: nil, body: ""),
            "acmPrice": MacroDef(arity: 1, optDefault: nil, body: ""),
            "copyrightyear": MacroDef(arity: 1, optDefault: nil, body: ""),
            "CopyrightYear": MacroDef(arity: 1, optDefault: nil, body: ""),
            "affiliation": MacroDef(arity: 1, optDefault: nil, body: ""),
            "institution": MacroDef(arity: 1, optDefault: nil, body: "#1"),
            "city": MacroDef(arity: 1, optDefault: nil, body: "#1"),
            "country": MacroDef(arity: 1, optDefault: nil, body: "#1"),
            "email": MacroDef(arity: 1, optDefault: nil, body: "#1"),
            "orcidID": MacroDef(arity: 1, optDefault: nil, body: ""),
            // IEEE-specific
            "IEEEauthorblockN": MacroDef(arity: 1, optDefault: nil, body: "#1"),
            "IEEEauthorblockA": MacroDef(arity: 1, optDefault: nil, body: ""),
            "IEEEoverridecommandlockouts": MacroDef(arity: 0, optDefault: nil, body: ""),
            // LLNCS-specific
            "inst": MacroDef(arity: 1, optDefault: nil, body: ""),
            "keywords": MacroDef(arity: 1, optDefault: nil, body: "\\textbf{Keywords:} #1"),
            // General typography
            "textwidth": MacroDef(arity: 0, optDefault: nil, body: "0pt"),
            "columnwidth": MacroDef(arity: 0, optDefault: nil, body: "0pt"),
            "linewidth": MacroDef(arity: 0, optDefault: nil, body: "0pt"),
            "textheight": MacroDef(arity: 0, optDefault: nil, body: "0pt"),
            "hfill": MacroDef(arity: 0, optDefault: nil, body: " "),
            "vfill": MacroDef(arity: 0, optDefault: nil, body: ""),
            "hline": MacroDef(arity: 0, optDefault: nil, body: ""),
            "hrule": MacroDef(arity: 0, optDefault: nil, body: ""),
            "rule": MacroDef(arity: 2, optDefault: nil, body: ""),
            "today": MacroDef(arity: 0, optDefault: nil, body: TeXExpander.todayString()),
            "thepage": MacroDef(arity: 0, optDefault: nil, body: "1"),
            "thesection": MacroDef(arity: 0, optDefault: nil, body: ""),
            "baselineskip": MacroDef(arity: 0, optDefault: nil, body: "12pt"),
        ]
    }
}

// MARK: - TeXExpander today helper

extension TeXExpander {
    static func todayString() -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .long
        return fmt.string(from: Date())
    }
}
