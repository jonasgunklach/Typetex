//  TeXTypesetter.swift — Converts [TexBlock] AST to TypesetDocument
import Foundation
import CoreText
import CoreGraphics
#if os(macOS)
import AppKit
import ImageIO
#else
import UIKit
import ImageIO
#endif

final class TeXTypesetter {

    // MARK: - Configuration

    var geometry: DocumentGeometry = .article
    var fonts:    TeXFontConfig    = .palatino
    /// Document class string (e.g. "IEEEtran", "llncs", "acmart") — drives class-aware rendering.
    var documentClass: String      = "article"
    var citationResolver: CitationResolver? = nil
    /// Directory containing the source .tex file; used to resolve relative image paths.
    var sourceDirectory: URL? = nil

    private var counters     = TeXCounters()
    private var pendingTitle:    String?
    private var pendingAuthors:  [String] = []
    private var pendingAbstract: String?
    private var labels:          [String: String] = [:]
    private var footnotes:       [Int: [TexInline]] = [:]
    private var nextFootnote     = 1

    // MARK: - Entry point

    func typeset(_ blocks: [TexBlock]) -> TypesetDocument {
        counters = TeXCounters()
        pendingTitle = nil; pendingAuthors = []
        pendingAbstract = nil; labels = [:]
        footnotes = [:]; nextFootnote = 1

        scanPreamble(blocks)

        var pages:   [TypesetPage] = [TypesetPage(pageNumber: 1)]
        var col:     Int           = 0
        var cursorY: CGFloat       = geometry.marginTop
        var afterHeading = true  // suppress first-line indent right after headings/title

        var pending = [NSAttributedString]()

        func flushPending() {
            guard !pending.isEmpty else { return }
            let combined = NSMutableAttributedString()
            for p in pending { combined.append(p) }
            pending = []
            appendTextBlock(combined, pages: &pages, col: &col,
                            cursorY: &cursorY, geometry: geometry)
        }

        for block in blocks {
            switch block {

            case .documentMetadata(let title, let authors, _):
                pendingTitle = title; pendingAuthors = authors

            case .abstract(let inner):
                flushPending(); pendingAbstract = extractPlainText(inner)

            case .titleBlock:
                flushPending()
                if let t = pendingTitle {
                    emitTitleBlock(title: t, authors: pendingAuthors,
                                   abstract: pendingAbstract,
                                   pages: &pages, col: &col, cursorY: &cursorY,
                                   geometry: geometry, fonts: fonts)
                }
                afterHeading = true  // first section after title has no indent

            case .heading(let level, let numbered, let inlines):
                flushPending()
                let isIEEEDoc = documentClass.lowercased().contains("ieee")
                let numStr: String
                switch level {
                case 0, 1:
                    if numbered {
                        let n = counters.incrementSectionRaw()
                        numStr = isIEEEDoc
                            ? romanNumeral(n, upper: true) + ".\u{2002}"
                            : "\(n)\u{2002}"
                    } else { numStr = "" }
                case 2:
                    if numbered {
                        let n = counters.incrementSubsectionRaw()
                        if isIEEEDoc {
                            let c = n >= 1 && n <= 26 ? String(UnicodeScalar(64 + n)!) : "\(n)"
                            numStr = "\(c).\u{2002}"
                        } else {
                            numStr = "\(counters.section).\(n)\u{2002}"
                        }
                    } else { numStr = "" }
                case 3:
                    if numbered {
                        let n = counters.incrementSubsubsectionRaw()
                        numStr = isIEEEDoc
                            ? "\(n))\u{2002}"
                            : "\(counters.section).\(counters.subsection).\(n)\u{2002}"
                    } else { numStr = "" }
                default:
                    numStr = ""
                }
                let headText = numStr + inlinesToPlain(inlines)
                let aStr   = makeHeadingAttrStr(headText, level: level, fonts: fonts)
                let above: CGFloat = level <= 1 ? fonts.bodySize * 1.0 : fonts.bodySize * 0.5
                addVS(above, cursorY: &cursorY)
                appendTextBlock(aStr, pages: &pages, col: &col,
                                cursorY: &cursorY, geometry: geometry)
                addVS(fonts.bodySize * 0.3, cursorY: &cursorY)
                afterHeading = true

            case .paragraph(let inlines):
                let indent: CGFloat = afterHeading ? 0 : fonts.bodySize * 1.5
                afterHeading = false
                let a = makeParaAttrStr(inlines, fonts: fonts, firstLineIndent: indent)
                pending.append(a)
                pending.append(NSAttributedString(string: "\n\n", attributes: parasepAttrs(fonts)))

            case .mathDisplay(let src):
                flushPending()
                emitDisplayMath(src, pages: &pages, col: &col, cursorY: &cursorY,
                                fonts: fonts, geometry: geometry)

            case .codeBlock(let src):
                flushPending()
                addVS(fonts.bodySize * 0.4, cursorY: &cursorY)
                appendTextBlock(makeCodeAttrStr(src, fonts: fonts),
                                pages: &pages, col: &col, cursorY: &cursorY, geometry: geometry)
                addVS(fonts.bodySize * 0.4, cursorY: &cursorY)

            case .verbatimBlock(let code, let opts):
                flushPending()
                addVS(fonts.bodySize * 0.5, cursorY: &cursorY)
                let a = makeVerbatimAttrStr(code, opts: opts, fonts: fonts)
                if opts.frame != "none" && !opts.frame.isEmpty {
                    let colR = geometry.columnRect(index: col)
                    let bh   = measureAttrStringHeight(a, width: colR.width) + 4
                    let br   = CGRect(x: colR.minX - 2, y: cursorY - 2,
                                     width: colR.width + 4, height: bh)
                    pages[pages.count-1].blocks.append(
                        .colorRule(color: CGColor(gray: 0.85, alpha: 1), rect: br))
                }
                appendTextBlock(a, pages: &pages, col: &col, cursorY: &cursorY, geometry: geometry)
                addVS(fonts.bodySize * 0.5, cursorY: &cursorY)

            case .bulletList(let items, let opts):
                flushPending()
                let sep: CGFloat = opts.noitemsep ? fonts.bodySize * 0.05 : fonts.bodySize * 0.2
                addVS(sep, cursorY: &cursorY)
                for item in items {
                    let a = makeListItemAttrStr(extractInlinesFromBlocks(item),
                                                bullet: bulletLabel(opts: opts),
                                                fonts: fonts, opts: opts)
                    appendTextBlock(a, pages: &pages, col: &col,
                                    cursorY: &cursorY, geometry: geometry)
                    if opts.noitemsep { addVS(fonts.bodySize * 0.05, cursorY: &cursorY) }
                }
                addVS(sep, cursorY: &cursorY)

            case .numberedList(let items, let opts):
                flushPending()
                let sep: CGFloat = opts.noitemsep ? fonts.bodySize * 0.05 : fonts.bodySize * 0.2
                let start = opts.start ?? 1
                addVS(sep, cursorY: &cursorY)
                for (i, item) in items.enumerated() {
                    let a = makeListItemAttrStr(extractInlinesFromBlocks(item),
                                                bullet: numberedLabel(opts: opts, index: start + i),
                                                fonts: fonts, opts: opts)
                    appendTextBlock(a, pages: &pages, col: &col,
                                    cursorY: &cursorY, geometry: geometry)
                    if opts.noitemsep { addVS(fonts.bodySize * 0.05, cursorY: &cursorY) }
                }
                addVS(sep, cursorY: &cursorY)

            case .descriptionList(let items):
                flushPending()
                for (labelInlines, bodyBlocks) in items {
                    let body = extractInlinesFromBlocks(bodyBlocks)
                    let combined: [TexInline] = [.bold(labelInlines), .text(" ")] + body
                    appendTextBlock(makeParaAttrStr(combined, fonts: fonts),
                                    pages: &pages, col: &col,
                                    cursorY: &cursorY, geometry: geometry)
                }

            case .blockQuote(let inner):
                flushPending()
                addVS(fonts.bodySize * 0.3, cursorY: &cursorY)
                for b in inner {
                    if case .paragraph(let inlines) = b {
                        appendTextBlock(makeBlockQuoteAttrStr(inlines, fonts: fonts),
                                        pages: &pages, col: &col,
                                        cursorY: &cursorY, geometry: geometry)
                    } else {
                        let sub = TeXTypesetter()
                        sub.geometry = geometry; sub.fonts = fonts
                        let sd = sub.typeset([b])
                        for pg in sd.pages { for blk in pg.blocks {
                            pages[pages.count-1].blocks.append(blk) } }
                    }
                }
                addVS(fonts.bodySize * 0.3, cursorY: &cursorY)

            case .table(let header, let rows, _):
                flushPending()
                addVS(fonts.bodySize * 0.6, cursorY: &cursorY)
                appendTextBlock(
                    makeSimpleTableAttrStr(header: header, rows: rows, fonts: fonts),
                    pages: &pages, col: &col, cursorY: &cursorY, geometry: geometry)
                addVS(fonts.bodySize * 0.6, cursorY: &cursorY)

            case .tableDetailed(let rows, let spec, let booktabs):
                flushPending()
                addVS(fonts.bodySize * 0.8, cursorY: &cursorY)
                var tdata = TableTypesetter.build(
                    rows: rows, spec: spec, booktabs: booktabs,
                    availableWidth: geometry.columnWidth, fonts: fonts)
                let colR = geometry.columnRect(index: col)
                let tx   = colR.minX + (colR.width - tdata.rect.width) / 2
                tdata.rect = CGRect(x: tx, y: cursorY,
                                   width: tdata.rect.width, height: tdata.rect.height)
                if !fitsInColumn(height: tdata.rect.height, cursorY: cursorY, geometry: geometry) {
                    advanceColumn(pages: &pages, col: &col, cursorY: &cursorY, geometry: geometry)
                    let cr2 = geometry.columnRect(index: col)
                    tdata.rect = CGRect(x: cr2.minX + (cr2.width - tdata.rect.width) / 2,
                                        y: cursorY, width: tdata.rect.width, height: tdata.rect.height)
                }
                pages[pages.count-1].blocks.append(.tableGrid(tdata))
                cursorY += tdata.rect.height + fonts.bodySize * 0.8

            case .figure(let src, let caption):
                flushPending()
                emitFigure(src: src,
                            options: GraphicxOptions(parsing: ""),
                            caption: caption,
                            label: nil,
                            pages: &pages, col: &col, cursorY: &cursorY,
                            geometry: geometry, fonts: fonts)

            case .figureDetailed(let src, let opts, let caption, let label):
                flushPending()
                emitFigure(src: src, options: opts, caption: caption, label: label,
                            pages: &pages, col: &col, cursorY: &cursorY,
                            geometry: geometry, fonts: fonts)

            case .coloredBlock(let color, let inner):
                flushPending()
                for b in inner {
                    if case .paragraph(let inlines) = b {
                        let ci: [TexInline] = [.colored(color: color, content: inlines)]
                        appendTextBlock(makeParaAttrStr(ci, fonts: fonts),
                                        pages: &pages, col: &col,
                                        cursorY: &cursorY, geometry: geometry)
                    }
                }

            case .tcolorboxBlock(let opts, let inner):
                flushPending()
                emitTcolorbox(opts: opts, content: inner,
                              pages: &pages, col: &col, cursorY: &cursorY,
                              geometry: geometry, fonts: fonts)

            case .thematicBreak:
                flushPending()
                let colR = geometry.columnRect(index: col)
                pages[pages.count-1].blocks.append(
                    .rule(CGRect(x: colR.minX, y: cursorY+2, width: colR.width, height: 0.5)))
                cursorY += 5

            case .newPage, .pageBreak:
                flushPending()
                advanceColumn(pages: &pages, col: &col, cursorY: &cursorY, geometry: geometry)

            case .vspace(let h):
                flushPending(); addVS(h, cursorY: &cursorY)

            case .hspace:
                break

            case .comment:
                break

            default:
                break
            }
        }

        flushPending()

        // Auto-generate bibliography if an external bib file was loaded and citations were made.
        // This handles \bibliography{file} / \printbibliography (both skipped by parser).
        if let resolver = citationResolver, !resolver.citationOrder.isEmpty {
            emitBibliography(resolver: resolver,
                             pages: &pages, col: &col, cursorY: &cursorY,
                             geometry: geometry, fonts: fonts)
        }

        // Emit page number for the final page (advanceColumn handles earlier pages).
        let lastPageNum = pages.last?.pageNumber ?? 1
        if lastPageNum >= 1 {
            let numW: CGFloat = 60; let numH: CGFloat = 14
            let numX = (geometry.paperWidth - numW) / 2
            let numY = geometry.paperHeight - geometry.marginBottom * 0.55
            pages[pages.count - 1].blocks.append(
                .pageNumberBlock(number: lastPageNum,
                                 rect: CGRect(x: numX, y: numY, width: numW, height: numH)))
        }

        return TypesetDocument(pages: pages, geometry: geometry, fonts: fonts)
    }

