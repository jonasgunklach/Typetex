//  KnuthPlassBreaker.swift — Knuth-Plass optimal paragraph line-breaking
import Foundation
import CoreText
import CoreGraphics

// MARK: - Box/Glue/Penalty items

enum KPItem {
    case box(width: CGFloat, index: Int)        // non-breaking piece (a word)
    case glue(width: CGFloat, stretch: CGFloat, shrink: CGFloat) // elastic space
    case penalty(width: CGFloat, value: CGFloat, flagged: Bool)  // break opportunity
}

struct KPParagraph {
    let items:      [KPItem]
    let lineWidths: [CGFloat]   // per-line widths (last repeats)
    let linePenalty: CGFloat    // added to badness of every line (~10)
    let tolerance:  CGFloat     // max badness before line is too loose (~200)
    let hyphenDemerits: CGFloat // extra penalty for adjacent hyphenated lines (~50)

    func lineWidth(at index: Int) -> CGFloat {
        lineWidths.indices.contains(index) ? lineWidths[index] : (lineWidths.last ?? 0)
    }
}

struct KPBreakResult {
    let breakpoints: [Int]   // indices into items where breaks occur
    let adjustRatios: [CGFloat] // r for each resulting line
}

// MARK: - Active node for DP

private struct ActiveNode {
    let position: Int        // item index of break
    let line: Int            // line number
    let fitness: Int         // fitness class 0..3
    let totalWidth: CGFloat
    let totalStretch: CGFloat
    let totalShrink: CGFloat
    let totalDemerits: CGFloat
    let previous: Int?       // index into activeNodes array
}

// MARK: - The Knuth-Plass breaker

final class KnuthPlassBreaker {

    static func breakLines(_ para: KPParagraph) -> KPBreakResult {
        let items = para.items
        guard !items.isEmpty else { return KPBreakResult(breakpoints: [], adjustRatios: []) }

        // Sum widths up to each item
        var sumW = [CGFloat](repeating: 0, count: items.count + 1)
        var sumStr = [CGFloat](repeating: 0, count: items.count + 1)
        var sumShr = [CGFloat](repeating: 0, count: items.count + 1)
        for (i, item) in items.enumerated() {
            sumW[i+1]   = sumW[i]
            sumStr[i+1] = sumStr[i]
            sumShr[i+1] = sumShr[i]
            switch item {
            case .box(let w, _):     sumW[i+1] += w
            case .glue(let w, let s, let sh): sumW[i+1] += w; sumStr[i+1] += s; sumShr[i+1] += sh
            case .penalty(let w, _, _): sumW[i+1] += w
            }
        }

        // Active nodes (deque)
        var active: [ActiveNode] = [ActiveNode(
            position: 0, line: 0, fitness: 1,
            totalWidth: 0, totalStretch: 0, totalShrink: 0,
            totalDemerits: 0, previous: nil)]

        var best = [Int: (demerits: CGFloat, node: Int)]()  // line -> best node index

        for (b, item) in items.enumerated() {
            // Check if this is a feasible breakpoint
            let isFeasible: Bool
            switch item {
            case .penalty(_, let v, _): isFeasible = v < 10000
            case .glue: isFeasible = b > 0 && { switch items[b-1] { case .box: return true; default: return false } }()
            default: isFeasible = false
            }
            guard isFeasible else { continue }

            var newActive = [ActiveNode]()

            for (ai, a) in active.enumerated() {
                let lineNum = a.line
                let lw = para.lineWidth(at: lineNum)

                // Compute natural width from a.position to b
                let natW = sumW[b+1] - sumW[a.position]
                    - (a.position > 0 ? glueWidth(items[a.position]) : 0)

                let stretch = sumStr[b+1] - sumStr[a.position]
                let shrink  = sumShr[b+1] - sumShr[a.position]

                let diff = lw - natW
                let r: CGFloat
                if diff > 0 && stretch > 0 { r = diff / stretch }
                else if diff < 0 && shrink > 0 { r = diff / shrink }
                else if diff == 0 { r = 0 }
                else { r = diff > 0 ? CGFloat.greatestFiniteMagnitude : -CGFloat.greatestFiniteMagnitude }

                // Line is too full or too loose?
                if r < -1 {
                    // Deactivate a (no hope of fitting)
                    continue
                }
                if r > para.tolerance { newActive.append(a); continue }

                // Badness and demerits
                let badness: CGFloat = r >= 0 ? min(100 * pow(r, 3), 10000) : min(100 * pow(-r, 3), 10000)

                let penValue: CGFloat
                let penFlagged: Bool
                switch item {
                case .penalty(_, let v, let f): penValue = v; penFlagged = f
                default: penValue = 0; penFlagged = false
                }

                let lineDemerit: CGFloat
                if penValue >= 0 {
                    lineDemerit = pow(para.linePenalty + badness, 2) + pow(penValue, 2)
                } else if penValue > -10000 {
                    lineDemerit = pow(para.linePenalty + badness, 2) - pow(penValue, 2)
                } else {
                    lineDemerit = pow(para.linePenalty + badness, 2)
                }

                // Fitness class
                let fitness: Int
                if r < -0.5 { fitness = 0 }
                else if r < 0.5 { fitness = 1 }
                else if r < 1.0 { fitness = 2 }
                else { fitness = 3 }

                // Fitness penalty
                let fd = abs(fitness - a.fitness) > 1 ? para.hyphenDemerits : CGFloat(0)

                // Hyphen demerit for consecutive flagged breaks
                let hd: CGFloat
                if penFlagged, case .penalty(_, _, let pf) = items[a.position], pf {
                    hd = para.hyphenDemerits
                } else { hd = 0 }

                let totalDemerits = a.totalDemerits + lineDemerit + fd + hd

                // Keep as new active node
                let newNode = ActiveNode(
                    position: b, line: lineNum + 1, fitness: fitness,
                    totalWidth: sumW[b+1], totalStretch: sumStr[b+1], totalShrink: sumShr[b+1],
                    totalDemerits: totalDemerits, previous: ai)

                // Track best for this line
                if let prev = best[lineNum + 1] {
                    if totalDemerits < prev.demerits {
                        best[lineNum + 1] = (totalDemerits, active.count + newActive.count)
                        newActive.append(newNode)
                    }
                } else {
                    best[lineNum + 1] = (totalDemerits, active.count + newActive.count)
                    newActive.append(newNode)
                }

                newActive.append(a)  // keep a in active for future lines
            }

            active = newActive
        }

        // Find the best last active node
        guard let last = active.min(by: { $0.totalDemerits < $1.totalDemerits }) else {
            return KPBreakResult(breakpoints: [], adjustRatios: [])
        }

        // Trace back to get break positions
        var breaks = [Int]()
        var cur: ActiveNode? = last
        var traced = [ActiveNode]()
        while let c = cur {
            traced.append(c)
            if let prevIdx = c.previous, prevIdx < active.count {
                cur = active[prevIdx]
            } else { break }
        }
        traced.reverse()
        for t in traced where t.position > 0 { breaks.append(t.position) }

        // Compute adjustment ratios for each line
        var ratios = [CGFloat]()
        var prev = 0
        for (li, bp) in breaks.enumerated() {
            let lw = para.lineWidth(at: li)
            let natW = sumW[bp+1] - sumW[prev]
            let s = sumStr[bp+1] - sumStr[prev]
            let sh = sumShr[bp+1] - sumShr[prev]
            let diff = lw - natW
            let r: CGFloat
            if diff > 0 && s > 0 { r = diff / s }
            else if diff < 0 && sh > 0 { r = diff / sh }
            else { r = 0 }
            ratios.append(r)
            prev = bp
        }

        return KPBreakResult(breakpoints: breaks, adjustRatios: ratios)
    }

