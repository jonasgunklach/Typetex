//
//  SettingsView.swift
//  Typetex
//
//  macOS  → native tab-pane Settings window (no NavigationStack)
//  iPadOS → NavigationStack + Form sheet
//

import SwiftUI

// ─────────────────────────────────────────────────────────────────
// MARK: - Shared AppStorage keys (same defaults everywhere)
// ─────────────────────────────────────────────────────────────────

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
#if os(macOS)
        MacSettingsView()
#else
        iPadSettingsView(dismiss: dismiss)
#endif
    }
}

// ─────────────────────────────────────────────────────────────────
// MARK: - macOS  –  Tab-pane window
// ─────────────────────────────────────────────────────────────────

#if os(macOS)
private struct MacSettingsView: View {
    var body: some View {
        TabView {
            EditorPane()
                .tabItem { Label("Editor", systemImage: "doc.text") }
                .tag(0)
            CompilationPane()
                .tabItem { Label("Compilation", systemImage: "terminal") }
                .tag(1)
            ShortcutsPane()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
                .tag(2)
            AboutPane()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(3)
        }
        .padding(20)
        .frame(width: 480)
        // Each pane controls its own height via fixedSize
    }
}

// ── Editor pane ──────────────────────────────────────────────────

private struct EditorPane: View {
    @AppStorage("editorFontSize")   private var fontSize:   Double = 15
    @AppStorage("editorFontFamily") private var fontFamily: String = ""
    @AppStorage("editorTheme")      private var theme:      String = "default"
    @AppStorage("showLineNumbers")  private var lineNumbers: Bool  = true
    @AppStorage("wordWrap")         private var wordWrap:    Bool  = true
    @AppStorage("spellCheck")       private var spellCheck:  Bool  = false

