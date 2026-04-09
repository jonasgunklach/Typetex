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

indirect enum TexBlock {
    case heading(level: Int, numbered: Bool, inlines: [TexInline])
    case paragraph([TexInline])
    case mathDisplay(String)
    case codeBlock(String)
    case bulletList(items: [[TexBlock]])
    case numberedList(items: [[TexBlock]])
    case blockQuote([TexBlock])
    case thematicBreak
    // New: document metadata & structure
    case documentMetadata(title: String, authors: [String], date: String?)
    case abstract([TexBlock])
    case titleBlock                               // marker: emit title+abstract here
    case table(header: [[TexInline]], rows: [[[TexInline]]], spec: String)
    case figure(src: String?, caption: [TexInline])
}

indirect enum TexInline {
    case text(String)
    case bold([TexInline])
    case italic([TexInline])
    case underline([TexInline])
    case strikethrough([TexInline])
    case code(String)
    case mathInline(String)
    case lineBreak
    case link(_ label: String, url: String)
    case footnote([TexInline])
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

    // MARK: - Document parsing → AST

    static func parseDocument(_ source: String) -> [TexBlock] {
        // Extract preamble for metadata
        let preamble: String
        let body: String
        if let s = source.range(of: "\\begin{document}"),
           let e = source.range(of: "\\end{document}") {
            preamble = String(source[..<s.lowerBound])
            body = String(source[s.upperBound..<e.lowerBound])
        } else {
            preamble = ""
            body = source
        }

        var blocks: [TexBlock] = []

        // Scan preamble for \title, \author, \date
        let title   = extractCommand("title",  from: preamble) ?? ""
        let author  = extractCommand("author", from: preamble)
        let date    = extractCommand("date",   from: preamble)
        let authors = author.map { [$0] } ?? []

        if !title.isEmpty || !authors.isEmpty {
            blocks.append(.documentMetadata(title: title, authors: authors, date: date))
        }

        // Parse body
        let bodyBlocks = parseBlocks(Substring(stripComments(body)))

        // Check if \maketitle or \begin{abstract} present; insert titleBlock marker
        let hasMaketitle = body.contains("\\maketitle")
        if hasMaketitle || (!title.isEmpty && !body.contains("\\maketitle")) {
            if !title.isEmpty {
                blocks.append(.titleBlock)
            }
        }

        blocks.append(contentsOf: bodyBlocks)
        return blocks
    }

    private static func extractCommand(_ cmd: String, from text: String) -> String? {
        guard let r = text.range(of: "\\\\\(cmd){", options: .regularExpression) ?? text.range(of: "\\\(cmd){") else { return nil }
        let after = text[r.upperBound...]
        var depth = 1
        var result = ""
        for ch in after {
            if ch == "{" { depth += 1; result.append(ch) }
            else if ch == "}" { depth -= 1; if depth == 0 { break } else { result.append(ch) } }
            else { result.append(ch) }
        }
        let stripped = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? nil : stripped
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
            if t.hasPrefix(cmd + "{") || t.hasPrefix(cmd + "*{") { return true }
        }
        return t.hasPrefix("\\begin{") || t.hasPrefix("\\[") || t.hasPrefix("$$")
            || t.hasPrefix("\\hline") || t.hasPrefix("\\hrule") || t.hasPrefix("\\newpage")
            || t.hasPrefix("\\clearpage")
    }

    private static func parseBlocks(_ input: Substring) -> [TexBlock] {
        var blocks: [TexBlock] = []
        var sc = input

        while !sc.isEmpty {
            sc = sc.drop(while: { $0 == "\n" })
            if sc.isEmpty { break }

            // Display math \[...\]
            if sc.hasPrefix("\\[") {
                let body = sc.dropFirst(2)
                if let r = body.range(of: "\\]") {
                    blocks.append(.mathDisplay(
                        String(body[..<r.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)))
                    sc = body[r.upperBound...]
                    continue
                }
            }

            // Display math $$...$$
            if sc.hasPrefix("$$") {
                let body = sc.dropFirst(2)
                if let r = body.range(of: "$$") {
                    blocks.append(.mathDisplay(
                        String(body[..<r.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)))
                    sc = body[r.upperBound...]
                    continue
                }
            }

            // Environments
            if sc.hasPrefix("\\begin{") {
                if let (block, rest) = parseEnvBlock(sc) {
                    blocks.append(block)
                    sc = rest
                    continue
                }
            }

            // Thematic breaks + maketitle
            if sc.hasPrefix("\\hline") || sc.hasPrefix("\\hrule")
                || sc.hasPrefix("\\newpage") || sc.hasPrefix("\\clearpage") {
                blocks.append(.thematicBreak)
                sc = sc.drop(while: { $0 != "\n" })
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
                if sc.hasPrefix(star + "{") || sc.hasPrefix(cmd + "{") {
                    let numbered = !sc.hasPrefix(star + "{")
                    let skip = sc.hasPrefix(star + "{") ? star.count : cmd.count
                    let rest = sc.dropFirst(skip)
                    if let (title, after) = extractBrace(rest) {
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
            let skipCmds = ["\\maketitle", "\\tableofcontents", "\\listoffigures",
                            "\\listoftables", "\\printbibliography"]
            var skipped = false
            for cmd in skipCmds {
                if sc.hasPrefix(cmd) {
                    sc = sc.drop(while: { $0 != "\n" })
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

    private static func parseEnvBlock(_ sc: Substring) -> (TexBlock, Substring)? {
        guard sc.hasPrefix("\\begin{") else { return nil }
        let nameStart = sc.dropFirst("\\begin{".count)
        guard let nameEnd = nameStart.firstIndex(of: "}") else { return nil }
        let name = String(nameStart[..<nameEnd])
        let afterOpen = nameStart[nameStart.index(after: nameEnd)...]

        guard let (body, rest) = findMatchingEnd(afterOpen, name: name) else { return nil }

        let block: TexBlock
        switch name {
        case "verbatim", "lstlisting", "minted", "Verbatim", "alltt":
            block = .codeBlock(String(body).trimmingCharacters(in: CharacterSet(charactersIn: "\n")))
        case "equation", "equation*", "align", "align*", "gather", "gather*",
             "multline", "multline*", "eqnarray", "eqnarray*", "math", "displaymath":
            block = .mathDisplay(String(body).trimmingCharacters(in: .whitespacesAndNewlines))
        case "itemize", "description":
            block = .bulletList(items: parseItems(body))
        case "enumerate":
            block = .numberedList(items: parseItems(body))
        case "abstract":
            block = .abstract(parseBlocks(body))
        case "quote", "quotation":
            block = .blockQuote(parseBlocks(body))
        case "figure", "figure*":
            // Try to extract \includegraphics and \caption
            let bodyStr = String(body)
            let src = extractCommand("includegraphics", from: bodyStr)
            let captionText = extractCommand("caption", from: bodyStr) ?? ""
            let captionInlines: [TexInline] = captionText.isEmpty ? [] : [.text(captionText)]
            block = .figure(src: src, caption: captionInlines)
        case "tabular", "tabular*", "tabulary", "tabularx", "longtable":
            // Parse the optional column spec and table rows
            var spec = ""
            var bodyRest = afterOpen
            // Skip optional size arg for tabular*
            if name == "tabular*" || name == "tabulary" || name == "tabularx",
               let (_, a2) = extractBrace(bodyRest) { bodyRest = a2 }
            if let (s, a2) = extractBrace(bodyRest) { spec = s; _ = a2 }
            block = parseTabular(body: body, spec: spec)
        default:
            let inner = parseBlocks(body)
            if inner.isEmpty { return (TexBlock.thematicBreak, rest) }
            block = inner.count == 1 ? inner[0] : .blockQuote(inner)
        }
        return (block, rest)
    }

    private static func parseTabular(body: Substring, spec: String) -> TexBlock {
        // Split body into rows by \\ or \hline
        let rowSeparators = ["\\\\", "\n"]
        var rows: [[[TexInline]]] = []
        var header: [[TexInline]] = []
        var isFirstRow = true

        let bodyStr = String(body)
        // Strip \hline and split by \\
        let cleaned = bodyStr
            .replacingOccurrences(of: "\\hline", with: "")
            .replacingOccurrences(of: "\\toprule", with: "")
            .replacingOccurrences(of: "\\midrule", with: "")
            .replacingOccurrences(of: "\\bottomrule", with: "")

        let tableRows = cleaned.components(separatedBy: "\\\\")
        for rowStr in tableRows {
            let t = rowStr.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            let cells = t.components(separatedBy: "&").map { cell -> [TexInline] in
                parseInlines(Substring(cell.trimmingCharacters(in: .whitespaces)))
            }
            if isFirstRow {
                header = cells
                isFirstRow = false
            } else {
                rows.append(cells)
            }
        }
        return .table(header: header, rows: rows, spec: spec)
    }

    private static func findMatchingEnd(_ input: Substring, name: String) -> (Substring, Substring)? {
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

    private static func parseItems(_ content: Substring) -> [[TexBlock]] {
        String(content).components(separatedBy: "\\item")
            .dropFirst()
            .compactMap { part -> [TexBlock]? in
                let t = part.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !t.isEmpty else { return nil }
                return parseBlocks(Substring(t))
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

            // Em/en dashes
            if sc.hasPrefix("---") { buf += "\u{2014}"; sc = sc.dropFirst(3); continue }
            if sc.hasPrefix("--")  { buf += "\u{2013}"; sc = sc.dropFirst(2); continue }

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
                case "underline":
                    if let (a, r) = extractBrace(afterName) {
                        flush(); result.append(.underline(parseInlines(Substring(a)))); sc = r; continue
                    }
                case "sout", "st":
                    if let (a, r) = extractBrace(afterName) {
                        flush(); result.append(.strikethrough(parseInlines(Substring(a)))); sc = r; continue
                    }
                case "texttt":
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
                    if let (_, a2) = extractBrace(afterName), let (txt, r) = extractBrace(a2) {
                        flush(); result.append(contentsOf: parseInlines(Substring(txt))); sc = r; continue
                    }
                case "mbox", "hbox", "text", "textrm", "textnormal", "textsc", "textup":
                    if let (a, r) = extractBrace(afterName) {
                        flush(); result.append(contentsOf: parseInlines(Substring(a))); sc = r; continue
                    }
                case "noindent", "newline", "par":
                    flush(); result.append(.lineBreak); sc = afterName; continue
                case "LaTeX":
                    buf += "LaTeX"; sc = afterName; continue
                case "TeX":
                    buf += "TeX"; sc = afterName; continue
                case "ldots", "dots", "cdots":
                    buf += "\u{2026}"; sc = afterName; continue
                case "mdash":
                    buf += "\u{2014}"; sc = afterName; continue
                case "ndash":
                    buf += "\u{2013}"; sc = afterName; continue
                case "":
                    break  // bare backslash — fall through to consume char
                default:
                    // Unknown command: skip optional args silently
                    var rest = afterName
                    if rest.first == "[", let end = rest.firstIndex(of: "]") {
                        rest = rest[rest.index(after: end)...]
                    }
                    if rest.first == "{" { if let (_, r) = extractBrace(rest) { rest = r } }
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
        guard input.first == "{" else { return nil }
        var sc    = input.dropFirst()
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
}
