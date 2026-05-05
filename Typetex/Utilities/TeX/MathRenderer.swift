//  MathRenderer.swift — Full math layout & CoreGraphics drawing engine
import CoreGraphics
import CoreText
import Foundation

// MARK: - Math size computation and drawing

final class MathRenderer {

    static let shared = MathRenderer()

    // MARK: - Public API

    /// Compute bounding box of a math node (origin at baseline left)
    func size(of node: MathNode, style: MathStyle, baseFontSize: CGFloat) -> MathBox {
        let fs = style.fontSize(base: baseFontSize)
        return layoutBox(node, style: style, fs: fs)
    }

    /// Draw a math node into a CGContext. Origin = baseline-left of the node.
    func draw(_ node: MathNode, at origin: CGPoint, style: MathStyle,
              baseFontSize: CGFloat, color: CGColor, in ctx: CGContext) {
        let fs = style.fontSize(base: baseFontSize)
        ctx.saveGState()
        ctx.setFillColor(color)
        ctx.setStrokeColor(color)
        drawNode(node, at: origin, style: style, fs: fs, ctx: ctx)
        ctx.restoreGState()
    }

    // MARK: - Box (width, height above baseline, depth below baseline)

    struct MathBox {
        var width:  CGFloat
        var height: CGFloat   // above baseline
        var depth:  CGFloat   // below baseline (positive)
        var totalHeight: CGFloat { height + depth }
    }

    // MARK: - CTFont helpers

    private func ctFont(face: String, size: CGFloat) -> CTFont {
        CTFontCreateWithName(face as CFString, size, nil)
    }

    private func mathFont(fs: CGFloat) -> CTFont {
        // Prefer STIX Two Math; fallback to Palatino-Italic
        let candidates = ["STIXTwoMath-Regular", "STIX-Regular", "Palatino-Italic", "Georgia-Italic"]
        for name in candidates {
            let f = CTFontCreateWithName(name as CFString, fs, nil)
            if CTFontGetGlyphCount(f) > 100 { return f }
        }
        return CTFontCreateWithName("Helvetica" as CFString, fs, nil)
    }

    private func textFont(fs: CGFloat, bold: Bool = false, italic: Bool = false) -> CTFont {
        let names: [String]
        if bold && italic { names = ["Palatino-BoldItalic", "Georgia-BoldItalic"] }
        else if bold      { names = ["Palatino-Bold",       "Georgia-Bold"] }
        else if italic    { names = ["Palatino-Italic",     "Georgia-Italic"] }
        else              { names = ["Palatino-Roman",      "Georgia"] }
        for n in names {
            let f = CTFontCreateWithName(n as CFString, fs, nil)
            if CTFontGetGlyphCount(f) > 100 { return f }
        }
return CTFontCreateWithName("Helvetica" as CFString, fs, nil)
    }

    // MARK: - Metrics

    private func axisHeight(_ fs: CGFloat) -> CGFloat { fs * 0.258 }
    private func ruleThickness(_ fs: CGFloat) -> CGFloat { max(fs * 0.055, 0.4) }
    private func sqrtKern(_ fs: CGFloat) -> CGFloat { fs * 0.1 }

    private func measureString(_ s: String, font: CTFont) -> MathBox {
        let attrStr = NSAttributedString(string: s, attributes: [kCTFontAttributeName as NSAttributedString.Key: font])
        let line = CTLineCreateWithAttributedString(attrStr as CFAttributedString)
        var asc: CGFloat = 0, desc: CGFloat = 0, lead: CGFloat = 0
        let w = CTLineGetTypographicBounds(line, &asc, &desc, &lead)
        return MathBox(width: CGFloat(w), height: asc, depth: abs(desc))
    }

    // MARK: - Layout (returns bounding box)

