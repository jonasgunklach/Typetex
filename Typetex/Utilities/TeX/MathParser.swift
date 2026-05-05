//  MathParser.swift — Tokenizes LaTeX math strings into MathNode trees
import Foundation

final class MathParser {

    static func parse(_ src: String) -> MathNode {
        var idx = src.startIndex
        let nodes = parseGroup(src, idx: &idx)
        return .group(nodes)
    }

    // MARK: - Tokenizer

    private static func parseGroup(_ src: String, idx: inout String.Index) -> [MathNode] {
        var result = [MathNode]()
        while idx < src.endIndex {
            let c = src[idx]
            if c == "}" { advance(&idx, in: src); break }
            if let node = parseNext(src, idx: &idx) {
                // Check for script/super
                if idx < src.endIndex && (src[idx] == "^" || src[idx] == "_") {
                    result.append(parseScript(base: node, src: src, idx: &idx))
                } else {
                    result.append(node)
                }
            }
        }
        return result
    }

    private static func parseNext(_ src: String, idx: inout String.Index) -> MathNode? {
        guard idx < src.endIndex else { return nil }
        let c = src[idx]

        if c.isWhitespace { advance(&idx, in: src); return nil }

        if c == "{" {
            advance(&idx, in: src)
            let inner = parseGroup(src, idx: &idx)
            return .group(inner)
        }

        if c == "\\" {
            return parseCommand(src, idx: &idx)
        }

        if c == "^" || c == "_" {
            return nil  // handled by caller
        }

        advance(&idx, in: src)

        // Single character atom
        if c.isLetter { return .atom(String(c), .ord, font: .it) }
        if c.isNumber { return .atom(String(c), .ord, font: .rm) }

        let sym = singleCharSymbol(c)
        if sym.1 != .ord { return .atom(sym.0, sym.1, font: .rm) }
        return .atom(String(c), .ord, font: .rm)
    }

    private static func parseCommand(_ src: String, idx: inout String.Index) -> MathNode? {
        advance(&idx, in: src)  // consume '\'
        guard idx < src.endIndex else { return nil }

        var cmd = ""
        if src[idx].isLetter {
            while idx < src.endIndex && src[idx].isLetter {
                cmd.append(src[idx]); advance(&idx, in: src)
            }
            // Skip trailing spaces after command
            while idx < src.endIndex && src[idx] == " " { advance(&idx, in: src) }
        } else {
            cmd = String(src[idx]); advance(&idx, in: src)
        }

        return dispatch(cmd, src: src, idx: &idx)
    }

