import SwiftUI
import Core

public struct FretboardView: View {
    @StateObject private var viewModel = FretboardViewModel()
    private let maxFret = 15

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("标准调弦 E A D G B E")
                    .foregroundStyle(SwiftAppTheme.muted)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("变调夹 \(viewModel.capo) 品").foregroundStyle(SwiftAppTheme.text)
                        Slider(value: Binding(
                            get: { Double(viewModel.capo) },
                            set: { viewModel.capo = Int($0.rounded()) }
                        ), in: 0...12, step: 1)
                        .tint(SwiftAppTheme.brand)
                    }
                    Toggle("仅自然音", isOn: $viewModel.naturalOnly)
                    Toggle("左右镜像", isOn: $viewModel.mirror)
                }
                .appCard()

                ScrollView([.vertical, .horizontal]) {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(0...maxFret, id: \.self) { fret in
                            HStack(spacing: 4) {
                                Text(fret == 0 ? "0 空弦" : "\(fret)")
                                    .frame(width: 44, alignment: .leading)
                                    .foregroundStyle(SwiftAppTheme.muted)
                                ForEach(stringIndices(), id: \.self) { stringIndex in
                                    Button(viewModel.labelForCell(stringIndex: stringIndex, fret: fret) ?? "·") {
                                        viewModel.playCell(stringIndex: stringIndex, fret: fret)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(SwiftAppTheme.surfaceSoft)
                                    .foregroundStyle(SwiftAppTheme.text)
                                    .frame(width: 50)
                                }
                            }
                        }
                    }
                }
                .appCard()
            }
            .padding(SwiftAppTheme.pagePadding)
        }
        .navigationTitle("吉他指板")
        .appPageBackground()
    }

    private func stringIndices() -> [Int] {
        viewModel.mirror ? [5, 4, 3, 2, 1, 0] : [0, 1, 2, 3, 4, 5]
    }
}