    private func layoutBox(_ node: MathNode, style: MathStyle, fs: CGFloat) -> MathBox {
        switch node {

        case .atom(let s, _, let mf):
            let font: CTFont
            switch mf {
            case .it: font = textFont(fs: fs, italic: true)
            case .bf: font = textFont(fs: fs, bold: true)
            case .tt: font = ctFont(face: "Menlo-Regular", size: fs)
            default:  font = textFont(fs: fs, italic: s.count == 1 && s.first?.isLetter == true)
            }
            let box = measureString(s, font: font)
            return MathBox(width: box.width + 0.5, height: box.height, depth: box.depth)

        case .group(let nodes):
            return layoutGroup(nodes, style: style, fs: fs)

        case .text(let s):
            let font = textFont(fs: fs)
            return measureString(s, font: font)

        case .space(let w):
            return MathBox(width: w * fs / 18, height: fs * 0.7, depth: 0)

        case .script(let base, let sup, let sub):
            return layoutScript(base: base, sup: sup, sub: sub, style: style, fs: fs)

        case .fraction(let num, let denom, _):
            return layoutFraction(num: num, denom: denom, style: style, fs: fs)

        case .radical(_, let body):
            return layoutRadical(body: body, style: style, fs: fs)

        case .largeOp(let name, let sub, let sup, let limits):
            return layoutLargeOp(name: name, sub: sub, sup: sup, limits: limits, style: style, fs: fs)

        case .fence(let open, let body, let close):
            let inner = layoutGroup(body, style: style, fs: fs)
            let oh = fenceHeight(inner.totalHeight, fs: fs)
            let ow = fenceWidth(fs)
            return MathBox(width: ow + inner.width + ow + 1,
                           height: oh * 0.6, depth: oh * 0.4)

        case .matrix(let rows, _):
            return layoutMatrix(rows: rows, style: style, fs: fs)
        }
    }

    private func layoutGroup(_ nodes: [MathNode], style: MathStyle, fs: CGFloat) -> MathBox {
        var totalWidth: CGFloat = 0
        var maxHeight: CGFloat = 0
        var maxDepth:  CGFloat = 0
        for n in nodes {
            let b = layoutBox(n, style: style, fs: fs)
            totalWidth += b.width
            maxHeight = max(maxHeight, b.height)
            maxDepth  = max(maxDepth,  b.depth)
        }
        return MathBox(width: totalWidth, height: maxHeight, depth: maxDepth)
    }

    private func layoutScript(base: MathNode, sup: MathNode?, sub: MathNode?, style: MathStyle, fs: CGFloat) -> MathBox {
        let baseBox  = layoutBox(base, style: style, fs: fs)
        let scriptFs = style.subscriptStyle.fontSize(base: fs)
        var totalW = baseBox.width
        var h = baseBox.height
        var d = baseBox.depth

        if let sup = sup {
            let b = layoutBox(sup, style: style.subscriptStyle, fs: scriptFs)
            let raise = baseBox.height * 0.5 + fs * 0.1
            h = max(h, raise + b.height)
            totalW = max(totalW, baseBox.width + b.width)
        }
        if let sub = sub {
            let b = layoutBox(sub, style: style.subscriptStyle, fs: scriptFs)
            let drop = baseBox.depth + fs * 0.1
            d = max(d, drop + b.depth)
            totalW = max(totalW, baseBox.width + b.width)
        }
        return MathBox(width: totalW, height: h, depth: d)
    }

    private func layoutFraction(num: MathNode, denom: MathNode, style: MathStyle, fs: CGFloat) -> MathBox {
        let ns = style.numeratorStyle
        let ds = style.denominatorStyle
        let nb = layoutBox(num,   style: ns, fs: ns.fontSize(base: fs))
        let db = layoutBox(denom, style: ds, fs: ds.fontSize(base: fs))
        let ruleT   = ruleThickness(fs)
        let axisH   = axisHeight(fs)
        let numGap  = fs * 0.12
        let denomGap = fs * 0.12
        let w = max(nb.width, db.width) + fs * 0.3
        let h = axisH + ruleT / 2 + numGap + nb.totalHeight
        let d = -axisH + ruleT / 2 + denomGap + db.totalHeight
        return MathBox(width: w, height: h, depth: max(d, 0))
    }

