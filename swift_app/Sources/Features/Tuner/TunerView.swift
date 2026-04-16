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
                    Text(errorText).foregroundStyle(.red).appCard()
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
                            Text("目标：第 \(6 - viewModel.selectedStringIndex) 弦 · \(String(format: "%.2f Hz", viewModel.targetHz))")
                                .foregroundStyle(SwiftAppTheme.muted)
                            Text(String(format: "%+.0f cent", viewModel.cents))
                                .foregroundStyle(SwiftAppTheme.brand)
                        }
                    }
                    MeterBar(cents: viewModel.cents, active: viewModel.frequencyHz != nil)
                        .frame(height: 20)
                }
                .appCard()

                VStack(alignment: .leading, spacing: 10) {
                    Text("选择弦").appSectionTitle()
                    HStack(spacing: 8) {
                        ForEach(0..<6, id: \.self) { i in
                            Button(labels[i]) {
                                viewModel.setSelectedString(i)
                                if viewModel.isListening {
                                    viewModel.updateFrequencySample(viewModel.targetHz)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(viewModel.selectedStringIndex == i ? SwiftAppTheme.brand : SwiftAppTheme.surfaceSoft)
                            .foregroundStyle(viewModel.selectedStringIndex == i ? Color.white : SwiftAppTheme.text)
                        }
                    }
                }
                .appCard()

                Button(viewModel.isListening ? "停止监听" : "开始监听") {
                    viewModel.isListening ? viewModel.stop() : viewModel.start()
                }
                .appPrimaryButton()
            }
            .padding(SwiftAppTheme.pagePadding)
        }
        .navigationTitle("调音器")
        .appPageBackground()
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