    private static func dispatch(_ cmd: String, src: String, idx: inout String.Index) -> MathNode? {
        switch cmd {
        // Fractions
        case "frac":
            let num   = parseBraceArg(src, idx: &idx)
            let denom = parseBraceArg(src, idx: &idx)
            return .fraction(num: num, denom: denom, rule: true)
        case "dfrac":
            let num   = parseBraceArg(src, idx: &idx)
            let denom = parseBraceArg(src, idx: &idx)
            return .fraction(num: num, denom: denom, rule: true)
        case "binom":
            let top = parseBraceArg(src, idx: &idx)
            let bot = parseBraceArg(src, idx: &idx)
            return .fence(open: "(", body: [.fraction(num: top, denom: bot, rule: false)], close: ")")

        // Radicals
        case "sqrt":
            // Check for optional degree
            var degree: MathNode? = nil
            if idx < src.endIndex && src[idx] == "[" {
                advance(&idx, in: src)
                var d = [MathNode]()
                while idx < src.endIndex && src[idx] != "]" {
                    if let n = parseNext(src, idx: &idx) { d.append(n) }
                }
                if idx < src.endIndex { advance(&idx, in: src) }
                degree = .group(d)
            }
            let body = parseBraceArg(src, idx: &idx)
            return .radical(degree: degree, body: body)

        // Text
        case "text", "mathrm", "mbox":
            let arg = parseBraceArg(src, idx: &idx)
            // extract string from atom group
            return flattenToText(arg)

        case "mathbf", "boldsymbol":
            let arg = parseBraceArgRaw(src, idx: &idx)
            return .atom(arg, .ord, font: .bf)
        case "mathtt":
            let arg = parseBraceArgRaw(src, idx: &idx)
            return .atom(arg, .ord, font: .tt)
        case "mathcal":
            let arg = parseBraceArgRaw(src, idx: &idx)
            return .atom(arg, .ord, font: .cal)

        // Spaces
        case ",":  return .space(3)
        case ";":  return .space(5)
        case "!":  return .space(-3)
        case " ":  return .space(6)
        case "quad":  return .space(18)
        case "qquad": return .space(36)

        // Large operators
        case "sum":    return parseLargeOp("sum",    src: src, idx: &idx)
        case "prod":   return parseLargeOp("prod",   src: src, idx: &idx)
        case "int":    return parseLargeOp("int",    src: src, idx: &idx)
        case "iint":   return parseLargeOp("iint",   src: src, idx: &idx)
        case "iiint":  return parseLargeOp("iiint",  src: src, idx: &idx)
        case "oint":   return parseLargeOp("oint",   src: src, idx: &idx)
        case "bigcup": return parseLargeOp("bigcup", src: src, idx: &idx)
        case "bigcap": return parseLargeOp("bigcap", src: src, idx: &idx)
        case "lim":    return parseLargeOp("lim",    src: src, idx: &idx, limits: true)
        case "sup":    return parseLargeOp("sup",    src: src, idx: &idx, limits: true)
        case "inf":    return parseLargeOp("inf",    src: src, idx: &idx, limits: true)
        case "max":    return parseLargeOp("max",    src: src, idx: &idx, limits: true)
        case "min":    return parseLargeOp("min",    src: src, idx: &idx, limits: true)
        case "det":    return parseLargeOp("det",    src: src, idx: &idx, limits: true)
        case "log":    return .atom("log", .op, font: .rm)
        case "exp":    return .atom("exp", .op, font: .rm)
        case "sin":    return .atom("sin", .op, font: .rm)
        case "cos":    return .atom("cos", .op, font: .rm)
        case "tan":    return .atom("tan", .op, font: .rm)

        // Delimiters / fences
        case "left":
            let open = parseDelim(src, idx: &idx)
            var body = [MathNode]()
            while idx < src.endIndex {
                if src[idx] == "\\" {
                    let savedIdx = idx
                    advance(&idx, in: src)
                    var cmd2 = ""
                    while idx < src.endIndex && src[idx].isLetter {
                        cmd2.append(src[idx]); advance(&idx, in: src)
                    }
                    if cmd2 == "right" { break }
                    idx = savedIdx
                }
                if let n = parseNext(src, idx: &idx) { body.append(n) }
            }
            let close = parseDelim(src, idx: &idx)
            return .fence(open: open, body: body, close: close)

        // Greek letters
        case "alpha": return .atom("α", .ord, font: .it)
        case "beta":  return .atom("β", .ord, font: .it)
        case "gamma": return .atom("γ", .ord, font: .it)
        case "delta": return .atom("δ", .ord, font: .it)
        case "epsilon": return .atom("ε", .ord, font: .it)
        case "varepsilon": return .atom("ε", .ord, font: .it)
        case "zeta":  return .atom("ζ", .ord, font: .it)
        case "eta":   return .atom("η", .ord, font: .it)
        case "theta": return .atom("θ", .ord, font: .it)
        case "iota":  return .atom("ι", .ord, font: .it)
        case "kappa": return .atom("κ", .ord, font: .it)
        case "lambda":return .atom("λ", .ord, font: .it)
        case "mu":    return .atom("μ", .ord, font: .it)
        case "nu":    return .atom("ν", .ord, font: .it)
        case "xi":    return .atom("ξ", .ord, font: .it)
        case "pi":    return .atom("π", .ord, font: .it)
        case "rho":   return .atom("ρ", .ord, font: .it)
        case "sigma": return .atom("σ", .ord, font: .it)
        case "tau":   return .atom("τ", .ord, font: .it)
        case "upsilon": return .atom("υ", .ord, font: .it)
        case "phi":   return .atom("φ", .ord, font: .it)
        case "varphi":return .atom("φ", .ord, font: .it)
        case "chi":   return .atom("χ", .ord, font: .it)
        case "psi":   return .atom("ψ", .ord, font: .it)
        case "omega": return .atom("ω", .ord, font: .it)
        case "Gamma": return .atom("Γ", .ord, font: .rm)
        case "Delta": return .atom("Δ", .ord, font: .rm)
        case "Theta": return .atom("Θ", .ord, font: .rm)
        case "Lambda":return .atom("Λ", .ord, font: .rm)
        case "Xi":    return .atom("Ξ", .ord, font: .rm)
        case "Pi":    return .atom("Π", .ord, font: .rm)
        case "Sigma": return .atom("Σ", .ord, font: .rm)
        case "Upsilon":return .atom("Υ", .ord, font: .rm)
        case "Phi":   return .atom("Φ", .ord, font: .rm)
        case "Psi":   return .atom("Ψ", .ord, font: .rm)
        case "Omega": return .atom("Ω", .ord, font: .rm)
        case "nabla": return .atom("∇", .ord, font: .rm)
        case "partial": return .atom("∂", .ord, font: .rm)
        case "infty": return .atom("∞", .ord, font: .rm)

        // Operators / relations
        case "cdot":  return .atom("·", .bin, font: .rm)
        case "times": return .atom("×", .bin, font: .rm)
        case "div":   return .atom("÷", .bin, font: .rm)
        case "pm":    return .atom("±", .bin, font: .rm)
        case "mp":    return .atom("∓", .bin, font: .rm)
        case "cap":   return .atom("∩", .bin, font: .rm)
        case "cup":   return .atom("∪", .bin, font: .rm)
        case "circ":  return .atom("∘", .bin, font: .rm)
        case "bullet": return .atom("•", .bin, font: .rm)
        case "oplus": return .atom("⊕", .bin, font: .rm)
        case "otimes":return .atom("⊗", .bin, font: .rm)
        case "leq","le": return .atom("≤", .rel, font: .rm)
        case "geq","ge": return .atom("≥", .rel, font: .rm)
        case "neq","ne": return .atom("≠", .rel, font: .rm)
        case "approx":return .atom("≈", .rel, font: .rm)
        case "equiv": return .atom("≡", .rel, font: .rm)
        case "sim":   return .atom("∼", .rel, font: .rm)
        case "simeq": return .atom("≃", .rel, font: .rm)
        case "cong":  return .atom("≅", .rel, font: .rm)
        case "in":    return .atom("∈", .rel, font: .rm)
        case "notin": return .atom("∉", .rel, font: .rm)
        case "subset":return .atom("⊂", .rel, font: .rm)
        case "supset":return .atom("⊃", .rel, font: .rm)
        case "subseteq": return .atom("⊆", .rel, font: .rm)
        case "supseteq": return .atom("⊇", .rel, font: .rm)
        case "to","rightarrow": return .atom("→", .rel, font: .rm)
        case "leftarrow": return .atom("←", .rel, font: .rm)
        case "Rightarrow": return .atom("⇒", .rel, font: .rm)
        case "Leftarrow":  return .atom("⇐", .rel, font: .rm)
        case "Leftrightarrow": return .atom("⇔", .rel, font: .rm)
        case "leftrightarrow": return .atom("↔", .rel, font: .rm)
        case "mapsto":    return .atom("↦", .rel, font: .rm)
        case "forall":    return .atom("∀", .ord, font: .rm)
        case "exists":    return .atom("∃", .ord, font: .rm)
        case "neg","lnot": return .atom("¬", .ord, font: .rm)
        case "land":      return .atom("∧", .bin, font: .rm)
        case "lor":       return .atom("∨", .bin, font: .rm)
        case "ell":       return .atom("ℓ", .ord, font: .it)
        case "hbar":      return .atom("ℏ", .ord, font: .rm)
        case "Re":        return .atom("ℜ", .ord, font: .rm)
        case "Im":        return .atom("ℑ", .ord, font: .rm)
        case "ldots","dots": return .atom("…", .ord, font: .rm)
        case "cdots":     return .atom("⋯", .ord, font: .rm)
        case "vdots":     return .atom("⋮", .ord, font: .rm)
        case "ddots":     return .atom("⋱", .ord, font: .rm)
        case "prime":     return .atom("′", .ord, font: .rm)
        case "dagger":    return .atom("†", .bin, font: .rm)
        case "ddagger":   return .atom("‡", .bin, font: .rm)
        case "star":      return .atom("⋆", .bin, font: .rm)
        case "ast":       return .atom("∗", .bin, font: .rm)
        case "perp":      return .atom("⊥", .rel, font: .rm)
        case "parallel":  return .atom("∥", .rel, font: .rm)
        case "angle":     return .atom("∠", .ord, font: .rm)

        // Environments
        case "begin":
            return parseBeginEnv(src, idx: &idx)

        // Overline / underline decorators
        case "overline":
            let arg = parseBraceArg(src, idx: &idx)
            return .radical(degree: nil, body: arg)  // reuse radical for overline-like
        case "hat":
            let arg = parseBraceArg(src, idx: &idx)
            return .group([arg, .atom("̂", .ord, font: .rm)])
        case "tilde":
            let arg = parseBraceArg(src, idx: &idx)
            return .group([arg, .atom("̃", .ord, font: .rm)])
        case "bar":
            let arg = parseBraceArg(src, idx: &idx)
            return .group([arg, .atom("̄", .ord, font: .rm)])
        case "vec":
            let arg = parseBraceArg(src, idx: &idx)
            return .group([arg, .atom("⃗", .ord, font: .rm)])

        // Brackets as open/close
        case "langle": return .atom("⟨", .open, font: .rm)
        case "rangle": return .atom("⟩", .close, font: .rm)
        case "lfloor": return .atom("⌊", .open, font: .rm)
        case "rfloor": return .atom("⌋", .close, font: .rm)
        case "lceil":  return .atom("⌈", .open, font: .rm)
        case "rceil":  return .atom("⌉", .close, font: .rm)
        case "lbrace": return .atom("{", .open, font: .rm)
        case "rbrace": return .atom("}", .close, font: .rm)

        // Not
        case "not":
            if let next = parseNext(src, idx: &idx) { return .group([next, .atom("̸", .ord, font: .rm)]) }
            return nil

        default:
            // Unknown command → show as Roman text
            return .atom("\\\(cmd)", .ord, font: .rm)
        }
    }

