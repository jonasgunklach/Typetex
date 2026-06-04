//
//  EditorViewModel.swift
//  Typetex
//

import SwiftUI
import Foundation

// MARK: - Compile state

enum CompileState: Equatable {
    case idle
    case compiling
    case success(Date)
    case failed(Date)
}

// MARK: - View model

@Observable
final class EditorViewModel {

    // Current document (optional — nil when none selected)
    private(set) var document: LaTeXDocument?

    // Parsed state
    var outlineItems: [OutlineItem] = []
    var todoItems: [TodoItem] = []
    var compileMessages: [CompileMessage] = []

    // Compilation
    var compileState: CompileState = .idle
    var renderedDocument: [TexBlock] = []
    var typesetDocument: TypesetDocument = .empty

    // Word count (updated on reparse)
    var wordCount: Int = 0

    // Editor preferences (mirrored from AppStorage)
    var fontSize:      Double = 15
    var fontFamily:    String = ""        // "" = system monospaced
    var themeName:     String = "default"
    var showLineNumbers: Bool = true

    private var reparseTask: Task<Void, Never>?

    init() {}

    // MARK: - Document management

    func setDocument(_ doc: LaTeXDocument?) {
        reparseTask?.cancel()
        document = doc
        if let doc {
            // Workspace file: refresh content from disk, then reparse
            if let workspace = doc.workspace, let relativePath = doc.relativePath {
                let bookmarkData = workspace.bookmarkData
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let fresh = Self.readFromDisk(bookmarkData: bookmarkData, relativePath: relativePath),
                       fresh != doc.content {
                        doc.content    = fresh
                        doc.modifiedAt = Date()
                    }
                    self.reparse()
                }
            } else {
                reparse()
            }
        } else {
            outlineItems    = []
            todoItems       = []
            compileMessages   = []
            compileState     = .idle
            renderedDocument = []
        }
    }

    // Called by the editor when text changes
    func contentChanged(_ newContent: String) {
        guard let doc = document else { return }
        doc.content    = newContent
        doc.modifiedAt = Date()
        // Write back to disk for workspace files
        if let workspace = doc.workspace, let relativePath = doc.relativePath {
            let bookmarkData = workspace.bookmarkData
            Task.detached {
                Self.writeToDisk(bookmarkData: bookmarkData, relativePath: relativePath, content: newContent)
            }
        }
        scheduleReparse()
    }

    // MARK: - Disk helpers (static, safe to call off-thread)

    private static func readFromDisk(bookmarkData: Data, relativePath: String) -> String? {
        var isStale = false
#if os(macOS)
        guard let folderURL = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        guard folderURL.startAccessingSecurityScopedResource() else { return nil }
        defer { folderURL.stopAccessingSecurityScopedResource() }
#else
        guard let folderURL = try? URL(
            resolvingBookmarkData: bookmarkData,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
#endif
        return try? String(contentsOf: folderURL.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private static func writeToDisk(bookmarkData: Data, relativePath: String, content: String) {
        var isStale = false
#if os(macOS)
        guard let folderURL = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return }
        guard folderURL.startAccessingSecurityScopedResource() else { return }
        defer { folderURL.stopAccessingSecurityScopedResource() }
#else
        guard let folderURL = try? URL(
            resolvingBookmarkData: bookmarkData,
            bookmarkDataIsStale: &isStale
        ) else { return }
#endif
        try? content.write(to: folderURL.appendingPathComponent(relativePath), atomically: true, encoding: .utf8)
    }

    private func scheduleReparse() {
        reparseTask?.cancel()
        reparseTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            reparse()
        }
    }

    private func reparse() {
        guard let doc = document else { return }
        outlineItems = LaTeXParser.parseOutline(from: doc.content)
        todoItems    = LaTeXParser.parseTodos(from: doc.content)
        if case .idle = compileState {
            compileMessages = LaTeXParser.syntaxCheck(doc.content)
        }
        // Count words (ignoring LaTeX commands)
        let stripped = doc.content
            .replacingOccurrences(of: #"\\[a-zA-Z]+\{[^}]*\}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\\[a-zA-Z]+"#,           with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\$[^$]*\$"#,             with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"%[^\n]*"#,               with: " ", options: .regularExpression)
        wordCount = stripped.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.count
    }

    // MARK: - Compile (native renderer)

    @MainActor
    func compile() async {
        guard let doc = document else { return }
        compileState    = .compiling
        compileMessages = []
        let source      = doc.content
        compileMessages = LaTeXParser.syntaxCheck(source)

        // Parse the full AST
        var blocks = LaTeXParser.parseDocument(source)
        renderedDocument = blocks

        // Build citation resolver from any .bib in the same workspace
        let bibContent = loadBibliography(for: doc)
        var resolver: CitationResolver? = nil
        if let bib = bibContent {
            resolver = CitationResolver()
            resolver?.loadBibFile(bib)
        }

        // Detect document class to choose geometry/fonts
        let geo: DocumentGeometry
        let fnt: TeXFontConfig
        let cls: String
        if source.contains("acmart") || source.contains("sigconf") {
            geo = .acmSigConf;    fnt = .timesACM;   cls = "acmart"
        } else if source.contains("ieee") || source.contains("IEEEtran") {
            geo = .ieeeConference; fnt = .timesIEEE;  cls = "IEEEtran"
        } else if source.contains("llncs") || source.contains("lncs") {
            geo = .lncs;           fnt = .timesLNCS;  cls = "llncs"
        } else {
            geo = .article;        fnt = .palatino;   cls = "article"
        }

        let typesetter              = TeXTypesetter()
        typesetter.geometry         = geo
        typesetter.fonts            = fnt
        typesetter.documentClass    = cls
        typesetter.citationResolver = resolver
        typesetDocument         = typesetter.typeset(blocks)

        compileState = compileMessages.contains { $0.severity == .error }
            ? .failed(Date()) : .success(Date())
    }

    // MARK: - PDF Export

    @MainActor
    func exportPDF() -> Data? {
        guard !typesetDocument.pages.isEmpty else { return nil }
        return PDFExporter().export(typesetDocument, title: document?.title)
    }

    // MARK: - Bibliography helper

    private func loadBibliography(for doc: LaTeXDocument) -> String? {
        guard let workspace = doc.workspace,
              let relativePath = doc.relativePath else { return nil }
        let bookmarkData = workspace.bookmarkData
        var isStale = false
        let folderURL: URL
        #if os(macOS)
        guard let u = try? URL(resolvingBookmarkData: bookmarkData,
                               options: .withSecurityScope,
                               relativeTo: nil,
                               bookmarkDataIsStale: &isStale) else { return nil }
        guard u.startAccessingSecurityScopedResource() else { return nil }
        defer { u.stopAccessingSecurityScopedResource() }
        folderURL = u
        #else
        guard let u = try? URL(resolvingBookmarkData: bookmarkData,
                               bookmarkDataIsStale: &isStale) else { return nil }
        folderURL = u
        #endif
        // Look for .bib files in the same directory
        let docDir = folderURL.appendingPathComponent(relativePath)
            .deletingLastPathComponent()
        let bibs = (try? FileManager.default.contentsOfDirectory(
            at: docDir, includingPropertiesForKeys: nil)) ?? []
        for bib in bibs where bib.pathExtension == "bib" {
            if let content = try? String(contentsOf: bib, encoding: .utf8) { return content }
        }
        return nil
    }
}