    // MARK: - Bibliography

    private func emitBibliography(resolver: CitationResolver,
                                   pages: inout [TypesetPage], col: inout Int,
                                   cursorY: inout CGFloat,
                                   geometry: DocumentGeometry, fonts: TeXFontConfig) {
        let isIEEE  = documentClass.lowercased().contains("ieee")
        let isLNCS  = documentClass == "llncs"

        // Section heading
        let sectionNum = counters.incrementSectionRaw()
        let headText: String
        if isIEEE {
            headText = "\(romanNumeral(sectionNum, upper: true)).\u{2002}References"
        } else {
            headText = "References"
        }
        let headAttr = makeHeadingAttrStr(headText, level: 1, fonts: fonts)
        addVS(fonts.bodySize * 1.0, cursorY: &cursorY)
        appendTextBlock(headAttr, pages: &pages, col: &col, cursorY: &cursorY, geometry: geometry)
        addVS(fonts.bodySize * 0.4, cursorY: &cursorY)

        // Entries
        let entries = resolver.formattedBibliography(style: .numeric)
        let sz: CGFloat = isLNCS ? fonts.bodySize * 0.9 : fonts.bodySize * 0.85
        let bodyFont = CTFontCreateWithName(fonts.bodyFace as CFString, sz, nil)
        let boldFont = CTFontCreateWithName(fonts.boldFace as CFString, sz, nil)

        for entry in entries {
            let para = NSMutableParagraphStyle()
            para.alignment = .left
            para.firstLineHeadIndent = 0
            para.headIndent          = sz * 2.5  // hanging indent after label
            para.lineSpacing         = sz * 0.05

            let r = NSMutableAttributedString()
            r.append(NSAttributedString(string: entry.label + " ", attributes: [
                kCTFontAttributeName as NSAttributedString.Key: boldFont,
                NSAttributedString.Key.paragraphStyle: para,
                kCTForegroundColorFromContextAttributeName as NSAttributedString.Key: true
            ]))
            r.append(NSAttributedString(string: cleanBibLatex(entry.text), attributes: [
                kCTFontAttributeName as NSAttributedString.Key: bodyFont,
                NSAttributedString.Key.paragraphStyle: para,
                kCTForegroundColorFromContextAttributeName as NSAttributedString.Key: true
            ]))
            appendTextBlock(r, pages: &pages, col: &col, cursorY: &cursorY, geometry: geometry)
            addVS(sz * 0.25, cursorY: &cursorY)
        }
    }

