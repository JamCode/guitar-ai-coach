import SwiftUI
import Core
#if os(iOS)
import UIKit
#endif

// MARK: - 品格按钮按下反馈

private struct FretboardNoteCellButtonStyle: ButtonStyle {
    var labelOpacity: Double
    var isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        let showActive = isActive && !configuration.isPressed
        configuration.label
            .foregroundStyle(showActive ? .white : SwiftAppTheme.text.opacity(labelOpacity))
            .padding(.horizontal, 4)
            .padding(.vertical, 7)
            .frame(minWidth: 44, minHeight: 34, maxHeight: 34)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        configuration.isPressed
                        ? SwiftAppTheme.brandSoft
                        : (showActive ? SwiftAppTheme.brand : SwiftAppTheme.surfaceSoft)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        configuration.isPressed || showActive ? SwiftAppTheme.brand.opacity(0.6) : SwiftAppTheme.line,
                        lineWidth: configuration.isPressed || showActive ? 2 : 1
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

public struct FretboardView: View {
    @StateObject private var viewModel = FretboardViewModel()
    private let maxFret = 15
    #if os(iOS)
    @State private var haptics = UIImpactFeedbackGenerator(style: .light)
    #endif

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

                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(0...maxFret, id: \.self) { fret in
                        HStack(spacing: 4) {
                            Text("\(fret)")
                                .frame(width: 22, alignment: .leading)
                                .foregroundStyle(SwiftAppTheme.muted)
                            ForEach(stringIndices(), id: \.self) { stringIndex in
                                let label = viewModel.labelForCell(stringIndex: stringIndex, fret: fret)
                                let dimmed = viewModel.naturalOnly && viewModel.isAccidentalCell(stringIndex: stringIndex, fret: fret)
                                let isActive = viewModel.activeCell == .init(stringIndex: stringIndex, fret: fret)
                                Button {
                                    viewModel.playCell(stringIndex: stringIndex, fret: fret)
                                    #if os(iOS)
                                    haptics.impactOccurred()
                                    haptics.prepare()
                                    #endif
                                } label: {
                                    Text(label)
                                        .font(.caption.monospaced())
                                        .minimumScaleFactor(0.65)
                                        .lineLimit(1)
                                }
                                .buttonStyle(FretboardNoteCellButtonStyle(labelOpacity: dimmed ? 0.32 : 1, isActive: isActive))
                            }
                        }
                    }
                }
                .padding(.trailing, 6)
                .appCard()
            }
            .padding(SwiftAppTheme.pagePadding)
        }
        .navigationTitle("吉他指板")
        .appPageBackground()
        .task {
            viewModel.prepareAudio()
            #if os(iOS)
            haptics.prepare()
            #endif
        }
    }

    private func stringIndices() -> [Int] {
        viewModel.mirror ? [5, 4, 3, 2, 1, 0] : [0, 1, 2, 3, 4, 5]
    }
}

