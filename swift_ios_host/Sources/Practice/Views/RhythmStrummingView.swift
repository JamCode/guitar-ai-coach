import SwiftUI
import Core
import Practice

/// 节奏扫弦练习：按内置常用扫弦型展示 4/4 八分网格图示；可选保存记录（对齐 Flutter）。
struct RhythmStrummingView: View {
    let task: PracticeTask
    let store: PracticeSessionStore

    @Environment(\.dismiss) private var dismiss

    @State private var selectedDifficulty: StrummingDifficulty = .初级
    @State private var pattern: StrummingPattern = StrummingPatternGenerator.defaultPattern(for: .初级)
    @State private var openedAt: Date = Date()

    @State private var showSettings: Bool = false
    @State private var showHelp: Bool = false
    @State private var showFinishSheet: Bool = false
    @State private var noteText: String = ""

    @State private var savingError: String?
    @State private var savedToast: Bool = false

    private let beatLabels: [String] = ["1", "&", "2", "&", "3", "&", "4", "&"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(task.description)
                    .foregroundStyle(SwiftAppTheme.text)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("本组练习")
                            .appSectionTitle()
                        Spacer()
                        Text(selectedDifficulty.rawValue)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(SwiftAppTheme.brand)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(SwiftAppTheme.brandSoft)
                            .clipShape(Capsule())
                    }
                    Text("当前节奏：\(pattern.name) · \(pattern.subtitle)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SwiftAppTheme.text)
                        .lineLimit(2)
                    Text("点击「下一组」按当前难度抽取常用扫弦型；难度在右上角齿轮设置。")
                        .font(.footnote)
                        .foregroundStyle(SwiftAppTheme.muted)
                }
                .appCard()

                VStack(alignment: .leading, spacing: 8) {
                    Text("一小节（4/4，八分六线谱）")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SwiftAppTheme.text)
                    StrummingTabStaffView(events: pattern.events, beatLabels: beatLabels)
                }
                .appCard()

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lightbulb")
                        .foregroundStyle(SwiftAppTheme.brand)
                    Text(pattern.tip)
                        .foregroundStyle(SwiftAppTheme.text)
                        .font(.subheadline)
                }
                .appCard()

                Button("下一组") { nextPattern() }
                    .appSecondaryButton()
                    .frame(maxWidth: .infinity)

            }
            .padding(SwiftAppTheme.pagePadding)
        }
        .navigationTitle(task.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("练习设置")
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                Form {
                    Section("难度") {
                        Picker("难度", selection: $selectedDifficulty) {
                            ForEach(StrummingDifficulty.allCases, id: \.self) { lv in
                                Text(lv.rawValue).tag(lv)
                            }
                        }
                        .pickerStyle(.menu)
                        Text("选择后会立即按该难度抽取新的扫弦型。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Section("图示说明") {
                        Text(
                            """
                            每一格对应一拍里的两个八分位置之一，顺序为「1 & 2 & 3 & 4 &」。

                            六线谱弦序固定为：① 在上、⑥ 在下（最粗弦在最下）。

                            在该弦序下：↑ 表示下扫，↓ 表示上扫，· 表示空拍，× 表示拍弦/切音。

                            本页为 4/4 常用型，可与节拍器或歌曲一起练习；本期不含内置节拍器与音频。
                            """
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("练习设置")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("完成") { showSettings = false }
                    }
                }
            }
        }
        .alert("图示说明", isPresented: $showHelp) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(
                """
                每一格对应一拍里的两个八分位置之一，顺序为「1 & 2 & 3 & 4 &」。

                六线谱弦序固定为：① 在上、⑥ 在下（最粗弦在最下）。

                在该弦序下：↑ 表示下扫，↓ 表示上扫，· 表示空拍，× 表示拍弦/切音。

                本页为 4/4 常用型，可与节拍器或歌曲一起练习；本期不含内置节拍器与音频。
                """
            )
        }
        .alert("保存失败", isPresented: Binding(get: { savingError != nil }, set: { if !$0 { savingError = nil } })) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(savingError ?? "")
        }
        .alert("记录已保存", isPresented: $savedToast) {
            Button("返回", role: .cancel) { dismiss() }
        }
        .sheet(isPresented: $showFinishSheet) {
            PracticeFinishDialog(
                title: "本次练习",
                showCompletedGoal: false,
                noteText: $noteText,
                onCancel: { showFinishSheet = false },
                onSave: { result in
                    showFinishSheet = false
                    Task { await save(result: result) }
                }
            )
        }
        .appPageBackground()
        .onAppear {
            openedAt = Date()
            // 首次进入按默认难度抽一次，避免每次都固定显示池子首项。
            nextPattern()
        }
        .onChange(of: selectedDifficulty) { _, _ in
            nextPattern()
        }
    }

    private func nextPattern() {
        var rng = SystemRandomNumberGenerator()
        pattern = StrummingPatternGenerator.nextPattern(
            difficulty: selectedDifficulty,
            excluding: pattern.id,
            using: &rng
        )
    }

    @MainActor
    private func save(result: PracticeFinishResult) async {
        do {
            let endedAt = Date()
            let durationSeconds = max(0, Int(endedAt.timeIntervalSince(openedAt)))
            guard durationSeconds >= PracticeRecordingPolicy.minForegroundSecondsToPersist else { return }
            try await store.saveSession(
                task: task,
                startedAt: openedAt,
                endedAt: endedAt,
                durationSeconds: durationSeconds,
                completed: result.completed,
                difficulty: result.difficulty,
                note: result.note,
                progressionId: nil,
                musicKey: nil,
                complexity: nil,
                rhythmPatternId: pattern.id,
                scaleWarmupDrillId: nil
            )
            savedToast = true
        } catch {
            savingError = String(describing: error)
        }
    }
}

