# Typetex

A native LaTeX editor for **macOS** and **iPadOS** — written entirely in Swift, with an on-device rendering pipeline built on CoreText and CoreGraphics. No TeX binary, no server, no internet connection required.

---

## Features

### On-Device LaTeX Rendering
- **Native Swift typesetter** — parses LaTeX source into an AST (`TexBlock` / `TexInline`) and typesets it into pages using CoreText and CoreGraphics.
- **Knuth–Plass optimal line breaking** — a full implementation of the classic DP algorithm for high-quality paragraph layout, matching traditional TeX output.
- **Math layout engine** — supports inline (`$...$`) and display (`$$...$$`) math with fractions, radicals, sub/superscripts, operators, and auto-sized delimiters. Renders via CoreGraphics without any JavaScript or web views.
- **Multi-column layouts** — accurate two-column geometry (e.g., ACM `sigconf`-style documents) with proper gutter, margins, and page flow.
- **Live preview** — the typeset preview updates automatically as you type.

### Full Compilation via Tectonic (macOS)
- Ships with a **TectonicFFI** static library — a Rust-compiled build of the [Tectonic](https://tectonic-typesetting.github.io) TeX engine exposed via a C FFI.
- Produces pixel-perfect PDF output from any `.tex` source, with access to a bundled TeX package archive.
- App Store distributable: no external binaries or TeX distributions required.

### VS Code–Style Editor
- Syntax highlighting for LaTeX commands, environments, math, and comments.
- Debounced incremental highlighting (120 ms after last keystroke).
- Line-number gutter with current-line highlight.
- Auto-close for `{`, `[`, `(`, and `$`.
- `⌘/` comment toggle, `Tab`/`⇧Tab` indent/dedent.
- NSTextFinder-based find/replace, jump-to-line.
- Snippet insertion.
- Multiple themes (default, dark, light, …).
- Configurable font family and size.

### Workspace & Document Management
- Open any folder as a **workspace**; all `.tex`, `.bib`, `.cls`, `.sty`, and related files are scanned and shown in the sidebar.
- SwiftData-backed persistence for documents and workspaces.
- Sidebar tabs: **Documents**, **Outline** (sections/chapters), **TODOs** (`% TODO:` comments), and **Compile Messages** (errors/warnings).
- Cascading delete: removing a workspace removes its SwiftData mirrors; files on disk are left untouched.

### Templates
Built-in starter templates:
- Standard Article
- ACM CHI `sigconf` two-column paper
- More coming soon

### ACM CHI Test Bench
A built-in comparison view that compiles a sample CHI paper through the full native pipeline, letting you visually diff output against Overleaf or a reference PDF.

---

## Architecture

```
LaTeXParser         →  LaTeXRenderer (SwiftUI)
     ↓                       ↓
  TexBlock AST         Lightweight preview
     ↓
TeXTypesetter (CoreText / CoreGraphics)
     ↓
TypesetDocument  →  TeXPageView (SwiftUI canvas)
     ↓
  PDF export (planned)
```

**Key files:**

| File | Purpose |
|---|---|
| `LaTeXParser.swift` | Tokenises LaTeX and produces `TexBlock` / `TexInline` AST |
| `LaTeXRenderer.swift` | SwiftUI views for quick in-app preview |
| `TeXTypesetter.swift` | CoreText-based typesetter: AST → pages + frames |
| `KnuthPlassBreaker.swift` | Knuth–Plass DP line-breaking algorithm |
| `MathParser.swift` | Recursive-descent math expression parser |
| `MathRenderer.swift` | CoreGraphics math layout and drawing engine |
| `TeXPageCanvasView.swift` | SwiftUI canvas that draws a `TypesetPage` |
| `TeXTypes.swift` | Shared geometry, font config, counter types |
| `LaTeXEditorView.swift` | macOS `NSTextView`-based editor with syntax highlighting |
| `EditorViewModel.swift` | Observable VM: parse state, compile state, preferences |
| `LaTeXProject.swift` | SwiftData models: `LaTeXWorkspace`, `LaTeXDocument` |

---

## Requirements

| Platform | Minimum |
|---|---|
| macOS | 14 Sonoma |
| iPadOS | 17 |

- Xcode 15+
- Swift 5.9+

---

## Getting Started

1. Clone the repository:
   ```bash
   git clone https://github.com/jonasgunklach/Typetex.git
   cd Typetex
   ```
2. Open `Typetex.xcodeproj` in Xcode.
3. Select the `Typetex` scheme and your target device (Mac or iPad simulator).
4. Build and run (`⌘R`).

> **Note:** The `TectonicFFI.xcframework` headers and module map are included. The compiled static library (`libtectonic_ffi.a`, ~200 MB) is excluded from git. To enable full Tectonic compilation, build the library from [tectonic-typesetting/tectonic](https://github.com/tectonic-typesetting/tectonic) and drop it into `TectonicFFI.xcframework/macos-arm64/`. The native on-device renderer works without it.

---

## Roadmap

- [ ] Full PDF export from the native typesetter
- [ ] BibTeX / citation auto-complete
- [ ] iOS (iPhone) support
- [ ] iCloud Drive workspace sync
- [ ] Spell-check and grammar hints

---

## License

MIT — see [LICENSE](LICENSE) for details.
