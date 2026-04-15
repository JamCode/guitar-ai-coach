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
        .navigationTitle("实时和弦建议（Beta）")
    }

    private func statusCard(state: LiveChordUiState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle()
                    .fill(state.isListening ? .green : .gray)
                    .frame(width: 8, height: 8)
                Text(state.status).foregroundStyle(.secondary)
            }
            Text("Confidence \((state.confidence * 100).rounded())%")
                .font(.caption)
                .foregroundStyle(.secondary)
            ProgressView(value: max(0, min(1, state.confidence)))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
                    .background(cand.label == state.stableChord ? Color.blue.opacity(0.2) : Color.gray.opacity(0.15))
                    .clipShape(Capsule())
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
                            .background(chord == state.stableChord ? Color.blue.opacity(0.2) : Color.gray.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func controls(state: LiveChordUiState) -> some View {
        VStack(spacing: 8) {
            Button(state.isListening ? "暂停" : "开始") {
                Task {
                    if state.isListening { await controller.stop() }
                    else { await controller.start() }
                }
            }
            .buttonStyle(.borderedProminent)

            HStack {
                Button("快速识别") {
                    Task { await controller.setMode(.fast) }
                }
                .buttonStyle(.bordered)
                .tint(state.mode == .fast ? .blue : .gray)
                Button("稳定识别") {
                    Task { await controller.setMode(.stable) }
                }
                .buttonStyle(.bordered)
                .tint(state.mode == .stable ? .blue : .gray)
            }
        }
    }
}

