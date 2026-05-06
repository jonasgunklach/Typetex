//  TeXPageCanvasView.swift — Cross-platform CoreText page rendering view
import SwiftUI
import CoreText
import CoreGraphics
import Foundation

#if os(macOS)
import AppKit

// MARK: - NSView page canvas

final class TeXPageNSView: NSView {
    var page:     TypesetPage    = TypesetPage()
    var geometry: DocumentGeometry = .article
    var fonts:    TeXFontConfig    = .palatino

    override var isFlipped: Bool { false }  // We handle coordinate flip manually

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        TeXPageRenderer.render(page: page, geometry: geometry, fonts: fonts,
                               in: ctx, bounds: bounds)
    }
}

// MARK: - NSViewRepresentable wrapper

struct TeXPageRepresentable: NSViewRepresentable {
    let page:     TypesetPage
    let geometry: DocumentGeometry
    let fonts:    TeXFontConfig

    func makeNSView(context: Context) -> TeXPageNSView {
        let v = TeXPageNSView()
        v.page = page
        v.geometry = geometry
        v.fonts = fonts
        return v
    }
    func updateNSView(_ v: TeXPageNSView, context: Context) {
        v.page = page
        v.geometry = geometry
        v.fonts = fonts
        v.setNeedsDisplay(v.bounds)
    }
}

#else
import UIKit

// MARK: - UIView page canvas

final class TeXPageUIView: UIView {
    var page:     TypesetPage     = TypesetPage()
    var geometry: DocumentGeometry = .article
    var fonts:    TeXFontConfig    = .palatino

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        TeXPageRenderer.render(page: page, geometry: geometry, fonts: fonts,
                               in: ctx, bounds: bounds)
    }
}

// MARK: - UIViewRepresentable wrapper

struct TeXPageRepresentable: UIViewRepresentable {
    let page:     TypesetPage
    let geometry: DocumentGeometry
    let fonts:    TeXFontConfig

    func makeUIView(context: Context) -> TeXPageUIView {
        let v = TeXPageUIView()
        v.page = page
        v.geometry = geometry
        v.fonts = fonts
        v.backgroundColor = .clear
        return v
    }
    func updateUIView(_ v: TeXPageUIView, context: Context) {
        v.page = page
        v.geometry = geometry
        v.fonts = fonts
        v.setNeedsDisplay()
    }
}

#endif

// MARK: - Renderer (shared between platforms)

enum TeXPageRenderer {

    static func render(page: TypesetPage, geometry: DocumentGeometry,
                       fonts: TeXFontConfig, in ctx: CGContext, bounds: CGRect) {
        ctx.saveGState()

        // Draw paper (white with subtle cream tint, like TeX output)
        let paperRect = CGRect(origin: .zero, size: bounds.size)

        // Drop shadow
        ctx.setShadow(offset: CGSize(width: 3, height: -4), blur: 10,
                      color: CGColor(gray: 0, alpha: 0.22))
        ctx.setFillColor(CGColor(red: 0.995, green: 0.993, blue: 0.985, alpha: 1))
        ctx.fill(paperRect)
        ctx.setShadow(offset: .zero, blur: 0, color: nil)

        // Thin border
        ctx.setStrokeColor(CGColor(gray: 0.7, alpha: 0.4))
        ctx.setLineWidth(0.3)
        ctx.stroke(paperRect.insetBy(dx: 0.15, dy: 0.15))

        // Text color
        ctx.setFillColor(CGColor(gray: 0.04, alpha: 1))
        ctx.setStrokeColor(CGColor(gray: 0.04, alpha: 1))

        // Render each block
        for block in page.blocks {
            renderBlock(block, geometry: geometry, fonts: fonts,
                        in: ctx, paperH: bounds.height)
        }

        ctx.restoreGState()
    }

    private static func renderBlock(_ block: TypesetBlock, geometry: DocumentGeometry,
                                     fonts: TeXFontConfig, in ctx: CGContext, paperH: CGFloat) {
        switch block {

        case .ctFrame(let frame, let rect):
            // CoreText uses y-from-bottom; our rect uses y-from-top
            let flipped = toFlipped(rect, paperH: paperH)
            ctx.saveGState()
            ctx.textMatrix = .identity
            // Translate so CoreText draws in the right place
            ctx.translateBy(x: 0, y: paperH)
            ctx.scaleBy(x: 1, y: -1)
            // Now rect.minY in original = paperH - rect.maxY in CoreText coords
            // CTFrame was built with flipped rect, so draw at origin
            CTFrameDraw(frame, ctx)
            ctx.restoreGState()

        case .mathDisplay(let node, let rect):
            ctx.saveGState()
            ctx.setFillColor(CGColor(gray: 0.04, alpha: 1))
            ctx.setStrokeColor(CGColor(gray: 0.04, alpha: 1))
            ctx.textMatrix = .identity
            // Math also needs coordinate flip
            ctx.translateBy(x: 0, y: paperH)
            ctx.scaleBy(x: 1, y: -1)
            let flipped = toFlipped(rect, paperH: paperH)
            let origin = CGPoint(x: flipped.minX, y: flipped.minY + flipped.height * 0.2)
            MathRenderer.shared.draw(node, at: origin, style: .display,
                                     baseFontSize: fonts.bodySize * 1.1,
                                     color: CGColor(gray: 0.04, alpha: 1),
                                     in: ctx)
            ctx.restoreGState()

        case .rule(let rect):
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            ctx.fill(toFlipped(rect, paperH: paperH))

        case .titleBlock(let tb):
            renderTitleBlock(tb, fonts: fonts, in: ctx, paperH: paperH)

        case .verticalSpace:
            break

        case .columnBreak:
            break
        }
    }

