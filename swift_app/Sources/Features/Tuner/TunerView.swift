import SwiftUI
import Core

private struct TunerScrollContentWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// 调音器「状态」卡片内层：与运行时同一套排版，便于对最坏文案做 `sizeThatFits`。
private struct TunerStatusCardBody: View {
    let helper: String
    let title: String
    let titleColor: Color
    let detail: String
    let targetCaption: String
    let rotationText: String?
    let cents: Double
    let meterActive: Bool
    let isInTune: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("状态").appSectionTitle()
            Text(helper)
                .foregroundStyle(SwiftAppTheme.muted)
                .lineLimit(2)
                .minimumScaleFactor(0.9)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 16) {
                Text(title)
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(width: 148, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text(detail)
                        .foregroundStyle(SwiftAppTheme.text)
                        .lineLimit(3)
                        .minimumScaleFactor(0.88)
                    Text(targetCaption)
                        .foregroundStyle(SwiftAppTheme.muted)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    Text(String(format: "%+.0f cent", cents))
                        .foregroundStyle(SwiftAppTheme.brand)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let rotationText, !rotationText.isEmpty {
                Text(rotationText)
                    .font(.caption)
                    .foregroundStyle(SwiftAppTheme.muted)
                    .lineLimit(5)
                    .minimumScaleFactor(0.92)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            MeterBar(cents: cents, active: meterActive, isInTune: isInTune)
                .frame(height: 20)
        }
    }
}

public struct TunerView: View {
    @StateObject private var viewModel = TunerViewModel()
    /// 由最坏文案在**当前内容宽度**下 `sizeThatFits` 得到的高度；随横向宽度变化可再增大，不缩小。
    @State private var statusCardMeasuredHeight: CGFloat = 0

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

                TunerStatusCardBody(
                    helper: tuningGuidance.helper,
                    title: tuningGuidance.title,
                    titleColor: tuningGuidance.color,
                    detail: tuningGuidance.detail,
                    targetCaption: targetCaption,
                    rotationText: rotationHintText,
                    cents: viewModel.cents,
                    meterActive: viewModel.frequencyHz != nil,
                    isInTune: viewModel.isInTune
                )
                .frame(maxWidth: .infinity)
                .frame(height: statusCardEffectiveHeight, alignment: .topLeading)
                .clipped()
                .appCard()

                VStack(alignment: .leading, spacing: 10) {
                    Text("选择弦").appSectionTitle()
                    Text("按琴头旋钮位置选择：点弦钮会播放该弦标准参考音；再轻拨同一根弦，对照表头指针调准。")
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
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: TunerScrollContentWidthKey.self, value: geo.size.width)
                }
            )
            .onPreferenceChange(TunerScrollContentWidthKey.self) { width in
                recomputeStatusCardHeight(scrollContentWidth: width)
            }
        }
        .navigationTitle("调音器")
        .appPageBackground()
        .onAppear {
            AudioStartupWarmup.shared.scheduleIfNeeded()
            if !viewModel.isListening {
                viewModel.statusMessage = "轻点下方弦钮开始调音"
            }
        }
        .onDisappear {
            viewModel.stop()
        }
    }

    /// 宽度 preference 未到前用占位；有估算值后取 max(地板, 估算)，且高度只增不减（避免裁切后无法再放大）。
    private var statusCardEffectiveHeight: CGFloat {
        let floor: CGFloat = 268
        let placeholder: CGFloat = 300
        if statusCardMeasuredHeight > 0 {
            return max(floor, statusCardMeasuredHeight)
        }
        return placeholder
    }

    private func recomputeStatusCardHeight(scrollContentWidth: CGFloat) {
        guard scrollContentWidth > 40 else { return }
        // `GeometryReader` 附在已加 `pagePadding` 的 VStack 上：先得到内容列宽，再扣 `appCard` 内边距。
        let contentColumnWidth = max(0, scrollContentWidth - SwiftAppTheme.pagePadding * 2)
        let innerWidth = max(80, contentColumnWidth - 14 * 2)
        let h = TunerStatusCardLayoutMetrics.estimatedWorstCaseHeight(contentInnerWidth: innerWidth)
        let merged = max(statusCardMeasuredHeight, h)
        if abs(merged - statusCardMeasuredHeight) > 0.5 {
            statusCardMeasuredHeight = merged
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
        if viewModel.isInTune {
            return ("已调准", "保持当前旋钮位置即可", "已在中线附近，基本完成", SwiftAppTheme.dynamic(.green, .green))
        }
        if viewModel.cents < 0 {
            return ("偏低", "把音高调高一点（继续慢调）", "红点在左，慢慢拧紧一点", SwiftAppTheme.brand)
        }
        return ("偏高", "把音高调低一点（继续慢调）", "红点在右，轻微放松一点", SwiftAppTheme.brand)
    }

    private var rotationHintText: String? {
        guard let selectedIndex = viewModel.selectedStringIndex, viewModel.frequencyHz != nil else { return nil }
        if viewModel.isInTune { return nil }
        let side = selectedIndex <= 2 ? "左侧旋钮" : "右侧旋钮"
        if viewModel.cents < 0 {
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
    let isInTune: Bool

    var body: some View {
        GeometryReader { geo in
            let t = TunerMeterMetrics.normalizedPosition(for: cents)
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
                        .fill(isInTune ? SwiftAppTheme.dynamic(.green, .green) : SwiftAppTheme.brand)
                        .frame(width: 14)
                        .position(x: geo.size.width * t, y: geo.size.height / 2)
                        .animation(.interpolatingSpring(stiffness: 220, damping: 24), value: cents)
                        .animation(.easeInOut(duration: 0.18), value: isInTune)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: active)
        }
    }
}

private struct TuningStringInfo {
    let number: Int
    let hint: String
}
