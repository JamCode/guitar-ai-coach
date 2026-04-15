import SwiftUI

public struct ChordLookupView: View {
    @State private var root = "C"
    @State private var quality = ""
    @State private var bass = ""
    @State private var selectedKey = "C"
    @State private var errorText: String?
    @State private var resultPayload: ChordExplainMultiPayload?

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
        Form {
            Section("当前和弦") {
                Text(displaySymbol.isEmpty ? "—" : displaySymbol).font(.title.bold())
                Text("C 调记谱：\(builtSymbol.isEmpty ? "—" : builtSymbol) · 查看调：\(selectedKey)")
                    .foregroundStyle(.secondary)
            }
            Section("选择") {
                Picker("根音", selection: $root) {
                    ForEach(ChordSelectCatalog.keys, id: \.self) { Text($0).tag($0) }
                }
                Picker("和弦性质", selection: $quality) {
                    ForEach(ChordSelectCatalog.qualOptions) { Text($0.label).tag($0.id) }
                }
                Picker("低音 / 转位", selection: $bass) {
                    ForEach(ChordSelectCatalog.bassOptions) { Text($0.label).tag($0.id) }
                }
                Picker("目标调（变调预览）", selection: $selectedKey) {
                    ForEach(ChordSelectCatalog.keys, id: \.self) { Text($0).tag($0) }
                }
            }
            Section {
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
                if let errorText { Text(errorText).foregroundStyle(.red) }
            }
        }
        .navigationTitle("和弦字典")
        .sheet(item: Binding(
            get: { resultPayload.map(ResultSheetModel.init(payload:)) },
            set: { _ in resultPayload = nil }
        )) { model in
            ChordResultSheet(payload: model.payload)
        }
    }
}

private struct ResultSheetModel: Identifiable {
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
            Text(payload.chordSummary.notesExplainZh).font(.subheadline).foregroundStyle(.secondary)

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
                Text(payload.disclaimer).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(20)
    }
}