    /// Strip common LaTeX commands from bib field values (titles, author names, etc.)
    private func cleanBibLatex(_ s: String) -> String {
        var out = s
        // Strip common commands that wrap content: {\TeX} → TeX, {\LaTeX} → LaTeX
        let logos: [(String, String)] = [
            ("\\LaTeX{}", "LaTeX"), ("\\LaTeX ", "LaTeX "), ("\\LaTeX", "LaTeX"),
            ("\\TeX{}", "TeX"), ("\\TeX ", "TeX "), ("\\TeX", "TeX"),
            ("\\BibTeX", "BibTeX"), ("\\XeLaTeX", "XeLaTeX"), ("\\LuaLaTeX", "LuaLaTeX"),
        ]
        for (from, to) in logos { out = out.replacingOccurrences(of: from, with: to) }
        // Remove braces used for case protection: {T}ex → Tex, {NeurIPS} → NeurIPS
        // Simple heuristic: strip single-char or all-caps tokens in braces
        if let rx = try? NSRegularExpression(pattern: #"\{([^{}]+)\}"#) {
            var keepGoing = true
            while keepGoing {
                let prev = out
                out = rx.stringByReplacingMatches(in: out,
                    range: NSRange(out.startIndex..., in: out), withTemplate: "$1")
                keepGoing = out != prev
            }
        }
        // Strip backslash commands that have no visible content
        for cmd in ["\\url", "\\emph", "\\textbf", "\\textit", "\\textrm", "\\texttt"] {
            var result = ""
            var cur = out[out.startIndex...]
            while let r = cur.range(of: cmd + "{") {
                result += cur[cur.startIndex..<r.lowerBound]
                var after = cur[r.upperBound...]
                var depth = 1; var inner = ""
                while !after.isEmpty {
                    let ch = after.removeFirst()
                    if ch == "{" { depth += 1; inner.append(ch) }
                    else if ch == "}" { depth -= 1; if depth == 0 { break } else { inner.append(ch) } }
                    else { inner.append(ch) }
                }
                result += inner
                cur = after
            }
            result += cur
            out = result
        }
        // Replace -- with en-dash and --- with em-dash
        out = out.replacingOccurrences(of: "---", with: "\u{2014}")
        out = out.replacingOccurrences(of: "--",  with: "\u{2013}")
        return out
    }

    // MARK: - Display math

    private func emitDisplayMath(_ src: String,
                                  pages: inout [TypesetPage], col: inout Int,
                                  cursorY: inout CGFloat,
                                  fonts: TeXFontConfig,
                                  geometry: DocumentGeometry) {
        let node    = MathParser.parse(src)
        let boxSize = MathRenderer.shared.size(of: node, style: .display,
                                               baseFontSize: fonts.bodySize * 1.1)
        let mathH   = boxSize.totalHeight + fonts.bodySize * 0.8
        if !fitsInColumn(height: mathH, cursorY: cursorY, geometry: geometry) {
            advanceColumn(pages: &pages, col: &col, cursorY: &cursorY, geometry: geometry)
        }
        addVS(fonts.bodySize * 0.4, cursorY: &cursorY)
        let colW  = geometry.columnWidth
        let mathX = geometry.columnRect(index: col).minX + (colW - boxSize.width) / 2
        let mathRect = CGRect(x: mathX, y: cursorY + fonts.bodySize * 0.3,
                              width: boxSize.width, height: boxSize.totalHeight)
        pages[pages.count-1].blocks.append(.mathDisplay(node, mathRect))
        cursorY += mathH
        addVS(fonts.bodySize * 0.4, cursorY: &cursorY)
    }

    // MARK: - Figure

    private func emitFigure(src: String?, options: GraphicxOptions, caption: [TexInline],
                             label: String?,
                             pages: inout [TypesetPage], col: inout Int,
                             cursorY: inout CGFloat,
                             geometry: DocumentGeometry, fonts: TeXFontConfig) {
        addVS(fonts.bodySize * 0.8, cursorY: &cursorY)
        let colR = geometry.columnRect(index: col)
        let colW = colR.width
        var displayW: CGFloat = colW * 0.8
        var displayH: CGFloat = displayW * 0.6
        var cgImage: CGImage? = nil
        if let path = src { cgImage = loadImage(named: path) }
        if let img = cgImage {
            let nW = CGFloat(img.width); let nH = CGFloat(img.height)
            let aspect = nW > 0 && nH > 0 ? nW / nH : 1.0
            switch options.width {
            case .points(let w):            displayW = w; displayH = w / aspect
            case .textwidthFraction(let f): displayW = colW * f; displayH = displayW / aspect
            case .none:
                if case .points(let h) = options.height { displayH = h; displayW = h * aspect }
                else if let s = options.scale { displayW = nW*s; displayH = nH*s }
                else { displayW = min(colW*0.8, nW); displayH = displayW / aspect }
            }
            if case .points(let h) = options.height { displayH = h }
        }
        let figX    = colR.minX + (colW - displayW) / 2
        let figRect = CGRect(x: figX, y: cursorY, width: displayW, height: displayH)
        if !fitsInColumn(height: displayH + fonts.bodySize * 3, cursorY: cursorY, geometry: geometry) {
            advanceColumn(pages: &pages, col: &col, cursorY: &cursorY, geometry: geometry)
        }
        var captionAttrStr: NSAttributedString? = nil
        if !caption.isEmpty {
            captionAttrStr = makeCaptionAttrStr(caption,
                number: counters.incrementFigure(), fonts: fonts)
        }
        let imgData = ImageBlockData(rect: figRect, cgImage: cgImage,
                                     aspectRatio: displayH > 0 ? displayW/displayH : 1,
                                     caption: captionAttrStr)
        pages[pages.count-1].blocks.append(.imageBlock(imgData))
        cursorY += displayH
        if let cap = captionAttrStr {
            let capW = colW * 0.9
            let capH = measureAttrStringHeight(cap, width: capW)
            let capX = colR.minX + (colW - capW) / 2
            addVS(fonts.bodySize * 0.2, cursorY: &cursorY)
            let capRect = CGRect(x: capX, y: cursorY, width: capW, height: capH)
            let path = CGPath(rect: capRect, transform: nil)
            let fs    = CTFramesetterCreateWithAttributedString(cap as CFAttributedString)
            let frame = CTFramesetterCreateFrame(fs, CFRangeMake(0,0), path, nil)
            pages[pages.count-1].blocks.append(.ctFrame(frame, capRect))
            cursorY += capH
        }
        addVS(fonts.bodySize * 0.8, cursorY: &cursorY)
    }

    // MARK: - Tcolorbox