enum StrummingTabStaffGlyph: Equatable {
    case downStroke
    case upStroke
    case rest
    case mute

    static func from(kind: StrumCellKind) -> Self {
        switch kind {
        case .down: .downStroke
        case .up: .upStroke
        case .rest: .rest
        case .mute: .mute
        }
    }

    static func from(action kind: StrumActionKind) -> Self {
        switch kind {
        case .down: .downStroke
        case .up: .upStroke
        case .rest: .rest
        case .mute: .mute
        }
    }

    var symbol: String {
        switch self {
        case .downStroke: "↑" // 下扫（①上⑥下坐标系）
        case .upStroke: "↓" // 上扫
        case .rest: "·" // 空拍
        case .mute: "×" // 拍弦/切音
        }
    }
}

private struct StrumDisplaySlot {
    let glyph: StrummingTabStaffGlyph
    let isPrimary: Bool
}

private struct StrummingTabStaffView: View {
    let events: [StrumActionEvent]
    let beatLabels: [String]
    private let stringLabels = ["①", "②", "③", "④", "⑤", "⑥"]
    private let totalUnits = 8

    private var slots: [StrumDisplaySlot] {
        makeDisplaySlots(from: events, totalUnits: totalUnits)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(" ")
                    .frame(width: 18)
                ForEach(0..<totalUnits, id: \.self) { i in
                    Text(beatLabels[i])
                        .font(.caption)
                        .foregroundStyle(SwiftAppTheme.muted)
                        .frame(maxWidth: .infinity)
                }
            }

            HStack(alignment: .top, spacing: 8) {
                VStack(spacing: 8) {
                    ForEach(stringLabels, id: \.self) { label in
                        Text(label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(SwiftAppTheme.muted)
                            .frame(width: 18, height: 10)
                    }
                }
                .padding(.top, 6)

                ZStack {
                    VStack(spacing: 10) {
                        ForEach(0..<6, id: \.self) { _ in
                            Rectangle()
                                .fill(SwiftAppTheme.line)
                                .frame(height: 1)
                        }
                    }

                    HStack(spacing: 6) {
                        ForEach(0..<totalUnits, id: \.self) { i in
                            let slot = slots[safe: i] ?? StrumDisplaySlot(glyph: .rest, isPrimary: true)
                            Text(slot.isPrimary ? slot.glyph.symbol : "—")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(slot.isPrimary ? SwiftAppTheme.text : SwiftAppTheme.muted)
                                .opacity(slot.isPrimary ? 1.0 : 0.7)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 6)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 76)
                .padding(10)
                .background(SwiftAppTheme.surfaceSoft.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(SwiftAppTheme.line, lineWidth: 1)
                )
            }

            Text("图例：↑ 下扫，↓ 上扫，· 空拍，× 拍弦；弦序为 ① 在上、⑥ 在下（最粗弦）。同一动作跨一拍时，首格显示动作，后续格显示延续占位。")
                .font(.caption)
                .foregroundStyle(SwiftAppTheme.muted)
        }
    }
}

private func makeDisplaySlots(from events: [StrumActionEvent], totalUnits: Int) -> [StrumDisplaySlot] {
    var slots: [StrumDisplaySlot] = []
    for event in events {
        guard event.units > 0 else { continue }
        let glyph = StrummingTabStaffGlyph.from(action: event.kind)
        slots.append(StrumDisplaySlot(glyph: glyph, isPrimary: true))
        if event.units > 1 {
            slots.append(contentsOf: Array(repeating: StrumDisplaySlot(glyph: glyph, isPrimary: false), count: event.units - 1))
        }
    }
    if slots.count < totalUnits {
        slots.append(contentsOf: Array(repeating: StrumDisplaySlot(glyph: .rest, isPrimary: true), count: totalUnits - slots.count))
    }
    return Array(slots.prefix(totalUnits))
}

private extension Array {
    subscript(safe idx: Int) -> Element? {
        guard idx >= 0, idx < count else { return nil }
        return self[idx]
    }
}

