import SwiftUI
import Chords
import ChordChart

public struct ChordLookupMergedView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case quick
        case custom
        var id: String { rawValue }
        var title: String {
            switch self {
            case .quick: return "常用和弦"
            case .custom: return "自定义速查"
            }
        }
    }

    @State private var mode: Mode = .quick

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            Picker("模式", selection: $mode) {
                ForEach(Mode.allCases) { m in
                    Text(m.title).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, SwiftAppTheme.pagePadding)
            .padding(.top, 8)

            Group {
                if mode == .quick {
                    ChordChartView()
                } else {
                    ChordLookupView()
                }
            }
        }
        .navigationTitle("和弦速查")
        .appPageBackground()
    }
}
