import SwiftUI
import Chords
import Core
import Combine

struct FullChordChartView: View {
    let entry: TranscriptionHistoryEntry
    @ObservedObject var vm: TranscriptionPlayerViewModel

    @State private var currentSegmentIndex: Int? = nil
    @State private var currentRowIndex: Int? = nil
    @State private var currentChordIndexInRow: Int? = nil
    @State private var isEditing = false
    @State private var workingRows: [[TranscriptionSegment]] = []
    @State private var loadedEditedSegments: [TranscriptionSegment]? = nil
    @State private var loadedEditedRowSizes: [Int]? = nil
    @State private var didLoadPersistedEditedState = false
    @State private var selectedPosition: ChordRowPosition? = nil
    @State private var chordNameDraft = ""
    @State private var showingChordActions = false
    @State private var showingRenameAlert = false
    @State private var showingDiscardChangesDialog = false
    @State private var showingRestoreOriginalDialog = false
    @State private var showingSaveError = false
    @State private var showingSongChordFingerings = true
    @State private var saveErrorMessage = ""
    @State private var isSaving = false

    private let historyStore = TranscriptionHistoryStore()

    private var originalPreparedChartSegments: [TranscriptionSegment] {
        let raw = vm.activeChordChartSource(from: entry)
        let sanitizer = vm.displaySanitizer(for: entry)
        return TranscriptionChordResolver.makeDisplayChordSegments(rawSegments: raw, sanitizer: sanitizer)
    }

    private var originalPreparedChartRows: [[TranscriptionSegment]] {
        TranscriptionChordChartRowLayout.chunkRows(from: originalPreparedChartSegments)
    }

    private var persistedChartRows: [[TranscriptionSegment]] {
        if didLoadPersistedEditedState {
            if let edited = loadedEditedSegments, !edited.isEmpty {
                return TranscriptionChordChartRowLayout.rebuildRows(from: edited, rowSizes: loadedEditedRowSizes)
            }
            return originalPreparedChartRows
        }
        if let edited = entry.editedChordChartSegments, !edited.isEmpty {
            return TranscriptionChordChartRowLayout.rebuildRows(from: edited, rowSizes: entry.editedChordChartRowSizes)
        }
        return originalPreparedChartRows
    }

    private var displayedRows: [[TranscriptionSegment]] {
        isEditing ? workingRows : persistedChartRows
    }

    private var sortedSegments: [TranscriptionSegment] {
        TranscriptionChordChartRowLayout.flattenRows(displayedRows)
    }

    private var hasUnsavedChanges: Bool {
        isEditing && workingRows != persistedChartRows
    }

    private var canSaveChanges: Bool {
        isEditing && !sortedSegments.isEmpty && hasUnsavedChanges && !isSaving
    }

    private var canRestoreOriginal: Bool {
        guard isEditing else { return false }
        if workingRows != originalPreparedChartRows {
            return true
        }
        if didLoadPersistedEditedState {
            return (loadedEditedSegments?.isEmpty == false) || (loadedEditedRowSizes?.isEmpty == false)
        }
        return (entry.editedChordChartSegments?.isEmpty == false) || (entry.editedChordChartRowSizes?.isEmpty == false)
    }

    private var rows: [[TranscriptionSegment]] {
        displayedRows
    }

