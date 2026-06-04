// PDFExporter.swift — Export a TypesetDocument to PDF using CGPDFContext
import Foundation
import CoreGraphics
import CoreText
#if os(macOS)
import AppKit
#else
import UIKit
#endif

final class PDFExporter {

    // MARK: - Export to Data

    /// Render the given TypesetDocument to PDF bytes.
    func export(_ doc: TypesetDocument, title: String? = nil,
                author: String? = nil) -> Data? {
        guard !doc.pages.isEmpty else { return nil }

        let pageWidth  = doc.geometry.paperWidth
        let pageHeight = doc.geometry.paperHeight

        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return nil }

        var auxiliaryInfo: [String: Any] = [:]
        if let t = title  { auxiliaryInfo[kCGPDFContextTitle  as String] = t }
        if let a = author { auxiliaryInfo[kCGPDFContextAuthor as String] = a }

        guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox,
                                   auxiliaryInfo as CFDictionary) else { return nil }

        for page in doc.pages {
            ctx.beginPDFPage(nil)

            // White background
            ctx.setFillColor(CGColor(red: 0.995, green: 0.993, blue: 0.985, alpha: 1))
            ctx.fill(mediaBox)

            ctx.setFillColor(CGColor(gray: 0.04, alpha: 1))
            ctx.setStrokeColor(CGColor(gray: 0.04, alpha: 1))
            ctx.textMatrix = .identity

            TeXPageRenderer.render(
                page: page,
                geometry: doc.geometry,
                fonts: doc.fonts,
                in: ctx,
                bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))

            ctx.endPDFPage()
        }

        ctx.closePDF()
        return data as Data
    }

    // MARK: - Save to file

    /// Write PDF to a temporary file, return URL.
    func exportToTemporaryFile(_ doc: TypesetDocument,
                               title: String? = nil) -> URL? {
        guard let data = export(doc, title: title) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        try? data.write(to: url)
        return url
    }

    // MARK: - Render statistics

    struct RenderStats {
        var pageCount: Int
        var blockCount: Int
        var renderTimeMs: Double
        var pdfSizeBytes: Int
    }

    func exportWithStats(_ doc: TypesetDocument,
                         title: String? = nil) -> (data: Data?, stats: RenderStats) {
        let t0 = Date()
        let data = export(doc, title: title)
        let elapsed = Date().timeIntervalSince(t0) * 1000
        let stats = RenderStats(
            pageCount: doc.pages.count,
            blockCount: doc.pages.reduce(0) { $0 + $1.blocks.count },
            renderTimeMs: elapsed,
            pdfSizeBytes: data?.count ?? 0)
        return (data, stats)
    }
}
