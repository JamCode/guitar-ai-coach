import ChordChart
import Chords
import Core
import SwiftUI

struct ChordPracticeConfig: Equatable {
    let progression: ChordProgression
    let key: String
    let complexity: ChordComplexity
    let resolvedChords: [String]
}

/// 和弦进行选择页：选进行、预览指法图；调性在齿轮内；复杂度按进行风格自动决定并显示档级标签。
struct ChordPracticeSelectionView: View {
    let task: PracticeTask
    let store: PracticeSessionStore

    @State private var selectedProgression: ChordProgression = kChordProgressions.first!
    @State private var selectedKey: String = "C"

    @State private var showPickerSheet: Bool = false
    @State private var showPracticeSettings: Bool = false

    private var impliedComplexity: ChordComplexity {
        selectedProgression.impliedComplexity
    }

    private var resolvedChords: [String] {
        ChordProgressionEngine.resolveChordNames(
            romanNumerals: selectedProgression.romanNumerals,
            key: selectedKey,
            complexity: impliedComplexity
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    previewCard

                    VStack(alignment: .leading, spacing: 8) {
                        Text("和弦进行").appSectionTitle()
                        Button {
                            showPickerSheet = true
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(selectedProgression.name)
                                        .foregroundStyle(SwiftAppTheme.text)
                                        .font(.headline)
                                    Text("\(kStyleLabels[selectedProgression.style] ?? selectedProgression.style) · \(selectedProgression.romanNumerals)")
                                        .foregroundStyle(SwiftAppTheme.muted)
                                        .font(.subheadline)
                                        .lineLimit(2)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(SwiftAppTheme.muted)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .appCard()
                }
                .padding(SwiftAppTheme.pagePadding)
            }
        }
        .safeAreaInset(edge: .bottom) {
            NavigationLink {
                TabBarHiddenContainer {
                    ChordPracticeSessionView(
                        task: task,
                        store: store,
                        config: ChordPracticeConfig(
                            progression: selectedProgression,
                            key: selectedKey,
                            complexity: impliedComplexity,
                            resolvedChords: resolvedChords
                        )
                    )
                }
            } label: {
                Label("开始练习", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .appPrimaryButton()
            .padding(.horizontal, SwiftAppTheme.pagePadding)
            .padding(.vertical, 10)
            .background(SwiftAppTheme.bg)
        }
        .navigationTitle("和弦切换练习")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showPracticeSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("练习设置与调性")
            }
        }
        .sheet(isPresented: $showPickerSheet) {
            ChordProgressionPickerSheet(
                selectedId: selectedProgression.id,
                onSelected: { p in
                    selectedProgression = p
                    showPickerSheet = false
                }
            )
        }
        .sheet(isPresented: $showPracticeSettings) {
            NavigationStack {
                Form {
                    Section("调性") {
                        Picker("调性", selection: $selectedKey) {
                            ForEach(kMusicKeys, id: \.self) { Text("\($0) 调").tag($0) }
                        }
                    }
                    Section("难度档") {
                        Text(impliedComplexity.practiceTierZh)
                            .font(.title3.weight(.semibold))
                        Text(impliedComplexity.fullLabel)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text("根据所选「和弦进行」的音乐风格自动选用三和弦 / 七和弦 / 九和弦等档次，无需手选。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("练习设置")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("完成") { showPracticeSettings = false }
                    }
                }
            }
        }
        .appPageBackground()
    }

    @ViewBuilder
    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text("当前选择预览")
                    .appSectionTitle()
                    .foregroundStyle(SwiftAppTheme.text)
                Spacer()
                Text(impliedComplexity.practiceTierZh)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SwiftAppTheme.brand)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(SwiftAppTheme.brandSoft)
                    .clipShape(Capsule())
            }

            ChordPracticeDiagramStrip(chordSymbols: resolvedChords)

            Text("\(selectedProgression.name) · \(impliedComplexity.practiceTierZh)")
                .font(.subheadline)
                .foregroundStyle(SwiftAppTheme.muted)
        }
        .appCard()
    }
}

private struct ChordProgressionPickerSheet: View {
    let selectedId: String
    let onSelected: (ChordProgression) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""

    private var filtered: [ChordProgression] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return kChordProgressions }
        return kChordProgressions.filter { p in
            let styleZh = (kStyleLabels[p.style] ?? "").lowercased()
            return p.name.lowercased().contains(q)
                || p.romanNumerals.lowercased().contains(q)
                || p.style.lowercased().contains(q)
                || styleZh.contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(kProgressionStyles, id: \.self) { style in
                    let items = filtered.filter { $0.style == style }
                    if !items.isEmpty {
                        Section(header: Text(kStyleLabels[style] ?? style)) {
                            ForEach(items) { p in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(p.name)
                                        Text(p.romanNumerals)
                                            .font(.subheadline)
                                            .foregroundStyle(SwiftAppTheme.muted)
                                    }
                                    Spacer()
                                    if p.id == selectedId {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(SwiftAppTheme.brand)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { onSelected(p) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("选择和弦进行")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .searchable(text: $query, prompt: "搜索名称、级数或风格")
            .appPageBackground()
        }
    }
}
