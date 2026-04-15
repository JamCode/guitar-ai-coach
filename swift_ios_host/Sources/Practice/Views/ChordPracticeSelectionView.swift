import SwiftUI
import Core

struct ChordPracticeConfig: Equatable {
    let progression: ChordProgression
    let key: String
    let complexity: ChordComplexity
    let resolvedChords: [String]
}

/// 和弦进行选择页：选进行 / 调 / 复杂度，预览实际和弦名，进入练习（对齐 Flutter）。
struct ChordPracticeSelectionView: View {
    let task: PracticeTask
    let store: PracticeSessionStore

    @State private var selectedProgression: ChordProgression = kChordProgressions.first!
    @State private var selectedKey: String = "C"
    @State private var selectedComplexity: ChordComplexity = .basic

    @State private var showPickerSheet: Bool = false

    private var resolvedChords: [String] {
        ChordProgressionEngine.resolveChordNames(
            romanNumerals: selectedProgression.romanNumerals,
            key: selectedKey,
            complexity: selectedComplexity
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    previewCard

                    VStack(alignment: .leading, spacing: 8) {
                        Text("调性").appSectionTitle()
                        Picker("调性", selection: $selectedKey) {
                            ForEach(kMusicKeys, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.menu)
                    }
                    .appCard()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("复杂度").appSectionTitle()
                        Picker("复杂度", selection: $selectedComplexity) {
                            ForEach(ChordComplexity.allCases) { c in
                                Text(c.label).tag(c)
                            }
                        }
                        .pickerStyle(.segmented)
                        Text(selectedComplexity.fullLabel)
                            .font(.subheadline)
                            .foregroundStyle(SwiftAppTheme.muted)
                    }
                    .appCard()

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
                ChordPracticeSessionView(
                    task: task,
                    store: store,
                    config: ChordPracticeConfig(
                        progression: selectedProgression,
                        key: selectedKey,
                        complexity: selectedComplexity,
                        resolvedChords: resolvedChords
                    )
                )
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
        .sheet(isPresented: $showPickerSheet) {
            ChordProgressionPickerSheet(
                selectedId: selectedProgression.id,
                onSelected: { p in
                    selectedProgression = p
                    showPickerSheet = false
                }
            )
        }
        .appPageBackground()
    }

    @ViewBuilder
    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("当前选择预览").appSectionTitle()
                .foregroundStyle(SwiftAppTheme.text)

            FlowLayout(spacing: 8, runSpacing: 6) {
                ForEach(Array(resolvedChords.enumerated()), id: \.offset) { idx, chord in
                    Text(chord)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(SwiftAppTheme.brand)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(SwiftAppTheme.brandSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityLabel("预览和弦 \(chord) \(idx + 1)")
                }
            }

            Text("\(selectedProgression.name) · \(selectedKey) 调 · \(selectedComplexity.label) · 点和弦名查看指法")
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