    private func emitTcolorbox(opts: TcolorboxOptions, content: [TexBlock],
                                pages: inout [TypesetPage], col: inout Int,
                                cursorY: inout CGFloat,
                                geometry: DocumentGeometry, fonts: TeXFontConfig) {
        let colR = geometry.columnRect(index: col)
        let pad: CGFloat = fonts.bodySize * 0.5
        let bw = opts.borderWidth
        let iW = colR.width - pad * 2 - bw * 2

        var titleH: CGFloat = 0
        var titleStr: NSAttributedString? = nil
        if !opts.title.isEmpty {
            let tf = CTFontCreateWithName(fonts.boldFace as CFString, fonts.bodySize, nil)
            let p  = NSMutableParagraphStyle(); p.alignment = .left
            titleStr = NSAttributedString(string: opts.title, attributes: [
                kCTFontAttributeName as NSAttributedString.Key: tf,
                kCTForegroundColorAttributeName as NSAttributedString.Key: opts.coltitle.cgColor,
                NSAttributedString.Key.paragraphStyle: p
            ])
            titleH = measureAttrStringHeight(titleStr!, width: iW) + pad
        }

        let sub = TeXTypesetter()
        sub.geometry = DocumentGeometry(paperWidth: iW, paperHeight: 1000,
            marginTop: 0, marginBottom: 0, marginLeft: 0, marginRight: 0,
            columnCount: 1, columnSep: 0)
        sub.fonts = fonts
        let sd = sub.typeset(content)
        var contentH: CGFloat = pad * 2
        for pg in sd.pages { for blk in pg.blocks {
            switch blk {
            case .ctFrame(_, let r):       contentH += r.height
            case .verticalSpace(let h):    contentH += h
            case .mathDisplay(_, let r):   contentH += r.height
            default:                        contentH += fonts.bodySize * 1.5
            }
        } }
        contentH = max(contentH, fonts.bodySize * 2)
        let totalH = titleH + contentH + bw * 2

        if !fitsInColumn(height: totalH, cursorY: cursorY, geometry: geometry) {
            advanceColumn(pages: &pages, col: &col, cursorY: &cursorY, geometry: geometry)
        }
        var contentBlocks = [TypesetBlock]()
        for pg in sd.pages { contentBlocks.append(contentsOf: pg.blocks) }

        let boxRect = CGRect(x: colR.minX, y: cursorY, width: colR.width, height: totalH)
        let boxData = TcolorboxData(
            rect: boxRect, title: titleStr, contentBlocks: contentBlocks,
            background: opts.colback.cgColor, borderColor: opts.colframe.cgColor,
            titleBackground: opts.colbacktitle.cgColor,
            borderWidth: bw, cornerRadius: opts.cornerRadius)
        pages[pages.count-1].blocks.append(.tcolorboxBlock(boxData))
        cursorY += totalH + fonts.bodySize * 0.5
    }

    // MARK: - Column / page management

    private func fitsInColumn(height: CGFloat, cursorY: CGFloat,
                               geometry: DocumentGeometry) -> Bool {
        cursorY + height <= geometry.paperHeight - geometry.marginBottom
    }

    private func advanceColumn(pages: inout [TypesetPage], col: inout Int,
                                cursorY: inout CGFloat,
                                geometry: DocumentGeometry) {
        if geometry.columnCount > 1 && col == 0 {
            col = 1; cursorY = geometry.marginTop
        } else {
            // Emit page number at bottom of the page we're leaving
            let pageNum = pages.last?.pageNumber ?? 1
            let numW: CGFloat = 60; let numH: CGFloat = 14
            let numX = (geometry.paperWidth - numW) / 2
            let numY = geometry.paperHeight - geometry.marginBottom * 0.55
            let numRect = CGRect(x: numX, y: numY, width: numW, height: numH)
            pages[pages.count - 1].blocks.append(.pageNumberBlock(number: pageNum, rect: numRect))

            col = 0; cursorY = geometry.marginTop
            pages.append(TypesetPage(pageNumber: pages.count + 1))
        }
    }

    private func addVS(_ h: CGFloat, cursorY: inout CGFloat) {
        cursorY += h
    }

    // MARK: - Text block emission with overflow

    private func appendTextBlock(_ attrStr: NSAttributedString,
                                  pages: inout [TypesetPage],
                                  col: inout Int,
                                  cursorY: inout CGFloat,
                                  geometry: DocumentGeometry) {
        var remaining: NSAttributedString = attrStr
        while remaining.length > 0 {
            let availH = geometry.paperHeight - geometry.marginBottom - cursorY
            guard availH > geometry.bodyFontSize * 2 else {
                advanceColumn(pages: &pages, col: &col, cursorY: &cursorY, geometry: geometry)
                continue
            }
            let colRect  = geometry.columnRect(index: col)
            let textRect = CGRect(x: colRect.minX, y: cursorY,
                                  width: colRect.width, height: availH)
            let path  = CGPath(rect: textRect, transform: nil)
            let fs    = CTFramesetterCreateWithAttributedString(remaining as CFAttributedString)
            let frame = CTFramesetterCreateFrame(fs, CFRangeMake(0,0), path, nil)
            let vis   = CTFrameGetVisibleStringRange(frame)
            let consumed = max(vis.length, 0)
            pages[pages.count-1].blocks.append(.ctFrame(frame, textRect))
            let fittedStr = remaining.attributedSubstring(
                from: NSRange(location: 0, length: min(consumed, remaining.length)))
            let actualH = measureAttrStringHeight(fittedStr, width: colRect.width)
            cursorY += actualH
            if consumed >= remaining.length { break }
            remaining = remaining.attributedSubstring(
                from: NSRange(location: consumed, length: remaining.length - consumed))
            advanceColumn(pages: &pages, col: &col, cursorY: &cursorY, geometry: geometry)
        }
    }

