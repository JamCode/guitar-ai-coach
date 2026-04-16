import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import Core

public struct LiveChordView: View {
    @StateObject private var controller = LiveChordController()

    public init() {}

    public var body: some View {
        let state = controller.state
        VStack(spacing: 0) {
            topSection(state: state)

            VStack {
                Spacer(minLength: 0)
                stageContent(state: state)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .appCard()
            .padding(.horizontal, SwiftAppTheme.pagePadding)
            .padding(.vertical, 12)

            controlsSection(state: state)
        }
        .navigationTitle("扒歌")
        .appPageBackground()
    }

    // MARK: - Top Section

    private func topSection(state: LiveChordUiState) -> some View {
        VStack(spacing: 12) {
            statusRow(state: state)
            chordTrackCard(state: state)
        }
        .padding(.horizontal, SwiftAppTheme.pagePadding)
        .padding(.top, 8)
    }

    private func statusRow(state: LiveChordUiState) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(state.isListening ? SwiftAppTheme.dynamic(.green, .green) : SwiftAppTheme.muted)
                .frame(width: 8, height: 8)
            Text(state.error ?? state.status)
                .font(.caption)
                .foregroundStyle(state.error != nil ? SwiftAppTheme.brand : SwiftAppTheme.muted)
            Spacer()
        }
    }

    private func chordTrackCard(state: LiveChordUiState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("最近和弦进行").appSectionTitle()
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if state.timeline.isEmpty {
                            Text(state.isListening ? "正在聆听…" : "识别到的和弦会出现在这里")
                                .font(.caption)
                                .foregroundStyle(SwiftAppTheme.muted)
                        } else {
                            ForEach(Array(state.timeline.enumerated()), id: \.offset) { idx, chord in
                                Text(chord)
                                    .font(.headline)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        state.isListening && chord == state.stableChord
                                            ? SwiftAppTheme.brandSoft
                                            : SwiftAppTheme.surfaceSoft
                                    )
                                    .clipShape(Capsule())
                                    .id(idx)
                            }
                        }
                    }
                }
                .onChange(of: state.timeline.count) { _, _ in
                    if let last = state.timeline.indices.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last, anchor: .trailing)
                        }
                    }
                }
            }
        }
        .appCard()
    }

    // MARK: - Stage Content

    @ViewBuilder
    private func stageContent(state: LiveChordUiState) -> some View {
        if state.error != nil {
            errorStage(message: state.error!)
        } else if !state.isListening && state.timeline.isEmpty {
            idleStage()
        } else if state.isListening && state.stableChord == "Unknown" {
            listeningEmptyStage()
        } else if state.isListening {
            listeningActiveStage(state: state)
        } else {
            pausedStage(state: state)
        }
    }

    private func idleStage() -> some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 40))
                .foregroundStyle(SwiftAppTheme.muted)
                .padding(.bottom, 4)
            Text("播放音乐或弹奏吉他")
                .font(.headline)
            Text("点击下方按钮开始识别和弦")
                .font(.caption)
                .foregroundStyle(SwiftAppTheme.muted)
        }
    }

    private func listeningEmptyStage() -> some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("---")
                .font(.system(size: 44, weight: .heavy))
                .foregroundStyle(SwiftAppTheme.line)
            Text("正在分析音频…")
                .font(.caption)
                .foregroundStyle(SwiftAppTheme.muted)
        }
    }

    private func listeningActiveStage(state: LiveChordUiState) -> some View {
        VStack(spacing: 12) {
            Text(state.stableChord)
                .font(.system(size: 44, weight: .heavy))
            ProgressView().controlSize(.small)
            HStack(spacing: 8) {
                ForEach(state.topK.prefix(3), id: \.label) { cand in
                    VStack(spacing: 2) {
                        Text(cand.label).font(.headline)
                        Text(String(format: "%.2f", cand.score)).font(.caption2)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(cand.label == state.stableChord ? SwiftAppTheme.brandSoft : SwiftAppTheme.surfaceSoft)
                    .clipShape(Capsule())
                }
            }
            HStack(spacing: 6) {
                Text("Confidence")
                    .font(.caption)
                    .foregroundStyle(SwiftAppTheme.muted)
                ProgressView(value: max(0, min(1, state.confidence)))
                    .tint(SwiftAppTheme.brand)
                    .frame(width: 60)
                Text("\(Int((state.confidence * 100).rounded()))%")
                    .font(.caption)
                    .foregroundStyle(SwiftAppTheme.muted)
            }
        }
    }

    private func pausedStage(state: LiveChordUiState) -> some View {
        VStack(spacing: 8) {
            Text(state.timeline.last ?? "—")
                .font(.system(size: 44, weight: .heavy))
                .foregroundStyle(SwiftAppTheme.muted)
            Text("已暂停 · 识别到 \(state.timeline.count) 个和弦")
                .font(.caption)
                .foregroundStyle(SwiftAppTheme.muted)
            if !state.timeline.isEmpty {
                Text(state.timeline.joined(separator: " → "))
                    .font(.caption)
                    .foregroundStyle(SwiftAppTheme.muted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(SwiftAppTheme.surfaceSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func errorStage(message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "mic.slash")
                .font(.system(size: 32))
                .foregroundStyle(SwiftAppTheme.brand)
                .padding(.bottom, 4)
            Text(message)
                .font(.headline)
                .foregroundStyle(SwiftAppTheme.brand)
            Text("请在系统设置中允许本应用访问麦克风")
                .font(.caption)
                .foregroundStyle(SwiftAppTheme.muted)
                .multilineTextAlignment(.center)
            #if os(iOS)
            Button("前往系统设置 →") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.caption)
            .foregroundStyle(SwiftAppTheme.brand)
            #endif
        }
    }

    // MARK: - Controls

    private func controlsSection(state: LiveChordUiState) -> some View {
        VStack(spacing: 8) {
            Button(mainButtonTitle(state: state)) {
                Task {
                    if state.isListening {
                        await controller.stop()
                    } else {
                        await controller.start()
                    }
                }
            }
            .appPrimaryButton()

            HStack {
                if !state.isListening && !state.timeline.isEmpty {
                    Button("清除") {
                        controller.clear()
                    }
                    .buttonStyle(.bordered)
                    .tint(SwiftAppTheme.brand)
                }
                Spacer()
                Button("快速识别") {
                    Task { await controller.setMode(.fast) }
                }
                .buttonStyle(.bordered)
                .tint(state.mode == .fast ? SwiftAppTheme.brand : SwiftAppTheme.muted)
                Button("稳定识别") {
                    Task { await controller.setMode(.stable) }
                }
                .buttonStyle(.bordered)
                .tint(state.mode == .stable ? SwiftAppTheme.brand : SwiftAppTheme.muted)
            }
        }
        .padding(.horizontal, SwiftAppTheme.pagePadding)
        .padding(.bottom, 12)
        .padding(.top, 8)
    }

    private func mainButtonTitle(state: LiveChordUiState) -> String {
        if state.error != nil { return "重试" }
        if state.isListening { return "暂停" }
        if !state.timeline.isEmpty { return "继续" }
        return "开始"
    }
}
