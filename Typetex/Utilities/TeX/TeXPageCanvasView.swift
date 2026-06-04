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

        // Column separator rule for two-column layouts
        if geometry.columnCount == 2 {
            let sepX = geometry.marginLeft + geometry.columnWidth + geometry.columnSep / 2
            let ruleTop    = geometry.marginTop
            let ruleBottom = geometry.paperHeight - geometry.marginBottom
            let ruleTopFlipped    = bounds.height - ruleTop
            let ruleBottomFlipped = bounds.height - ruleBottom
            ctx.saveGState()
            ctx.setStrokeColor(CGColor(gray: 0.5, alpha: 0.35))
            ctx.setLineWidth(0.4)
            ctx.move(to: CGPoint(x: sepX, y: ruleBottomFlipped))
            ctx.addLine(to: CGPoint(x: sepX, y: ruleTopFlipped))
            ctx.strokePath()
            ctx.restoreGState()
        }

        ctx.restoreGState()
    }

    private static func renderBlock(_ block: TypesetBlock, geometry: DocumentGeometry,
                                     fonts: TeXFontConfig, in ctx: CGContext, paperH: CGFloat) {
        switch block {

        case .ctFrame(let frame, _):
            // CTFrame paths are in Y-DOWN (typesetter) coords. CoreText requires a
            // Y-DOWN context — flip before drawing so glyphs are right-side-up.
            ctx.saveGState()
            ctx.textMatrix = .identity
            ctx.translateBy(x: 0, y: paperH)
            ctx.scaleBy(x: 1, y: -1)
            CTFrameDraw(frame, ctx)
            ctx.restoreGState()

        case .mathDisplay(let node, let rect):
            ctx.saveGState()
            ctx.setFillColor(CGColor(gray: 0.04, alpha: 1))
            ctx.setStrokeColor(CGColor(gray: 0.04, alpha: 1))
            ctx.textMatrix = .identity
            // Use toFlipped coords directly — same y-up system as the context
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

        case .colorRule(let color, let rect):
            ctx.setFillColor(color)
            ctx.fill(toFlipped(rect, paperH: paperH))

        case .titleBlock(let tb):
            renderTitleBlock(tb, fonts: fonts, in: ctx, paperH: paperH)

        case .imageBlock(let imgData):
            renderImageBlock(imgData, in: ctx, paperH: paperH)

        case .tableGrid(let tableData):
            renderTableGrid(tableData, in: ctx, paperH: paperH, fonts: fonts)

        case .tcolorboxBlock(let boxData):
            renderTcolorbox(boxData, in: ctx, paperH: paperH, fonts: fonts)

        case .pageNumberBlock(let number, let rect):
            ctx.saveGState()
            ctx.textMatrix = .identity
            ctx.translateBy(x: 0, y: paperH)
            ctx.scaleBy(x: 1, y: -1)
            let sz: CGFloat = fonts.bodySize * 0.9
            let font = CTFontCreateWithName(fonts.bodyFace as CFString, sz, nil)
            let para = NSMutableParagraphStyle(); para.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                kCTFontAttributeName as NSAttributedString.Key: font,
                NSAttributedString.Key.paragraphStyle: para,
                kCTForegroundColorFromContextAttributeName as NSAttributedString.Key: true
            ]
            let numStr = NSAttributedString(string: "\(number)", attributes: attrs)
            let path   = CGPath(rect: rect, transform: nil)
            let fs     = CTFramesetterCreateWithAttributedString(numStr as CFAttributedString)
            let frame  = CTFramesetterCreateFrame(fs, CFRangeMake(0, 0), path, nil)
            CTFrameDraw(frame, ctx)
            ctx.restoreGState()

        case .verticalSpace:
            break

        case .columnBreak:
            break

        default:
            break
        }
    }

    // MARK: - Image block

    private static func renderImageBlock(_ imgData: ImageBlockData,
                                          in ctx: CGContext, paperH: CGFloat) {
        let rect = toFlipped(imgData.rect, paperH: paperH)
        ctx.saveGState()
        if let img = imgData.cgImage {
            ctx.draw(img, in: rect)
        } else {
            // Placeholder grey box with diagonal cross
            ctx.setFillColor(CGColor(gray: 0.85, alpha: 1))
            ctx.fill(rect)
            ctx.setStrokeColor(CGColor(gray: 0.6, alpha: 1))
            ctx.setLineWidth(0.5)
            ctx.stroke(rect)
            ctx.move(to: rect.origin)
            ctx.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            ctx.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            ctx.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    // MARK: - Table grid

    private static func renderTableGrid(_ tableData: TableGridData,
                                         in ctx: CGContext, paperH: CGFloat,
                                         fonts: TeXFontConfig) {
        let tableRect = toFlipped(tableData.rect, paperH: paperH)
        ctx.saveGState()

        // Background
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(tableRect)

        var y = tableRect.maxY  // top of table in flipped coords

        // Draw rows
        var rowIdx = 0
        for (ri, row) in tableData.cells.enumerated() {
            let rowH: CGFloat = ri < tableData.rowHeights.count ? tableData.rowHeights[ri] : 20
            let rowY = y - rowH

            // Header background
            if ri == 0 {
                ctx.setFillColor(CGColor(gray: 0.92, alpha: 1))
                ctx.fill(CGRect(x: tableRect.minX, y: rowY, width: tableRect.width, height: rowH))
            }

            var x = tableRect.minX
            for (ci, cell) in row.enumerated() {
                let colW = ci < tableData.columnWidths.count ? tableData.columnWidths[ci] : 60
                let pad: CGFloat = 4
                let cellRect = CGRect(x: x + pad, y: rowY + pad,
                                      width: colW - pad * 2, height: rowH - pad * 2)
                ctx.saveGState()
                ctx.textMatrix = .identity
                // cellRect is already in y-up coords — draw directly, no per-cell flip
                let path  = CGPath(rect: cellRect, transform: nil)
                let fs    = CTFramesetterCreateWithAttributedString(cell.content as CFAttributedString)
                let frame = CTFramesetterCreateFrame(fs, CFRangeMake(0,0), path, nil)
                CTFrameDraw(frame, ctx)
                ctx.restoreGState()
                x += colW
            }

            // Draw row separator
            ctx.setStrokeColor(CGColor(gray: 0.7, alpha: 1))
            ctx.setLineWidth(0.5)
            ctx.move(to: CGPoint(x: tableRect.minX, y: rowY))
            ctx.addLine(to: CGPoint(x: tableRect.maxX, y: rowY))
            ctx.strokePath()

            y -= rowH
        }

        // Outer border
        ctx.setStrokeColor(CGColor(gray: 0.3, alpha: 1))
        ctx.setLineWidth(tableData.isBooktabs ? 1.5 : 0.8)
        ctx.stroke(tableRect)

        ctx.restoreGState()
    }

    // MARK: - Tcolorbox

    private static func renderTcolorbox(_ boxData: TcolorboxData,
                                         in ctx: CGContext, paperH: CGFloat,
                                         fonts: TeXFontConfig) {
        let rect = toFlipped(boxData.rect, paperH: paperH)
        ctx.saveGState()

        // Background
        ctx.setFillColor(boxData.background)
        let path = CGPath(roundedRect: rect,
                          cornerWidth: boxData.cornerRadius,
                          cornerHeight: boxData.cornerRadius, transform: nil)
        ctx.addPath(path); ctx.fillPath()

        // Border
        ctx.setStrokeColor(boxData.borderColor)
        ctx.setLineWidth(boxData.borderWidth)
        ctx.addPath(path); ctx.strokePath()

        // Title bar
        let bw = boxData.borderWidth
        if let titleStr = boxData.title {
            let titleH = suggestHeight(titleStr, width: rect.width - bw*2) + 8
            let titleBarRect = CGRect(x: rect.minX + bw, y: rect.maxY - titleH - bw,
                                      width: rect.width - bw*2, height: titleH)
            ctx.setFillColor(boxData.titleBackground)
            ctx.fill(titleBarRect)

            // Title text — flip context for CoreText; convert titleBarRect back to Y-DOWN.
            ctx.saveGState()
            ctx.textMatrix = .identity
            ctx.translateBy(x: 0, y: paperH)
            ctx.scaleBy(x: 1, y: -1)
            // titleBarRect is Y-UP; toFlipped converts it back to Y-DOWN coords.
            let titleBarRectDown = toFlipped(titleBarRect, paperH: paperH)
            let titleTextRect = CGRect(x: titleBarRectDown.minX + 4,
                                       y: titleBarRectDown.minY + 2,
                                       width: titleBarRectDown.width - 8,
                                       height: titleBarRectDown.height - 4)
            let titlePath  = CGPath(rect: titleTextRect, transform: nil)
            let titleFs    = CTFramesetterCreateWithAttributedString(titleStr as CFAttributedString)
            let titleFrame = CTFramesetterCreateFrame(titleFs, CFRangeMake(0,0), titlePath, nil)
            CTFrameDraw(titleFrame, ctx)
            ctx.restoreGState()
        }

        // Content blocks (already positioned in sub-typesetter space; need translation)
        // For tcolorbox, content blocks are positioned relative to the box origin
        let contentOffsetY = boxData.rect.minY + bw
        let contentOffsetX = boxData.rect.minX + bw
        ctx.saveGState()
        ctx.translateBy(x: contentOffsetX, y: 0)
        for blk in boxData.contentBlocks {
            renderBlock(blk, geometry: DocumentGeometry.article, fonts: fonts,
                        in: ctx, paperH: paperH)
        }
        ctx.restoreGState()

        ctx.restoreGState()
    }

    private static func renderTitleBlock(_ tb: TypesetTitleBlock, fonts: TeXFontConfig,
                                          in ctx: CGContext, paperH: CGFloat) {
        ctx.saveGState()
        // Flip to Y-DOWN so CTFrameDraw renders glyphs right-side-up.
        ctx.textMatrix = .identity
        ctx.translateBy(x: 0, y: paperH)
        ctx.scaleBy(x: 1, y: -1)
        ctx.setFillColor(CGColor(gray: 0.04, alpha: 1))

        // tb.rect is already in Y-DOWN (typesetter) coords — use directly.
        var y = tb.rect.minY  // top of title block (Y-DOWN: small y = near top)
        let titleX = tb.rect.minX
        let titleW = tb.rect.width

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
        let titleH = suggestHeight(titleAttr, width: titleW)
        let titleRect = CGRect(x: titleX, y: y, width: titleW, height: titleH)
        let titleFrame = makeFrame(titleAttr, rect: titleRect)
        CTFrameDraw(titleFrame, ctx)
        y += titleH + titleFs * 0.3

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
            let authorRect = CGRect(x: titleX, y: y, width: titleW, height: authorH)
            let authorFrame = makeFrame(authorAttr, rect: authorRect)
            CTFrameDraw(authorFrame, ctx)
            y += authorH + authorFs * 0.4
        }

        // Separator rule (direct fill in flipped Y-DOWN context — coords are Y-DOWN here)
        ctx.setFillColor(CGColor(gray: 0.2, alpha: 1))
        ctx.fill(CGRect(x: titleX + 20, y: y, width: titleW - 40, height: 0.5))

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
