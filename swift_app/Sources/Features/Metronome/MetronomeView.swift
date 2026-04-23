import SwiftUI
import Core

/// 独立节拍器页：练习工具风格，信息优先、无复杂动效。
public struct MetronomeView: View {
    @StateObject private var vm: MetronomeViewModel

    public init(viewModel: MetronomeViewModel = MetronomeViewModel()) {
        _vm = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                beatDotsSection()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)

                bpmSection()
                    .appCard()

                timeSignatureSection()
                    .appCard()

                soundAndVolumeSection()
                    .appCard()

                transportSection()
                    .appCard()
            }
            .padding(SwiftAppTheme.pagePadding)
        }
        .navigationTitle("节拍器")
        .appPageBackground()
        .onDisappear {
            vm.stop()
        }
        .alert("提示", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func beatDotsSection() -> some View {
        let n = vm.beatsPerMeasure
        HStack(spacing: 10) {
            ForEach(1...n, id: \.self) { idx in
                let isOn = vm.currentBeatIndex == idx
                let isAccent = idx == 1
                Circle()
                    .fill(dotFill(isOn: isOn, isAccent: isAccent))
                    .frame(width: isAccent ? 18 : 14, height: isAccent ? 18 : 14)
                    .overlay(
                        Circle()
                            .stroke(SwiftAppTheme.line, lineWidth: isOn ? 0 : 1)
                    )
            }
        }
        .animation(.easeOut(duration: 0.08), value: vm.currentBeatIndex)
    }

    private func dotFill(isOn: Bool, isAccent: Bool) -> Color {
        if isOn {
            return isAccent ? SwiftAppTheme.brand : SwiftAppTheme.brand.opacity(0.55)
        }
        return isAccent ? SwiftAppTheme.surfaceSoft : SwiftAppTheme.surfaceSoft.opacity(0.85)
    }

    private func bpmSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("速度（BPM）").appSectionTitle()
            Text("\(vm.config.bpm)")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(SwiftAppTheme.text)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 12) {
                Button {
                    vm.adjustBPM(delta: -1)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 36))
                }
                .buttonStyle(.plain)
                .foregroundStyle(SwiftAppTheme.brand)
                .accessibilityLabel("减慢 1 BPM")

                Slider(
                    value: Binding(
                        get: { Double(vm.config.bpm) },
                        set: { vm.setBPM(Int($0.rounded())) }
                    ),
                    in: Double(MetronomeConfig.bpmRange.lowerBound)...Double(MetronomeConfig.bpmRange.upperBound),
                    step: 1
                )
                .tint(SwiftAppTheme.brand)

                Button {
                    vm.adjustBPM(delta: 1)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 36))
                }
                .buttonStyle(.plain)
                .foregroundStyle(SwiftAppTheme.brand)
                .accessibilityLabel("加快 1 BPM")
            }
        }
    }

    private func timeSignatureSection() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("拍号").appSectionTitle()
            Picker("拍号", selection: Binding(
                get: { vm.config.timeSignature },
                set: { vm.setTimeSignature($0) }
            )) {
                ForEach(MetronomeTimeSignature.allCases) { sig in
                    Text(sig.rawValue).tag(sig)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func soundAndVolumeSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("音色与音量").appSectionTitle()
            Picker("音色", selection: Binding(
                get: { vm.config.soundPreset },
                set: { vm.setSoundPreset($0) }
            )) {
                ForEach(MetronomeSoundPreset.allCases) { p in
                    Text(p.rawValue).tag(p)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Image(systemName: "speaker.fill")
                    .foregroundStyle(SwiftAppTheme.muted)
                Slider(
                    value: Binding(
                        get: { vm.config.volume },
                        set: { vm.setVolume($0) }
                    ),
                    in: 0...1
                )
                .tint(SwiftAppTheme.brand)
                Image(systemName: "speaker.wave.3.fill")
                    .foregroundStyle(SwiftAppTheme.muted)
            }
            Text("音量 \(Int((vm.config.volume * 100).rounded()))%")
                .font(.footnote)
                .foregroundStyle(SwiftAppTheme.muted)
        }
    }

    private func transportSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("播放控制").appSectionTitle()
            HStack(spacing: 12) {
                Button(vm.transport == .running ? "暂停" : "开始") {
                    vm.toggleStartPause()
                }
                .buttonStyle(.borderedProminent)
                .tint(SwiftAppTheme.brand)
                .frame(maxWidth: .infinity)

                Button("停止") {
                    vm.stop()
                }
                .buttonStyle(.bordered)
                .tint(SwiftAppTheme.brand)
                .frame(maxWidth: .infinity)
            }
            Text(statusHint)
                .font(.footnote)
                .foregroundStyle(SwiftAppTheme.muted)
        }
    }

    private var statusHint: String {
        switch vm.transport {
        case .stopped:
            return "强拍为每小节第一拍（圆点更大）；点击开始后用扬声器或耳机听拍。"
        case .paused:
            return "已暂停，可按开始继续。"
        case .running:
            return "运行中；修改 BPM 或拍号会立即生效。"
        }
    }
}
