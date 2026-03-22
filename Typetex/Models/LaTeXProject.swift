//
//  LaTeXProject.swift  (LaTeXWorkspace model)
//  Typetex
//

import Foundation
import SwiftData
import SwiftUI

// MARK: - Workspace model (folder on disk)

@Model
final class LaTeXWorkspace {
    @Attribute(.unique) var id: UUID
    var name: String
    var bookmarkData: Data
    var createdAt: Date

    // Cascade: deleting a workspace removes its SwiftData mirror docs (files on disk are untouched)
    @Relationship(deleteRule: .cascade, inverse: \LaTeXDocument.workspace)
    var documents: [LaTeXDocument] = []

    init(name: String, bookmarkData: Data) {
        self.id           = UUID()
        self.name         = name
        self.bookmarkData = bookmarkData
        self.createdAt    = Date()
    }

    // MARK: - Helpers

    var sortedDocuments: [LaTeXDocument] {
        documents.sorted { ($0.relativePath ?? $0.title) < ($1.relativePath ?? $1.title) }
    }

    // MARK: - Security-scoped folder access

    /// Resolves the stored bookmark and calls `body` with the folder URL while access is held.
    @discardableResult
    func withFolderAccess<T>(_ body: (URL) -> T) -> T? {
        var isStale = false
#if os(macOS)
        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        guard url.startAccessingSecurityScopedResource() else { return nil }
        defer { url.stopAccessingSecurityScopedResource() }
#else
        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
#endif
        return body(url)
    }

    // MARK: - Scan & sync all text-editable files in the folder

    /// File extensions shown in the sidebar (all text/LaTeX-related files).
    static let editableExtensions: Set<String> = [
        "tex", "bib", "cls", "sty", "dtx", "ins", "def", "cfg",
        "txt", "md", "lua", "py", "sh",
    ]

    /// Non-editable extensions that are still shown as read-only in the sidebar.
    static let assetExtensions: Set<String> = [
        "png", "jpg", "jpeg", "pdf", "eps", "svg", "tikz",
    ]

    /// Scans the workspace folder and mirrors files as LaTeXDocument records.
    func scanAndSync(in context: ModelContext) {
        withFolderAccess { folderURL in
            let fm = FileManager.default
            guard let enumerator = fm.enumerator(
                at: folderURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { return }

            // Collect all relevant files
            var foundPaths: [String] = []
            while let fileURL = enumerator.nextObject() as? URL {
                let ext = fileURL.pathExtension.lowercased()
                if LaTeXWorkspace.editableExtensions.contains(ext)
                    || LaTeXWorkspace.assetExtensions.contains(ext) {
                    let rel = String(fileURL.path.dropFirst(folderURL.path.count))
                        .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    foundPaths.append(rel)
                }
            }
            foundPaths.sort()

            // Remove records for files no longer on disk
            for doc in documents {
                guard let path = doc.relativePath else { continue }
                if !foundPaths.contains(path) {
                    context.delete(doc)
                }
            }

            // Create records for newly found files
            let existingPaths = Set(documents.compactMap(\.relativePath))
            for relPath in foundPaths where !existingPaths.contains(relPath) {
                let fileURL = folderURL.appendingPathComponent(relPath)
                let ext = fileURL.pathExtension.lowercased()
                let isEditable = LaTeXWorkspace.editableExtensions.contains(ext)
                // Only read content for text files; assets get empty content placeholder
                let content = isEditable
                    ? ((try? String(contentsOf: fileURL, encoding: .utf8)) ?? "")
                    : ""
                let doc = LaTeXDocument(
                    title: fileURL.deletingPathExtension().lastPathComponent,
                    content: content,
                    templateName: isEditable ? "External" : "Asset"
                )
                doc.relativePath = relPath
                doc.workspace    = self
                context.insert(doc)
            }
        }
    }
}

// MARK: - Factory helper

extension LaTeXWorkspace {
    /// Creates a workspace from a folder URL returned by fileImporter,
    /// stores a security-scoped bookmark, and immediately syncs files.
    @discardableResult
    static func create(from folderURL: URL, in context: ModelContext) -> LaTeXWorkspace? {
        let bookmarkData: Data?
#if os(macOS)
        _ = folderURL.startAccessingSecurityScopedResource()
        bookmarkData = try? folderURL.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        folderURL.stopAccessingSecurityScopedResource()
#else
        bookmarkData = try? folderURL.bookmarkData()
#endif
        guard let data = bookmarkData else { return nil }
        let workspace = LaTeXWorkspace(name: folderURL.lastPathComponent, bookmarkData: data)
        context.insert(workspace)
        workspace.scanAndSync(in: context)
        return workspace
    }
}