    private func layoutRadical(body: MathNode, style: MathStyle, fs: CGFloat) -> MathBox {
        let bb = layoutBox(body, style: style, fs: fs)
        let kern = sqrtKern(fs)
        let signW = fs * 0.55
        return MathBox(width: signW + bb.width + kern * 2,
                       height: bb.height + kern + ruleThickness(fs) * 1.5,
                       depth: bb.depth)
    }

    private func layoutLargeOp(name: String, sub: MathNode?, sup: MathNode?,
                                limits: Bool, style: MathStyle, fs: CGFloat) -> MathBox {
        let opFs = style == .display ? fs * 1.4 : fs
        let font = mathFont(fs: opFs)
        let sym  = largeOpSymbol(name)
        let ob   = measureString(sym, font: font)
        let scriptFs = style.subscriptStyle.fontSize(base: fs)
        var w = ob.width
        var h = ob.height
        var d = ob.depth

        if limits && style == .display {
            if let s = sup {
                let b = layoutBox(s, style: style.subscriptStyle, fs: scriptFs)
                h += b.totalHeight + fs * 0.1
                w = max(w, b.width)
            }
            if let s = sub {
                let b = layoutBox(s, style: style.subscriptStyle, fs: scriptFs)
                d += b.totalHeight + fs * 0.1
                w = max(w, b.width)
            }
        }
        return MathBox(width: w, height: h, depth: d)
    }

    private func layoutMatrix(rows: [[MathNode]], style: MathStyle, fs: CGFloat) -> MathBox {
        guard !rows.isEmpty, !rows[0].isEmpty else { return MathBox(width: 0, height: 0, depth: 0) }
        let cols = rows[0].count
        var colWidths = [CGFloat](repeating: 0, count: cols)
        var rowHeights = [(h: CGFloat, d: CGFloat)]()
        for row in rows {
            var rh: CGFloat = 0; var rd: CGFloat = 0
            for (ci, cell) in row.enumerated() {
                let b = layoutBox(cell, style: style, fs: fs)
                colWidths[ci] = max(colWidths[ci], b.width)
                rh = max(rh, b.height); rd = max(rd, b.depth)
            }
            rowHeights.append((rh, rd))
        }
        let colSep: CGFloat = fs * 0.7
        let rowSep: CGFloat = fs * 0.35
        let totalW = colWidths.reduce(0, +) + colSep * CGFloat(cols - 1)
        let totalH = rowHeights.reduce(0) { $0 + $1.h + $1.d } + rowSep * CGFloat(rows.count - 1)
        return MathBox(width: totalW, height: totalH * 0.5, depth: totalH * 0.5)
    }

    // MARK: - Drawing

