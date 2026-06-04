// BibTeXParser.swift — Parse .bib database files into structured BibEntry records
import Foundation

// MARK: - BibEntry

struct BibEntry: Identifiable {
    let id: String                // cite key
    var type: String              // article, inproceedings, book, etc.
    var fields: [String: String]  // lowercased field name → value

    // Convenience accessors
    var title:   String { fields["title"]   ?? "" }
    var authors: [String] {
        let raw = fields["author"] ?? ""
        if raw.isEmpty { return [] }
        return raw.components(separatedBy: " and ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    var year:    String { fields["year"]    ?? "" }
    var journal: String { fields["journal"] ?? fields["booktitle"] ?? "" }
    var volume:  String { fields["volume"]  ?? "" }
    var number:  String { fields["number"]  ?? "" }
    var pages:   String { fields["pages"]   ?? "" }
    var doi:     String { fields["doi"]     ?? "" }
    var url:     String { fields["url"]     ?? "" }
    var note:    String { fields["note"]    ?? "" }
    var publisher: String { fields["publisher"] ?? "" }
}

// MARK: - BibTeX parser

final class BibTeXParser {

    var entries: [String: BibEntry] = [:]
    var strings: [String: String]   = [:]  // @string macros

    // MARK: - Entry point

    func parse(_ source: String) {
        var scanner = StringScanner(source)
        while !scanner.isAtEnd {
            scanner.skipTo("@")
            guard !scanner.isAtEnd else { break }
            scanner.advance()  // consume @
            let entryType = scanner.scanName().lowercased()
            scanner.skipWhitespace()
            guard scanner.peek() == "{" || scanner.peek() == "(" else { continue }
            let closeDelim: Character = scanner.peek() == "{" ? "}" : ")"
            scanner.advance()  // consume open delimiter
            scanner.skipWhitespace()
            switch entryType {
            case "string":
                parseString(&scanner)
            case "comment", "preamble":
                _ = scanner.scanUntil(closeDelim)
                scanner.advance()
            default:
                parseEntry(type: entryType, scanner: &scanner, closeDelim: closeDelim)
            }
        }
    }

    // MARK: - String macro

    private func parseString(_ scanner: inout StringScanner) {
        scanner.skipWhitespace()
        let key = scanner.scanName().lowercased()
        scanner.skipWhitespace()
        if scanner.peek() == "=" { scanner.advance() }
        scanner.skipWhitespace()
        if let value = parseFieldValue(&scanner) {
            strings[key] = value
        }
    }

    // MARK: - Entry

    private func parseEntry(type: String, scanner: inout StringScanner, closeDelim: Character) {
        scanner.skipWhitespace()
        // Cite key — scan until , or closeDelim
        var key = ""
        while !scanner.isAtEnd {
            guard let c = scanner.peek() else { break }
            if c == "," || c == closeDelim || c.isWhitespace { break }
            key.append(c); scanner.advance()
        }
        key = key.trimmingCharacters(in: .whitespaces)
        if key.isEmpty { return }
        scanner.skipWhitespace()
        if scanner.peek() == "," { scanner.advance() }

        var fields: [String: String] = [:]
        while !scanner.isAtEnd {
            scanner.skipWhitespace()
            guard let c = scanner.peek(), c != "}" && c != ")" else { break }
            if c == "," { scanner.advance(); continue }
            // Field name
            let fieldName = scanner.scanFieldName().lowercased()
            if fieldName.isEmpty { scanner.advance(); continue }
            scanner.skipWhitespace()
            if scanner.peek() == "=" { scanner.advance() }
            scanner.skipWhitespace()
            if let val = parseFieldValue(&scanner) {
                fields[fieldName] = delatexify(val)
            }
        }
        if scanner.peek() == "}" || scanner.peek() == ")" { scanner.advance() }

        var entry = BibEntry(id: key, type: type, fields: fields)
        entries[key] = entry
    }

    // MARK: - Field value parsing

    private func parseFieldValue(_ scanner: inout StringScanner) -> String? {
        var parts: [String] = []
        while !scanner.isAtEnd {
            scanner.skipWhitespace()
            guard let c = scanner.peek() else { break }
            if c == "," || c == "}" || c == ")" { break }
            if c == "\"" {
                scanner.advance()  // open quote
                var val = ""
                var depth = 0
                while !scanner.isAtEnd {
                    let ch = scanner.peek()!
                    if ch == "\\" { val.append(ch); scanner.advance(); if !scanner.isAtEnd { val.append(scanner.peek()!); scanner.advance() }; continue }
                    if ch == "{" { depth += 1; val.append(ch); scanner.advance(); continue }
                    if ch == "}" { depth -= 1; if depth < 0 { break }; val.append(ch); scanner.advance(); continue }
                    if ch == "\"" && depth == 0 { scanner.advance(); break }
                    val.append(ch); scanner.advance()
                }
                parts.append(val)
            } else if c == "{" {
                if let (inner, _) = scanner.scanBrace() {
                    parts.append(inner)
                }
            } else if c == "#" {
                scanner.advance()  // concatenation operator
            } else {
                // Bare name — string macro reference
                let name = scanner.scanFieldName().lowercased()
                if let expanded = strings[name] { parts.append(expanded) }
                else { parts.append(name) }
            }
        }
        return parts.isEmpty ? nil : parts.joined()
    }

    /// Remove LaTeX formatting from a field value for display
    static func delatexify(_ s: String) -> String {
        var result = s
        // Common LaTeX commands → plain text
        let replacements: [(String, String)] = [
            ("\\textbf{", ""), ("\\textit{", ""), ("\\emph{", ""),
            ("\\texttt{", ""), ("\\textrm{", ""), ("\\textsc{", ""),
            ("---", "—"), ("--", "–"),
            ("``", "\u{201C}"), ("''", "\u{201D}"),
            ("`", "\u{2018}"), ("'", "\u{2019}"),
            ("\\LaTeX", "LaTeX"), ("\\TeX", "TeX"),
            ("\\ldots", "…"), ("\\dots", "…"),
            ("{", ""), ("}", ""),
        ]
        for (from, to) in replacements {
            result = result.replacingOccurrences(of: from, with: to)
        }
        // Strip remaining \commands
        if let rx = try? NSRegularExpression(pattern: #"\\[a-zA-Z]+"#) {
            result = rx.stringByReplacingMatches(in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: "")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func delatexify(_ s: String) -> String { BibTeXParser.delatexify(s) }
}

// MARK: - StringScanner extension for bibtex field names

extension StringScanner {
    mutating func scanFieldName() -> String {
        var name = ""
        while !isAtEnd {
            let c = peek()!
            if c.isLetter || c.isNumber || c == "_" || c == "-" { name.append(c); advance() }
            else { break }
        }
        return name
    }
}

// MARK: - Citation Resolver

final class CitationResolver {

    /// Ordered list of loaded bib entries (insertion order = declaration order)
    private(set) var bibliography: [String: BibEntry] = [:]
    private(set) var citationOrder: [String] = []   // keys in order first cited
    private var nextNumber: Int = 1

    func loadBibFile(_ content: String) {
        let parser = BibTeXParser()
        parser.parse(content)
        for (key, entry) in parser.entries { bibliography[key] = entry }
    }

    /// Returns citation label for a cite key, registering it if first encounter.
    /// Returns something like "[1]" or "[Smith2023]".
    func resolveCite(key: String, style: CitationStyle = .numeric) -> String {
        if let idx = citationOrder.firstIndex(of: key) {
            return label(for: key, number: idx + 1, style: style)
        }
        let num = nextNumber; nextNumber += 1
        citationOrder.append(key)
        return label(for: key, number: num, style: style)
    }

    func resolveCites(keys: [String], style: CitationStyle = .numeric) -> String {
        let labels = keys.map { resolveCite(key: $0, style: style) }
        return "[" + labels.map { s in
            // strip brackets if numeric
            s.hasPrefix("[") && s.hasSuffix("]") ? String(s.dropFirst().dropLast()) : s
        }.joined(separator: ",") + "]"
    }

    private func label(for key: String, number: Int, style: CitationStyle) -> String {
        switch style {
        case .numeric:
            return "[\(number)]"
        case .authorYear:
            guard let entry = bibliography[key] else { return "[\(key)]" }
            let lastName = entry.authors.first?.components(separatedBy: ",").first
                ?? entry.authors.first?.components(separatedBy: " ").last ?? key
            return "[\(lastName), \(entry.year)]"
        case .alpha:
            guard let entry = bibliography[key] else { return "[\(key)]" }
            let lastName = String((entry.authors.first?.components(separatedBy: ",").first ?? key).prefix(3))
            return "[\(lastName)\(String(entry.year.suffix(2)))]"
        }
    }

    /// Generate the bibliography section text
    func formattedBibliography(style: CitationStyle = .numeric) -> [(label: String, text: String)] {
        var items: [(label: String, text: String)] = []
        for (idx, key) in citationOrder.enumerated() {
            guard let entry = bibliography[key] else { continue }
            let lbl = label(for: key, number: idx + 1, style: style)
            let text = formatEntry(entry, number: idx + 1)
            items.append((label: lbl, text: text))
        }
        return items
    }

    private func formatEntry(_ e: BibEntry, number: Int) -> String {
        var parts: [String] = []
        let authors = e.authors.isEmpty ? "" : e.authors.map { formatAuthor($0) }.joined(separator: ", ")
        if !authors.isEmpty {
            // Trim trailing period from author string to avoid double-period with separator
            parts.append(authors.hasSuffix(".") ? String(authors.dropLast()) : authors)
        }
        if !e.title.isEmpty { parts.append("\"\(e.title)\"") }
        if !e.journal.isEmpty { parts.append("In \(e.journal)") }
        if !e.publisher.isEmpty { parts.append(e.publisher) }
        if !e.volume.isEmpty {
            var v = "vol. \(e.volume)"
            if !e.number.isEmpty { v += ", no. \(e.number)" }
            parts.append(v)
        }
        if !e.pages.isEmpty { parts.append("pp. \(e.pages)") }
        if !e.year.isEmpty { parts.append(e.year) }
        return parts.joined(separator: ". ") + "."
    }

    private func formatAuthor(_ a: String) -> String {
        let parts = a.components(separatedBy: ", ")
        if parts.count >= 2 {
            let last = parts[0]; let first = parts[1]
            let initials = first.components(separatedBy: " ").compactMap { $0.first }.map { "\($0)." }.joined(separator: " ")
            return "\(last), \(initials)"
        }
        let words = a.components(separatedBy: " ").filter { !$0.isEmpty }
        if words.count >= 2 {
            let last = words.last!
            let initials = words.dropLast().compactMap { $0.first }.map { "\($0)." }.joined(separator: " ")
            return "\(last), \(initials)"
        }
        return a
    }
}

enum CitationStyle {
    case numeric        // [1], [2], …
    case authorYear     // [Smith, 2023]
    case alpha          // [Smi23]
}
