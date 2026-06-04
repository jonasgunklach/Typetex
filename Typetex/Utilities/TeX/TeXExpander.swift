// TeXExpander.swift — Macro expansion and preamble processing
// Handles \newcommand, \def, \newenvironment, \usepackage, counters, and
// basic conditionals. Returns an expanded source string plus parsed preamble
// metadata consumed by the pipeline.
import Foundation

// MARK: - Macro definition

struct MacroDef {
    let arity: Int           // number of required args #1..#n
    let optDefault: String?  // default value for optional first arg (nil = no opt arg)
    let body: String         // template with #1, #2, …
}

struct EnvironmentDef {
    let arity: Int
    let optDefault: String?
    let beginCode: String    // inserted at \begin{name}
    let endCode: String      // inserted at \end{name}
}

// MARK: - Preamble metadata

struct LaTeXPreamble {
    var documentClass: String = "article"
    var documentClassOptions: [String] = []
    var packages: [(name: String, options: String)] = []
    var title: String = ""
    var authors: [String] = []
    var date: String = ""
    var isTwoColumn: Bool = false
    var isACM: Bool = false
    var isIEEE: Bool = false
    var isLNCS: Bool = false
    var isBeamer: Bool = false
    var paperWidth: Double? = nil   // pts, from geometry package
    var paperHeight: Double? = nil
    var marginTop: Double? = nil
    var marginBottom: Double? = nil
    var marginLeft: Double? = nil
    var marginRight: Double? = nil
}

// MARK: - Main expander

final class TeXExpander {

    // Built-in macro tables (populated from preamble)
    private(set) var macros: [String: MacroDef] = [:]
    private(set) var environments: [String: EnvironmentDef] = [:]
    private(set) var counters: [String: Int] = [:]
    private(set) var preamble = LaTeXPreamble()

    /// Register a macro from outside (e.g. from PackageRegistry)
    func registerMacro(_ name: String, def: MacroDef) { macros[name] = def }
    func registerEnvironment(_ name: String, def: EnvironmentDef) { environments[name] = def }

    // Configurable recursion depth guard
    private var expansionDepth = 0
    private let maxDepth = 20

    // MARK: - Entry point

    /// Expand the full source: parses preamble, registers macros, expands body.
    func expand(_ source: String) -> (expanded: String, preamble: LaTeXPreamble) {
        macros = [:]
        environments = [:]
        counters = [:]
        preamble = LaTeXPreamble()

        // 1. Split into preamble / body
        let (preambText, bodyText) = splitDocument(source)

        // 2. Parse preamble: document class, packages, macro definitions
        parsePreamble(preambText)

        // 3. Expand macros in the body
        let expandedBody = expandSource(bodyText)

        // 4. Reconstruct full document
        let result = preambText + "\n\\begin{document}\n" + expandedBody + "\n\\end{document}"
        return (result, preamble)
    }

    // MARK: - Document splitting

    private func splitDocument(_ src: String) -> (preamble: String, body: String) {
        if let beginRange = src.range(of: "\\begin{document}") {
            let preamb = String(src[..<beginRange.lowerBound])
            let afterBegin = src[beginRange.upperBound...]
            let body: String
            if let endRange = afterBegin.range(of: "\\end{document}") {
                body = String(afterBegin[..<endRange.lowerBound])
            } else {
                body = String(afterBegin)
            }
            return (preamb, body)
        }
        return ("", src)
    }

    // MARK: - Preamble parsing

    private func parsePreamble(_ text: String) {
        // Document class
        extractDocumentClass(text)
        // Package declarations
        extractPackages(text)
        // Macro definitions
        extractMacroDefinitions(text)
        // Extract metadata commands
        extractMetadata(text)
    }

