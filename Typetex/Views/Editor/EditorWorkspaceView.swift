//
//  EditorWorkspaceView.swift
//  Typetex
//
//  Wraps LaTeXEditorView with compile toolbar and sheet management.
//

import SwiftUI

struct EditorContentView: View {
    @Bindable var document: LaTeXDocument
    @Binding var sidebarTab: SidebarTab

    @Environment(EditorViewModel.self) private var vm
    @State private var showingSnippets = false
    @State private var showingSettings = false

    @AppStorage("editorFontSize") private var fontSize: Double = 15
    @AppStorage("editorTheme")    private var theme:    String = "default"

    var body: some View {
        LaTeXEditorView(document: document, sidebarTab: $sidebarTab)
            .clipped()                      // prevent ruler/scroll view bleeding into toolbar
            .ignoresSafeArea(edges: .bottom) // let editor fill to window bottom edge
            .navigationTitle($document.title)
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                compileButton
                snippetsButton
                wordCountItem
                findButton
                shareButton
                errorsIndicator
#if os(macOS)
                fontSizeControls
                themePickerButton
                ToolbarItem {
                    Button { showingSettings = true } label: { Image(systemName: "gear") }
                        .help("Settings")
                }
#else
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showingSettings = true } label: { Image(systemName: "gear") }
                }
#endif
            }
            .sheet(isPresented: $showingSnippets) {
                SnippetsView { code in
                    NotificationCenter.default.post(
                        name: .insertSnippet,
                        object: nil,
                        userInfo: ["code": code]
                    )
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
    }

    // MARK: Toolbar items

    @ToolbarContentBuilder
    private var compileButton: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await vm.compile() }
            } label: {
                switch vm.compileState {
                case .compiling:
                    ProgressView().controlSize(.small)
                case .success:
                    Label("Compile", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .failed:
                    Label("Compile", systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                default:
                    Label("Compile", systemImage: "play.fill")
                }
            }
            .disabled(vm.compileState == .compiling)
            .help("Compile document")
            .keyboardShortcut("b", modifiers: [.command, .shift])
        }
    }

    @ToolbarContentBuilder
    private var wordCountItem: some ToolbarContent {
        ToolbarItem(placement: .secondaryAction) {
            Text("\(vm.wordCount) words")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .help("Word count (LaTeX commands excluded)")
        }
    }

    @ToolbarContentBuilder
    private var findButton: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                NotificationCenter.default.post(name: .toggleFind, object: nil)
            } label: {
                Label("Find & Replace", systemImage: "magnifyingglass")
            }
            .help("Find & Replace (⌘F)")
            .keyboardShortcut("f", modifiers: .command)
        }
    }

    @ToolbarContentBuilder
    private var snippetsButton: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { showingSnippets = true } label: {
                Label("Snippets", systemImage: "text.badge.plus")
            }
            .help("Insert LaTeX snippet")
        }
    }

    @ToolbarContentBuilder
    private var shareButton: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            if let content = vm.document?.content {
                ShareLink(item: content) {
                    Label("Share Source", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var errorsIndicator: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            let errors   = vm.compileMessages.filter { $0.severity == .error }.count
            let warnings = vm.compileMessages.filter { $0.severity == .warning }.count

            if errors > 0 {
                Button { sidebarTab = .errors } label: {
                    Label("\(errors)", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
                .help("\(errors) error(s)")
            } else if warnings > 0 {
                Button { sidebarTab = .errors } label: {
                    Label("\(warnings)", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                .help("\(warnings) warning(s)")
            }
        }
    }

#if os(macOS)
    @ToolbarContentBuilder
    private var fontSizeControls: some ToolbarContent {
        ToolbarItem {
            HStack(spacing: 2) {
                Button {
                    fontSize = max(10, fontSize - 1)
                } label: {
                    Image(systemName: "textformat.size.smaller")
                }
                .help("Decrease font size")
                Button {
                    fontSize = min(28, fontSize + 1)
                } label: {
                    Image(systemName: "textformat.size.larger")
                }
                .help("Increase font size")
            }
        }
    }

    @ToolbarContentBuilder
    private var themePickerButton: some ToolbarContent {
        ToolbarItem {
            Menu {
                Picker("Theme", selection: $theme) {
                    Text("Default")       .tag("default")
                    Text("Solarized Dark").tag("solarized")
                    Text("Monokai")       .tag("monokai")
                }
            } label: {
                Image(systemName: "paintpalette")
            }
            .help("Editor theme")
        }
    }
#endif
}

// MARK: - Find & Replace toolbar button support

