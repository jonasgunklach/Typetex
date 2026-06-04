// main.swift — Render every LaTeX template with the native Swift engine
// and write typetex_<name>.pdf alongside the original .tex file.
// Usage: swift run generate-pdfs
//   (run from the workspace root: /path/to/Typetex)

import Foundation
import CoreGraphics
import PDFKit

// MARK: - Helpers (mirror ParityTestView logic)

func configureTypesetter(_ ts: TeXTypesetter, source: String) {
    let lo = source.lowercased()
    if lo.contains("sigconf") || lo.contains("acmart") {
        ts.geometry = .acmSigConf; ts.fonts = .timesACM; ts.documentClass = "acmart"
    } else if lo.contains("ieee") || lo.contains("ieeetran") {
        ts.geometry = .ieeeConference; ts.fonts = .timesIEEE; ts.documentClass = "IEEEtran"
    } else if lo.contains("lncs") || lo.contains("llncs") {
        ts.geometry = .lncs; ts.fonts = .timesLNCS; ts.documentClass = "llncs"
    } else {
        ts.geometry = .article; ts.fonts = .palatino; ts.documentClass = "article"
    }
}

func findBib(near dir: URL, source: String) -> String? {
    guard let r = source.range(of: "\\bibliography{") else { return nil }
    let after = source[r.upperBound...]
    let name  = String(after.prefix(while: { $0 != "}" }))
    let candidates = [
        dir.appendingPathComponent(name + ".bib").path,
        dir.appendingPathComponent(name).path,
        dir.appendingPathComponent("sample-base.bib").path,
    ]
    for p in candidates {
        if let txt = try? String(contentsOfFile: p, encoding: .utf8) { return txt }
    }
    return nil
}

// MARK: - Corpus discovery

struct TemplateEntry {
    let name:      String
    let texURL:    URL
    let source:    String
}

func discoverTemplates(workspaceRoot: URL) -> [TemplateEntry] {
    let fm = FileManager.default
    let searchDirs = [
        workspaceRoot.appendingPathComponent("templates/acm-chi/samples"),
        workspaceRoot.appendingPathComponent("templates/article"),
        workspaceRoot.appendingPathComponent("templates/ieee"),
        workspaceRoot.appendingPathComponent("templates/lncs"),
        workspaceRoot.appendingPathComponent("templates/beamer"),
    ]
    var entries: [TemplateEntry] = []
    for dir in searchDirs {
        guard let items = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
        for item in items.sorted() where item.hasSuffix(".tex") {
            let url = dir.appendingPathComponent(item)
            guard let src = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let name = item.replacingOccurrences(of: ".tex", with: "")
            entries.append(TemplateEntry(name: name, texURL: url, source: src))
        }
    }
    return entries
}

// MARK: - Main

let workspaceRoot: URL = {
    // When run via `swift run`, cwd is the package root
    URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
}()

print("Workspace: \(workspaceRoot.path)")
let templates = discoverTemplates(workspaceRoot: workspaceRoot)
print("Found \(templates.count) templates\n")

var succeeded = 0
var failed    = 0

for entry in templates {
    let t0 = Date()

    // 1. Parse
    let blocks = LaTeXParser.parseDocument(entry.source)

    // 2. Typeset
    let typesetter = TeXTypesetter()
    typesetter.sourceDirectory = entry.texURL.deletingLastPathComponent()
    configureTypesetter(typesetter, source: entry.source)

    // 3. Load bibliography if available
    if let bibText = findBib(near: entry.texURL.deletingLastPathComponent(), source: entry.source) {
        let resolver = CitationResolver()
        resolver.loadBibFile(bibText)
        typesetter.citationResolver = resolver
    }

    let doc = typesetter.typeset(blocks)
    let renderMs = Date().timeIntervalSince(t0) * 1000

    // 4. Export PDF
    let outURL = entry.texURL.deletingLastPathComponent()
        .appendingPathComponent("typetex_\(entry.name).pdf")

    if doc.pages.isEmpty {
        print("  ✗  \(entry.name): 0 pages — blocks=\(blocks.count) blockTypes=\(blocks.prefix(5).map { "\($0)" }.joined(separator: ", "))")
        failed += 1
    } else if let data = PDFExporter().export(doc, title: entry.name) {
        do {
            try data.write(to: outURL)
            let kb = data.count / 1024
            print(String(format: "  ✓  %-48s  %4d pages  %5.0f ms  %4d KB",
                         entry.name, doc.pages.count, renderMs, kb))
            succeeded += 1
        } catch {
            print("  ✗  \(entry.name): write failed – \(error)")
            failed += 1
        }
    } else {
        print("  ✗  \(entry.name): PDFExporter returned nil (0 pages?), pages=\(doc.pages.count)")
        failed += 1
    }
}

print("""

=== Done: \(succeeded) exported, \(failed) failed ===
PDFs written as typetex_<name>.pdf next to each .tex file.
""")