    // MARK: - Helpers

    private static func parseLargeOp(_ name: String, src: String, idx: inout String.Index,
                                      limits: Bool = false) -> MathNode {
        // Look ahead for ^ and _
        var sub: MathNode? = nil
        var sup: MathNode? = nil
        while idx < src.endIndex && (src[idx] == "^" || src[idx] == "_" || src[idx] == " ") {
            if src[idx] == " " { advance(&idx, in: src); continue }
            let type = src[idx]; advance(&idx, in: src)
            let arg = parseBraceOrSingle(src, idx: &idx)
            if type == "^" { sup = arg }
            else { sub = arg }
        }
        return .largeOp(name: name, sub: sub, sup: sup, limits: limits)
    }

    private static func parseBraceArg(_ src: String, idx: inout String.Index) -> MathNode {
        skipSpaces(src, idx: &idx)
        if idx < src.endIndex && src[idx] == "{" {
            advance(&idx, in: src)
            let inner = parseGroup(src, idx: &idx)
            return inner.count == 1 ? inner[0] : .group(inner)
        }
        // Single char
        if idx < src.endIndex {
            let c = src[idx]; advance(&idx, in: src)
            if c.isLetter { return .atom(String(c), .ord, font: .it) }
            return .atom(String(c), .ord, font: .rm)
        }
        return .group([])
    }

