import SwiftUI
import Core

public struct TunerView: View {
    @StateObject private var viewModel = TunerViewModel()
    private let strings: [TuningStringInfo] = [
        .init(number: 6, hint: "最粗弦"),
        .init(number: 5, hint: "次粗弦"),
        .init(number: 4, hint: "中间偏粗"),
        .init(number: 3, hint: "中间偏细"),
        .init(number: 2, hint: "次细弦"),
        .init(number: 1, hint: "最细弦")
    ]

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let errorText = viewModel.errorText {
                    Text(errorText)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .appCard()
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("状态").appSectionTitle()
                    Text(tuningGuidance.helper).foregroundStyle(SwiftAppTheme.muted)
                    HStack(alignment: .lastTextBaseline, spacing: 16) {
                        Text(tuningGuidance.title)
                            .font(.system(size: 42, weight: .bold))
                            .foregroundStyle(tuningGuidance.color)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tuningGuidance.detail)
                                .foregroundStyle(SwiftAppTheme.text)
                            Text(targetCaption)
                                .foregroundStyle(SwiftAppTheme.muted)
                            Text(String(format: "%+.0f cent", viewModel.cents))
                                .foregroundStyle(SwiftAppTheme.brand)
                        }
                    }
                    if let rotationHintText {
                        Text(rotationHintText)
                            .font(.caption)
                            .foregroundStyle(SwiftAppTheme.muted)
                    }
                    MeterBar(cents: viewModel.cents, active: viewModel.frequencyHz != nil)
                        .frame(height: 20)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .appCard()

                VStack(alignment: .leading, spacing: 10) {
                    Text("选择弦").appSectionTitle()
                    Text("按琴头旋钮位置选择：先轻拨一根弦，再点对应旋钮位置")
                        .font(.caption)
                        .foregroundStyle(SwiftAppTheme.muted)
                    HStack {
                        Spacer(minLength: 0)
                        HStack(alignment: .center, spacing: 14) {
                            VStack(spacing: 14) {
                                headstockStringButton(index: 2)
                                headstockStringButton(index: 1)
                                headstockStringButton(index: 0)
                            }
                            headstockCenter
                            VStack(spacing: 14) {
                                headstockStringButton(index: 3)
                                headstockStringButton(index: 4)
                                headstockStringButton(index: 5)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                    Text("不知道拧哪个琴钮时：先轻拨这根弦，再慢慢拧，观察红点是否回到中间。")
                        .font(.caption)
                        .foregroundStyle(SwiftAppTheme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .appCard()
            }
            .padding(SwiftAppTheme.pagePadding)
        }
        .navigationTitle("调音器")
        .appPageBackground()
        .onAppear {
            if !viewModel.isListening {
                viewModel.statusMessage = "轻点下方弦钮开始调音"
            }
        }
        .onDisappear {
            viewModel.stop()
        }
    }

    private var targetCaption: String {
        guard let i = viewModel.selectedStringIndex, let hz = viewModel.targetHz else {
            return "目标：请先选择弦"
        }
        return "目标：第 \(6 - i) 弦 · \(String(format: "%.2f Hz", hz))"
    }

    private var tuningGuidance: (title: String, detail: String, helper: String, color: Color) {
        guard viewModel.selectedStringIndex != nil else {
            return ("先选弦", "点下方按钮选择要调的弦", "先点下面的弦号，再拨那根弦", SwiftAppTheme.text)
        }
        guard viewModel.frequencyHz != nil else {
            return ("开始拨弦", "持续轻拨当前弦，观察红点是否居中", "只看红点是否回到中间区域", SwiftAppTheme.text)
        }
        let cents = viewModel.cents
        if abs(cents) <= 5 {
            return ("已调准", "保持当前旋钮位置即可", "已在中线附近，基本完成", SwiftAppTheme.dynamic(.green, .green))
        }
        if cents < 0 {
            return ("偏低", "把音高调高一点（继续慢调）", "红点在左，慢慢拧紧一点", SwiftAppTheme.brand)
        }
        return ("偏高", "把音高调低一点（继续慢调）", "红点在右，轻微放松一点", SwiftAppTheme.brand)
    }

    private var rotationHintText: String? {
        guard let selectedIndex = viewModel.selectedStringIndex, viewModel.frequencyHz != nil else { return nil }
        let cents = viewModel.cents
        if abs(cents) <= 5 { return nil }
        let side = selectedIndex <= 2 ? "左侧旋钮" : "右侧旋钮"
        if cents < 0 {
            return "操作建议（\(side)）：向拧紧方向小幅旋转约 1/8 圈；若红点离中线更远，立即反向。"
        }
        return "操作建议（\(side)）：向放松方向小幅旋转约 1/8 圈；若红点离中线更远，立即反向。"
    }

    private func headstockStringButton(index: Int) -> some View {
        let stringInfo = strings[index]
        let isSelected = viewModel.selectedStringIndex == index
        return Button {
            Task { await viewModel.selectStringForTuning(index) }
        } label: {
            ZStack {
                Circle()
                    .fill(isSelected ? SwiftAppTheme.brand : SwiftAppTheme.surfaceSoft)
                    .frame(width: 60, height: 60)
                Circle()
                    .stroke(isSelected ? SwiftAppTheme.brand : SwiftAppTheme.line, lineWidth: 1.5)
                    .frame(width: 60, height: 60)
                VStack(spacing: 2) {
                    Text("\(stringInfo.number)")
                        .font(.system(size: 20, weight: .bold))
                    Text(stringInfo.hint)
                        .font(.system(size: 9))
                        .lineLimit(1)
                }
                .foregroundStyle(isSelected ? Color.white : SwiftAppTheme.text)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("第 \(stringInfo.number) 弦，\(stringInfo.hint)")
    }

    private var headstockCenter: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(SwiftAppTheme.surfaceSoft)
                .frame(width: 92, height: 228)
            VStack(spacing: 8) {
                Text("琴头")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SwiftAppTheme.muted)
                Divider().frame(width: 56)
                Text("6 → 1")
                    .font(.caption2)
                    .foregroundStyle(SwiftAppTheme.muted)
                Text("粗 → 细")
                    .font(.caption2)
                    .foregroundStyle(SwiftAppTheme.muted)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(SwiftAppTheme.line, lineWidth: 1)
        )
    }
}

private struct MeterBar: View {
    let cents: Double
    let active: Bool

    var body: some View {
        GeometryReader { geo in
            let maxC = 50.0
            let t = min(1.0, max(0.0, (cents + maxC) / (2.0 * maxC)))
            ZStack(alignment: .leading) {
                Capsule().fill(SwiftAppTheme.surfaceSoft)
                RoundedRectangle(cornerRadius: geo.size.height / 2, style: .continuous)
                    .fill(SwiftAppTheme.dynamic(.green.opacity(0.18), .green.opacity(0.22)))
                    .frame(width: max(18, geo.size.width * 0.12), height: geo.size.height)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                Rectangle()
                    .fill(SwiftAppTheme.line)
                    .frame(width: 3)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                if active {
                    Capsule()
                        .fill(abs(cents) <= 5 ? SwiftAppTheme.dynamic(.green, .green) : SwiftAppTheme.brand)
                        .frame(width: 14)
                        .position(x: geo.size.width * t, y: geo.size.height / 2)
                }
            }
        }
    }
}

private struct TuningStringInfo {
    let number: Int
    let hint: String
}