    private func drawNode(_ node: MathNode, at origin: CGPoint, style: MathStyle, fs: CGFloat, ctx: CGContext) {
        switch node {

        case .atom(let s, _, let mf):
            let font: CTFont
            switch mf {
            case .it: font = textFont(fs: fs, italic: true)
            case .bf: font = textFont(fs: fs, bold: true)
            case .tt: font = ctFont(face: "Menlo-Regular", size: fs)
            default:  font = textFont(fs: fs, italic: s.count == 1 && s.first?.isLetter == true)
            }
            drawString(s, at: origin, font: font, ctx: ctx)

        case .text(let s):
            drawString(s, at: origin, font: textFont(fs: fs), ctx: ctx)

        case .space:
            break

        case .group(let nodes):
            var x = origin.x
            for n in nodes {
                let b = layoutBox(n, style: style, fs: fs)
                drawNode(n, at: CGPoint(x: x, y: origin.y), style: style, fs: fs, ctx: ctx)
                x += b.width
            }

        case .script(let base, let sup, let sub):
            drawScript(base: base, sup: sup, sub: sub, at: origin, style: style, fs: fs, ctx: ctx)

        case .fraction(let num, let denom, let rule):
            drawFraction(num: num, denom: denom, rule: rule, at: origin, style: style, fs: fs, ctx: ctx)

        case .radical(let degree, let body):
            drawRadical(degree: degree, body: body, at: origin, style: style, fs: fs, ctx: ctx)

        case .largeOp(let name, let sub, let sup, let limits):
            drawLargeOp(name: name, sub: sub, sup: sup, limits: limits, at: origin, style: style, fs: fs, ctx: ctx)

        case .fence(let open, let body, let close):
            drawFence(open: open, body: body, close: close, at: origin, style: style, fs: fs, ctx: ctx)

        case .matrix(let rows, _):
            drawMatrix(rows: rows, at: origin, style: style, fs: fs, ctx: ctx)
        }
    }

    private func drawString(_ s: String, at origin: CGPoint, font: CTFont, ctx: CGContext) {
        let attrStr = NSAttributedString(string: s, attributes: [
            kCTFontAttributeName as NSAttributedString.Key: font,
            kCTForegroundColorFromContextAttributeName as NSAttributedString.Key: true
        ])
        let line = CTLineCreateWithAttributedString(attrStr as CFAttributedString)
        ctx.textPosition = origin
        CTLineDraw(line, ctx)
    }

    private func drawScript(base: MathNode, sup: MathNode?, sub: MathNode?,
                            at origin: CGPoint, style: MathStyle, fs: CGFloat, ctx: CGContext) {
        let baseBox  = layoutBox(base, style: style, fs: fs)
        drawNode(base, at: origin, style: style, fs: fs, ctx: ctx)
        let scriptFs = style.subscriptStyle.fontSize(base: fs)
        let scriptStyle = style.subscriptStyle

        if let sup = sup {
            let supY = origin.y + baseBox.height * 0.5 + fs * 0.1
            drawNode(sup, at: CGPoint(x: origin.x + baseBox.width, y: supY),
                     style: scriptStyle, fs: scriptFs, ctx: ctx)
        }
        if let sub = sub {
            let subY = origin.y - baseBox.depth - fs * 0.1
            drawNode(sub, at: CGPoint(x: origin.x + baseBox.width, y: subY),
                     style: scriptStyle, fs: scriptFs, ctx: ctx)
        }
    }

    private func drawFraction(num: MathNode, denom: MathNode, rule: Bool,
                              at origin: CGPoint, style: MathStyle, fs: CGFloat, ctx: CGContext) {
        let ns = style.numeratorStyle
        let ds = style.denominatorStyle
        let nsfs = ns.fontSize(base: fs)
        let dsfs = ds.fontSize(base: fs)
        let nb  = layoutBox(num,   style: ns, fs: nsfs)
        let db  = layoutBox(denom, style: ds, fs: dsfs)
        let ruleT  = ruleThickness(fs)
        let axisH  = axisHeight(fs)
        let numGap = fs * 0.12
        let totalW = max(nb.width, db.width) + fs * 0.3

        // Rule
        if rule {
            ctx.fill(CGRect(x: origin.x, y: origin.y + axisH - ruleT / 2,
                            width: totalW, height: ruleT))
        }
        // Numerator (centered, above rule)
        let numX = origin.x + (totalW - nb.width) / 2
        let numY = origin.y + axisH + ruleT / 2 + numGap + nb.depth
        drawNode(num, at: CGPoint(x: numX, y: numY), style: ns, fs: nsfs, ctx: ctx)

        // Denominator (centered, below rule)
        let denomX = origin.x + (totalW - db.width) / 2
        let denomY = origin.y + axisH - ruleT / 2 - numGap - db.height
        drawNode(denom, at: CGPoint(x: denomX, y: denomY), style: ds, fs: dsfs, ctx: ctx)
    }

