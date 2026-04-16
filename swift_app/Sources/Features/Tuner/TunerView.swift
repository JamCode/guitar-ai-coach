import SwiftUI
import Core

public struct TunerView: View {
    @StateObject private var viewModel = TunerViewModel()
    private let labels = ["6\nE", "5\nA", "4\nD", "3\nG", "2\nB", "1\ne"]

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
                    Text(viewModel.statusMessage).foregroundStyle(SwiftAppTheme.muted)
                    HStack(alignment: .lastTextBaseline, spacing: 16) {
                        Text(viewModel.noteName)
                            .font(.system(size: 48, weight: .bold))
                            .foregroundStyle(SwiftAppTheme.text)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(viewModel.frequencyHz.map { String(format: "%.1f Hz", $0) } ?? "-- Hz")
                                .foregroundStyle(SwiftAppTheme.text)
                            Text(targetCaption)
                                .foregroundStyle(SwiftAppTheme.muted)
                            Text(String(format: "%+.0f cent", viewModel.cents))
                                .foregroundStyle(SwiftAppTheme.brand)
                        }
                    }
                    MeterBar(cents: viewModel.cents, active: viewModel.frequencyHz != nil)
                        .frame(height: 20)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .appCard()

                VStack(alignment: .leading, spacing: 10) {
                    Text("选择弦").appSectionTitle()
                    // 均分整行，避免卡片拉满后弦钮仍靠左、右侧大块留白
                    HStack(spacing: 6) {
                        ForEach(0..<6, id: \.self) { i in
                            Button(labels[i]) {
                                Task { await viewModel.selectStringForTuning(i) }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(viewModel.selectedStringIndex == i ? SwiftAppTheme.brand : SwiftAppTheme.surfaceSoft)
                            .foregroundStyle(viewModel.selectedStringIndex == i ? Color.white : SwiftAppTheme.text)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                        }
                    }
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
                Rectangle()
                    .fill(SwiftAppTheme.line)
                    .frame(width: 2)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                if active {
                    Capsule()
                        .fill(SwiftAppTheme.brand)
                        .frame(width: 14)
                        .position(x: geo.size.width * t, y: geo.size.height / 2)
                }
            }
        }
    }
}