    private func toFlippedRect(_ r: CGRect, paperH: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: paperH - r.maxY, width: r.width, height: r.height)
    }

    // MARK: - Title block

    private func emitTitleBlock(title: String, authors: [String], abstract: String?,
                                 pages: inout [TypesetPage], col: inout Int,
                                 cursorY: inout CGFloat,
                                 geometry: DocumentGeometry, fonts: TeXFontConfig) {
        let colW   = geometry.textWidth
        let cleanTitle = expandTitleText(title)
        let titleA = makeTitleAttrStr(cleanTitle, fonts: fonts)
        let titleH = measureAttrStringHeight(titleA, width: colW)
        let authStr = authors.map { cleanAuthorName($0) }.joined(separator: "  .  ")
        let authA   = makeAuthorAttrStr(authStr, fonts: fonts)
        let authH   = measureAttrStringHeight(authA, width: colW)
        let blockH  = titleH + authH + fonts.bodySize * 2
        let cleanedAuthors = authors.map { cleanAuthorName($0) }
        let tb = TypesetTitleBlock(title: cleanTitle, authors: cleanedAuthors, abstract: abstract,
                                    rect: CGRect(x: geometry.marginLeft, y: cursorY,
                                                 width: colW, height: blockH))
        pages[pages.count-1].blocks.append(.titleBlock(tb))
        cursorY += blockH

        if let abs = abstract, !abs.isEmpty {
            let isIEEEDoc = documentClass.lowercased().contains("ieee")
            let absA: NSAttributedString
            if isIEEEDoc {
                // IEEE abstract: "Abstract—" prefix in bold italic, body in regular at 9pt
                let sz      = fonts.bodySize * 0.9
                let bIFont  = CTFontCreateWithName(fonts.boldItalicFace as CFString, sz, nil)
                let bFont   = CTFontCreateWithName(fonts.bodyFace       as CFString, sz, nil)
                let absP    = justifiedParagraphStyle(lineHeight: sz * 1.3)
                let combined = NSMutableAttributedString()
                combined.append(NSAttributedString(string: "Abstract\u{2014}", attributes: [
                    kCTFontAttributeName as NSAttributedString.Key: bIFont,
                    NSAttributedString.Key.paragraphStyle: absP,
                    kCTForegroundColorFromContextAttributeName as NSAttributedString.Key: true
                ]))
                combined.append(NSAttributedString(string: abs, attributes: [
                    kCTFontAttributeName as NSAttributedString.Key: bFont,
                    NSAttributedString.Key.paragraphStyle: absP,
                    kCTForegroundColorFromContextAttributeName as NSAttributedString.Key: true
                ]))
                absA = combined
            } else {
                absA = makeAbstractAttrStr(abs, fonts: fonts)
            }
            let absW    = isIEEEDoc ? colW : colW * 0.9
            let absH    = measureAttrStringHeight(absA, width: absW)
            let absRect = CGRect(x: geometry.marginLeft + (colW - absW) / 2,
                                 y: cursorY, width: absW, height: absH + fonts.bodySize)
            let path  = CGPath(rect: absRect, transform: nil)
            let fs    = CTFramesetterCreateWithAttributedString(absA as CFAttributedString)
            let frame = CTFramesetterCreateFrame(fs, CFRangeMake(0,0), path, nil)
            pages[pages.count-1].blocks.append(.ctFrame(frame, absRect))
            cursorY += absH + fonts.bodySize * 1.5
        }
    }

    private func cleanAuthorName(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // IEEE: extract just the name from \IEEEauthorblockN{...}, ignoring affiliation
        if s.contains("\\IEEEauthorblockN") {
            if let r = s.range(of: "\\IEEEauthorblockN{") {
                var after = s[r.upperBound...]
                var depth = 1; var name = ""
                while !after.isEmpty {
                    let ch = after.removeFirst()
                    if ch == "{" { depth += 1; name.append(ch) }
                    else if ch == "}" { depth -= 1; if depth == 0 { break }
                                       else { name.append(ch) } }
                    else { name.append(ch) }
                }
                s = name
            }
        }
        // Strip LaTeX commands that wrap text (keep the inner text)
        for cmd in ["\\textbf", "\\textit", "\\emph", "\\textsc", "\\texttt", "\\textrm",
                    "\\textsuperscript", "\\textsubscript", "\\footnote",
                    "\\IEEEauthorblockN", "\\IEEEauthorblockA",
                    "\\affiliation", "\\institution", "\\city", "\\country",
                    "\\email", "\\orcidID", "\\inst"] {
            var result = ""
            var cur = s[s.startIndex...]
            while let r = cur.range(of: cmd + "{") {
                result += cur[cur.startIndex..<r.lowerBound]
                var after = cur[r.upperBound...]
                var depth = 1; var inner = ""
                while !after.isEmpty {
                    let ch = after.removeFirst()
                    if ch == "{" { depth += 1; inner.append(ch) }
                    else if ch == "}" { depth -= 1; if depth == 0 { break }
                                       else { inner.append(ch) } }
                    else { inner.append(ch) }
                }
                // For affiliation/ORCID/inst blocks, discard the content
                let isAffilBlock = ["\\IEEEauthorblockA", "\\affiliation",
                                    "\\institution", "\\city", "\\country",
                                    "\\email", "\\orcidID", "\\inst"].contains(cmd)
                if !isAffilBlock { result += inner }
                cur = after
            }
            result += cur
            s = result
        }
        // Remove remaining IEEE structural commands without braces
        for cmd in ["\\and", "\\maketitle", "\\linebreak", "\\newline"] {
            s = s.replacingOccurrences(of: cmd, with: " ")
        }
        // Strip remaining {…} braces iteratively
        var prev = ""
        while prev != s {
            prev = s
            if let rx = try? NSRegularExpression(pattern: #"\{([^{}]*)\}"#) {
                s = rx.stringByReplacingMatches(in: s,
                    range: NSRange(s.startIndex..., in: s), withTemplate: "$1")
            }
        }
        // Strip ordinal prefixes like "1st", "2nd", "3rd" at the start
        if let rx = try? NSRegularExpression(pattern: #"^\d+(st|nd|rd|th)\s*"#, options: .caseInsensitive) {
            s = rx.stringByReplacingMatches(in: s,
                range: NSRange(s.startIndex..., in: s), withTemplate: "")
        }
        // Strip remaining backslash commands
        s = s.replacingOccurrences(of: "\\\\", with: " ")
        if let rx = try? NSRegularExpression(pattern: #"\\[a-zA-Z@]+"#) {
            s = rx.stringByReplacingMatches(in: s,
                range: NSRange(s.startIndex..., in: s), withTemplate: "")
        }
        // Collapse whitespace
        s = s.components(separatedBy: .whitespacesAndNewlines)
              .filter { !$0.isEmpty }
              .joined(separator: " ")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Measurement

    func measureAttrStringHeight(_ a: NSAttributedString, width: CGFloat) -> CGFloat {
        guard !a.string.isEmpty else { return 0 }
        let fs = CTFramesetterCreateWithAttributedString(a as CFAttributedString)
        let s  = CTFramesetterSuggestFrameSizeWithConstraints(
            fs, CFRangeMake(0,0), nil,
            CGSize(width: max(width, 1), height: CGFloat.greatestFiniteMagnitude), nil)
        return ceil(s.height) + 1
    }

    // MARK: - Attributed string builders

    private func makeHeadingAttrStr(_ text: String, level: Int,
                                    fonts: TeXFontConfig) -> NSAttributedString {
        let isIEEEDoc = documentClass.lowercased().contains("ieee")
        let isLNCS    = documentClass == "llncs"
        let sz: CGFloat
        let face: String
        let para = NSMutableParagraphStyle()
        para.lineSpacing = fonts.bodySize * 0.05

        if isIEEEDoc {
            // IEEE: all headings at body size; sections bold, subsections bold-italic
            sz   = fonts.bodySize
            face = level <= 1 ? fonts.boldFace
                             : (level == 2 ? fonts.boldItalicFace : fonts.italicFace)
            para.alignment = .left
        } else if isLNCS {
            // LNCS: sections bold (slightly larger), subsections bold, run-in paragraphs bold-italic
            switch level {
            case 0, 1: sz = fonts.bodySize * 1.2; face = fonts.boldFace;        para.alignment = .left
            case 2:    sz = fonts.bodySize * 1.1; face = fonts.boldFace;        para.alignment = .left
            case 3:    sz = fonts.bodySize;       face = fonts.boldItalicFace;  para.alignment = .left
            default:   sz = fonts.bodySize;       face = fonts.boldItalicFace;  para.alignment = .left
            }
        } else {
            // Default article/book sizing
            let sizes = fonts.headingSizes
            sz   = level < sizes.count ? sizes[level] : fonts.bodySize
            face = level <= 2 ? fonts.boldFace : fonts.bodyFace
            para.alignment = .left
        }

        let font = CTFontCreateWithName(face as CFString, sz, nil)
        return NSAttributedString(string: text, attributes: [
            kCTFontAttributeName as NSAttributedString.Key: font,
            NSAttributedString.Key.paragraphStyle: para,
            kCTForegroundColorFromContextAttributeName as NSAttributedString.Key: true
        ])
    }

    /// Build an attributed string from an inline sequence, preserving nested bold/italic/color.
    private func makeParaAttrStr(_ inlines: [TexInline],
                                  fonts: TeXFontConfig,
                                  firstLineIndent: CGFloat = 0) -> NSAttributedString {
        let result   = NSMutableAttributedString()
        let bodyFont = CTFontCreateWithName(fonts.bodyFace       as CFString, fonts.bodySize,       nil)
        let boldFont = CTFontCreateWithName(fonts.boldFace       as CFString, fonts.bodySize,       nil)
        let itFont   = CTFontCreateWithName(fonts.italicFace     as CFString, fonts.bodySize,       nil)
        let biFont   = CTFontCreateWithName(fonts.boldItalicFace as CFString, fonts.bodySize,       nil)
        let ttFont   = CTFontCreateWithName(fonts.monoFace       as CFString, fonts.bodySize * 0.9, nil)
        let mFont    = CTFontCreateWithName(fonts.mathFace       as CFString, fonts.bodySize,       nil)
        let para     = justifiedParagraphStyle(lineHeight: fonts.bodySize * 1.3,
                                               firstLineIndent: firstLineIndent)

        func resolveFont(_ isBold: Bool, _ isItalic: Bool) -> CTFont {
            switch (isBold, isItalic) {
            case (true,  true ): return biFont
            case (true,  false): return boldFont
            case (false, true ): return itFont
            default:             return bodyFont
            }
        }

        func app(_ s: String, font f: CTFont, color: CGColor? = nil) {
            var attrs: [NSAttributedString.Key: Any] = [
                kCTFontAttributeName as NSAttributedString.Key: f,
                NSAttributedString.Key.paragraphStyle: para
            ]
            if let c = color {
                attrs[kCTForegroundColorAttributeName as NSAttributedString.Key] = c
            } else {
                attrs[kCTForegroundColorFromContextAttributeName as NSAttributedString.Key] = true
            }
            result.append(NSAttributedString(string: s, attributes: attrs))
        }

        // Recursive inline renderer — preserves nesting of bold, italic, color, size.
        func appendInline(_ inline: TexInline, isBold: Bool, isItalic: Bool, color: CGColor?) {
            let f = resolveFont(isBold, isItalic)
            switch inline {
            case .text(let s):
                app(s, font: f, color: color)
            case .bold(let i):
                for inner in i { appendInline(inner, isBold: true,  isItalic: isItalic, color: color) }
            case .italic(let i):
                for inner in i { appendInline(inner, isBold: isBold, isItalic: true,    color: color) }
            case .boldItalic(let i):
                for inner in i { appendInline(inner, isBold: true,  isItalic: true,     color: color) }
            case .underline(let i):
                let start = result.length
                for inner in i { appendInline(inner, isBold: isBold, isItalic: isItalic, color: color) }
                if result.length > start {
                    result.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue,
                                        range: NSRange(location: start, length: result.length - start))
                }
            case .strikethrough(let i):
                let start = result.length
                for inner in i { appendInline(inner, isBold: isBold, isItalic: isItalic, color: color) }
                if result.length > start {
                    result.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue,
                                        range: NSRange(location: start, length: result.length - start))
                }
            case .smallcaps(let i):
                let scF = CTFontCreateWithName(fonts.bodyFace as CFString, fonts.bodySize * 0.85, nil)
                app(inlinesToPlain(i).uppercased(), font: scF, color: color)
            case .code(let s):
                app(s, font: ttFont, color: color)
            case .mathInline(let s):
                app(mathInlineUnicode(s), font: mFont, color: color)
            case .lineBreak:
                app("\n", font: f, color: color)
            case .link(let t, _):
                app(t, font: f, color: color ?? CGColor(red: 0, green: 0, blue: 0.8, alpha: 1))
            case .footnote(let inner):
                app("[\(inlinesToPlain(inner))]", font: ttFont, color: color)
            case .colored(let c, let inner):
                for i in inner { appendInline(i, isBold: isBold, isItalic: isItalic, color: c.cgColor) }
            case .coloredBackground(_, let inner):
                for i in inner { appendInline(i, isBold: isBold, isItalic: isItalic, color: color) }
            case .sized(let sz, let inner):
                let face = isBold ? (isItalic ? fonts.boldItalicFace : fonts.boldFace)
                                  : (isItalic ? fonts.italicFace     : fonts.bodyFace)
                let sF = CTFontCreateWithName(face as CFString, sz, nil)
                for i in inner { app(inlineToPlain(i), font: sF, color: color) }
            case .ref(let lbl):
                app(labels[lbl] ?? "??", font: f,
                    color: color ?? CGColor(red: 0, green: 0, blue: 0.7, alpha: 1))
            case .eqref(let lbl):
                app("(\(labels[lbl] ?? "??"))", font: f,
                    color: color ?? CGColor(red: 0, green: 0, blue: 0.7, alpha: 1))
            case .cite(let keys):
                let resolved = citationResolver?.resolveCites(keys: keys)
                    ?? "[\(keys.joined(separator: ","))]"
                app(resolved, font: f,
                    color: color ?? CGColor(red: 0, green: 0, blue: 0.7, alpha: 1))
            case .icon(let n):
                app(n, font: f, color: color)
            }
        }

        for inline in inlines { appendInline(inline, isBold: false, isItalic: false, color: nil) }
        return result
    }

    private func makeCodeAttrStr(_ src: String, fonts: TeXFontConfig) -> NSAttributedString {
        let f  = CTFontCreateWithName(fonts.monoFace as CFString, fonts.bodySize * 0.87, nil)
        let p  = NSMutableParagraphStyle()
        p.alignment = .left; p.lineSpacing = fonts.bodySize * 0.1
        p.firstLineHeadIndent = fonts.bodySize; p.headIndent = fonts.bodySize
        return NSAttributedString(string: src, attributes: [
            kCTFontAttributeName as NSAttributedString.Key: f,
            NSAttributedString.Key.paragraphStyle: p,
            kCTForegroundColorFromContextAttributeName as NSAttributedString.Key: true
        ])
    }

    private func makeVerbatimAttrStr(_ code: String, opts: ListingsOptions,
                                     fonts: TeXFontConfig) -> NSAttributedString {
        let sz = fonts.bodySize * 0.85
        let f  = CTFontCreateWithName(fonts.monoFace as CFString, sz, nil)
        let p  = NSMutableParagraphStyle()
        p.alignment = .left; p.lineSpacing = sz * 0.1
        var attrs: [NSAttributedString.Key: Any] = [
            kCTFontAttributeName as NSAttributedString.Key: f,
            NSAttributedString.Key.paragraphStyle: p,
            kCTForegroundColorFromContextAttributeName as NSAttributedString.Key: true
        ]
        if let bg = opts.backgroundcolor {
            attrs[NSAttributedString.Key.backgroundColor] = bg.cgColor
        }
        return NSAttributedString(string: code, attributes: attrs)
    }

    private func makeListItemAttrStr(_ item: [TexInline], bullet: String,
                                     fonts: TeXFontConfig,
                                     opts: ListOptions) -> NSAttributedString {
        let indent: CGFloat = opts.leftmargin ?? (fonts.bodySize * 1.5)
        let f = CTFontCreateWithName(fonts.bodyFace as CFString, fonts.bodySize, nil)
        let p = NSMutableParagraphStyle()
        p.alignment = .left; p.firstLineHeadIndent = indent / 2; p.headIndent = indent
        p.lineSpacing = opts.noitemsep ? 0 : fonts.bodySize * 0.05
        let r = NSMutableAttributedString()
        r.append(NSAttributedString(string: bullet + "  ", attributes: [
            kCTFontAttributeName as NSAttributedString.Key: f,
            NSAttributedString.Key.paragraphStyle: p,
            kCTForegroundColorFromContextAttributeName as NSAttributedString.Key: true
        ]))
        r.append(makeParaAttrStr(item, fonts: fonts))
        return r
    }

    private func makeBlockQuoteAttrStr(_ inlines: [TexInline],
                                       fonts: TeXFontConfig) -> NSAttributedString {
        let sz = fonts.bodySize * 0.95
        let p  = NSMutableParagraphStyle()
        p.alignment = .left
        p.firstLineHeadIndent = fonts.bodySize * 2; p.headIndent = fonts.bodySize * 2
        p.tailIndent = -(fonts.bodySize * 2); p.lineSpacing = sz * 0.1
        // Use makeParaAttrStr so inline math/bold/italic render correctly,
        // then override paragraph style for the indentation
        let base = makeParaAttrStr(inlines, fonts: TeXFontConfig(
            bodyFace: fonts.italicFace, boldFace: fonts.boldFace,
            italicFace: fonts.italicFace, boldItalicFace: fonts.boldItalicFace,
            monoFace: fonts.monoFace, mathFace: fonts.mathFace, bodySize: sz))
        let result = NSMutableAttributedString(attributedString: base)
        result.addAttribute(.paragraphStyle, value: p,
                            range: NSRange(location: 0, length: result.length))
        return result
    }

    private func makeSimpleTableAttrStr(header: [[TexInline]], rows: [[[TexInline]]],
                                         fonts: TeXFontConfig) -> NSAttributedString {
        let r    = NSMutableAttributedString()
        let body = CTFontCreateWithName(fonts.bodyFace as CFString, fonts.bodySize, nil)
        let bold = CTFontCreateWithName(fonts.boldFace as CFString, fonts.bodySize, nil)
        let para = NSMutableParagraphStyle(); para.alignment = .left
        func addRow(_ cells: [[TexInline]], isHeader: Bool) {
            let f    = isHeader ? bold : body
            let line = cells.map { inlinesToPlain($0) }.joined(separator: "   ")
            r.append(NSAttributedString(string: line + "\n", attributes: [
                kCTFontAttributeName as NSAttributedString.Key: f,
                NSAttributedString.Key.paragraphStyle: para,
                kCTForegroundColorFromContextAttributeName as NSAttributedString.Key: true
            ]))
        }
        if !header.isEmpty { addRow(header, isHeader: true) }
        for row in rows { addRow(row, isHeader: false) }
        return r
    }

    private func makeCaptionAttrStr(_ inlines: [TexInline], number: String,
                                    fonts: TeXFontConfig) -> NSAttributedString {
        let sz   = fonts.bodySize * 0.9
        let body = CTFontCreateWithName(fonts.bodyFace as CFString, sz, nil)
        let bold = CTFontCreateWithName(fonts.boldFace as CFString, sz, nil)
        let para = NSMutableParagraphStyle(); para.alignment = .center
        let r = NSMutableAttributedString()
        r.append(NSAttributedString(string: "Figure \(number). ", attributes: [
            kCTFontAttributeName as NSAttributedString.Key: bold,
            NSAttributedString.Key.paragraphStyle: para,
            kCTForegroundColorFromContextAttributeName as NSAttributedString.Key: true
        ]))
        r.append(NSAttributedString(string: inlinesToPlain(inlines), attributes: [
            kCTFontAttributeName as NSAttributedString.Key: body,
            NSAttributedString.Key.paragraphStyle: para,
            kCTForegroundColorFromContextAttributeName as NSAttributedString.Key: true
        ]))
        return r
    }

    /// Expand common inline LaTeX macros found in \title{...} content.
    private func expandTitleText(_ raw: String) -> String {
        var s = raw
        // Replace newline macro \\ with actual newline
        s = s.replacingOccurrences(of: "\\\\", with: "\n")
        // Replace named logos
        s = s.replacingOccurrences(of: "\\LaTeX{}", with: "LaTeX")
        s = s.replacingOccurrences(of: "\\LaTeX ",   with: "LaTeX ")
        s = s.replacingOccurrences(of: "\\LaTeX\n",  with: "LaTeX\n")
        s = s.replacingOccurrences(of: "\\LaTeX",    with: "LaTeX")
        s = s.replacingOccurrences(of: "\\TeX{}",    with: "TeX")
        s = s.replacingOccurrences(of: "\\TeX ",     with: "TeX ")
        s = s.replacingOccurrences(of: "\\TeX",      with: "TeX")
        // Strip size commands that precede text
        for cmd in ["\\large", "\\Large", "\\LARGE", "\\huge", "\\Huge",
                    "\\small", "\\footnotesize", "\\normalsize"] {
            s = s.replacingOccurrences(of: cmd + " ",  with: "")
            s = s.replacingOccurrences(of: cmd + "\n", with: "")
            s = s.replacingOccurrences(of: cmd,         with: "")
        }
        // Strip wrapping commands (keep content): \textbf{...}, \textsuperscript{...}, etc.
        for cmd in ["\\textbf", "\\textit", "\\emph", "\\textrm", "\\textsc", "\\texttt",
                    "\\textsuperscript", "\\textsubscript", "\\footnote"] {
            var result = ""
            var cur = s[s.startIndex...]
            while let r = cur.range(of: cmd + "{") {
                result += cur[cur.startIndex..<r.lowerBound]
                var after = cur[r.upperBound...]
                var depth = 1; var inner = ""
                while !after.isEmpty {
                    let ch = after.removeFirst()
                    if ch == "{" { depth += 1; inner.append(ch) }
                    else if ch == "}" { depth -= 1; if depth == 0 { break } else { inner.append(ch) } }
                    else { inner.append(ch) }
                }
                // Discard footnote content, keep others
                if cmd != "\\footnote" { result += inner }
                cur = after
            }
            result += cur
            s = result
        }
        // Strip remaining bare {…} brace groups (keep content)
        var prev = ""
        while prev != s {
            prev = s
            if let rx = try? NSRegularExpression(pattern: #"\{([^{}]*)\}"#) {
                s = rx.stringByReplacingMatches(in: s,
                    range: NSRange(s.startIndex..., in: s), withTemplate: "$1")
            }
        }
        // Strip remaining backslash commands (no braces)
        if let rx = try? NSRegularExpression(pattern: #"\\[a-zA-Z@]+\*?"#) {
            s = rx.stringByReplacingMatches(in: s,
                range: NSRange(s.startIndex..., in: s), withTemplate: "")
        }
        // Collapse multiple whitespace/newlines but keep single newlines
        let lines = s.components(separatedBy: "\n").map {
            $0.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
        }.filter { !$0.isEmpty }
        s = lines.joined(separator: "\n")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func makeTitleAttrStr(_ title: String, fonts: TeXFontConfig) -> NSAttributedString {
        let sz = fonts.bodySize * 1.9
        let f  = CTFontCreateWithName(fonts.boldFace as CFString, sz, nil)
        let p  = NSMutableParagraphStyle(); p.alignment = .center
        let cleaned = expandTitleText(title)
        return NSAttributedString(string: cleaned, attributes: [
            kCTFontAttributeName as NSAttributedString.Key: f,
            NSAttributedString.Key.paragraphStyle: p,
            kCTForegroundColorFromContextAttributeName as NSAttributedString.Key: true
        ])
    }

    private func makeAuthorAttrStr(_ authors: String, fonts: TeXFontConfig) -> NSAttributedString {
        let sz = fonts.bodySize
        let f  = CTFontCreateWithName(fonts.italicFace as CFString, sz, nil)
        let p  = NSMutableParagraphStyle(); p.alignment = .center
        return NSAttributedString(string: authors, attributes: [
            kCTFontAttributeName as NSAttributedString.Key: f,
            NSAttributedString.Key.paragraphStyle: p,
            kCTForegroundColorFromContextAttributeName as NSAttributedString.Key: true
        ])
    }

    private func makeAbstractAttrStr(_ text: String, fonts: TeXFontConfig) -> NSAttributedString {
        let sz = fonts.bodySize * 0.9
        let f  = CTFontCreateWithName(fonts.bodyFace as CFString, sz, nil)
        let p  = justifiedParagraphStyle(lineHeight: sz * 1.3)
        return NSAttributedString(string: text, attributes: [
            kCTFontAttributeName as NSAttributedString.Key: f,
            NSAttributedString.Key.paragraphStyle: p,
            kCTForegroundColorFromContextAttributeName as NSAttributedString.Key: true
        ])
    }

    private func parasepAttrs(_ fonts: TeXFontConfig) -> [NSAttributedString.Key: Any] {
        let f = CTFontCreateWithName(fonts.bodyFace as CFString, fonts.bodySize, nil)
        let p = NSMutableParagraphStyle(); p.paragraphSpacing = fonts.bodySize * 0.4
        return [kCTFontAttributeName as NSAttributedString.Key: f,
                NSAttributedString.Key.paragraphStyle: p]
    }

    private func justifiedParagraphStyle(lineHeight: CGFloat,
                                          firstLineIndent: CGFloat = 0) -> NSMutableParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.alignment = .justified
        p.minimumLineHeight = lineHeight; p.maximumLineHeight = lineHeight * 1.05
        p.hyphenationFactor = 0.9; p.lineBreakMode = .byWordWrapping
        p.firstLineHeadIndent = firstLineIndent
        return p
    }

    // MARK: - List label helpers

    private func bulletLabel(opts: ListOptions) -> String {
        guard let lbl = opts.label else { return "\u{2022}" }
        switch lbl {
        case "\\textbullet": return "\u{2022}"
        case "\\textendash": return "\u{2013}"
        case "\\textemdash": return "\u{2014}"
        case "\\textasteriskcentered": return "\u{2217}"
        case "\\textperiodcentered":   return "\u{00B7}"
        default: return lbl
        }
    }

    private func numberedLabel(opts: ListOptions, index: Int) -> String {
        guard let lbl = opts.label else { return "\(index)." }
        switch lbl {
        case "\\alph*", "\\alph":
            let c = (index >= 1 && index <= 26) ? String(UnicodeScalar(96 + index)!) : "\(index)"
            return "\(c)."
        case "\\Alph*", "\\Alph":
            let c = (index >= 1 && index <= 26) ? String(UnicodeScalar(64 + index)!) : "\(index)"
            return "\(c)."
        case "\\roman*": return "\(romanNumeral(index, upper: false))."
        case "\\Roman*": return "\(romanNumeral(index, upper: true))."
        case "\\arabic*": return "\(index)."
        case "(\\alph*)":
            let c = (index >= 1 && index <= 26) ? String(UnicodeScalar(96 + index)!) : "\(index)"
            return "(\(c))"
        case "(\\roman*)": return "(\(romanNumeral(index, upper: false)))"
        case "(\\arabic*)": return "(\(index))"
        default:
            return lbl.replacingOccurrences(of: "\\arabic*", with: "\(index)")
                      .replacingOccurrences(of: "*", with: "\(index)")
        }
    }

    private func romanNumeral(_ n: Int, upper: Bool) -> String {
        let vals  = [1000,900,500,400,100,90,50,40,10,9,5,4,1]
        let lower = ["m","cm","d","cd","c","xc","l","xl","x","ix","v","iv","i"]
        let upper2 = ["M","CM","D","CD","C","XC","L","XL","X","IX","V","IV","I"]
        let syms  = upper ? upper2 : lower
        var r = ""; var rem = n
        for (i, v) in vals.enumerated() { while rem >= v { r += syms[i]; rem -= v } }
        return r
    }

    // MARK: - Image loading

    private func loadImage(named name: String) -> CGImage? {
        #if os(macOS)
        if let img = NSImage(named: name) {
            var rect = CGRect(x: 0, y: 0, width: img.size.width, height: img.size.height)
            return img.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        }
        #else
        if let img = UIImage(named: name) { return img.cgImage }
        #endif
        let exts = ["", ".png", ".jpg", ".jpeg", ".pdf", ".tiff", ".gif"]
        var searchPaths: [String]
        if name.hasPrefix("/") {
            searchPaths = [name]
        } else {
            // Search in sourceDirectory first, then relative paths
            if let dir = sourceDirectory {
                let dirPath = dir.path
                var dirPaths: [String] = []
                for ext in exts {
                    dirPaths.append(dirPath + "/" + name + ext)
                    dirPaths.append(dirPath + "/../" + name + ext)
                }
                searchPaths = dirPaths
            } else {
                searchPaths = []
            }
            searchPaths += exts.map { name + $0 }
        }
        for path in searchPaths {
            let url = URL(fileURLWithPath: path).standardized
            if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
               let img = CGImageSourceCreateImageAtIndex(src, 0, nil) { return img }
        }
        return nil
    }

    // MARK: - Inline helpers

    private func inlinesToPlain(_ inlines: [TexInline]) -> String {
        inlines.map { inlineToPlain($0) }.joined()
    }

    private func inlineToPlain(_ inline: TexInline) -> String {
        switch inline {
        case .text(let s): return s
        case .bold(let i), .italic(let i), .underline(let i),
             .strikethrough(let i), .smallcaps(let i), .boldItalic(let i): return inlinesToPlain(i)
        case .colored(_, let i), .coloredBackground(_, let i), .sized(_, let i): return inlinesToPlain(i)
        case .code(let s): return s
        case .mathInline(let s): return mathInlineUnicode(s)
        case .lineBreak: return "\n"
        case .link(let t, _): return t
        case .footnote(let i): return "[\(inlinesToPlain(i))]"
        case .ref(let l): return labels[l] ?? "??"
        case .eqref(let l): return "(\(labels[l] ?? "??"))"
        case .cite(let keys): return "[\(keys.joined(separator: ","))]"
        case .icon(let n): return n
        }
    }

    private func mathInlineUnicode(_ src: String) -> String {
        let subs: [(String, String)] = [
            ("\\alpha","\u{03B1}"),("\\beta","\u{03B2}"),("\\gamma","\u{03B3}"),
            ("\\delta","\u{03B4}"),("\\epsilon","\u{03B5}"),("\\theta","\u{03B8}"),
            ("\\lambda","\u{03BB}"),("\\mu","\u{03BC}"),("\\pi","\u{03C0}"),
            ("\\sigma","\u{03C3}"),("\\tau","\u{03C4}"),("\\phi","\u{03C6}"),
            ("\\psi","\u{03C8}"),("\\omega","\u{03C9}"),("\\Gamma","\u{0393}"),
            ("\\Delta","\u{0394}"),("\\Theta","\u{0398}"),("\\Lambda","\u{039B}"),
            ("\\Pi","\u{03A0}"),("\\Sigma","\u{03A3}"),("\\Phi","\u{03A6}"),
            ("\\Psi","\u{03A8}"),("\\Omega","\u{03A9}"),
            ("\\pm","\u{00B1}"),("\\times","\u{00D7}"),("\\div","\u{00F7}"),
            ("\\leq","\u{2264}"),("\\geq","\u{2265}"),("\\neq","\u{2260}"),
            ("\\approx","\u{2248}"),("\\infty","\u{221E}"),
            ("\\rightarrow","\u{2192}"),("\\leftarrow","\u{2190}"),
            ("\\Rightarrow","\u{21D2}"),("\\Leftarrow","\u{21D0}"),
            ("\\cdot","\u{00B7}"),("\\ldots","\u{2026}"),
        ]
        var r = src
        for (f, t) in subs { r = r.replacingOccurrences(of: f, with: t) }
        r = r.replacingOccurrences(of: "\\", with: "")
        return r
    }

    // MARK: - Preamble scanner

    private func scanPreamble(_ blocks: [TexBlock]) {
        for block in blocks {
            switch block {
            case .documentMetadata(let t, let a, _): pendingTitle = t; pendingAuthors = a
            case .abstract(let inner): pendingAbstract = extractPlainText(inner)
            default: break
            }
        }
    }

    private func extractPlainText(_ blocks: [TexBlock]) -> String {
        blocks.compactMap { block -> String? in
            if case .paragraph(let i) = block { return inlinesToPlain(i) }
            return nil
        }.joined(separator: " ")
    }

    private func extractInlinesFromBlocks(_ blocks: [TexBlock]) -> [TexInline] {
        var r = [TexInline]()
        for block in blocks {
            if case .paragraph(let i) = block { r.append(contentsOf: i) }
            else { r.append(.text(extractPlainText([block]))) }
        }
        return r
    }
}

// MARK: - TeXCounters figure/table

extension TeXCounters {
    mutating func incrementFigure() -> String { figure += 1; return "\(figure)" }
    mutating func incrementTable()  -> String { table  += 1; return "\(table)"  }
}

// MARK: - DocumentGeometry helpers

extension DocumentGeometry {
    var bodyFontSize: CGFloat {
        columnWidth < 250 ? 9 : (columnWidth < 350 ? 10 : 11)
    }
}