    private static func glueWidth(_ item: KPItem) -> CGFloat {
        if case .glue(let w, _, _) = item { return w }
        return 0
    }
}

// MARK: - Build KP items from attributed string + font

extension KnuthPlassBreaker {

    /// Build KP items from plain text using CoreText metrics.
    /// Returns items and an array of word ranges in `text` for reconstruction.
    static func buildItems(from text: String, font: CTFont,
                            hyphenChar: String = "\u{00AD}") -> ([KPItem], [Range<String.Index>]) {
        let em = CTFontGetSize(font)
        let spaceW  = measureWord(" ", font: font)
        let stretch = em / 6
        let shrink  = em / 9

        var items   = [KPItem]()
        var ranges  = [Range<String.Index>]()
        var idx     = 0

        // Tokenize into words
        let words = text.split(separator: " ", omittingEmptySubsequences: false)
        var strIdx = text.startIndex

        for word in words {
            if word.isEmpty {
                // Extra space
                items.append(.glue(width: spaceW, stretch: stretch, shrink: shrink))
                strIdx = text.index(after: strIdx)
                continue
            }
            let start = strIdx
            let wordStr = String(word)
            let w = measureWord(wordStr, font: font)
            items.append(.box(width: w, index: idx))
            let end = text.index(strIdx, offsetBy: word.count)
            ranges.append(start..<end)
            strIdx = text.index(end, offsetBy: 1, limitedBy: text.endIndex) ?? text.endIndex
            items.append(.glue(width: spaceW, stretch: stretch, shrink: shrink))
            idx += 1
        }

        // Ensure final penalty
        items.append(.penalty(width: 0, value: -10000, flagged: false))
        return (items, ranges)
    }

    static func measureWord(_ word: String, font: CTFont) -> CGFloat {
        let attrStr = NSAttributedString(string: word,
            attributes: [kCTFontAttributeName as NSAttributedString.Key: font])
        let line = CTLineCreateWithAttributedString(attrStr as CFAttributedString)
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }
}
