import SwiftUI

/// 试听各选项 —— 可折叠的水平和弦符号按钮行。
/// 练耳（和弦听辨）和专项训练共用此组件。
struct ChordPreviewRow: View {
    let symbols: [String]
    let isDisabled: Bool
    let onTap: (Int) -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Text("试听各选项")
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(SwiftAppTheme.brand)
            }
            .buttonStyle(.borderless)

            if isExpanded {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(symbols.enumerated()), id: \.offset) { idx, symbol in
                            Button {
                                onTap(idx)
                            } label: {
                                Text(symbol)
                                    .font(.subheadline.weight(.semibold).monospaced())
                                    .foregroundStyle(SwiftAppTheme.text)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.78)
                                    .frame(minWidth: 48)
                            }
                            .buttonStyle(.borderless)
                            .disabled(isDisabled)
                            .opacity(isDisabled ? 0.45 : 1)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 10)
                            .background(SwiftAppTheme.surfaceSoft)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(SwiftAppTheme.line, lineWidth: 1)
                            )
                            .accessibilityLabel("试听 \(symbol)")
                        }
                    }
                    .padding(.vertical, 1)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.top, 2)
    }
}
