import ChordChart
import Chords
import Core
import SwiftUI

/// 和弦切换推荐练习：由 `ChordSwitchGenerator` 生成多组序列与 BPM 说明。
public struct ChordSwitchTrainingPracticeView: View {
    @State private var exercises: [ChordSwitchExercise] = []

    public init() {}

    public var body: some View {
        List {
            Section {
                Text(
                    "按难度自动组卷：每组内从左到右切换；BPM 与每和弦拍数为固定区间随机。"
                        + "下方直接展示常用把位指法图。"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Section("推荐练习") {
                ForEach(exercises) { item in
                    NavigationLink {
                        ChordSwitchExerciseDetailView(exercise: item)
                    } label: {
                        HStack(alignment: .center, spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(item.segments.count) 组")
                                    .font(.headline)
                                Text(item.bpmHintZh)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Text(item.difficulty.rawValue)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(SwiftAppTheme.brand)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(SwiftAppTheme.brandSoft)
                                .clipShape(Capsule())
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section {
                Button("换一组") { reload() }
            }
        }
        .navigationTitle("和弦切换")
        .appNavigationBarChrome()
        .onAppear { reload() }
    }

    private func reload() {
        var rng = SystemRandomNumberGenerator()
        exercises = ChordSwitchGenerator.recommendedExercises(using: &rng)
    }
}

// MARK: - 详情

private struct ChordSwitchExerciseDetailView: View {
    let exercise: ChordSwitchExercise

    @State private var showKeySettings = false

    private static var keyGearToolbarPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .primaryAction
        #endif
    }

    private var previewChords: [String] {
        exercise.segments.first?.chords ?? []
    }

    private var referenceKeyLabel: String {
        ChordSwitchKeyResolver.referenceMajorKeyLabel(for: exercise)
    }

    var body: some View {
        List {
            Section {
                ChordSwitchSelectionPreviewCard(
                    chords: previewChords,
                    difficulty: exercise.difficulty
                )
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                .listRowBackground(Color.clear)
            }

            Section {
                Text(exercise.promptZh).font(.body)
                Text(exercise.bpmHintZh)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !exercise.goalsZh.isEmpty {
                Section("训练目标") {
                    ForEach(Array(exercise.goalsZh.enumerated()), id: \.offset) { _, line in
                        Text("· \(line)")
                    }
                }
            }

            Section("分组") {
                ForEach(Array(exercise.segments.enumerated()), id: \.offset) { i, seg in
                    VStack(alignment: .leading, spacing: 10) {
                        Text("第 \(i + 1) 组").font(.subheadline.weight(.semibold))
                        Text(seg.summaryZh)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 12) {
                                ForEach(Array(seg.chords.enumerated()), id: \.offset) { _, sym in
                                    ChordSwitchSymbolCell(symbol: sym)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("和弦切换")
        .appNavigationBarChrome()
        .toolbar {
            ToolbarItem(placement: Self.keyGearToolbarPlacement) {
                Button {
                    showKeySettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("参考调性")
            }
        }
        .sheet(isPresented: $showKeySettings) {
            NavigationStack {
                Form {
                    Section("参考调性") {
                        Text(referenceKeyLabel)
                            .font(.title3.weight(.semibold))
                        Text(
                            "根据本练习中出现的和弦符号，自动匹配最可能的自然大调主音，"
                                + "便于理解级数与移调；若和弦来自多调混合，请以听感为准。"
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("练习设置")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("完成") { showKeySettings = false }
                    }
                }
            }
        }
    }
}

// MARK: - 预览卡片（首组）

private struct ChordSwitchSelectionPreviewCard: View {
    let chords: [String]
    let difficulty: ChordSwitchDifficulty

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text("当前选择预览")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SwiftAppTheme.muted)
                Spacer()
                Text(difficulty.rawValue)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SwiftAppTheme.brand)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(SwiftAppTheme.brandSoft)
                    .clipShape(Capsule())
            }

            if chords.isEmpty {
                Text("暂无和弦序列")
                    .font(.footnote)
                    .foregroundStyle(SwiftAppTheme.muted)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(Array(chords.enumerated()), id: \.offset) { _, sym in
                            ChordSwitchSymbolCell(symbol: sym)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Text("和弦切换 · \(difficulty.rawValue)")
                .font(.caption)
                .foregroundStyle(SwiftAppTheme.muted)
        }
        .padding(14)
        .background(SwiftAppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: SwiftAppTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SwiftAppTheme.cardRadius, style: .continuous)
                .stroke(SwiftAppTheme.line, lineWidth: 1)
        )
    }
}

private struct ChordSwitchSymbolCell: View {
    let symbol: String

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let entry = ChordChartData.chordChartEntry(symbol: symbol) {
                    ChordDiagramView(frets: entry.frets)
                        .frame(width: 72, height: 92)
                        .padding(6)
                        .background(SwiftAppTheme.surfaceSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(SwiftAppTheme.line.opacity(0.85), lineWidth: 1)
                        )
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(SwiftAppTheme.surfaceSoft)
                        Text("无本地指法")
                            .font(.caption2)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(SwiftAppTheme.muted)
                            .padding(6)
                    }
                    .frame(width: 84, height: 104)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(SwiftAppTheme.line.opacity(0.85), lineWidth: 1)
                    )
                }
            }

            Text(symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(SwiftAppTheme.text)
        }
    }
}