    private static func parseBraceArgRaw(_ src: String, idx: inout String.Index) -> String {
        skipSpaces(src, idx: &idx)
        if idx < src.endIndex && src[idx] == "{" {
            advance(&idx, in: src)
            var r = ""
            while idx < src.endIndex && src[idx] != "}" {
                r.append(src[idx]); advance(&idx, in: src)
            }
            if idx < src.endIndex { advance(&idx, in: src) }
            return r
        }
        if idx < src.endIndex {
            let c = src[idx]; advance(&idx, in: src); return String(c)
        }
        return ""
    }

    private static func parseBraceOrSingle(_ src: String, idx: inout String.Index) -> MathNode {
        parseBraceArg(src, idx: &idx)
    }

    private static func parseScript(base: MathNode, src: String, idx: inout String.Index) -> MathNode {
        var sup: MathNode? = nil
        var sub: MathNode? = nil
        while idx < src.endIndex && (src[idx] == "^" || src[idx] == "_") {
            let t = src[idx]; advance(&idx, in: src)
            let arg = parseBraceArg(src, idx: &idx)
            if t == "^" { sup = arg } else { sub = arg }
        }
        return .script(base: base, sup: sup, sub: sub)
    }

    private static func parseDelim(_ src: String, idx: inout String.Index) -> String {
        skipSpaces(src, idx: &idx)
        guard idx < src.endIndex else { return "" }
        let c = src[idx]
        if c == "." { advance(&idx, in: src); return "" }
        if c == "\\" {
            advance(&idx, in: src)
            var cmd = ""
            while idx < src.endIndex && src[idx].isLetter {
                cmd.append(src[idx]); advance(&idx, in: src)
            }
            let delimMap = ["langle":"⟨","rangle":"⟩","lfloor":"⌊","rfloor":"⌋",
                            "lceil":"⌈","rceil":"⌉","lbrace":"{","rbrace":"}","|":"‖"]
            return delimMap[cmd] ?? cmd
        }
        let r = String(c); advance(&idx, in: src); return r
    }

