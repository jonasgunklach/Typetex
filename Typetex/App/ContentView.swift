//
//  ContentView.swift
//  Typetex
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Query(sort: \LaTeXDocument.modifiedAt, order: .reverse)
    private var documents: [LaTeXDocument]

    @Query(sort: \LaTeXWorkspace.name)
    private var workspaces: [LaTeXWorkspace]

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "tiff", "bmp", "webp"]

    @State private var selectedDocument: LaTeXDocument?
    @State private var editorVM = EditorViewModel()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var sidebarTab: SidebarTab = .documents
    @State private var showingSettings = false

    @AppStorage("editorFontSize")   private var fontSize:   Double = 15
    @AppStorage("editorFontFamily") private var fontFamily: String = ""
    @AppStorage("editorTheme")      private var themeName:  String = "default"
    @AppStorage("showLineNumbers")  private var lineNumbers: Bool  = true

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // ── Sidebar ──────────────────────────────────────────
            SidebarContainerView(
                workspaces: workspaces,
                documents: documents,
                selectedDocument: $selectedDocument,
                tab: $sidebarTab
            )
        } content: {
            // ── Editor ───────────────────────────────────────────
            if let doc = selectedDocument {
                let ext = URL(fileURLWithPath: doc.relativePath ?? "_.tex").pathExtension.lowercased()
                if ContentView.imageExtensions.contains(ext) {
                    ImagePreviewView(doc: doc)
                        .id(doc.id)
                } else if LaTeXWorkspace.assetExtensions.contains(ext) {
                    // Asset file — show info instead of editor
                    AssetPlaceholderView(doc: doc)
                } else {
                    EditorContentView(document: doc, sidebarTab: $sidebarTab)
                        .id(doc.id)
                }
            } else {
                WelcomePlaceholderView(selectedDocument: $selectedDocument)
            }
        } detail: {
            // ── PDF Preview ──────────────────────────────────────
            if selectedDocument != nil {
                PDFPreviewView()
            } else {
                PDFPlaceholderView()
            }
        }
        .navigationSplitViewStyle(.balanced)
        .environment(editorVM)
        .onAppear {
            // Sync stored preferences into VM on first launch
            // (onChange only fires on *changes*, not the initial value)
            editorVM.fontSize        = fontSize
            editorVM.fontFamily      = fontFamily
            editorVM.themeName       = themeName
            editorVM.showLineNumbers = lineNumbers
        }
        .onChange(of: selectedDocument) { _, new in
            editorVM.setDocument(new)
        }
        .onChange(of: fontSize)    { _, new in editorVM.fontSize   = new }
        .onChange(of: fontFamily)   { _, new in editorVM.fontFamily  = new }
        .onChange(of: themeName)    { _, new in editorVM.themeName   = new }
        .onChange(of: lineNumbers)  { _, new in editorVM.showLineNumbers = new }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }
}

// MARK: - Sidebar tabs

enum SidebarTab: String, CaseIterable {
    case documents = "Documents"
    case outline   = "Outline"
    case todos     = "TODOs"
    case errors    = "Errors"

    var systemImage: String {
        switch self {
        case .documents: return "doc.on.doc"
        case .outline:   return "list.bullet.indent"
        case .todos:     return "checkmark.circle"
        case .errors:    return "exclamationmark.triangle"
        }
    }
}

// MARK: - Sidebar container

struct SidebarContainerView: View {
    let workspaces: [LaTeXWorkspace]
    let documents: [LaTeXDocument]
    @Binding var selectedDocument: LaTeXDocument?
    @Binding var tab: SidebarTab

    var body: some View {
        Group {
            switch tab {
            case .documents:
                DocumentListView(
                    workspaces: workspaces,
                    documents: documents,
                    selectedDocument: $selectedDocument
                )
            case .outline:
                OutlineListView(document: selectedDocument)
            case .todos:
                TodoListView(document: selectedDocument)
            case .errors:
                ErrorListView(document: selectedDocument)
            }
        }
        .toolbar {
#if os(iOS)
            ToolbarItem(placement: .navigationBarLeading) { sidebarPicker }
#else
            ToolbarItem { sidebarPicker }
#endif
        }
        .navigationTitle(tab.rawValue)
    }

    private var sidebarPicker: some View {
        Menu {
            ForEach(SidebarTab.allCases, id: \.self) { t in
                Button {
                    tab = t
                } label: {
                    Label(t.rawValue, systemImage: t.systemImage)
                }
            }
        } label: {
            Image(systemName: tab.systemImage)
        }
    }
}

