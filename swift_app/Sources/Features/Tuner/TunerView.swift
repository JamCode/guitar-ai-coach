import SwiftUI

public struct TunerView: View {
    @StateObject private var viewModel = TunerViewModel()
    private let labels = ["6\nE", "5\nA", "4\nD", "3\nG", "2\nB", "1\ne"]

    public init() {}

    public var body: some View {
        List {
            if let errorText = viewModel.errorText {
                Text(errorText).foregroundStyle(.red)
            }
            Section("状态") {
                Text(viewModel.statusMessage)
                HStack(alignment: .lastTextBaseline, spacing: 16) {
                    Text(viewModel.noteName)
                        .font(.system(size: 48, weight: .bold))
                    VStack(alignment: .leading) {
                        Text(viewModel.frequencyHz.map { String(format: "%.1f Hz", $0) } ?? "-- Hz")
                        Text("目标：第 \(6 - viewModel.selectedStringIndex) 弦 · \(String(format: "%.2f Hz", viewModel.targetHz))")
                        Text(String(format: "%+.0f cent", viewModel.cents))
                            .foregroundStyle(.blue)
                    }
                }
                MeterBar(cents: viewModel.cents, active: viewModel.frequencyHz != nil)
                    .frame(height: 20)
            }
            Section("选择弦") {
                HStack(spacing: 8) {
                    ForEach(0..<6, id: \.self) { i in
                        Button(labels[i]) {
                            viewModel.setSelectedString(i)
                            if viewModel.isListening {
                                viewModel.updateFrequencySample(viewModel.targetHz)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(viewModel.selectedStringIndex == i ? .blue : .gray)
                    }
                }
            }
            Section {
                Button(viewModel.isListening ? "停止监听" : "开始监听") {
                    viewModel.isListening ? viewModel.stop() : viewModel.start()
                }
            }
        }
        .navigationTitle("调音器")
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
                Capsule().fill(.gray.opacity(0.25))
                Rectangle()
                    .fill(.secondary)
                    .frame(width: 2)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                if active {
                    Capsule()
                        .fill(.blue)
                        .frame(width: 14)
                        .position(x: geo.size.width * t, y: geo.size.height / 2)
                }
            }
        }
    }
}