    private static func parseBeginEnv(_ src: String, idx: inout String.Index) -> MathNode? {
        let env = parseBraceArgRaw(src, idx: &idx)
        var rows = [[MathNode]]()
        var currentRow = [MathNode]()
        var currentCell = [MathNode]()

        while idx < src.endIndex {
            if src[idx] == "\\" {
                let savedIdx = idx
                advance(&idx, in: src)
                var cmd = ""
                while idx < src.endIndex && src[idx].isLetter {
                    cmd.append(src[idx]); advance(&idx, in: src)
                }
                if cmd == "end" {
                    _ = parseBraceArgRaw(src, idx: &idx)
                    currentCell = currentCell.isEmpty ? currentCell : currentCell
                    currentRow.append(currentCell.count == 1 ? currentCell[0] : .group(currentCell))
                    rows.append(currentRow)
                    break
                }
                if src[idx] == "\\" {
                    // \\ = row separator
                    advance(&idx, in: src)
                    currentRow.append(currentCell.count == 1 ? currentCell[0] : .group(currentCell))
                    rows.append(currentRow)
                    currentRow = []
                    currentCell = []
                    continue
                }
                idx = savedIdx
            }
            if idx < src.endIndex && src[idx] == "&" {
                // Column separator
                currentRow.append(currentCell.count == 1 ? currentCell[0] : .group(currentCell))
                currentCell = []
                advance(&idx, in: src)
                continue
            }
            if let n = parseNext(src, idx: &idx) { currentCell.append(n) }
        }
        return .matrix(rows: rows, env: env)
    }

    private static func flattenToText(_ node: MathNode) -> MathNode {
        var s = ""
        func collect(_ n: MathNode) {
            switch n {
            case .atom(let t, _, _): s += t
            case .group(let ns): ns.forEach { collect($0) }
            case .text(let t): s += t
            default: break
            }
        }
        collect(node)
        return .text(s)
    }

    private static func singleCharSymbol(_ c: Character) -> (String, MathAtomType) {
        switch c {
        case "+": return ("+", .bin)
        case "-": return ("−", .bin)
        case "*": return ("*", .bin)
        case "/": return ("/", .bin)
        case "=": return ("=", .rel)
        case "<": return ("<", .rel)
        case ">": return (">", .rel)
        case "!": return ("!", .close)
        case "(": return ("(", .open)
        case ")": return (")", .close)
        case "[": return ("[", .open)
        case "]": return ("]", .close)
        case "|": return ("|", .open)
        case ",": return (",", .punct)
        case ";": return (";", .punct)
        case ":": return (":", .rel)
        default:  return (String(c), .ord)
        }
    }

    private static func advance(_ idx: inout String.Index, in str: String) {
        if idx < str.endIndex { idx = str.index(after: idx) }
    }

    private static func skipSpaces(_ str: String, idx: inout String.Index) {
        while idx < str.endIndex && str[idx] == " " { advance(&idx, in: str) }
    }
}