    private func drawRadical(degree: MathNode?, body: MathNode,
                             at origin: CGPoint, style: MathStyle, fs: CGFloat, ctx: CGContext) {
        let bb    = layoutBox(body, style: style, fs: fs)
        let kern  = sqrtKern(fs)
        let ruleT = ruleThickness(fs) * 1.5
        let signW = fs * 0.55
        let totalH = bb.totalHeight + kern + ruleT

        // Draw sqrt sign using bezier path
        ctx.setLineWidth(ruleT * 0.7)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        let bx = origin.x
        let by = origin.y - bb.depth
        let topY = by + totalH

        let path = CGMutablePath()
        // Approach stroke (small serif at bottom-left)
        path.move(to: CGPoint(x: bx, y: by + totalH * 0.5))
        // Down-left to bottom
        path.addLine(to: CGPoint(x: bx + signW * 0.3, y: by))
        // Up-right to top of radical sign
        path.addLine(to: CGPoint(x: bx + signW, y: topY))
        // Vinculum (horizontal bar over body)
        path.addLine(to: CGPoint(x: bx + signW + bb.width + kern, y: topY))
        ctx.addPath(path)
        ctx.strokePath()

        // Draw body
        drawNode(body, at: CGPoint(x: origin.x + signW + kern * 0.5, y: origin.y),
                 style: style, fs: fs, ctx: ctx)

        // Degree (small, top-left)
        if let deg = degree {
            let dfs = fs * 0.6
            drawNode(deg, at: CGPoint(x: origin.x, y: origin.y + bb.height + kern),
                     style: .script, fs: dfs, ctx: ctx)
        }
    }

    private func largeOpSymbol(_ name: String) -> String {
        let table: [String: String] = [
            "sum": "\u{2211}", "prod": "\u{220F}", "coprod": "\u{2210}",
            "int": "\u{222B}", "iint": "\u{222C}", "iiint": "\u{222D}",
            "oint": "\u{222E}", "bigcup": "\u{22C3}", "bigcap": "\u{22C2}",
            "bigoplus": "\u{2A01}", "bigotimes": "\u{2A02}",
            "bigvee": "\u{22C1}", "bigwedge": "\u{22C0}",
            "lim": "lim", "sup": "sup", "inf": "inf",
            "max": "max", "min": "min", "det": "det",
        ]
        return table[name] ?? name
    }

    private func drawLargeOp(name: String, sub: MathNode?, sup: MathNode?, limits: Bool,
                             at origin: CGPoint, style: MathStyle, fs: CGFloat, ctx: CGContext) {
        let opFs = style == .display ? fs * 1.4 : fs
        let font = mathFont(fs: opFs)
        let sym  = largeOpSymbol(name)
        let ob   = measureString(sym, font: font)

        let scriptFs = style.subscriptStyle.fontSize(base: fs)
        let ss = style.subscriptStyle

        if limits && style == .display {
            var yTop = origin.y + ob.height
            if let sup = sup {
                let sb = layoutBox(sup, style: ss, fs: scriptFs)
                yTop += sb.depth + fs * 0.1
                let sx = origin.x + (ob.width - sb.width) / 2
                drawNode(sup, at: CGPoint(x: sx, y: yTop), style: ss, fs: scriptFs, ctx: ctx)
                yTop += sb.height
            }
            drawString(sym, at: CGPoint(x: origin.x, y: origin.y), font: font, ctx: ctx)
            var yBot = origin.y - ob.depth
            if let sub = sub {
                let sb = layoutBox(sub, style: ss, fs: scriptFs)
                yBot -= sb.height + fs * 0.1
                let sx = origin.x + (ob.width - sb.width) / 2
                drawNode(sub, at: CGPoint(x: sx, y: yBot), style: ss, fs: scriptFs, ctx: ctx)
            }
        } else {
            drawString(sym, at: origin, font: font, ctx: ctx)
            let x2 = origin.x + ob.width
            if let sup = sup {
                let sb = layoutBox(sup, style: ss, fs: scriptFs)
                drawNode(sup, at: CGPoint(x: x2, y: origin.y + ob.height * 0.4 + fs * 0.1),
                         style: ss, fs: scriptFs, ctx: ctx)
                _ = sb
            }
            if let sub = sub {
                drawNode(sub, at: CGPoint(x: x2, y: origin.y - ob.depth - fs * 0.1),
                         style: ss, fs: scriptFs, ctx: ctx)
            }
        }
    }

