// ParityTestView.swift
// Side-by-side parity test: native Swift CoreText renderer (left) vs. pre-compiled reference PDF (right).
// Corpus: templates/**/samples/*.tex plus templates/**/*.tex that have matching .pdf neighbours.
// Pixel diff and SSIM computed on-demand via CoreImage.

import SwiftUI
import PDFKit
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - Corpus entry

struct CorpusEntry: Identifiable, Hashable, Equatable {
    let id        = UUID()
    let name:       String       // display name
    let source:     String       // full LaTeX source
    let sourceURL:  URL          // absolute path to .tex
    let referencePDF: URL?       // absolute path to companion .pdf, if any

    static func == (l: CorpusEntry, r: CorpusEntry) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

// MARK: - Comparison result

struct ComparisonResult {
    var nativeRenderMs:    Double = 0
    var totalNativePages:  Int    = 0
    var nativePages:       [TypesetPage] = []
    var nativeGeo:         DocumentGeometry = .article
    var nativeFonts:       TeXFontConfig    = .palatino
    var refPDF:            PDFDocument?     = nil
    var ssimScores:        [Double]         = []    // per-page
    var diffImages:        [CGImage?]       = []    // per-page RGB diff
}

// MARK: - ParityTestView

struct ParityTestView: View {

    @State private var corpus:        [CorpusEntry] = []
    @State private var selected:      CorpusEntry?  = nil
    @State private var pageIndex:     Int           = 0
    @State private var comparison:    ComparisonResult? = nil
    @State private var isRendering:   Bool          = false
    @State private var showDiffOnly:  Bool          = false
    @State private var diffScale:     Double        = 3.0   // amplification for diff image
    @State private var isExporting:   Bool          = false
    @State private var exportStatus:  String?       = nil

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationTitle("Parity Test Bench")
        .task { await loadCorpus() }
        .toolbar { toolbarContent }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(corpus, selection: $selected) { entry in
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).font(.caption.bold())
                HStack(spacing: 4) {
                    Circle()
                        .fill(entry.referencePDF != nil ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(entry.referencePDF != nil ? "ref PDF" : "no ref")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .tag(entry)
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 175, ideal: 210)
        .onChange(of: selected) { _, _ in pageIndex = 0; Task { await render() } }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if isRendering {
            ProgressView("Rendering…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let c = comparison {
            VStack(spacing: 0) {
                pageBar(c)
                Divider()
                HStack(spacing: 0) {
                    nativePane(c)
                    Divider()
                    referencePane(c)
                }
                if !c.diffImages.isEmpty {
                    Divider()
                    diffBar(c)
                }
            }
        } else if corpus.isEmpty {
            noCorpusView
        } else {
            Text("Select a document")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Page navigation bar

    private func pageBar(_ c: ComparisonResult) -> some View {
        HStack(spacing: 12) {
            Button { pageIndex = max(0, pageIndex - 1); Task { await render() } }
                label: { Image(systemName: "chevron.left") }
                .disabled(pageIndex == 0)

            Text("Page \(pageIndex + 1) / \(c.totalNativePages)")
                .monospacedDigit().font(.callout)

            Button { pageIndex = min(c.totalNativePages - 1, pageIndex + 1); Task { await render() } }
                label: { Image(systemName: "chevron.right") }
                .disabled(pageIndex >= c.totalNativePages - 1)

            Spacer()

            if let score = c.ssimScores.first(where: { _ in true }) {
                Text(String(format: "SSIM p%d: %.3f", pageIndex + 1, score))
                    .font(.caption)
                    .foregroundStyle(score > 0.80 ? .green : score > 0.60 ? .orange : .red)
            }

            Text(String(format: "%.0f ms render", c.nativeRenderMs))
                .font(.caption).foregroundStyle(.secondary)

            Toggle("Diff overlay", isOn: $showDiffOnly)
                .toggleStyle(.switch).controlSize(.mini)
                .labelsHidden()
            Text("Diff").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: Native pane (left)

    @ViewBuilder
    private func nativePane(_ c: ComparisonResult) -> some View {
        VStack(spacing: 0) {
            paneHeader("Native Swift CoreText", color: .blue)
            ScrollView {
                if pageIndex < c.nativePages.count {
                    TeXPageView(page: c.nativePages[pageIndex],
                                geometry: c.nativeGeo,
                                fonts: c.nativeFonts)
                        .padding(20)
                } else {
                    Text("(no pages)").foregroundStyle(.secondary).padding()
                }
            }
            .background(Color(white: 0.82))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Reference pane (right)

    @ViewBuilder
    private func referencePane(_ c: ComparisonResult) -> some View {
        VStack(spacing: 0) {
            paneHeader("Reference (pre-compiled PDF)", color: .green)
            ScrollView {
                if showDiffOnly, pageIndex < c.diffImages.count, let diff = c.diffImages[pageIndex] {
                    Image(diff, scale: 1, label: Text("diff"))
                        .resizable().scaledToFit()
                        .padding(20)
                } else if let pdf = c.refPDF {
                    PDFPageView(document: pdf, pageIndex: pageIndex)
                        .padding(20)
                } else {
                    noRefView
                }
            }
            .background(Color(white: 0.82))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Diff bar

    private func diffBar(_ c: ComparisonResult) -> some View {
        HStack(spacing: 12) {
            Text("Diff amplify:").font(.caption2).foregroundStyle(.secondary)
            Slider(value: $diffScale, in: 1...10, step: 0.5) {
                Text("Scale")
            }
            .frame(width: 120)
            Text(String(format: "×%.1f", diffScale)).font(.caption2).foregroundStyle(.secondary)
            Spacer()
            if !c.ssimScores.isEmpty {
                let avg = c.ssimScores.reduce(0, +) / Double(c.ssimScores.count)
                Text(String(format: "Avg SSIM: %.3f", avg))
                    .font(.caption).foregroundStyle(avg > 0.80 ? .green : .orange)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: Helpers

    private func paneHeader(_ title: String, color: Color) -> some View {
        HStack {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).font(.caption.bold())
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var noRefView: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.questionmark").font(.system(size: 36)).foregroundStyle(.secondary)
            Text("No reference PDF").font(.headline)
            Text("Place a compiled .pdf alongside the .tex file to enable comparison.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, minHeight: 300).padding()
    }

    private var noCorpusView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass").font(.system(size: 48)).foregroundStyle(.secondary)
            Text("No corpus loaded").font(.headline)
            Text("No .tex files found in templates/.\nCheck the workspace root path.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Button("Re-render") { Task { await render() } }
                .disabled(selected == nil || isRendering)
        }
        ToolbarItem(placement: .automatic) {
            Button("Run All") { Task { await runAll() } }
                .disabled(isRendering)
        }
        ToolbarItem(placement: .automatic) {
            Button("Export All PDFs") { Task { await exportAll() } }
                .disabled(isRendering || isExporting || corpus.isEmpty)
                .help("Render all corpus documents with the native engine and save as typetex_<name>.pdf next to each .tex file")
        }
        if let status = exportStatus {
            ToolbarItem(placement: .automatic) {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Corpus loading

    private func loadCorpus() async {
        let base = workspaceRoot()
        let fm   = FileManager.default
        var entries: [CorpusEntry] = []

        let searchDirs = [
            base + "/templates/acm-chi/samples",
            base + "/templates/article",
            base + "/templates/ieee",
            base + "/templates/lncs",
            base + "/templates/beamer",
        ]
        for dir in searchDirs {
            guard let items = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for item in items.sorted() where item.hasSuffix(".tex") {
                let texPath = dir + "/" + item
                guard let src = try? String(contentsOfFile: texPath, encoding: .utf8) else { continue }
                let pdfPath = texPath.replacingOccurrences(of: ".tex", with: ".pdf")
                let pdfURL  = fm.fileExists(atPath: pdfPath) ? URL(fileURLWithPath: pdfPath) : nil
                let name    = item.replacingOccurrences(of: ".tex", with: "")
                entries.append(CorpusEntry(name: name, source: src,
                                           sourceURL: URL(fileURLWithPath: texPath),
                                           referencePDF: pdfURL))
            }
        }
        await MainActor.run { corpus = entries }
    }

    private func workspaceRoot() -> String {
        // Resolve from bundle or fall back to compiled-in path
        if let bundlePath = Bundle.main.bundlePath
                            .components(separatedBy: "/").prefix(while: { $0 != "build" }).joined(separator: "/")
                            .nonEmpty {
            let candidate = bundlePath + "/Documents/XCode/Typetex"
            if FileManager.default.fileExists(atPath: candidate + "/templates") { return candidate }
        }
        return "/Users/jonasgunklach/Documents/XCode/Typetex"
    }

    // MARK: - Rendering

    private func render() async {
        guard let entry = selected else { return }
        await MainActor.run { isRendering = true }
        let c = await buildComparison(entry, page: pageIndex)
        await MainActor.run { comparison = c; isRendering = false }
    }

    private func runAll() async {
        await MainActor.run { isRendering = true }
        var results: [(String, Double, Double?)] = []
        for entry in corpus {
            let c = await buildComparison(entry, page: 0)
            let avgSSIM = c.ssimScores.isEmpty ? nil
                : c.ssimScores.reduce(0, +) / Double(c.ssimScores.count)
            results.append((entry.name, c.nativeRenderMs, avgSSIM))
        }
        // Select first entry as display after run-all
        let first = corpus.first
        await MainActor.run {
            isRendering = false
            if let f = first { selected = f }
        }
        print("=== Parity Run-All Results ===")
        for (name, ms, ssim) in results {
            let ssimStr = ssim.map { String(format: "SSIM=%.3f", $0) } ?? "no-ref"
            print(String(format: "  %-45s  %6.0f ms  %@", name, ms, ssimStr))
        }
    }

    // MARK: - Export All PDFs

    private func exportAll() async {
        await MainActor.run { isExporting = true; exportStatus = "Exporting…" }
        let fm = FileManager.default
        var exported = 0
        for entry in corpus {
            // Parse + typeset
            let blocks     = LaTeXParser.parseDocument(entry.source)
            let typesetter = TeXTypesetter()
            typesetter.sourceDirectory = entry.sourceURL.deletingLastPathComponent()
            configureTypesetter(typesetter, source: entry.source)
            if let bibText = findBib(near: entry.sourceURL.deletingLastPathComponent(),
                                     source: entry.source) {
                let resolver = CitationResolver()
                resolver.loadBibFile(bibText)
                typesetter.citationResolver = resolver
            }
            let doc = typesetter.typeset(blocks)
            guard let data = PDFExporter().export(doc, title: entry.name) else { continue }

            // Save as typetex_<name>.pdf next to the .tex file
            let outURL = entry.sourceURL.deletingLastPathComponent()
                .appendingPathComponent("typetex_\(entry.name).pdf")
            do {
                try data.write(to: outURL)
                exported += 1
                print("[Export] wrote \(outURL.lastPathComponent)")
            } catch {
                print("[Export] failed \(entry.name): \(error)")
            }
        }
        await MainActor.run {
            isExporting   = false
            exportStatus  = "Exported \(exported)/\(corpus.count)"
        }
        print("=== Export done: \(exported)/\(corpus.count) PDFs written ===")
    }

    private func buildComparison(_ entry: CorpusEntry, page: Int) async -> ComparisonResult {
        var c = ComparisonResult()

        // 1. Native render
        let t0 = Date()
        let blocks     = LaTeXParser.parseDocument(entry.source)
        let typesetter = TeXTypesetter()
        typesetter.sourceDirectory = entry.sourceURL.deletingLastPathComponent()
        configureTypesetter(typesetter, source: entry.source)
        let doc = typesetter.typeset(blocks)
        c.nativeRenderMs   = Date().timeIntervalSince(t0) * 1000
        c.nativeGeo        = typesetter.geometry
        c.nativeFonts      = typesetter.fonts
        c.totalNativePages = doc.pages.count
        c.nativePages      = doc.pages

        // Load bib if present
        let bibURL = entry.sourceURL.deletingLastPathComponent()
        let bib    = findBib(near: bibURL, source: entry.source)
        if let bibText = bib {
            let resolver = CitationResolver()
            resolver.loadBibFile(bibText)
            typesetter.citationResolver = resolver
        }

        // 2. Reference PDF
        if let pdfURL = entry.referencePDF,
           let pdfDoc = PDFDocument(url: pdfURL) {
            c.refPDF = pdfDoc

            // 3. Per-page SSIM comparison (first 3 pages max, async rasterise)
            let pagesToCompare = min(c.totalNativePages, min(pdfDoc.pageCount, 3))
            for pi in 0..<pagesToCompare {
                if pi < doc.pages.count,
                   let nativeCG = rasterisePage(doc.pages[pi], geo: typesetter.geometry,
                                                fonts: typesetter.fonts),
                   let pdfCG    = rasterisePDFPage(pdfDoc, pageIndex: pi) {
                    let (ssim, diff) = computeSSIM(nativeCG, pdfCG, diffScale: diffScale)
                    c.ssimScores.append(ssim)
                    c.diffImages.append(diff)
                }
            }
        }
        return c
    }

    private func configureTypesetter(_ ts: TeXTypesetter, source: String) {
        let lo = source.lowercased()
        if lo.contains("sigconf") || lo.contains("acmart") {
            ts.geometry = .acmSigConf; ts.fonts = .timesACM
            ts.documentClass = "acmart"
        } else if lo.contains("ieee") || lo.contains("ieeetran") {
            ts.geometry = .ieeeConference; ts.fonts = .timesIEEE
            ts.documentClass = "IEEEtran"
        } else if lo.contains("lncs") || lo.contains("llncs") {
            ts.geometry = .lncs; ts.fonts = .timesLNCS
            ts.documentClass = "llncs"
        } else if lo.contains("a4paper") {
            ts.geometry = .a4Article; ts.fonts = .palatino
            ts.documentClass = "article"
        } else {
            ts.geometry = .article; ts.fonts = .palatino
            ts.documentClass = "article"
        }
    }

    private func findBib(near dir: URL, source: String) -> String? {
        // Extract \bibliography{name} argument
        let pattern = "\\bibliography{"
        guard let r = source.range(of: pattern) else { return nil }
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

    // MARK: - Rasterisation

    private func rasterisePage(_ page: TypesetPage, geo: DocumentGeometry,
                                fonts: TeXFontConfig) -> CGImage? {
        let scale: CGFloat = 1.5
        let w = Int(geo.paperWidth  * scale)
        let h = Int(geo.paperHeight * scale)
        guard w > 0, h > 0 else { return nil }
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        ctx.scaleBy(x: scale, y: scale)
        let bounds = CGRect(origin: .zero, size: CGSize(width: geo.paperWidth, height: geo.paperHeight))
        TeXPageRenderer.render(page: page, geometry: geo, fonts: fonts, in: ctx, bounds: bounds)
        return ctx.makeImage()
    }

    private func rasterisePDFPage(_ doc: PDFDocument, pageIndex: Int) -> CGImage? {
        guard pageIndex < doc.pageCount, let page = doc.page(at: pageIndex) else { return nil }
        let scale: CGFloat = 1.5
        let bounds = page.bounds(for: .mediaBox)
        let w = Int(bounds.width  * scale)
        let h = Int(bounds.height * scale)
        guard w > 0, h > 0 else { return nil }
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        ctx.scaleBy(x: scale, y: -scale)
        ctx.translateBy(x: 0, y: -bounds.height)
        page.draw(with: .mediaBox, to: ctx)
        return ctx.makeImage()
    }

    // MARK: - SSIM

    /// Resize both images to the same size, compute per-pixel diff and SSIM approximation.
    private func computeSSIM(_ a: CGImage, _ b: CGImage, diffScale: Double) -> (Double, CGImage?) {
        let tW = min(a.width, b.width)
        let tH = min(a.height, b.height)
        guard tW > 0, tH > 0 else { return (0, nil) }

        let ciA = CIImage(cgImage: a).transformed(by: .identity)
        let ciB = CIImage(cgImage: b).transformed(by: .identity)

        // Crop to common size
        let cropRect = CGRect(x: 0, y: 0, width: CGFloat(tW), height: CGFloat(tH))
        let cropA = ciA.cropped(to: cropRect)
        let cropB = ciB.cropped(to: cropRect)

        // Difference
        let diffFilter = CIFilter.colorAbsoluteDifference()
        diffFilter.inputImage  = cropA
        diffFilter.inputImage2 = cropB
        guard let diffOut = diffFilter.outputImage else { return (0, nil) }

        // Amplify diff for visibility
        let amp = CIFilter.colorControls()
        amp.inputImage  = diffOut
        amp.brightness  = 0
        amp.contrast    = Float(diffScale)
        amp.saturation  = 1
        let ampOut = amp.outputImage ?? diffOut

        let ciCtx  = CIContext()
        let diffCG = ciCtx.createCGImage(ampOut, from: cropRect)

        // SSIM approximation: mean squared error → SSIM
        let stats = CIFilter.areaAverage()
        stats.inputImage = diffOut.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector":   CIVector(x: 1/3, y: 1/3, z: 1/3, w: 0),
            "inputGVector":   CIVector(x: 0,   y: 0,   z: 0,   w: 0),
            "inputBVector":   CIVector(x: 0,   y: 0,   z: 0,   w: 0),
            "inputAVector":   CIVector(x: 0,   y: 0,   z: 0,   w: 1),
            "inputBiasVector":CIVector(x: 0,   y: 0,   z: 0,   w: 0)
        ])
        stats.extent = cropRect
        guard let avgImg = stats.outputImage else { return (0, diffCG) }
        var pixel = [Float](repeating: 0, count: 4)
        ciCtx.render(avgImg, toBitmap: &pixel, rowBytes: 16,
                     bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                     format: .RGBAf, colorSpace: nil)
        let meanDiff = Double(pixel[0])          // mean absolute diff [0..1]
        let mse      = meanDiff * meanDiff
        // Simple SSIM proxy: 1 - normalised MSE
        let ssim = max(0, 1.0 - mse * 100)
        return (ssim, diffCG)
    }
}

// MARK: - PDFPageView — PDFKit page wrapped for SwiftUI

struct PDFPageView: NSViewRepresentable {
    let document:  PDFDocument
    let pageIndex: Int

    func makeNSView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales    = true
        v.displayMode   = .singlePage
        v.displayBox    = .mediaBox
        v.document      = document
        return v
    }
    func updateNSView(_ v: PDFView, context: Context) {
        if v.document !== document { v.document = document }
        if pageIndex < document.pageCount, let p = document.page(at: pageIndex) {
            v.go(to: p)
        }
    }
}

// MARK: - String helper

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

#Preview {
    ParityTestView()
        .frame(width: 1200, height: 900)
}
