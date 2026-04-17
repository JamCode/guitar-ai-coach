import SwiftUI
import Core

public struct ChordLookupView: View {
    @State private var root = "C"
    @State private var quality = ""
    @State private var bass = ""
    @State private var selectedKey = "C"
    @State private var errorText: String?
    @State private var resultPayload: ChordExplainMultiPayload?
    @StateObject private var voicingAudio = ChordLookupVoicingAudioHolder()

    public init() {}

    private var builtSymbol: String {
        ChordSymbolBuilder.build(root: root, qualityId: quality, bassId: bass)
    }

    private var displaySymbol: String {
        if selectedKey == ChordSelectCatalog.referenceKey { return builtSymbol }
        return ChordTransposeLocal.transposeChordSymbol(
            builtSymbol,
            from: ChordSelectCatalog.referenceKey,
            to: selectedKey
        )
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("当前和弦").appSectionTitle()
                    Text(displaySymbol.isEmpty ? "—" : displaySymbol)
                        .font(.title.bold())
                        .foregroundStyle(SwiftAppTheme.text)
                    Text("C 调记谱：\(builtSymbol.isEmpty ? "—" : builtSymbol) · 查看调：\(selectedKey)")
                        .foregroundStyle(SwiftAppTheme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .appCard()

                VStack(alignment: .leading, spacing: 10) {
                    Text("选择").appSectionTitle()
                    chordMenuRow(title: "根音") {
                        Picker("根音", selection: $root) {
                            ForEach(ChordSelectCatalog.keys, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.menu)
                    }
                    chordMenuRow(title: "和弦性质") {
                        Picker("和弦性质", selection: $quality) {
                            ForEach(ChordSelectCatalog.qualOptions) { Text($0.label).tag($0.id) }
                        }
                        .pickerStyle(.menu)
                    }
                    chordMenuRow(title: "低音 / 转位") {
                        Picker("低音 / 转位", selection: $bass) {
                            ForEach(ChordSelectCatalog.bassOptions) { Text($0.label).tag($0.id) }
                        }
                        .pickerStyle(.menu)
                    }
                    chordMenuRow(title: "转调后的查看调") {
                        Picker("转调后的查看调", selection: $selectedKey) {
                            ForEach(ChordSelectCatalog.keys, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.menu)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .appCard()

                VStack(alignment: .leading, spacing: 10) {
                    Button("查询和弦指法") {
                        let symbol = displaySymbol.trimmingCharacters(in: .whitespacesAndNewlines)
                        if symbol.isEmpty {
                            errorText = "请先选择和弦"
                            resultPayload = nil
                            return
                        }
                        if let payload = OfflineChordBuilder.buildPayload(displaySymbol: symbol) {
                            errorText = nil
                            resultPayload = payload
                        } else {
                            errorText = "无法从符号解析和弦（请检查根音与性质）"
                            resultPayload = nil
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .appPrimaryButton()
                    if let errorText { Text(errorText).foregroundStyle(.red) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SwiftAppTheme.pagePadding)
        }
        .navigationTitle("和弦速查")
        .appPageBackground()
        .onAppear {
            voicingAudio.tonePlayer.prepare()
        }
        .sheet(item: Binding(
            get: { resultPayload.map(ResultSheetModel.init(payload:)) },
            set: { _ in resultPayload = nil }
        )) { model in
            ChordResultSheet(payload: model.payload, tonePlayer: voicingAudio.tonePlayer)
                .onAppear {
                    voicingAudio.tonePlayer.prepare()
                }
        }
    }

    /// iOS `.menu` 样式的 Picker 往往只显示当前值，不显式展示 `Picker` 标题；用固定行标题区分「根音」与「转调后查看调」等。
    @ViewBuilder
    private func chordMenuRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(SwiftAppTheme.muted)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private final class ChordLookupVoicingAudioHolder: ObservableObject {
    let tonePlayer = ChordVoicingTonePlayer()
}

private struct ResultSheetModel: Identifiable {
    let id = UUID()
    let payload: ChordExplainMultiPayload
}

private struct ChordResultSheet: View {
    let payload: ChordExplainMultiPayload
    let tonePlayer: ChordVoicingTonePlayer
    @State private var pageIndex = 0
    private var totalPages: Int { max(payload.voicings.count, 1) }
    private var currentPageDisplay: Int { min(max(pageIndex + 1, 1), totalPages) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(payload.chordSummary.symbol).font(.largeTitle.bold())
            if !payload.chordSummary.notesLetters.isEmpty {
                Text("构成音：\(payload.chordSummary.notesLetters.joined(separator: " · "))")
            }
            Text(payload.chordSummary.notesExplainZh).font(.subheadline).foregroundStyle(SwiftAppTheme.muted)
            Text("点按指法图试听：先分解（低音→高音），再柱式和弦。")
                .font(.caption)
                .foregroundStyle(SwiftAppTheme.muted)

            TabView(selection: $pageIndex) {
                ForEach(Array(payload.voicings.enumerated()), id: \.offset) { index, item in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.labelZh).font(.headline)
                        ChordDiagramView(frets: item.explain.frets)
                            .frame(maxWidth: 280)
                            .frame(height: 200)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                tonePlayer.playChordFrets(item.explain.frets)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("指法图 \(item.labelZh)，点按试听和弦")
                            .accessibilityAddTraits(.isButton)
                            .accessibilityHint("先依次播放各弦再同时播放柱式和弦")
                        Text("6→1 弦：\(item.explain.frets.map { $0 < 0 ? "x" : String($0) }.joined(separator: " ")) · 起算品格：\(item.explain.baseFret)")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(SwiftAppTheme.muted)
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
            .frame(height: 360)

            if payload.voicings.count > 1 {
                HStack(spacing: 8) {
                    Text("把位 \(currentPageDisplay)/\(totalPages) · 左右滑动切换")
                        .font(.footnote)
                        .foregroundStyle(SwiftAppTheme.muted)
                    Spacer()
                    HStack(spacing: 6) {
                        ForEach(0..<payload.voicings.count, id: \.self) { idx in
                            Circle()
                                .fill(idx == pageIndex ? SwiftAppTheme.brand : SwiftAppTheme.line)
                                .frame(width: 7, height: 7)
                        }
                    }
                }
            }

            if !payload.disclaimer.isEmpty {
                Text(payload.disclaimer).font(.footnote).foregroundStyle(SwiftAppTheme.muted)
            }
        }
        .padding(20)
    }
}

