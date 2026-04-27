import ChordChart
import Chords
import Core
import Metronome
import SwiftUI

/// 和弦切换推荐练习：由 `ChordSwitchGenerator` 生成多组序列与 BPM 说明。
public struct ChordSwitchTrainingPracticeView: View {
    @State private var exercises: [ChordSwitchExercise] = []

    public init() {}

    public var body: some View {
        List {
            Section {
                Text(
                    "按难度自动组卷：固定 \(ChordSwitchGenerator.defaultKeyZh)，"
                        + "和弦进行按大调功能设计并标注级数；"
                        + "每组内从左到右切换，BPM 与每和弦拍数在区间内随机。"
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
                                Text("\(item.segments.count) 组 · \(item.flattenedChords.count) 和弦")
                                    .font(.headline)
                                Text(item.romanProgressionZh)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
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
    @StateObject private var metronomeVM = MetronomeViewModel()
    @State private var practicedBeatCount: Int = 0
    @State private var currentChordIndex: Int = 0
    @State private var beatAccumulator: Double = 0

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

    private var flattenedCount: Int {
        max(1, exercise.flattenedChords.count)
    }

    private var recommendedBPM: Int {
        let candidate: Int
        if exercise.bpmMin > 0, exercise.bpmMax > 0 {
            candidate = (exercise.bpmMin + exercise.bpmMax) / 2
        } else if exercise.bpmMin > 0 {
            candidate = exercise.bpmMin
        } else if exercise.bpmMax > 0 {
            candidate = exercise.bpmMax
        } else {
            candidate = 60
        }
        return MetronomeConfig.clampBPM(candidate)
    }

    private var beatsPerChordForPractice: Double {
        let raw = exercise.beatsPerChord
        return raw > 0 ? raw : 2
    }

    private var beatsPerChordLabel: String {
        let raw = beatsPerChordForPractice
        if abs(raw - raw.rounded()) < 1e-6 {
            return "每和弦 \(Int(raw.rounded())) 拍"
        }
        return "每和弦 \(String(format: "%.1f", raw)) 拍"
    }

    private func romanBase(segmentIndex: Int) -> Int {
        exercise.segments.prefix(segmentIndex).reduce(0) { $0 + $1.chords.count }
    }

    private func romanSlice(segmentIndex: Int) -> [String] {
        let base = romanBase(segmentIndex: segmentIndex)
        guard segmentIndex < exercise.segments.count else { return [] }
        let seg = exercise.segments[segmentIndex]
        let end = min(base + seg.chords.count, exercise.romanNumerals.count)
        guard base < end else { return [] }
        return Array(exercise.romanNumerals[base ..< end])
    }

    private func romanForChord(segmentIndex: Int, chordIndex: Int) -> String {
        let idx = romanBase(segmentIndex: segmentIndex) + chordIndex
        guard idx < exercise.romanNumerals.count else { return "—" }
        return exercise.romanNumerals[idx]
    }

    private func resetPracticeProgress() {
        metronomeVM.stop()
        practicedBeatCount = 0
        currentChordIndex = 0
        beatAccumulator = 0
    }

    private func handleMetronomeBeatTick() {
        practicedBeatCount += 1
        beatAccumulator += 1
        let step = beatsPerChordForPractice
        while beatAccumulator + 1e-9 >= step {
            beatAccumulator -= step
            currentChordIndex = (currentChordIndex + 1) % flattenedCount
        }
    }

    private func togglePracticeMetronome() {
        switch metronomeVM.transport {
        case .running:
            metronomeVM.pause()
        case .paused, .stopped:
            if metronomeVM.transport == .stopped {
                practicedBeatCount = 0
                beatAccumulator = 0
            }
            metronomeVM.setBPM(recommendedBPM)
            metronomeVM.start()
        }
    }

    var body: some View {
        List {
            Section {
                ChordSwitchSelectionPreviewCard(
                    chords: previewChords,
                    romans: romanSlice(segmentIndex: 0),
                    difficulty: exercise.difficulty,
                    keyZh: exercise.keyZh,
                    activeGlobalIndex: currentChordIndex
                )
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                .listRowBackground(Color.clear)
            }

            Section {
                Text(exercise.promptZh).font(.body)
                Text(exercise.bpmHintZh)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Button {
                            togglePracticeMetronome()
                        } label: {
                            Text(metronomeVM.transport == .running ? "⏸ 暂停" : "▶ 开始节拍")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .appSecondaryButton()
                        Text("BPM \(recommendedBPM) · \(beatsPerChordLabel)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(SwiftAppTheme.muted)
                    }
                    Text("当前拍数 \(practicedBeatCount) · 当前和弦 #\(currentChordIndex + 1)")
                        .font(.caption)
                        .foregroundStyle(SwiftAppTheme.muted)
                }
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
                        Text("级数：\(romanSlice(segmentIndex: i).joined(separator: " → "))")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Text(seg.summaryZh)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        ChordSwitchChordDiagramGrid(
                            items: seg.chords.enumerated().map { j, sym in
                                let globalIndex = romanBase(segmentIndex: i) + j
                                return (
                                    symbol: sym,
                                    roman: romanForChord(segmentIndex: i, chordIndex: j),
                                    globalIndex: globalIndex,
                                    isActive: globalIndex == currentChordIndex
                                )
                            }
                        )
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
        .onChange(of: metronomeVM.currentBeatIndex) { _, beat in
            guard beat != nil, metronomeVM.transport == .running else { return }
            handleMetronomeBeatTick()
        }
        .onDisappear {
            resetPracticeProgress()
        }
    }
}

// MARK: - 指法图网格（每行最多 4 个，自动换行）

private struct ChordSwitchChordDiagramGrid: View {
    let items: [(symbol: String, roman: String, globalIndex: Int, isActive: Bool)]

    private var widthToHeight: CGFloat {
        1 / ChordSwitchDiagramLayout.heightOverWidthRatio(
            chordCount: items.count,
            includeRomanLine: true
        )
    }

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .aspectRatio(widthToHeight, contentMode: .fit)
            .overlay(
                GeometryReader { geo in
                    let w = max(geo.size.width, 1)
                    let m = ChordSwitchDiagramLayout.metrics(containerWidth: w, includeRomanLine: true)
                    let rowGap = w * ChordSwitchDiagramLayout.rowGapOverWidth
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(), spacing: m.columnGutter),
                            count: ChordSwitchDiagramLayout.maxColumns
                        ),
                        alignment: .leading,
                        spacing: rowGap
                    ) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            ChordSwitchSymbolCell(
                                symbol: item.symbol,
                                roman: item.roman,
                                metrics: m,
                                isActive: item.isActive
                            )
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, m.outerHorizontalPadding)
                    .padding(.vertical, w * ChordSwitchDiagramLayout.verticalMarginOverWidth)
                    .frame(width: w, height: geo.size.height, alignment: .topLeading)
                }
            )
    }
}

// MARK: - 预览卡片（首组）

private struct ChordSwitchSelectionPreviewCard: View {
    let chords: [String]
    let romans: [String]
    let difficulty: ChordSwitchDifficulty
    let keyZh: String
    let activeGlobalIndex: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
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