    var body: some View {
        Form {
            // Font size
            LabeledContent("Font Size") {
                HStack(spacing: 10) {
                    Slider(value: $fontSize, in: 10...28, step: 1)
                        .frame(width: 180)
                    Text("\(Int(fontSize)) pt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
            }

            // Font family
            Picker("Font Family", selection: $fontFamily) {
                Text("System Monospaced").tag("")
                Divider()
                ForEach(monospacedFamilies, id: \.self) { name in
                    Text(name).tag(name)
                }
            }

            // Font preview
            LabeledContent("Preview") {
                Text("\\documentclass{article}")
                    .font(previewFont)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            // Theme
            Picker("Theme", selection: $theme) {
                HStack(spacing: 6) {
                    Circle().fill(.blue).frame(width: 9, height: 9)
                    Text("Default")
                }.tag("default")
                HStack(spacing: 6) {
                    Circle().fill(Color(red: 0, green: 0.17, blue: 0.21)).frame(width: 9, height: 9)
                    Text("Solarized Dark")
                }.tag("solarized")
                HStack(spacing: 6) {
                    Circle().fill(Color(red: 0.15, green: 0.16, blue: 0.13)).frame(width: 9, height: 9)
                    Text("Monokai")
                }.tag("monokai")
            }
            .pickerStyle(.radioGroup)

            Divider()

            Toggle("Show Line Numbers", isOn: $lineNumbers)
            Toggle("Word Wrap",         isOn: $wordWrap)
            Toggle("Spell Checking",    isOn: $spellCheck)
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize()
    }

    private var previewFont: Font {
        fontFamily.isEmpty
            ? .system(size: fontSize, design: .monospaced)
            : .custom(fontFamily, size: fontSize)
    }

    private var monospacedFamilies: [String] {
        NSFontManager.shared.availableFontFamilies.filter { family in
            guard let font = NSFont(name: family, size: 12) else { return false }
            return NSFontManager.shared.traits(of: font).contains(.fixedPitchFontMask)
        }.sorted()
    }
}

// ── Compilation pane ─────────────────────────────────────────────

private enum InstallState { case idle, installing, success, failed }

private struct CompilationPane: View {
    @AppStorage("latexEngine") private var engine:      String = "pdflatex"
    @AppStorage("autoCompile") private var autoCompile: Bool   = false

    @State private var detectedLatexPath: String? = nil
    @State private var brewPath:          String? = nil
    @State private var installState: InstallState = .idle
    @State private var installLog:   String = ""

    private static let latexCandidates = [
        "/Library/TeX/texbin/pdflatex",
        "/usr/texbin/pdflatex",
        "/usr/local/bin/pdflatex",
        "/opt/homebrew/bin/pdflatex",
    ]
    private static let brewCandidates = [
        "/opt/homebrew/bin/brew",
        "/usr/local/bin/brew",
    ]

    var body: some View {
        Form {
            // ── Installation status ──────────────────────────────
            LabeledContent("LaTeX Status") {
                if let path = detectedLatexPath {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text((path as NSString).deletingLastPathComponent)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                        Text("Not installed")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if detectedLatexPath == nil {
                switch installState {
                case .idle:
                    if let brew = brewPath {
                        LabeledContent("One-click Install") {
                            Button("Install MacTeX via Homebrew") {
                                runBrewInstall(brew: brew)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        Text("Installs MacTeX (no GUI tools, ~500 MB download) using your existing Homebrew. macOS will ask for your password once.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        LabeledContent("Install LaTeX") {
                            HStack(spacing: 12) {
                                Link("Download MacTeX Installer",
                                     destination: URL(string: "https://www.tug.org/mactex/")!)
                                Text("·")
                                    .foregroundStyle(.tertiary)
                                Link("Install Homebrew first",
                                     destination: URL(string: "https://brew.sh")!)
                            }
                        }
                        Text("Install Homebrew to enable one-click setup here, or download the MacTeX .pkg from the website.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                case .installing:
                    LabeledContent("Installing…") {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("This may take a few minutes")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !installLog.isEmpty {
                        ScrollView {
                            Text(installLog)
                                .font(.system(size: 10, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(6)
                        }
                        .frame(height: 80)
                        .background(Color.black.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                case .success:
                    LabeledContent("Done!") {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("MacTeX installed. You can now compile documents.")
                        }
                    }

                case .failed:
                    LabeledContent("Install failed") {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                            Link("Try the manual MacTeX installer",
                                 destination: URL(string: "https://www.tug.org/mactex/")!)
                        }
                    }
                    if !installLog.isEmpty {
                        ScrollView {
                            Text(installLog)
                                .font(.system(size: 10, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(6)
                        }
                        .frame(height: 80)
                        .background(Color.black.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }

            Divider()

            Picker("LaTeX Engine", selection: $engine) {
                Text("pdfLaTeX").tag("pdflatex")
                Text("XeLaTeX") .tag("xelatex")
                Text("LuaLaTeX").tag("lualatex")
            }
            .pickerStyle(.radioGroup)
            .disabled(detectedLatexPath == nil)

            Toggle("Auto-Compile on Save", isOn: $autoCompile)
                .disabled(detectedLatexPath == nil)
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .onAppear {
            detectedLatexPath = Self.latexCandidates
                .first { FileManager.default.fileExists(atPath: $0) }
            brewPath = Self.brewCandidates
                .first { FileManager.default.fileExists(atPath: $0) }
        }
    }

    private func runBrewInstall(brew: String) {
        installState = .installing
        installLog   = ""
        let candidates = Self.latexCandidates
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: brew)
            process.arguments     = ["install", "--cask", "mactex-no-gui"]
            process.environment   = ProcessInfo.processInfo.environment

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError  = pipe

            pipe.fileHandleForReading.readabilityHandler = { fh in
                let data = fh.availableData
                guard !data.isEmpty,
                      let str = String(data: data, encoding: .utf8) else { return }
                DispatchQueue.main.async { installLog += str }
            }

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                await MainActor.run {
                    installLog += "\nError: \(error.localizedDescription)"
                    installState = .failed
                }
                return
            }

            pipe.fileHandleForReading.readabilityHandler = nil
            let newPath = candidates
                .first { FileManager.default.fileExists(atPath: $0) }
            await MainActor.run {
                if process.terminationStatus == 0, let p = newPath {
                    detectedLatexPath = p
                    installState = .success
                } else {
                    installState = .failed
                }
            }
        }
    }
}

// ── Shortcuts pane ───────────────────────────────────────────────

private struct ShortcutsPane: View {
    private let shortcuts: [(String, String)] = [
        ("Compile",             "⇧⌘B"),
        ("Find & Replace",      "⌘F"),
        ("Comment / Uncomment", "⌘/"),
        ("Indent block",        "⇥"),
        ("Dedent block",        "⇧⇥"),
        ("Jump to Line",        "⌘L"),
    ]

    var body: some View {
        Form {
            ForEach(shortcuts, id: \.0) { action, keys in
                LabeledContent(action) {
                    Text(keys)
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize()
    }
}

// ── About pane ───────────────────────────────────────────────────

private struct AboutPane: View {
    var body: some View {
        Form {
            LabeledContent("Version") {
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
            }
            LabeledContent("Build") {
                Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
            }

            Divider()

            Link(destination: URL(string: "https://www.tug.org/mactex/")!) {
                Label("Download MacTeX", systemImage: "arrow.down.circle")
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize()
    }
}
#endif

// ─────────────────────────────────────────────────────────────────
// MARK: - iPadOS  –  NavigationStack sheet
// ─────────────────────────────────────────────────────────────────

#if os(iOS)
private struct iPadSettingsView: View {
    let dismiss: DismissAction

    @AppStorage("editorFontSize")   private var fontSize:    Double = 15
    @AppStorage("editorFontFamily") private var fontFamily:  String = ""
    @AppStorage("editorTheme")      private var theme:       String = "default"
    @AppStorage("latexEngine")      private var engine:      String = "pdflatex"
    @AppStorage("autoCompile")      private var autoCompile: Bool   = false
    @AppStorage("showLineNumbers")  private var lineNumbers: Bool   = true
    @AppStorage("wordWrap")         private var wordWrap:    Bool   = true
    @AppStorage("spellCheck")       private var spellCheck:  Bool   = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Editor") {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Font Size")
                            Spacer()
                            Text("\(Int(fontSize)) pt")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $fontSize, in: 10...28, step: 1)
                    }
                    .padding(.vertical, 4)

                    Picker("Font", selection: $fontFamily) {
                        Text("System Monospaced").tag("")
                        ForEach(["Menlo", "Courier New", "Monaco"], id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }

                    Picker("Theme", selection: $theme) {
                        Text("Default") .tag("default")
                        Text("Solarized Dark").tag("solarized")
                        Text("Monokai")  .tag("monokai")
                    }

                    Toggle("Line Numbers",  isOn: $lineNumbers)
                    Toggle("Word Wrap",     isOn: $wordWrap)
                    Toggle("Spell Check",   isOn: $spellCheck)
                }

                Section("Compilation") {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "desktopcomputer")
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Compilation requires macOS")
                                .font(.subheadline.bold())
                            Text("LaTeX cannot run on iPad. Open the same project on your Mac to compile, or use an online service.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)

                    Link(destination: URL(string: "https://www.overleaf.com")!) {
                        Label("Open Overleaf (online compiler)", systemImage: "arrow.up.right.square")
                    }

                    Picker("Engine (used on Mac)", selection: $engine) {
                        Text("pdfLaTeX").tag("pdflatex")
                        Text("XeLaTeX") .tag("xelatex")
                        Text("LuaLaTeX").tag("lualatex")
                    }
                }

                Section("Shortcuts") {
                    shortcutRow("Compile",           "⇧⌘B")
                    shortcutRow("Find & Replace",    "⌘F")
                    shortcutRow("Comment/Uncomment", "⌘/")
                    shortcutRow("Indent",            "⇥")
                    shortcutRow("Dedent",            "⇧⇥")
                }

                Section("About") {
                    LabeledContent("Version",
                        value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    LabeledContent("Build",
                        value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func shortcutRow(_ label: String, _ key: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(key).font(.body.monospaced()).foregroundStyle(.secondary)
        }
    }
}
#endif

// ─────────────────────────────────────────────────────────────────
#Preview {
    SettingsView()
}
