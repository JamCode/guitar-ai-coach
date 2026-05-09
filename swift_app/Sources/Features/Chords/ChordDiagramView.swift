import SwiftUI
import Core

/// 吉他和弦指法简图：6 根弦从左到右为 6→1 弦，品格为绝对品格（与「6→1 弦」数字一致）。
public struct ChordDiagramView: View {
    public let frets: [Int]

    public init(frets: [Int]) {
        self.frets = frets
    }

    private var strings: [Int] { ChordDiagramLayout.normalizedFrets(frets) }

    public var body: some View {
        let cfg = ChordDiagramLayout.config(for: strings)
        GeometryReader { _ in
            Canvas { ctx, size in
                drawDiagram(ctx: &ctx, size: size, cfg: cfg, strings: strings)
            }
        }
        .aspectRatio(0.78, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary(cfg: cfg, strings: strings))
    }

    private func accessibilitySummary(cfg: ChordDiagramLayout.Config, strings: [Int]) -> String {
        let nums = strings.map { $0 < 0 ? "闷" : String($0) }.joined(separator: ",")
        let range = cfg.showsNut ? "琴枕起 \(cfg.startFret)–\(cfg.endFret) 品" : "从第 \(cfg.startFret) 品起"
        return "指法图，\(range)，6→1 弦品格 \(nums)"
    }

    private func drawDiagram(
        ctx: inout GraphicsContext,
        size: CGSize,
        cfg: ChordDiagramLayout.Config,
        strings: [Int]
    ) {
        let leftGutter: CGFloat = cfg.positionLabel != nil ? 18 : 4
        let topBand: CGFloat = size.height * 0.14
        let nutHeight: CGFloat = cfg.showsNut ? 4 : 0
        let fretRows = CGFloat(cfg.endFret - cfg.startFret + 1)
        let fretAreaTop = topBand + nutHeight
        let fretAreaHeight = max(size.height - fretAreaTop, 1)
        let rowH = fretAreaHeight / fretRows
        let innerW = size.width - leftGutter
        let stringXs = (0..<6).map { i in
            leftGutter + (CGFloat(i) + 0.5) * (innerW / 6)
        }

        if let label = cfg.positionLabel {
            let t = contextText(String(label), color: SwiftAppTheme.muted, size: 11, weight: .semibold)
            ctx.draw(ctx.resolve(t), at: CGPoint(x: leftGutter * 0.45, y: fretAreaTop + rowH * 0.45), anchor: .center)
        }

        for i in 0..<6 {
            var p = Path()
            p.move(to: CGPoint(x: stringXs[i], y: topBand * 0.35))
            p.addLine(to: CGPoint(x: stringXs[i], y: size.height))
            ctx.stroke(p, with: .color(SwiftAppTheme.line), lineWidth: i == 0 || i == 5 ? 2 : 1.2)
        }

        if cfg.showsNut {
            var nut = Path()
            nut.move(to: CGPoint(x: leftGutter, y: topBand + nutHeight * 0.5))
            nut.addLine(to: CGPoint(x: size.width, y: topBand + nutHeight * 0.5))
            ctx.stroke(nut, with: .color(SwiftAppTheme.text), lineWidth: nutHeight)
        }

        for r in 0...Int(fretRows) {
            let y = fretAreaTop + CGFloat(r) * rowH
            var h = Path()
            h.move(to: CGPoint(x: leftGutter, y: y))
            h.addLine(to: CGPoint(x: size.width, y: y))
            ctx.stroke(h, with: .color(SwiftAppTheme.line), lineWidth: r == 0 && !cfg.showsNut ? 2 : 1)
        }

        // 简单横按检测：同一品位在相邻至少 2 根弦出现时绘制横按条。
        for barre in detectBarres(strings: strings) {
            guard barre.fret >= cfg.startFret && barre.fret <= cfg.endFret else { continue }
            let row = CGFloat(barre.fret - cfg.startFret)
            let cy = fretAreaTop + (row + 0.5) * rowH
            let x1 = stringXs[barre.startString]
            let x2 = stringXs[barre.endString]
            let height = min(rowH, innerW / 6) * 0.45
            let rect = CGRect(
                x: min(x1, x2) - height * 0.4,
                y: cy - height * 0.5,
                width: abs(x2 - x1) + height * 0.8,
                height: height
            )
            let path = Path(roundedRect: rect, cornerRadius: height * 0.45)
            ctx.fill(path, with: .color(SwiftAppTheme.brand.opacity(0.92)))
            ctx.stroke(path, with: .color(SwiftAppTheme.text), lineWidth: 1)
        }

        for s in 0..<6 {
            let fret = strings[s]
            let cx = stringXs[s]
            if fret < 0 {
                let t = contextText("×", color: SwiftAppTheme.text, size: 15, weight: .bold)
                ctx.draw(ctx.resolve(t), at: CGPoint(x: cx, y: topBand * 0.42), anchor: .center)
            } else if fret == 0 {
                let t = contextText("○", color: SwiftAppTheme.text, size: 13, weight: .regular)
                ctx.draw(ctx.resolve(t), at: CGPoint(x: cx, y: topBand * 0.42), anchor: .center)
            } else if fret >= cfg.startFret && fret <= cfg.endFret {
                let row = CGFloat(fret - cfg.startFret)
                let cy = fretAreaTop + (row + 0.5) * rowH
                let r = min(rowH, innerW / 6) * 0.32
                let dot = Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
                ctx.fill(dot, with: .color(SwiftAppTheme.brand))
                ctx.stroke(dot, with: .color(SwiftAppTheme.text), lineWidth: 1)
            }
        }
    }

    private func contextText(_ str: String, color: Color, size: CGFloat, weight: Font.Weight) -> Text {
        Text(str)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(color)
    }

    private func detectBarres(strings: [Int]) -> [BarreSpan] {
        var spans: [BarreSpan] = []
        var idx = 0
        while idx < strings.count {
            let fret = strings[idx]
            guard fret > 0 else {
                idx += 1
                continue
            }
            var end = idx
            while end + 1 < strings.count, strings[end + 1] == fret {
                end += 1
            }
            if end - idx + 1 >= 2 {
                spans.append(BarreSpan(fret: fret, startString: idx, endString: end))
            }
            idx = end + 1
        }
        return spans
    }
}

private struct BarreSpan {
    let fret: Int
    let startString: Int
    let endString: Int
}