            Text(keyZh)
                .font(.caption.weight(.semibold))
                .foregroundStyle(SwiftAppTheme.text)

            if chords.isEmpty {
                Text("暂无和弦序列")
                    .font(.footnote)
                    .foregroundStyle(SwiftAppTheme.muted)
            } else {
                ChordSwitchChordDiagramGrid(
                    items: chords.enumerated().map { i, sym in
                        (
                            symbol: sym,
                            roman: i < romans.count ? romans[i] : "—",
                            globalIndex: i,
                            isActive: i == activeGlobalIndex
                        )
                    }
                )
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
    let roman: String
    let metrics: ChordSwitchDiagramLayout.Metrics
    let isActive: Bool

    private var romanFontSize: CGFloat {
        max(9, metrics.columnWidth * 0.095)
    }

    private var symbolFontSize: CGFloat {
        max(10, metrics.columnWidth * 0.11)
    }

    var body: some View {
        VStack(spacing: metrics.cellVStackSpacing) {
            Group {
                if let entry = ChordChartData.chordChartEntry(symbol: symbol) {
                    ChordDiagramView(frets: entry.frets)
                        .frame(width: metrics.diagramWidth, height: metrics.diagramHeight)
                        .padding(metrics.diagramInnerPadding)
                        .background(SwiftAppTheme.surfaceSoft)
                        .clipShape(RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                                .stroke(SwiftAppTheme.line.opacity(0.85), lineWidth: 1)
                        )
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                            .fill(SwiftAppTheme.surfaceSoft)
                        Text("无本地指法")
                            .font(.system(size: max(9, metrics.columnWidth * 0.09)))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(SwiftAppTheme.muted)
                            .padding(metrics.diagramInnerPadding * 0.6)
                    }
                    .frame(width: metrics.placeholderWidth, height: metrics.placeholderHeight)
                    .overlay(
                        RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                            .stroke(SwiftAppTheme.line.opacity(0.85), lineWidth: 1)
                    )
                }
            }

            Text(roman)
                .font(.system(size: romanFontSize, weight: .semibold, design: .monospaced))
                .foregroundStyle(SwiftAppTheme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Text(symbol)
                .font(.system(size: symbolFontSize, weight: .semibold, design: .default))
                .foregroundStyle(isActive ? SwiftAppTheme.dynamic(.red, .red) : SwiftAppTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 4)
        .background(isActive ? SwiftAppTheme.brandSoft.opacity(0.45) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: max(8, metrics.cornerRadius), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: max(8, metrics.cornerRadius), style: .continuous)
                .stroke(isActive ? SwiftAppTheme.brand : .clear, lineWidth: isActive ? 1.8 : 0)
        )
        .frame(maxWidth: .infinity)
    }
}
