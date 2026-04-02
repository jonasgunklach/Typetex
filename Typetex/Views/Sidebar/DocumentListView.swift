//
//  DocumentListView.swift
//  Typetex
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Document list (sidebar)

struct DocumentListView: View {
    let workspaces: [LaTeXWorkspace]
    let documents: [LaTeXDocument]
    @Binding var selectedDocument: LaTeXDocument?

    @Environment(\.modelContext) private var modelContext

    @State private var showingNewDoc       = false
    @State private var showingFolderPicker = false

    private var standaloneDocuments: [LaTeXDocument] {
        documents.filter { $0.workspace == nil }
    }

    var body: some View {
        Group {
            if workspaces.isEmpty && standaloneDocuments.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingNewDoc = true
                    } label: {
                        Label("New Document", systemImage: "doc.badge.plus")
                    }
                    Button {
                        showingFolderPicker = true
                    } label: {
                        Label("Open Folder…", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewDoc) {
            NewDocumentSheet(selectedDocument: $selectedDocument)
        }
        .fileImporter(
            isPresented: $showingFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                LaTeXWorkspace.create(from: url, in: modelContext)
            }
        }
    }

    // MARK: List

    private var list: some View {
        List(selection: $selectedDocument) {
            if !workspaces.isEmpty {
                Section("Folders") {
                    ForEach(workspaces) { workspace in
                        WorkspaceDisclosureRow(
                            workspace: workspace,
                            selectedDocument: $selectedDocument
                        )
                    }
                }
            }

            if !standaloneDocuments.isEmpty {
                Section("Documents") {
                    ForEach(standaloneDocuments) { doc in
                        DocumentRow(doc: doc)
                            .tag(doc)
                            .contextMenu {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    deleteDoc(doc)
                                }
                            }
                    }
                    .onDelete { offsets in
                        for i in offsets { deleteDoc(standaloneDocuments[i]) }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No documents yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            VStack(spacing: 10) {
                Button("Open Folder…") {
                    showingFolderPicker = true
                }
                .buttonStyle(.borderedProminent)
                Button("New Document") {
                    showingNewDoc = true
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func deleteDoc(_ doc: LaTeXDocument) {
        if selectedDocument?.id == doc.id { selectedDocument = nil }
        modelContext.delete(doc)
    }
}

// MARK: - Workspace disclosure row

struct WorkspaceDisclosureRow: View {
    let workspace: LaTeXWorkspace
    @Binding var selectedDocument: LaTeXDocument?

    @Environment(\.modelContext) private var modelContext
    @State private var isExpanded    = true
    @State private var confirmRemove = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(workspace.sortedDocuments) { doc in
                DocumentRow(doc: doc, relativePath: doc.relativePath)
                    .tag(doc)
                    .contextMenu { docContextMenu(for: doc) }
            }
        } label: {
            workspaceLabel
        }
        .contextMenu {
            Button("Refresh", systemImage: "arrow.clockwise") {
                workspace.scanAndSync(in: modelContext)
            }
#if os(macOS)
            Button("Show in Finder", systemImage: "folder") {
                workspace.withFolderAccess { NSWorkspace.shared.open($0) }
            }
#endif
            Divider()
            Button("Remove Folder", systemImage: "folder.badge.minus", role: .destructive) {
                confirmRemove = true
            }
        }
        .confirmationDialog(
            "Remove \"\(workspace.name)\"?",
            isPresented: $confirmRemove,
            titleVisibility: .visible
        ) {
            Button("Remove from Sidebar", role: .destructive) {
                for doc in workspace.documents where selectedDocument?.id == doc.id {
                    selectedDocument = nil
                }
                modelContext.delete(workspace)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The folder and its files on disk are not affected.")
        }
        .task(id: workspace.id) {
            workspace.scanAndSync(in: modelContext)
        }
    }

    private var workspaceLabel: some View {
        Label {
            HStack {
                Text(workspace.name)
                    .font(.body.weight(.semibold))
                Spacer()
                Text("\(workspace.documents.count)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        } icon: {
            Image(systemName: "folder.fill")
                .foregroundStyle(.tint)
        }
    }

    @ViewBuilder
    private func docContextMenu(for doc: LaTeXDocument) -> some View {
#if os(macOS)
        Button("Show in Finder", systemImage: "folder") {
            guard let path = doc.relativePath else { return }
            workspace.withFolderAccess { folderURL in
                NSWorkspace.shared.activateFileViewerSelecting(
                    [folderURL.appendingPathComponent(path)]
                )
            }
        }
        Divider()
#endif
        Button("Remove from Sidebar", systemImage: "minus.circle", role: .destructive) {
            if selectedDocument?.id == doc.id { selectedDocument = nil }
            modelContext.delete(doc)
        }
    }
}

// MARK: - Document row

struct DocumentRow: View {
    let doc: LaTeXDocument
    var relativePath: String? = nil

    private var ext: String {
        guard let path = relativePath ?? (doc.relativePath) else { return "tex" }
        return URL(fileURLWithPath: path).pathExtension.lowercased()
    }

    private var displayTitle: String {
        if let path = relativePath ?? doc.relativePath {
            return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        }
        return doc.title
    }

    private var subdirSubtitle: String? {
        guard let path = relativePath ?? doc.relativePath else { return nil }
        let components = path.split(separator: "/")
        guard components.count > 1 else { return nil }
        return components.dropLast().joined(separator: "/")
    }

    private var fileIcon: String {
        switch ext {
        case "bib":               return "books.vertical"
        case "cls", "sty", "def": return "gearshape"
        case "png", "jpg", "jpeg": return "photo"
        case "pdf":               return "doc.richtext"
        case "svg", "eps":        return "pencil.and.scribble"
        case "md", "txt":         return "doc.plaintext"
        default:                  return "doc.text"
        }
    }

    private var isAsset: Bool {
        LaTeXWorkspace.assetExtensions.contains(ext)
    }

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(displayTitle)
                    .font(.body)
                    .lineLimit(1)
                    .foregroundStyle(isAsset ? .secondary : .primary)
                if let subdir = subdirSubtitle {
                    Text(subdir)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if !isAsset {
                    Text(doc.modifiedAt.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(ext.uppercased())
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        } icon: {
            Image(systemName: fileIcon)
                .foregroundStyle(isAsset ? Color.secondary : Color.accentColor)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - New document sheet

struct NewDocumentSheet: View {
    @Binding var selectedDocument: LaTeXDocument?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title            = ""
    @State private var selectedTemplate = LaTeXTemplate.article

    var body: some View {
        NavigationStack {
            Form {
                Section("Document Name") {
                    TextField("Untitled", text: $title)
                }
                Section("Template") {
                    ForEach(LaTeXTemplate.all) { template in
                        TemplateRow(
                            template: template,
                            isSelected: selectedTemplate.name == template.name
                        ) {
                            selectedTemplate = template
                        }
                    }
                }
            }
            .navigationTitle("New Document")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                }
            }
        }
#if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
#endif
    }

    private func create() {
        let finalTitle = title.trimmingCharacters(in: .whitespaces).isEmpty ? "Untitled" : title
        let doc = LaTeXDocument(
            title: finalTitle,
            content: selectedTemplate.content,
            templateName: selectedTemplate.name
        )
        modelContext.insert(doc)
        selectedDocument = doc
        dismiss()
    }
}

// MARK: - Template row

struct TemplateRow: View {
    let template: LaTeXTemplate
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: template.icon)
                    .font(.title3)
                    .foregroundStyle(isSelected ? .white : Color.accentColor)
                    .frame(width: 36, height: 36)
                    .background(isSelected ? Color.accentColor : Color.accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(template.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(template.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