    private func extractDocumentClass(_ text: String) {
        let pattern = #"\\documentclass\s*(?:\[([^\]]*)\])?\s*\{([^}]+)\}"#
        guard let rx = try? NSRegularExpression(pattern: pattern),
              let m = rx.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return }
        if m.numberOfRanges > 2, let r = Range(m.range(at: 2), in: text) {
            preamble.documentClass = String(text[r]).trimmingCharacters(in: .whitespaces)
        }
        if m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: text) {
            let opts = String(text[r]).components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            preamble.documentClassOptions = opts
            preamble.isTwoColumn = opts.contains("twocolumn") || opts.contains("sigconf") ||
                opts.contains("sigplan") || opts.contains("acmlarge") || opts.contains("conference")
        }
        let cls = preamble.documentClass.lowercased()
        preamble.isACM   = cls.hasPrefix("acmart") || cls == "sig-alternate"
        preamble.isIEEE  = cls.hasPrefix("ieee")
        preamble.isLNCS  = cls == "llncs"
        preamble.isBeamer = cls == "beamer"
        // ACM twocolumn classes
        if preamble.isACM {
            let acmTwoCol = ["sigconf", "sigplan", "acmsmall", "acmlarge", "acmtog"]
            if acmTwoCol.contains(where: { preamble.documentClassOptions.contains($0) }) {
                preamble.isTwoColumn = true
            }
        }
    }

    private func extractPackages(_ text: String) {
        let pattern = #"\\usepackage\s*(?:\[([^\]]*)\])?\s*\{([^}]+)\}"#
        guard let rx = try? NSRegularExpression(pattern: pattern) else { return }
        let range = NSRange(text.startIndex..., in: text)
        for m in rx.matches(in: text, range: range) {
            let opts = m.numberOfRanges > 1 ? (Range(m.range(at: 1), in: text).map { String(text[$0]) } ?? "") : ""
            guard let pkgRange = Range(m.range(at: 2), in: text) else { continue }
            let pkgList = text[pkgRange].components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            for pkg in pkgList {
                preamble.packages.append((name: pkg, options: opts))
                // Handle geometry options inline
                if pkg == "geometry" && !opts.isEmpty {
                    parseGeometryOptions(opts)
                }
            }
        }
    }

    private func parseGeometryOptions(_ opts: String) {
        // e.g. "margin=2.5cm", "top=1in, left=2cm", "a4paper"
        let ptPerCm = 28.3465
        let ptPerIn = 72.0
        func toPts(_ s: String) -> Double? {
            let trimmed = s.trimmingCharacters(in: .whitespaces)
            if trimmed.hasSuffix("cm"), let v = Double(trimmed.dropLast(2)) { return v * ptPerCm }
            if trimmed.hasSuffix("in"), let v = Double(trimmed.dropLast(2)) { return v * ptPerIn }
            if trimmed.hasSuffix("mm"), let v = Double(trimmed.dropLast(2)) { return v * ptPerCm / 10 }
            if trimmed.hasSuffix("pt"), let v = Double(trimmed.dropLast(2)) { return v }
            if let v = Double(trimmed) { return v }
            return nil
        }
        let parts = opts.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        for part in parts {
            if part == "a4paper" { preamble.paperWidth = 595.28; preamble.paperHeight = 841.89 }
            else if part == "letterpaper" { preamble.paperWidth = 612; preamble.paperHeight = 792 }
            else if part.hasPrefix("margin="), let v = toPts(String(part.dropFirst(7))) {
                preamble.marginTop = v; preamble.marginBottom = v
                preamble.marginLeft = v; preamble.marginRight = v
            }
            else if part.hasPrefix("top="), let v = toPts(String(part.dropFirst(4))) { preamble.marginTop = v }
            else if part.hasPrefix("bottom="), let v = toPts(String(part.dropFirst(7))) { preamble.marginBottom = v }
            else if part.hasPrefix("left="), let v = toPts(String(part.dropFirst(5))) { preamble.marginLeft = v }
            else if part.hasPrefix("right="), let v = toPts(String(part.dropFirst(6))) { preamble.marginRight = v }
            else if part.hasPrefix("hmargin="), let v = toPts(String(part.dropFirst(8))) {
                preamble.marginLeft = v; preamble.marginRight = v
            }
            else if part.hasPrefix("vmargin="), let v = toPts(String(part.dropFirst(8))) {
                preamble.marginTop = v; preamble.marginBottom = v
            }
        }
    }

    private func extractMetadata(_ text: String) {
        preamble.title   = extractCommand("title",  from: text) ?? ""
        preamble.date    = extractCommand("date",   from: text) ?? ""
        if let a = extractCommand("author", from: text) {
            // Split multi-author by \and
            preamble.authors = a.components(separatedBy: "\\and")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        if preamble.isACM {
            // ACM uses repeated \author{} calls
            extractACMAuthors(text)
        }
    }

    private func extractACMAuthors(_ text: String) {
        let pattern = #"\\author\{([^}]+)\}"#
        guard let rx = try? NSRegularExpression(pattern: pattern) else { return }
        var authors: [String] = []
        for m in rx.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            if let r = Range(m.range(at: 1), in: text) {
                authors.append(String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        if !authors.isEmpty { preamble.authors = authors }
    }

    // MARK: - Macro definition extraction

    func extractMacroDefinitions(_ text: String) {
        var scanner = StringScanner(text)
        while !scanner.isAtEnd {
            scanner.skipTo("\\")
            guard !scanner.isAtEnd else { break }
            scanner.advance() // consume \
            let cmdName = scanner.scanName()
            switch cmdName {
            case "newcommand", "renewcommand", "providecommand":
                parseNewcommand(named: cmdName, scanner: &scanner)
            case "def":
                parseDef(scanner: &scanner)
            case "newenvironment", "renewenvironment":
                parseNewenvironment(named: cmdName, scanner: &scanner)
            case "newcounter":
                if let (name, _) = scanner.scanBrace() {
                    counters[name] = 0
                }
            case "setcounter":
                if let (name, _) = scanner.scanBrace(),
                   let (valStr, _) = scanner.scanBrace(),
                   let val = Int(valStr.trimmingCharacters(in: .whitespaces)) {
                    counters[name] = val
                }
            default:
                break
            }
        }
        // Register built-in counter-based macros
        registerCounterAccessors()
    }

    private func parseNewcommand(named: String, scanner: inout StringScanner) {
        // \newcommand{\name}[n][default]{body}
        // or \newcommand\name{body}
        var csName: String
        scanner.skipWhitespace()
        if scanner.peek() == "{" {
            guard let (inner, _) = scanner.scanBrace() else { return }
            csName = inner.hasPrefix("\\") ? String(inner.dropFirst()) : inner
        } else if scanner.peek() == "\\" {
            scanner.advance()
            csName = scanner.scanName()
        } else { return }
        csName = csName.trimmingCharacters(in: .whitespaces)

        scanner.skipWhitespace()
        var arity = 0
        var optDefault: String? = nil
        // Optional arity [n]
        if scanner.peek() == "[" {
            scanner.advance()
            let arityStr = scanner.scanUntil("]")
            scanner.advance() // consume ]
            arity = Int(arityStr.trimmingCharacters(in: .whitespaces)) ?? 0
        }
        // Optional default [default]
        scanner.skipWhitespace()
        if scanner.peek() == "[" {
            scanner.advance()
            optDefault = scanner.scanUntil("]")
            scanner.advance()
        }
        // Body
        guard let (body, _) = scanner.scanBrace() else { return }
        let def = MacroDef(arity: arity, optDefault: optDefault, body: body)
        if named == "newcommand" || named == "renewcommand" {
            macros[csName] = def
        } else { // providecommand: only define if not already defined
            if macros[csName] == nil { macros[csName] = def }
        }
    }

    private func parseDef(scanner: inout StringScanner) {
        // \def\cmdname{body}  or  \def\cmdname#1{body}
        scanner.skipWhitespace()
        guard scanner.peek() == "\\" else { return }
        scanner.advance()
        let csName = scanner.scanName()
        scanner.skipWhitespace()
        // Count parameters #1 .. #9
        var arity = 0
        while scanner.peek() == "#" {
            scanner.advance() // #
            if let c = scanner.peek(), c.isNumber { scanner.advance(); arity += 1 }
        }
        guard let (body, _) = scanner.scanBrace() else { return }
        macros[csName] = MacroDef(arity: arity, optDefault: nil, body: body)
    }

    private func parseNewenvironment(named: String, scanner: inout StringScanner) {
        // \newenvironment{name}[n][default]{begin}{end}
        guard let (envName, _) = scanner.scanBrace() else { return }
        scanner.skipWhitespace()
        var arity = 0
        var optDefault: String? = nil
        if scanner.peek() == "[" {
            scanner.advance()
            arity = Int(scanner.scanUntil("]").trimmingCharacters(in: .whitespaces)) ?? 0
            scanner.advance()
        }
        scanner.skipWhitespace()
        if scanner.peek() == "[" {
            scanner.advance()
            optDefault = scanner.scanUntil("]")
            scanner.advance()
        }
        guard let (beginCode, _) = scanner.scanBrace(),
              let (endCode, _)   = scanner.scanBrace() else { return }
        let def = EnvironmentDef(arity: arity, optDefault: optDefault,
                                 beginCode: beginCode, endCode: endCode)
        environments[envName] = def
    }

    private func registerCounterAccessors() {
        // \the<counter> returns current counter value
        for (name, val) in counters {
            macros["the\(name)"] = MacroDef(arity: 0, optDefault: nil, body: "\(val)")
        }
    }

    // MARK: - Source expansion

    func expandSource(_ src: String) -> String {
        expansionDepth = 0
        return expandString(src)
    }

    private func expandString(_ src: String) -> String {
        guard !src.isEmpty else { return src }
        expansionDepth += 1
        defer { expansionDepth -= 1 }
        guard expansionDepth <= maxDepth else { return src }

        var result = ""
        var scanner = StringScanner(src)
        while !scanner.isAtEnd {
            if scanner.peek() == "%" {
                // Consume comment
                let comment = scanner.scanLine()
                result += comment + "\n"
                continue
            }
            if scanner.peek() == "\\" {
                scanner.advance()
                let name = scanner.scanName()
                if name.isEmpty {
                    result += "\\"
                    if let c = scanner.peek() { result += String(c); scanner.advance() }
                    continue
                }
                if let def = macros[name] {
                    let expansion = applyMacro(def, scanner: &scanner)
                    // Re-expand the result (for nested macros)
                    result += expandString(expansion)
                } else {
                    // Keep unknown commands verbatim (they'll be handled by the parser)
                    result += "\\" + name
                }
            } else {
                let c = scanner.peek()!
                result += String(c)
                scanner.advance()
            }
        }
        return result
    }

    private func applyMacro(_ def: MacroDef, scanner: inout StringScanner) -> String {
        var args: [String] = []
        scanner.skipWhitespace()

        // Collect optional arg if macro expects one
        if def.optDefault != nil {
            if scanner.peek() == "[" {
                scanner.advance()
                let val = scanner.scanBraceOrBracket(close: "]")
                scanner.skipIf("]")
                args.append(val)
            } else {
                args.append(def.optDefault!)
            }
        }
        // Collect required args
        for _ in 0..<def.arity {
            scanner.skipWhitespace()
            if scanner.peek() == "{" {
                let (val, _) = scanner.scanBrace() ?? ("", Substring(""))
                args.append(val)
            } else if let c = scanner.peek() {
                args.append(String(c)); scanner.advance()
            }
        }
        // Substitute #1, #2, ... in body
        var body = def.body
        for (i, arg) in args.enumerated() {
            body = body.replacingOccurrences(of: "#\(i + 1)", with: arg)
        }
        return body
    }

    // MARK: - Helper: extract command argument from text

    private func extractCommand(_ cmd: String, from text: String) -> String? {
        let pattern = #"\\\#(cmd)\s*\{"#.replacingOccurrences(of: "#(cmd)", with: cmd)
        // Manual extraction is safer
        guard let range = text.range(of: "\\\(cmd){") ?? text.range(of: "\\\(cmd) {") else { return nil }
        let after = text[range.upperBound...]
        var depth = 1; var result = ""
        for ch in after {
            if ch == "{" { depth += 1; result.append(ch) }
            else if ch == "}" { depth -= 1; if depth == 0 { break } else { result.append(ch) } }
            else { result.append(ch) }
        }
        let stripped = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? nil : stripped
    }
}

// MARK: - StringScanner (lightweight string cursor)

struct StringScanner {
    private let str: String
    private(set) var index: String.Index

    init(_ s: String) { str = s; index = s.startIndex }

    var isAtEnd: Bool { index >= str.endIndex }

    func peek() -> Character? {
        guard !isAtEnd else { return nil }
        return str[index]
    }

    mutating func advance() {
        guard !isAtEnd else { return }
        str.formIndex(after: &index)
    }

    mutating func skipWhitespace() {
        while !isAtEnd, str[index].isWhitespace { advance() }
    }

    mutating func skipIf(_ c: Character) {
        if !isAtEnd && str[index] == c { advance() }
    }

    /// Scan a TeX command name (letters only)
    mutating func scanName() -> String {
        var name = ""
        while !isAtEnd, str[index].isLetter { name.append(str[index]); advance() }
        // For single non-letter commands like \, \- etc.
        if name.isEmpty, !isAtEnd {
            let c = str[index]; advance()
            return String(c)
        }
        return name
    }

    /// Scan until character, without consuming it
    mutating func scanUntil(_ target: Character) -> String {
        var result = ""
        while !isAtEnd, str[index] != target { result.append(str[index]); advance() }
        return result
    }

    /// Scan to end of current line
    mutating func scanLine() -> String {
        var result = ""
        while !isAtEnd, str[index] != "\n" { result.append(str[index]); advance() }
        if !isAtEnd { advance() } // consume \n
        return result
    }

    /// Skip to the next occurrence of a character
    mutating func skipTo(_ target: Character) {
        while !isAtEnd, str[index] != target { advance() }
    }

    /// Scan a balanced brace group {…}, returning (content, remaining_substring)
    mutating func scanBrace() -> (String, Substring)? {
        skipWhitespace()
        guard !isAtEnd, str[index] == "{" else { return nil }
        advance() // consume {
        var depth = 1; var result = ""
        while !isAtEnd {
            let c = str[index]; advance()
            if c == "\\" {
                result.append(c)
                if !isAtEnd { result.append(str[index]); advance() }
                continue
            }
            if c == "{" { depth += 1; result.append(c) }
            else if c == "}" { depth -= 1; if depth == 0 { break } else { result.append(c) } }
            else { result.append(c) }
        }
        return (result, str[index...])
    }

    /// Scan a balanced brace or bracket group, up to matching close
    mutating func scanBraceOrBracket(close: Character) -> String {
        var result = ""; var depth = 0
        while !isAtEnd {
            let c = str[index]; advance()
            if c == "{" { depth += 1; result.append(c) }
            else if c == "}" { depth -= 1; if depth < 0 { break } else { result.append(c) } }
            else if c == close && depth == 0 { break }
            else { result.append(c) }
        }
        return result
    }
}
