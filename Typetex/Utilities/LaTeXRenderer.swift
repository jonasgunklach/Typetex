//
//  LaTeXRenderer.swift
//  Typetex
//
//  Native SwiftUI renderer for the LaTeX AST produced by LaTeXParser.
//

import SwiftUI

// MARK: - Document view

struct LaTeXDocumentView: View {
    let blocks: [TexBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                LaTeXBlockView(block: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Block view

struct LaTeXBlockView: View {
    let block: TexBlock

    var body: some View {
        switch block {
        case .heading(let level, _, let inlines):
            InlineTextView(inlines: inlines)
                .font(headingFont(level))
                .padding(.top, level < 2 ? 20 : 12)
                .padding(.bottom, 4)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .paragraph(let inlines):
            InlineTextView(inlines: inlines)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .mathDisplay(let math):
            Text(MathConverter.convert(math))
                .font(.system(.body, design: .serif))
                .multilineTextAlignment(.center)
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))

        case .codeBlock(let code):
            Text(code)
                .font(.system(.callout, design: .monospaced))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))

        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, itemBlocks in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\u{2022}").padding(.top, 1)
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(itemBlocks.enumerated()), id: \.offset) { _, b in
                                LaTeXBlockView(block: b)
                            }
                        }
                    }
                }
            }

        case .numberedList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, itemBlocks in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(idx + 1).")
                            .monospacedDigit()
                            .frame(minWidth: 24, alignment: .trailing)
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(itemBlocks.enumerated()), id: \.offset) { _, b in
                                LaTeXBlockView(block: b)
                            }
                        }
                    }
                }
            }

        case .blockQuote(let inner):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(inner.enumerated()), id: \.offset) { _, b in
                    LaTeXBlockView(block: b)
                }
            }
            .padding(.leading, 16)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor.opacity(0.5))
                    .frame(width: 3)
            }
            .padding(.vertical, 4)

        case .thematicBreak:
            Divider().padding(.vertical, 8)

        // New cases (handled by CoreText renderer; legacy view just shows placeholders)
        case .documentMetadata, .abstract, .titleBlock, .table, .figure:
            EmptyView()
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 0: return .largeTitle.bold()
        case 1: return .title.bold()
        case 2: return .title2.bold()
        case 3: return .title3.bold()
        default: return .headline
        }
    }
}

// MARK: - Inline text view

struct InlineTextView: View {
    let inlines: [TexInline]

    var body: some View {
        inlines.reduce(into: Text("")) { acc, node in
            acc = Text("\(acc)\(render(node))")
        }
    }

    private func render(_ node: TexInline) -> Text {
        switch node {
        case .text(let s):
            return Text(s)
        case .bold(let children):
            return children.reduce(into: Text("")) { acc, n in acc = Text("\(acc)\(render(n))") }.bold()
        case .italic(let children):
            return children.reduce(into: Text("")) { acc, n in acc = Text("\(acc)\(render(n))") }.italic()
        case .underline(let children):
            return children.reduce(into: Text("")) { acc, n in acc = Text("\(acc)\(render(n))") }.underline()
        case .strikethrough(let children):
            return children.reduce(into: Text("")) { acc, n in acc = Text("\(acc)\(render(n))") }.strikethrough()
        case .code(let s):
            return Text(s).font(.system(.body, design: .monospaced))
        case .mathInline(let s):
            return Text(MathConverter.convert(s)).font(.system(.body, design: .serif))
        case .lineBreak:
            return Text("\n")
        case .link(let label, _):
            return Text(label).underline().foregroundColor(.blue)
        case .footnote(let children):
            let inner = children.reduce(into: Text("")) { acc, n in acc = Text("\(acc)\(render(n))") }
            return Text(" [\(inner)]")
        }
    }
}

// MARK: - Math Unicode converter

enum MathConverter {