    private static func renderTitleBlock(_ tb: TypesetTitleBlock, fonts: TeXFontConfig,
                                          in ctx: CGContext, paperH: CGFloat) {
        ctx.saveGState()
        ctx.translateBy(x: 0, y: paperH)
        ctx.scaleBy(x: 1, y: -1)
        ctx.textMatrix = .identity
        ctx.setFillColor(CGColor(gray: 0.04, alpha: 1))

        let flipped = toFlipped(tb.rect, paperH: paperH)
        var y = flipped.maxY  // start at bottom of flipped rect (= top in original)

        // Title
        let titleFs = fonts.bodySize * 1.9
        let titleFont = CTFontCreateWithName(fonts.boldFace as CFString, titleFs, nil)
        let titlePara = NSMutableParagraphStyle()
        titlePara.alignment = .center
        let titleAttr = NSAttributedString(string: tb.title, attributes: [
            kCTFontAttributeName as NSAttributedString.Key: titleFont,
            NSAttributedString.Key.paragraphStyle: titlePara,
            kCTForegroundColorFromContextAttributeName as NSAttributedString.Key: true
        ])
        let titleW = tb.rect.width
        let titleH = suggestHeight(titleAttr, width: titleW)
        let titleRect = CGRect(x: flipped.minX, y: y - titleH, width: titleW, height: titleH)
        let titleFrame = makeFrame(titleAttr, rect: titleRect)
        CTFrameDraw(titleFrame, ctx)
        y -= titleH + titleFs * 0.3

        // Authors
        if !tb.authors.isEmpty {
            let authorStr = tb.authors.joined(separator: "\n")
            let authorFs  = fonts.bodySize * 1.0
            let authorFont = CTFontCreateWithName(fonts.italicFace as CFString, authorFs, nil)
            let authorPara = NSMutableParagraphStyle()
            authorPara.alignment = .center
            let authorAttr = NSAttributedString(string: authorStr, attributes: [
                kCTFontAttributeName as NSAttributedString.Key: authorFont,
                NSAttributedString.Key.paragraphStyle: authorPara,
                kCTForegroundColorFromContextAttributeName as NSAttributedString.Key: true
            ])
            let authorH = suggestHeight(authorAttr, width: titleW)
            let authorRect = CGRect(x: flipped.minX, y: y - authorH, width: titleW, height: authorH)
            let authorFrame = makeFrame(authorAttr, rect: authorRect)
            CTFrameDraw(authorFrame, ctx)
            y -= authorH + authorFs * 0.4
        }

        // Separator rule
        ctx.setFillColor(CGColor(gray: 0.2, alpha: 1))
        ctx.fill(CGRect(x: flipped.minX + 20, y: y - 0.5, width: titleW - 40, height: 0.5))

        ctx.restoreGState()
    }

    private static func makeFrame(_ attrStr: NSAttributedString, rect: CGRect) -> CTFrame {
        let path = CGPath(rect: rect, transform: nil)
        let fs   = CTFramesetterCreateWithAttributedString(attrStr as CFAttributedString)
        return CTFramesetterCreateFrame(fs, CFRangeMake(0, 0), path, nil)
    }

    private static func suggestHeight(_ attrStr: NSAttributedString, width: CGFloat) -> CGFloat {
        let fs = CTFramesetterCreateWithAttributedString(attrStr as CFAttributedString)
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            fs, CFRangeMake(0, 0), nil,
            CGSize(width: width, height: CGFloat.greatestFiniteMagnitude), nil)
        return ceil(size.height) + 4
    }

    static func toFlipped(_ rect: CGRect, paperH: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: paperH - rect.maxY, width: rect.width, height: rect.height)
    }
}

// MARK: - SwiftUI page container

struct TeXPageView: View {
    let page:     TypesetPage
    let geometry: DocumentGeometry
    let fonts:    TeXFontConfig

    var body: some View {
        TeXPageRepresentable(page: page, geometry: geometry, fonts: fonts)
            .frame(width: geometry.paperWidth, height: geometry.paperHeight)
    }
}