// MARK: - Welcome / placeholder views

struct AssetPlaceholderView: View {
    let doc: LaTeXDocument

    private var ext: String {
        URL(fileURLWithPath: doc.relativePath ?? "_.png").pathExtension.uppercased()
    }

    var body: some View {
        ContentUnavailableView(
            doc.title,
            systemImage: "photo",
            description: Text("\(ext) file — cannot be edited in Typetex.\nUse Finder to open it with another app.")
        )
        .navigationTitle(doc.title)
    }
}

struct WelcomePlaceholderView: View {
    @Binding var selectedDocument: LaTeXDocument?
    @State private var showingNewDoc = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "text.document")
                .font(.system(size: 72))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("No Document Open")
                    .font(.title2.bold())
                Text("Select a document from the sidebar\nor create a new one.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                showingNewDoc = true
            } label: {
                Label("New Document", systemImage: "plus")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .navigationTitle("Typetex")
        .sheet(isPresented: $showingNewDoc) {
            NewDocumentSheet(selectedDocument: $selectedDocument)
        }
    }
}

struct PDFPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "No PDF",
            systemImage: "doc.richtext",
            description: Text("Compile your document to see the PDF preview.")
        )
    }
}

// MARK: - Image Preview

struct ImagePreviewView: View {
    let doc: LaTeXDocument

    @State private var imageData: Data? = nil
    @State private var zoom: Double = 1.0

    var body: some View {
        Group {
            if let data = imageData {
                imageContent(data)
            } else {
                ProgressView("Loading image…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(doc.title)
        .toolbar {
            ToolbarItem {
                HStack(spacing: 4) {
                    Button { zoom = max(0.1, zoom - 0.25) } label: {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    .help("Zoom out")
                    Text("\(Int(zoom * 100))%")
                        .monospacedDigit()
                        .font(.caption)
                        .frame(minWidth: 44)
                    Button { zoom = min(10.0, zoom + 0.25) } label: {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .help("Zoom in")
                    Button { zoom = 1.0 } label: {
                        Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
                    }
                    .help("Reset zoom")
                }
            }
        }
        .task { await loadImage() }
    }

    @ViewBuilder
    private func imageContent(_ data: Data) -> some View {
#if os(macOS)
        if let img = NSImage(data: data) {
            GeometryReader { geo in
                let s = geo.size
                let fitScale = s.width > 0 && s.height > 0
                    ? min(s.width / img.size.width, s.height / img.size.height)
                    : 1.0
                let dispW = max(1, img.size.width  * fitScale * zoom)
                let dispH = max(1, img.size.height * fitScale * zoom)
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: img)
                        .resizable()
                        .frame(width: dispW, height: dispH)
                        .frame(minWidth: s.width, minHeight: s.height)
                }
                .background(Color(nsColor: .underPageBackgroundColor))
            }
        }
#else
        if let img = UIImage(data: data) {
            GeometryReader { geo in
                let s = geo.size
                let fitScale = s.width > 0 && s.height > 0
                    ? min(s.width / img.size.width, s.height / img.size.height)
                    : 1.0
                let dispW = max(1, img.size.width  * fitScale * zoom)
                let dispH = max(1, img.size.height * fitScale * zoom)
                ScrollView([.horizontal, .vertical]) {
                    Image(uiImage: img)
                        .resizable()
                        .frame(width: dispW, height: dispH)
                        .frame(minWidth: s.width, minHeight: s.height)
                }
            }
        }
#endif
    }

    @MainActor
    private func loadImage() async {
        guard let workspace = doc.workspace,
              let relativePath = doc.relativePath else { return }
        let bookmarkData = workspace.bookmarkData
        let path = relativePath
        let data = await Task.detached(priority: .userInitiated) {
            ImagePreviewView.readImageData(bookmarkData: bookmarkData, relativePath: path)
        }.value
        imageData = data
    }

    nonisolated private static func readImageData(bookmarkData: Data, relativePath: String) -> Data? {
        var isStale = false
#if os(macOS)
        guard let folderURL = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ), folderURL.startAccessingSecurityScopedResource() else { return nil }
        defer { folderURL.stopAccessingSecurityScopedResource() }
#else
        guard let folderURL = try? URL(
            resolvingBookmarkData: bookmarkData,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
#endif
        return try? Data(contentsOf: folderURL.appendingPathComponent(relativePath))
    }
}

#Preview {
    ContentView()
        .modelContainer(for: LaTeXDocument.self, inMemory: true)
}


