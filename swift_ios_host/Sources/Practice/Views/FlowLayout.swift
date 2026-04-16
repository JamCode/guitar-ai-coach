import SwiftUI

/// 一个轻量的 Flow Layout，用于小 chip 的自动换行。
struct FlowLayout: Layout {
    let spacing: CGFloat
    let runSpacing: CGFloat

    init(spacing: CGFloat, runSpacing: CGFloat) {
        self.spacing = spacing
        self.runSpacing = runSpacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0

        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0, x + sz.width > width {
                x = 0
                y += rowH + runSpacing
                rowH = 0
            }
            rowH = max(rowH, sz.height)
            x += (x == 0 ? 0 : spacing) + sz.width
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0

        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0, x + sz.width > bounds.width {
                x = 0
                y += rowH + runSpacing
                rowH = 0
            }
            s.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), proposal: ProposedViewSize(sz))
            rowH = max(rowH, sz.height)
            x += (x == 0 ? 0 : spacing) + sz.width
        }
    }
}