    private func fenceHeight(_ bodyH: CGFloat, fs: CGFloat) -> CGFloat {
        max(bodyH, fs * 0.8)
    }
    private func fenceWidth(_ fs: CGFloat) -> CGFloat { fs * 0.45 }

    private func drawFence(open: String, body: [MathNode], close: String,
                           at origin: CGPoint, style: MathStyle, fs: CGFloat, ctx: CGContext) {
        let inner = layoutGroup(body, style: style, fs: fs)
        let oh   = fenceHeight(inner.totalHeight, fs: fs)
        let ow   = fenceWidth(fs)

        // Scale parenthesis/bracket using matrix transform
        drawScaledFence(open, height: oh, at: origin, fs: fs, ctx: ctx)

        var x = origin.x + ow + 0.5
        let yBase = origin.y - (oh - inner.height) / 2 + inner.depth * 0.5
        for n in body {
            let b = layoutBox(n, style: style, fs: fs)
            drawNode(n, at: CGPoint(x: x, y: yBase), style: style, fs: fs, ctx: ctx)
            x += b.width
        }

        drawScaledFence(close, height: oh,
                        at: CGPoint(x: origin.x + ow + inner.width + 1, y: origin.y),
                        fs: fs, ctx: ctx)
    }

    private func drawScaledFence(_ s: String, height: CGFloat, at pt: CGPoint,
                                  fs: CGFloat, ctx: CGContext) {
        let baseFont = textFont(fs: fs)
        let nativeH  = measureString(s, font: baseFont).totalHeight
        guard nativeH > 0 else { return }
        let scale = height / nativeH
        ctx.saveGState()
        ctx.translateBy(x: pt.x, y: pt.y - (height - fs) / 2)
        ctx.scaleBy(x: 1.0, y: scale)
        drawString(s, at: .zero, font: baseFont, ctx: ctx)
        ctx.restoreGState()
    }

    private func drawMatrix(rows: [[MathNode]], at origin: CGPoint,
                            style: MathStyle, fs: CGFloat, ctx: CGContext) {
        let cols = rows.isEmpty ? 0 : rows[0].count
        var colWidths = [CGFloat](repeating: 0, count: cols)
        var rowBoxes = [[(MathBox, MathNode)]]()
        for row in rows {
            var rowData = [(MathBox, MathNode)]()
            for (ci, cell) in row.enumerated() {
                let b = layoutBox(cell, style: style, fs: fs)
                colWidths[ci] = max(colWidths[ci], b.width)
                rowData.append((b, cell))
            }
            rowBoxes.append(rowData)
        }
        let colSep: CGFloat = fs * 0.7
        let rowSep: CGFloat = fs * 1.1
        var y = origin.y
        for (ri, row) in rowBoxes.enumerated() {
            let rowH = row.map { $0.0.height }.max() ?? fs
            var x = origin.x
            for (ci, (box, node)) in row.enumerated() {
                let cellX = x + (colWidths[ci] - box.width) / 2
                drawNode(node, at: CGPoint(x: cellX, y: y), style: style, fs: fs, ctx: ctx)
                x += colWidths[ci] + colSep
            }
            if ri < rowBoxes.count - 1 { y -= rowH + rowSep }
        }
    }
}