    static func convert(_ latex: String) -> String {
        var s = latex
        s = replaceFracs(s)
        s = applySuper(s)
        s = applySub(s)
        // Replace longest commands first to avoid prefix collisions (e.g. \int vs \in)
        for (cmd, sym) in symbols.sorted(by: { $0.0.count > $1.0.count }) {
            s = s.replacingOccurrences(of: "\\\(cmd)", with: sym)
        }
        // Strip remaining unknown commands
        s = s.replacingOccurrences(of: #"\\[a-zA-Z]+"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "[{}]", with: "", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Fractions

    private static func replaceFracs(_ input: String) -> String {
        var s = input
        let rx = try? NSRegularExpression(pattern: #"\\frac\{([^{}]*)\}\{([^{}]*)\}"#)
        var iterations = 0
        while iterations < 20,
              let m = rx?.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let r = Range(m.range, in: s),
              let n = Range(m.range(at: 1), in: s),
              let d = Range(m.range(at: 2), in: s) {
            s.replaceSubrange(r, with: "\(s[n])/\(s[d])")
            iterations += 1
        }
        return s
    }

    // MARK: Superscripts

    private static func applySuper(_ input: String) -> String {
        var s = input
        let rx = try? NSRegularExpression(pattern: #"\^(?:\{([^}]*)\}|([a-zA-Z0-9]))"#)
        var iterations = 0
        while iterations < 50,
              let m = rx?.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let r = Range(m.range, in: s) {
            let content: String
            if let g = Range(m.range(at: 1), in: s)      { content = String(s[g]) }
            else if let g = Range(m.range(at: 2), in: s) { content = String(s[g]) }
            else { break }
            s.replaceSubrange(r, with: content.map { superChar($0) }.joined())
            iterations += 1
        }
        return s
    }

    // MARK: Subscripts

    private static func applySub(_ input: String) -> String {
        var s = input
        let rx = try? NSRegularExpression(pattern: #"_(?:\{([^}]*)\}|([a-zA-Z0-9]))"#)
        var iterations = 0
        while iterations < 50,
              let m = rx?.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let r = Range(m.range, in: s) {
            let content: String
            if let g = Range(m.range(at: 1), in: s)      { content = String(s[g]) }
            else if let g = Range(m.range(at: 2), in: s) { content = String(s[g]) }
            else { break }
            s.replaceSubrange(r, with: content.map { subChar($0) }.joined())
            iterations += 1
        }
        return s
    }

    private static func superChar(_ c: Character) -> String { superTable[c].map(String.init) ?? String(c) }
    private static func subChar(_ c: Character) -> String   { subTable[c].map(String.init)   ?? String(c) }

    private static let superTable: [Character: Character] = [
        "0":"0","1":"\u{00B9}","2":"\u{00B2}","3":"\u{00B3}","4":"\u{2074}",
        "5":"\u{2075}","6":"\u{2076}","7":"\u{2077}","8":"\u{2078}","9":"\u{2079}",
        "+":"\u{207A}","-":"\u{207B}","=":"\u{207C}","(":"\u{207D}",")":"\u{207E}",
        "n":"\u{207F}","i":"\u{2071}",
        "a":"\u{1D43}","b":"\u{1D47}","c":"\u{1D9C}","d":"\u{1D48}","e":"\u{1D49}",
        "f":"\u{1DA0}","g":"\u{1D4D}","h":"\u{02B0}","j":"\u{02B2}","k":"\u{1D4F}",
        "l":"\u{02E1}","m":"\u{1D50}","o":"\u{1D52}","p":"\u{1D56}","r":"\u{02B3}",
        "s":"\u{02E2}","t":"\u{1D57}","u":"\u{1D58}","v":"\u{1D5B}","w":"\u{02B7}",
        "x":"\u{02E3}","y":"\u{02B8}","z":"\u{1DBB}",
    ]

    private static let subTable: [Character: Character] = [
        "0":"\u{2080}","1":"\u{2081}","2":"\u{2082}","3":"\u{2083}","4":"\u{2084}",
        "5":"\u{2085}","6":"\u{2086}","7":"\u{2087}","8":"\u{2088}","9":"\u{2089}",
        "+":"\u{208A}","-":"\u{208B}","=":"\u{208C}","(":"\u{208D}",")":"\u{208E}",
        "a":"\u{2090}","e":"\u{2091}","o":"\u{2092}","x":"\u{2093}","i":"\u{1D62}",
        "n":"\u{2099}","r":"\u{1D63}","u":"\u{1D64}","v":"\u{1D65}",
    ]

    // Sorted longest-first at call site to avoid prefix collisions
    private static let symbols: [(String, String)] = [
        // Greek lowercase
        ("varepsilon","\u{03B5}"),("vartheta","\u{03D1}"),("varsigma","\u{03C2}"),
        ("varpi","\u{03D6}"),("varphi","\u{03C6}"),("varrho","\u{03F1}"),
        ("alpha","\u{03B1}"),("beta","\u{03B2}"),("gamma","\u{03B3}"),("delta","\u{03B4}"),
        ("epsilon","\u{03B5}"),("zeta","\u{03B6}"),("eta","\u{03B7}"),("theta","\u{03B8}"),
        ("iota","\u{03B9}"),("kappa","\u{03BA}"),("lambda","\u{03BB}"),("mu","\u{03BC}"),
        ("nu","\u{03BD}"),("xi","\u{03BE}"),("pi","\u{03C0}"),("rho","\u{03C1}"),
        ("sigma","\u{03C3}"),("tau","\u{03C4}"),("upsilon","\u{03C5}"),("phi","\u{03C6}"),
        ("chi","\u{03C7}"),("psi","\u{03C8}"),("omega","\u{03C9}"),
        // Greek uppercase
        ("Gamma","\u{0393}"),("Delta","\u{0394}"),("Theta","\u{0398}"),("Lambda","\u{039B}"),
        ("Xi","\u{039E}"),("Pi","\u{03A0}"),("Sigma","\u{03A3}"),("Upsilon","\u{03A5}"),
        ("Phi","\u{03A6}"),("Psi","\u{03A8}"),("Omega","\u{03A9}"),
        // Operators
        ("times","\u{00D7}"),("div","\u{00F7}"),("pm","\u{00B1}"),("mp","\u{2213}"),
        ("cdot","\u{00B7}"),("cdots","\u{22EF}"),("ldots","\u{2026}"),
        ("vdots","\u{22EE}"),("ddots","\u{22F1}"),("circ","\u{2218}"),("bullet","\u{2022}"),
        // Relations
        ("subseteq","\u{2286}"),("supseteq","\u{2287}"),("subset","\u{2282}"),("supset","\u{2283}"),
        ("approx","\u{2248}"),("equiv","\u{2261}"),("simeq","\u{2243}"),("cong","\u{2245}"),
        ("sim","\u{223C}"),("leq","\u{2264}"),("geq","\u{2265}"),("neq","\u{2260}"),("ne","\u{2260}"),
        ("propto","\u{221D}"),("notin","\u{2209}"),("in","\u{2208}"),("ni","\u{220B}"),
        ("ll","\u{226A}"),("gg","\u{226B}"),
        // Logic / set
        ("forall","\u{2200}"),("nexists","\u{2204}"),("exists","\u{2203}"),
        ("neg","\u{00AC}"),("land","\u{2227}"),("lor","\u{2228}"),
        ("varnothing","\u{2205}"),("emptyset","\u{2205}"),
        ("nabla","\u{2207}"),("partial","\u{2202}"),
        ("cap","\u{2229}"),("cup","\u{222A}"),
        // Arrows
        ("leftrightarrow","\u{2194}"),("Leftrightarrow","\u{21D4}"),
        ("leftarrow","\u{2190}"),("Leftarrow","\u{21D0}"),
        ("rightarrow","\u{2192}"),("Rightarrow","\u{21D2}"),
        ("uparrow","\u{2191}"),("downarrow","\u{2193}"),
        ("hookrightarrow","\u{21AA}"),("mapsto","\u{21A6}"),
        ("nearrow","\u{2197}"),("searrow","\u{2198}"),
        ("gets","\u{2190}"),("to","\u{2192}"),
        // Calculus / analysis
        ("iiint","\u{222D}"),("iint","\u{222C}"),("oint","\u{222E}"),("int","\u{222B}"),
        ("infty","\u{221E}"),("prod","\u{220F}"),("sum","\u{2211}"),
        ("arcsin","arcsin"),("arccos","arccos"),("arctan","arctan"),
        ("lim","lim"),("sup","sup"),("inf","inf"),("max","max"),("min","min"),
        ("log","log"),("ln","ln"),("sin","sin"),("cos","cos"),("tan","tan"),
        ("sqrt","\u{221A}"),("cbrt","\u{221B}"),
        // Misc
        ("hbar","\u{210F}"),("ell","\u{2113}"),("aleph","\u{2135}"),("wp","\u{2118}"),
        ("dagger","\u{2020}"),("ddagger","\u{2021}"),
        ("angle","\u{2220}"),("perp","\u{22A5}"),("parallel","\u{2225}"),
        ("oplus","\u{2295}"),("otimes","\u{2297}"),("ominus","\u{2296}"),
        ("lfloor","\u{230A}"),("rfloor","\u{230B}"),("lceil","\u{2308}"),("rceil","\u{2309}"),
        ("langle","\u{27E8}"),("rangle","\u{27E9}"),
        ("quad","  "),("qquad","    "),
        // Cleanup — no visible output
        ("left",""),("right",""),("bigg",""),("Bigg",""),("big",""),("Big",""),
        ("mathbf",""),("mathrm",""),("mathit",""),("mathcal",""),("mathbb",""),
        ("boldsymbol",""),("hat",""),("bar",""),("tilde",""),("dot",""),("ddot",""),
        ("vec",""),("widehat",""),("widetilde",""),("overline",""),
        ("text",""),(",",""),("!",""),
    ]
}
