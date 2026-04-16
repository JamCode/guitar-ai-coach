import SwiftUI
import Core

public struct LiveChordView: View {
    @StateObject private var controller = LiveChordController()

    public init() {}

    public var body: some View {
        let state = controller.state
        VStack {
            ScrollView {
                VStack(spacing: 12) {
                    statusCard(state: state)
                    mainChordCard(state: state)
                    timelineCard(state: state)
                    if let error = state.error {
                        Text(error)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(16)
            }
            controls(state: state)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .navigationTitle("扒歌")
        .appPageBackground()
    }

    private func statusCard(state: LiveChordUiState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle()
                    .fill(state.isListening ? SwiftAppTheme.dynamic(.green, .green) : SwiftAppTheme.muted)
                    .frame(width: 8, height: 8)
                Text(state.status).foregroundStyle(SwiftAppTheme.muted)
            }
            Text("Confidence \((state.confidence * 100).rounded())%")
                .font(.caption)
                .foregroundStyle(SwiftAppTheme.muted)
            ProgressView(value: max(0, min(1, state.confidence)))
                .tint(SwiftAppTheme.brand)
        }
        .appCard()
    }

    private func mainChordCard(state: LiveChordUiState) -> some View {
        VStack(spacing: 12) {
            Text(state.stableChord)
                .font(.system(size: 44, weight: .heavy))
            if state.isListening {
                ProgressView().controlSize(.small)
            }
            HStack {
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
        }
        .appCard()
    }

    private func timelineCard(state: LiveChordUiState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("最近和弦进行").font(.headline)
            ScrollView(.horizontal) {
                HStack {
                    ForEach(state.timeline, id: \.self) { chord in
                        Text(chord)
                            .font(.headline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(chord == state.stableChord ? SwiftAppTheme.brandSoft : SwiftAppTheme.surfaceSoft)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
        .appCard()
    }

    private func controls(state: LiveChordUiState) -> some View {
        VStack(spacing: 8) {
            Button(state.isListening ? "暂停" : "开始") {
                Task {
                    if state.isListening { await controller.stop() }
                    else { await controller.start() }
                }
            }
            .appPrimaryButton()

            HStack {
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
    }
}