    private var songChordFingerings: [SongChordFingeringItem] {
        SongChordFingeringItem.makeItems(from: sortedSegments)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                headerCard

                SongChordFingeringSection(
                    items: songChordFingerings,
                    isExpanded: $showingSongChordFingerings
                )

                LazyVStack(spacing: 8) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                        chordRow(rowIndex: rowIndex, row: row)
                    }
                }

                if isEditing {
                    editorActionBar
                }
            }
            .padding(SwiftAppTheme.pagePadding)
            .padding(.bottom, 96)
        }
        .onAppear {
            applyHighlight(for: vm.currentTimeMs)
        }
        .task(id: entry.id) {
            await loadLatestEditedSegments()
        }
        .onReceive(
            vm.$currentTimeMs
                .map { timeMs in
                    PlaybackSyncResolver.currentIndex(for: timeMs, segments: sortedSegments)
                }
                .removeDuplicates()
        ) { idx in
            updateCurrentHighlight(for: idx)
        }
        .onChange(of: sortedSegments) { _, _ in
            applyHighlight(for: vm.currentTimeMs)
        }
        .navigationTitle("我的和弦谱")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if isEditing {
                    Button("完成") {
                        finishEditingTapped()
                    }
                    .disabled(isSaving)
                } else {
                    Button("编辑") {
                        beginEditing()
                    }
                    .disabled(sortedSegments.isEmpty)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            CompactPlaybackBarHost(vm: vm, durationMs: entry.durationMs)
                .padding(.horizontal, 16)
                .padding(.top, 4)
        }
        .appPageBackground()
        .confirmationDialog(
            "编辑和弦",
            isPresented: $showingChordActions,
            titleVisibility: .visible
        ) {
            Button("修改和弦") {
                guard let selectedSegment else { return }
                chordNameDraft = selectedSegment.chord
                showingRenameAlert = true
            }
            Button("删除") {
                applyDelete()
            }
            Button("向前合并") {
                applyMergeBackward()
            }
            .disabled(!canMergeBackward)
            Button("向后合并") {
                applyMergeForward()
            }
            .disabled(!canMergeForward)
            Button("取消", role: .cancel) {
                selectedPosition = nil
            }
        } message: {
            if let selectedSegment {
                Text(selectedSegment.chord)
            }
        }
        .alert("修改和弦", isPresented: $showingRenameAlert) {
            TextField("例如：C#m", text: $chordNameDraft)
            Button("取消", role: .cancel) {
                selectedPosition = nil
            }
            Button("保存") {
                applyRename()
            }
        } message: {
            Text("只会修改这个和弦名称，不会改变时间位置。")
        }
        .confirmationDialog(
            "还有未保存的修改",
            isPresented: $showingDiscardChangesDialog,
            titleVisibility: .visible
        ) {
            Button("保存修改") {
                Task { await saveWorkingChanges() }
            }
            Button("放弃修改", role: .destructive) {
                cancelEditing()
            }
            Button("继续编辑", role: .cancel) {}
        } message: {
            Text("离开编辑模式前，先决定是否保留这次修改。")
        }
        .confirmationDialog(
            "恢复 AI 初始和弦谱",
            isPresented: $showingRestoreOriginalDialog,
            titleVisibility: .visible
        ) {
            Button("恢复 AI 初始和弦谱", role: .destructive) {
                workingRows = originalPreparedChartRows
                selectedPosition = nil
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会把当前草稿改回 AI 生成的初始和弦谱；点击“保存修改”后才会真正生效。")
        }
        .alert("保存失败", isPresented: $showingSaveError) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(saveErrorMessage)
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.displayName)
                .font(.title2.weight(.bold))
                .foregroundStyle(SwiftAppTheme.text)
                .lineLimit(1)
            Text("参考调：\(entry.originalKey)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SwiftAppTheme.brand)
            if isEditing {
                Text("你修改并保存后，主页面和这里都会显示这份和弦谱；播放时间轴不会改变。")
                    .font(.caption)
                    .foregroundStyle(SwiftAppTheme.muted)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(SwiftAppTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(SwiftAppTheme.line, lineWidth: 1)
        )
    }

    private func applyHighlight(for currentTimeMs: Int) {
        let idx = PlaybackSyncResolver.currentIndex(for: currentTimeMs, segments: sortedSegments)
        updateCurrentHighlight(for: idx)
    }

    @ViewBuilder
    private func chordRow(rowIndex: Int, row: [TranscriptionSegment]) -> some View {
        let isCurrentRow = rowIndex == currentRowIndex
        let currentChord = isCurrentRow ? currentChordIndexInRow : nil
        ChordRowView(
            rowIndex: rowIndex,
            row: row,
            isEditing: isEditing,
            isCurrentRow: isCurrentRow,
            currentChordIndexInRow: currentChord,
            onTapRow: {
                guard !isEditing, let first = row.first else { return }
                vm.seek(first.startMs)
            },
            onTapChord: { idxInRow, seg in
                if isEditing {
                    selectedPosition = ChordRowPosition(rowIndex: rowIndex, chordIndex: idxInRow)
                    showingChordActions = true
                } else {
                    vm.seek(seg.startMs)
                }
            }
        )
        .id("row-\(rowIndex)")
    }

    private var selectedSegment: TranscriptionSegment? {
        guard
            let selectedPosition,
            workingRows.indices.contains(selectedPosition.rowIndex),
            workingRows[selectedPosition.rowIndex].indices.contains(selectedPosition.chordIndex)
        else {
            return nil
        }
        return workingRows[selectedPosition.rowIndex][selectedPosition.chordIndex]
    }

    private var canMergeBackward: Bool {
        guard
            let selectedPosition,
            workingRows.indices.contains(selectedPosition.rowIndex)
        else {
            return false
        }
        return selectedPosition.chordIndex > 0
    }

    private var canMergeForward: Bool {
        guard
            let selectedPosition,
            workingRows.indices.contains(selectedPosition.rowIndex)
        else {
            return false
        }
        return selectedPosition.chordIndex + 1 < workingRows[selectedPosition.rowIndex].count
    }

    @ViewBuilder
    private var editorActionBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button(role: .destructive) {
                    showingRestoreOriginalDialog = true
                } label: {
                    Text("恢复 AI 初始")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!canRestoreOriginal || isSaving)

                Button {
                    Task { await saveWorkingChanges() }
                } label: {
                    if isSaving {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("保存修改")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSaveChanges)
            }

            Text("支持：改和弦名、删除、向前合并、向后合并。修改只在点击“保存修改”后生效。")
                .font(.caption)
                .foregroundStyle(SwiftAppTheme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(SwiftAppTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(SwiftAppTheme.line, lineWidth: 1)
        )
    }

    private func beginEditing() {
        workingRows = persistedChartRows
        selectedPosition = nil
        isEditing = true
    }

    private func finishEditingTapped() {
        if hasUnsavedChanges {
            showingDiscardChangesDialog = true
            return
        }
        cancelEditing()
    }

    private func cancelEditing() {
        selectedPosition = nil
        chordNameDraft = ""
        workingRows = []
        isEditing = false
    }

    private func applyRename() {
        guard
            let selectedPosition,
            let updated = TranscriptionChordChartEditing.rename(
                rows: workingRows,
                at: selectedPosition,
                to: chordNameDraft
            )
        else {
            return
        }
        workingRows = updated
    }

    private func applyDelete() {
        guard
            let selectedPosition,
            let updated = TranscriptionChordChartEditing.delete(rows: workingRows, at: selectedPosition)
        else {
            return
        }
        workingRows = updated
        self.selectedPosition = nil
    }

    private func applyMergeBackward() {
        guard
            let selectedPosition,
            let updated = TranscriptionChordChartEditing.mergeBackward(rows: workingRows, at: selectedPosition)
        else {
            return
        }
        workingRows = updated
        self.selectedPosition = ChordRowPosition(
            rowIndex: selectedPosition.rowIndex,
            chordIndex: max(0, selectedPosition.chordIndex - 1)
        )
    }

    private func applyMergeForward() {
        guard
            let selectedPosition,
            let updated = TranscriptionChordChartEditing.mergeForward(rows: workingRows, at: selectedPosition)
        else {
            return
        }
        workingRows = updated
        self.selectedPosition = ChordRowPosition(
            rowIndex: selectedPosition.rowIndex,
            chordIndex: min(selectedPosition.chordIndex, max(0, updated[selectedPosition.rowIndex].count - 1))
        )
    }

    private func loadLatestEditedSegments() async {
        guard let latest = await historyStore.load(id: entry.id) else { return }
        await MainActor.run {
            loadedEditedSegments = latest.editedChordChartSegments
            loadedEditedRowSizes = latest.editedChordChartRowSizes
            didLoadPersistedEditedState = true
        }
    }

    private func saveWorkingChanges() async {
        let flattened = TranscriptionChordChartRowLayout.flattenRows(workingRows)
        guard !flattened.isEmpty else {
            saveErrorMessage = "至少保留一个和弦后再保存。"
            showingSaveError = true
            return
        }
        guard !isSaving else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            if workingRows == originalPreparedChartRows {
                try await historyStore.clearEditedChordChartSegments(id: entry.id)
                loadedEditedSegments = nil
                loadedEditedRowSizes = nil
            } else {
                let rowSizes = workingRows.map(\.count)
                try await historyStore.updateEditedChordChartSegments(
                    id: entry.id,
                    segments: flattened,
                    rowSizes: rowSizes
                )
                loadedEditedSegments = flattened
                loadedEditedRowSizes = rowSizes
            }
            didLoadPersistedEditedState = true
            cancelEditing()
        } catch {
            saveErrorMessage = error.localizedDescription
            showingSaveError = true
        }
    }

    private func updateCurrentHighlight(for flattenedIndex: Int?) {
        currentSegmentIndex = flattenedIndex
        guard
            let flattenedIndex,
            let position = rowPosition(forFlattenedIndex: flattenedIndex, in: displayedRows)
        else {
            currentRowIndex = nil
            currentChordIndexInRow = nil
            return
        }
        currentRowIndex = position.rowIndex
        currentChordIndexInRow = position.chordIndex
    }

    private func rowPosition(
        forFlattenedIndex flattenedIndex: Int,
        in rows: [[TranscriptionSegment]]
    ) -> ChordRowPosition? {
        guard flattenedIndex >= 0 else { return nil }
        var cursor = 0
        for (rowIndex, row) in rows.enumerated() {
            let nextCursor = cursor + row.count
            if flattenedIndex < nextCursor {
                return ChordRowPosition(rowIndex: rowIndex, chordIndex: flattenedIndex - cursor)
            }
            cursor = nextCursor
        }
        return nil
    }
}

