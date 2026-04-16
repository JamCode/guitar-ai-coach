import SwiftUI
import Core
import Chords

/// 用和弦符号弹出底部指法层（离线构成音 + 指法图）。
///
/// 解析失败时提示用户改去和弦字典；不抛异常（对齐 Flutter 行为）。
struct ChordQuickReferenceSheetHost: ViewModifier {
    @Binding var chordSymbolToPresent: String?
    @State private var payload: ChordExplainMultiPayload?
    @State private var errorText: String?

    func body(content: Content) -> some View {
        content
            .onChange(of: chordSymbolToPresent) { _, newValue in
                let sym = (newValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !sym.isEmpty else { return }
                if let p = OfflineChordBuilder.buildPayload(displaySymbol: sym) {
                    payload = p
                    errorText = nil
                } else {
                    payload = nil
                    errorText = "暂无法解析「\(sym)」的离线指法，请到「工具」打开和弦字典。"
                }
            }
            .alert("提示", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
                Button("知道了", role: .cancel) { chordSymbolToPresent = nil }
            } message: {
                Text(errorText ?? "")
            }
            .sheet(item: Binding(
                get: { payload.map(SheetModel.init(payload:)) },
                set: { _ in
                    payload = nil
                    chordSymbolToPresent = nil
                }
            )) { model in
                ChordResultSheet(payload: model.payload)
            }
    }
}

extension View {
    func chordQuickReferenceSheet(chordSymbolToPresent: Binding<String?>) -> some View {
        self.modifier(ChordQuickReferenceSheetHost(chordSymbolToPresent: chordSymbolToPresent))
    }
}

private struct SheetModel: Identifiable {
    let id = UUID()
    let payload: ChordExplainMultiPayload
}

private struct ChordResultSheet: View {
    let payload: ChordExplainMultiPayload
    @State private var pageIndex = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(payload.chordSummary.symbol).font(.largeTitle.bold())
            if !payload.chordSummary.notesLetters.isEmpty {
                Text("构成音：\(payload.chordSummary.notesLetters.joined(separator: " · "))")
            }
            Text(payload.chordSummary.notesExplainZh).font(.subheadline).foregroundStyle(SwiftAppTheme.muted)

            TabView(selection: $pageIndex) {
                ForEach(Array(payload.voicings.enumerated()), id: \.offset) { index, item in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.labelZh).font(.headline)
                        Text("6→1 弦：\(item.explain.frets.map { $0 < 0 ? "x" : String($0) }.joined(separator: " ")) · 起算品格：\(item.explain.baseFret)")
                            .font(.system(.body, design: .monospaced))
                        Text(item.explain.voicingExplainZh).font(.subheadline)
                        Spacer()
                    }
                    .padding(.horizontal, 4)
                    .tag(index)
                }
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            #endif
            .frame(height: 200)

            if !payload.disclaimer.isEmpty {
                Text(payload.disclaimer).font(.footnote).foregroundStyle(SwiftAppTheme.muted)
            }
        }
        .padding(20)
    }
}

