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
            Text(LocalizedStringResource("tuner_section_status", bundle: .main)).appSectionTitle()
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
                    Text(String(format: AppL10n.t("tuner_cents_format"), cents))
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

    private var strings: [TuningStringInfo] {
        [6, 5, 4, 3, 2, 1].map { n in
            TuningStringInfo(number: n, hint: stringHint(n))
        }
    }

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
                    Text(LocalizedStringResource("tuner_select_string", bundle: .main)).appSectionTitle()
                    Text(LocalizedStringResource("tuner_howto_pick", bundle: .main))
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
                    Text(LocalizedStringResource("tuner_knob_unsure", bundle: .main))
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
        .navigationTitle(Text(LocalizedStringResource("tuner_nav_title", bundle: .main)))
        .appPageBackground()
        .onAppear {
            AudioStartupWarmup.shared.scheduleIfNeeded()
            if !viewModel.isListening {
                viewModel.statusMessage = AppL10n.t("tuner_status_tap_string")
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

    private func stringHint(_ stringNumber: Int) -> String {
        switch stringNumber {
        case 1: return AppL10n.t("tuner_hint_1")
        case 2: return AppL10n.t("tuner_hint_2")
        case 3: return AppL10n.t("tuner_hint_3")
        case 4: return AppL10n.t("tuner_hint_4")
        case 5: return AppL10n.t("tuner_hint_5")
        case 6: return AppL10n.t("tuner_hint_6")
        default: return ""
        }
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
            return AppL10n.t("tuner_target_pick_first")
        }
        return String(
            format: AppL10n.t("tuner_target_line_format"),
            Int64(6 - i),
            String(format: "%.2f", hz)
        )
    }

    private var tuningGuidance: (title: String, detail: String, helper: String, color: Color) {
        guard viewModel.selectedStringIndex != nil else {
            return (
                AppL10n.t("tuner_state_need_title"),
                AppL10n.t("tuner_state_need_detail"),
                AppL10n.t("tuner_state_need_helper"),
                SwiftAppTheme.text
            )
        }
        guard viewModel.frequencyHz != nil else {
            return (
                AppL10n.t("tuner_state_pluck_title"),
                AppL10n.t("tuner_state_pluck_detail"),
                AppL10n.t("tuner_state_pluck_helper"),
                SwiftAppTheme.text
            )
        }
        if viewModel.isInTune {
            return (
                AppL10n.t("tuner_state_intune_title"),
                AppL10n.t("tuner_state_intune_detail"),
                AppL10n.t("tuner_state_intune_helper"),
                SwiftAppTheme.dynamic(.green, .green)
            )
        }
        if viewModel.cents < 0 {
            return (
                AppL10n.t("tuner_state_low_title"),
                AppL10n.t("tuner_state_low_detail"),
                AppL10n.t("tuner_state_low_helper"),
                SwiftAppTheme.brand
            )
        }
        return (
            AppL10n.t("tuner_state_high_title"),
            AppL10n.t("tuner_state_high_detail"),
            AppL10n.t("tuner_state_high_helper"),
            SwiftAppTheme.brand
        )
    }

    private var rotationHintText: String? {
        guard let selectedIndex = viewModel.selectedStringIndex, viewModel.frequencyHz != nil else { return nil }
        if viewModel.isInTune { return nil }
        let side = selectedIndex <= 2 ? AppL10n.t("tuner_knob_left") : AppL10n.t("tuner_knob_right")
        if viewModel.cents < 0 {
            return String(format: AppL10n.t("tuner_rot_tight_fmt"), side)
        }
        return String(format: AppL10n.t("tuner_rot_loose_fmt"), side)
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
        .accessibilityLabel(String(format: AppL10n.t("tuner_a11y_string_format"), Int64(stringInfo.number), stringInfo.hint))
    }

    private var headstockCenter: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(SwiftAppTheme.surfaceSoft)
                .frame(width: 92, height: 228)
            VStack(spacing: 8) {
                Text(LocalizedStringResource("tuner_headstock", bundle: .main))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SwiftAppTheme.muted)
                Divider().frame(width: 56)
                Text(LocalizedStringResource("tuner_6_to_1", bundle: .main))
                    .font(.caption2)
                    .foregroundStyle(SwiftAppTheme.muted)
                Text(LocalizedStringResource("tuner_thick_to_thin", bundle: .main))
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