private struct ChordRowView: View, Equatable {
    let rowIndex: Int
    let row: [TranscriptionSegment]
    let isEditing: Bool
    let isCurrentRow: Bool
    let currentChordIndexInRow: Int?
    let onTapRow: () -> Void
    let onTapChord: (Int, TranscriptionSegment) -> Void

    static func == (lhs: ChordRowView, rhs: ChordRowView) -> Bool {
        lhs.rowIndex == rhs.rowIndex
            && lhs.row == rhs.row
            && lhs.isEditing == rhs.isEditing
            && lhs.isCurrentRow == rhs.isCurrentRow
            && lhs.currentChordIndexInRow == rhs.currentChordIndexInRow
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(formatMs(row.first?.startMs ?? 0))
                .font(.caption.monospacedDigit())
                .foregroundStyle(isCurrentRow ? SwiftAppTheme.brand : SwiftAppTheme.muted)
                .frame(width: 44, alignment: .leading)

            HStack(spacing: 6) {
                ForEach(Array(row.enumerated()), id: \.offset) { idx, segment in
                    let isCurrentChord = currentChordIndexInRow == idx
                    Button {
                        onTapChord(idx, segment)
                    } label: {
                        Text(segment.chord)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(isCurrentChord ? .white : SwiftAppTheme.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .padding(.horizontal, 10)
                            .frame(height: 34)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(isCurrentChord ? SwiftAppTheme.brand : (isCurrentRow ? SwiftAppTheme.surfaceSoft.opacity(0.95) : SwiftAppTheme.surfaceSoft))
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(isCurrentChord ? SwiftAppTheme.brand : SwiftAppTheme.line, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(height: 58, alignment: .center)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(SwiftAppTheme.surface.opacity(isCurrentRow ? 0.98 : 0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    isCurrentRow ? SwiftAppTheme.brand.opacity(0.5) : SwiftAppTheme.line,
                    lineWidth: isCurrentRow ? 1.3 : 1
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isEditing else { return }
            onTapRow()
        }
    }

    private func formatMs(_ ms: Int) -> String {
        let totalSeconds = max(0, ms / 1000)
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

struct ChordRowPosition: Equatable {
    let rowIndex: Int
    let chordIndex: Int
}

private struct SongChordFingeringItem: Identifiable, Equatable {
    let id: String
    let displaySymbol: String
    let resolved: ResolvedChordFingering?

    static func makeItems(from segments: [TranscriptionSegment]) -> [SongChordFingeringItem] {
        var seen = Set<String>()
        var items: [SongChordFingeringItem] = []

        for segment in segments {
            let normalized = ChordFingeringResolver.normalizeChordName(segment.chord)
            guard !ChordFingeringResolver.isInvalidChordName(normalized) else { continue }
            let key = normalized.lowercased()
            guard seen.insert(key).inserted else { continue }

            let resolved = ChordFingeringResolver.resolve(normalized)
            items.append(
                SongChordFingeringItem(
                    id: key,
                    displaySymbol: resolved?.symbol ?? normalized,
                    resolved: resolved
                )
            )
        }

        return items
    }
}

private struct SongChordFingeringSection: View {
    let items: [SongChordFingeringItem]
    @Binding var isExpanded: Bool

    private let columns = [
        GridItem(.adaptive(minimum: 104, maximum: 132), spacing: 10, alignment: .top)
    ]

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("本曲和弦指法")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(SwiftAppTheme.text)
                            Text("\(items.count) 种和弦，按首次出现顺序排列")
                                .font(.caption)
                                .foregroundStyle(SwiftAppTheme.muted)
                        }

                        Spacer()

                        Image(systemName: "chevron.down")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(SwiftAppTheme.muted)
                            .rotationEffect(.degrees(isExpanded ? 0 : -90))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isExpanded {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                        ForEach(items) { item in
                            SongChordFingeringCard(item: item)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(SwiftAppTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(SwiftAppTheme.line, lineWidth: 1)
            )
        }
    }
}

private struct SongChordFingeringCard: View {
    let item: SongChordFingeringItem

    var body: some View {
        VStack(spacing: 8) {
            Text(item.displaySymbol)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(SwiftAppTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)

            if let resolved = item.resolved {
                ChordDiagramView(frets: resolved.frets)
                    .frame(height: 124)

                if let bassHint = resolved.bassHint {
                    Text("低音 \(bassHint)")
                        .font(.caption2)
                        .foregroundStyle(SwiftAppTheme.muted)
                        .lineLimit(1)
                }
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(SwiftAppTheme.surfaceSoft)
                    .overlay(
                        Text("暂无指法")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(SwiftAppTheme.muted)
                    )
                    .frame(height: 124)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(SwiftAppTheme.surfaceSoft.opacity(0.75))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(SwiftAppTheme.line.opacity(0.9), lineWidth: 1)
        )
    }
}

enum TranscriptionChordChartRowLayout {
    static func chunkRows(
        from segments: [TranscriptionSegment],
        defaultRowWidth: Int = 4
    ) -> [[TranscriptionSegment]] {
        guard !segments.isEmpty else { return [] }
        guard defaultRowWidth > 0 else { return [segments] }
        return stride(from: 0, to: segments.count, by: defaultRowWidth).map { start in
            Array(segments[start..<min(start + defaultRowWidth, segments.count)])
        }
    }

    static func rebuildRows(
        from segments: [TranscriptionSegment],
        rowSizes: [Int]?,
        defaultRowWidth: Int = 4
    ) -> [[TranscriptionSegment]] {
        guard !segments.isEmpty else { return [] }
        guard let rowSizes, !rowSizes.isEmpty else {
            return chunkRows(from: segments, defaultRowWidth: defaultRowWidth)
        }

        var rows: [[TranscriptionSegment]] = []
        var cursor = 0
        for size in rowSizes where size > 0 {
            guard cursor < segments.count else { break }
            let end = min(cursor + size, segments.count)
            rows.append(Array(segments[cursor..<end]))
            cursor = end
        }
        if cursor < segments.count {
            rows.append(
                contentsOf: chunkRows(
                    from: Array(segments[cursor...]),
                    defaultRowWidth: defaultRowWidth
                )
            )
        }
        return rows.isEmpty ? chunkRows(from: segments, defaultRowWidth: defaultRowWidth) : rows
    }

    static func flattenRows(_ rows: [[TranscriptionSegment]]) -> [TranscriptionSegment] {
        rows.flatMap { $0 }
    }
}

private struct CompactPlaybackBarHost: View {
    @ObservedObject var vm: TranscriptionPlayerViewModel
    let durationMs: Int

    var body: some View {
        CompactPlaybackBar(
            currentTime: vm.currentTimeMs,
            duration: durationMs,
            isPlaying: vm.isPlaying,
            playbackRate: vm.playbackRate,
            isLooping: vm.isLooping,
            onSeek: { vm.seek($0) },
            onPlayPause: { vm.togglePlay() },
            onToggleLoop: { vm.toggleLoop() },
            onChangeRate: { vm.cyclePlaybackRate() }
        )
    }
}

enum TranscriptionChordChartEditing {
    static func rename(
        rows: [[TranscriptionSegment]],
        at position: ChordRowPosition,
        to chord: String
    ) -> [[TranscriptionSegment]]? {
        guard
            rows.indices.contains(position.rowIndex),
            rows[position.rowIndex].indices.contains(position.chordIndex)
        else {
            return nil
        }
        let trimmed = chord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var updated = rows
        let current = updated[position.rowIndex][position.chordIndex]
        updated[position.rowIndex][position.chordIndex] = TranscriptionSegment(
            startMs: current.startMs,
            endMs: current.endMs,
            chord: trimmed
        )
        return updated
    }

    static func delete(
        rows: [[TranscriptionSegment]],
        at position: ChordRowPosition
    ) -> [[TranscriptionSegment]]? {
        guard
            rows.indices.contains(position.rowIndex),
            rows[position.rowIndex].indices.contains(position.chordIndex)
        else {
            return nil
        }
        var updated = rows
        updated[position.rowIndex].remove(at: position.chordIndex)
        if updated[position.rowIndex].isEmpty {
            updated.remove(at: position.rowIndex)
        }
        return updated
    }

    static func mergeBackward(
        rows: [[TranscriptionSegment]],
        at position: ChordRowPosition
    ) -> [[TranscriptionSegment]]? {
        guard
            rows.indices.contains(position.rowIndex),
            position.chordIndex > 0,
            rows[position.rowIndex].indices.contains(position.chordIndex)
        else {
            return nil
        }
        var updated = rows
        let prev = updated[position.rowIndex][position.chordIndex - 1]
        let current = updated[position.rowIndex][position.chordIndex]
        updated[position.rowIndex][position.chordIndex - 1] = TranscriptionSegment(
            startMs: prev.startMs,
            endMs: current.endMs,
            chord: prev.chord
        )
        updated[position.rowIndex].remove(at: position.chordIndex)
        return updated
    }

    static func mergeForward(
        rows: [[TranscriptionSegment]],
        at position: ChordRowPosition
    ) -> [[TranscriptionSegment]]? {
        guard
            rows.indices.contains(position.rowIndex),
            rows[position.rowIndex].indices.contains(position.chordIndex),
            position.chordIndex + 1 < rows[position.rowIndex].count
        else {
            return nil
        }
        var updated = rows
        let current = updated[position.rowIndex][position.chordIndex]
        let next = updated[position.rowIndex][position.chordIndex + 1]
        updated[position.rowIndex][position.chordIndex + 1] = TranscriptionSegment(
            startMs: current.startMs,
            endMs: next.endMs,
            chord: next.chord
        )
        updated[position.rowIndex].remove(at: position.chordIndex)
        return updated
    }
}

private struct CompactPlaybackBar: View {
    let currentTime: Int
    let duration: Int
    let isPlaying: Bool
    let playbackRate: Double
    let isLooping: Bool
    let onSeek: (Int) -> Void
    let onPlayPause: () -> Void
    let onToggleLoop: () -> Void
    let onChangeRate: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text(formatMs(currentTime))
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundStyle(SwiftAppTheme.muted)
                    .frame(width: 52, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { Double(currentTime) },
                        set: { onSeek(Int($0.rounded())) }
                    ),
                    in: 0...Double(max(duration, 1))
                )
                .tint(SwiftAppTheme.brand)
                .frame(maxWidth: .infinity)

                Text(formatMs(duration))
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundStyle(SwiftAppTheme.muted)
                    .frame(width: 52, alignment: .trailing)
            }

            HStack {
                Button(String(format: "%.1fx", playbackRate)) {
                    onChangeRate()
                }
                .frame(width: 60, height: 36)
                .buttonStyle(.bordered)
                .tint(SwiftAppTheme.brand)

                Spacer()

                Button {
                    onPlayPause()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                        .background(Circle().fill(SwiftAppTheme.brand))
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    onToggleLoop()
                } label: {
                    Image(systemName: "repeat")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(isLooping ? SwiftAppTheme.brand : SwiftAppTheme.muted)
                        .frame(width: 60, height: 36)
                }
                .buttonStyle(.bordered)
                .tint(SwiftAppTheme.brand)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(height: 84)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(SwiftAppTheme.surface.opacity(0.88))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(SwiftAppTheme.line, lineWidth: 1)
        )
    }

    private func formatMs(_ ms: Int) -> String {
        let totalSeconds = max(0, ms / 1000)
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}
