import SwiftUI
import Core

/// `UserDefaults` 键：完成后不再展示首次导览。
enum FirstLaunchTourStorage {
    static let completedKey = "AIGuitarFirstLaunchTourCompleted_v1"

    static func isCompleted(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: completedKey)
    }

    static func markCompleted(in defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: completedKey)
    }

    static func resetForTesting(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: completedKey)
    }
}

/// 全屏横向分页导览；完成或跳过后写入 `completedKey`。
struct FirstLaunchTourView: View {
    @AppStorage(FirstLaunchTourStorage.completedKey) private var tourCompleted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct PageSpec: Identifiable {
        let id: Int
        let title: String
        let body: String
        let symbol: String
    }

    private let specs: [PageSpec] = [
        PageSpec(
            id: 0,
            title: "欢迎使用玩乐吉他",
            body: "用底部四个分区完成练习、管理曲谱、扒歌与常用工具。左右滑动可浏览各分区说明。",
            symbol: "guitars"
        ),
        PageSpec(
            id: 1,
            title: "练习",
            body: "计时、音阶热身、节奏扫弦与和弦练习等入口集中在这里，适合每日固定练习流程。",
            symbol: "figure.strengthtraining.traditional"
        ),
        PageSpec(
            id: 2,
            title: "我的谱",
            body: "导入与管理你的曲谱与练习材料，需要时系统会请求访问相册以导入图片或视频。",
            symbol: "music.note.list"
        ),
        PageSpec(
            id: 3,
            title: "扒歌",
            body: "导入音频或视频后可在本机分析和弦走向；处理时间与文件大小有关，请保持应用在前台直至完成。",
            symbol: "waveform.path.ecg"
        ),
        PageSpec(
            id: 4,
            title: "工具",
            body: "调音器、指板、和弦速查与常用和弦图等工具在此；帮助与反馈、隐私政策与版本信息也在本页。",
            symbol: "wrench.and.screwdriver"
        ),
        PageSpec(
            id: 5,
            title: "权限与隐私",
            body: "调音与部分练习会使用麦克风；导入谱面或媒体时可能访问相册或文件。我们仅在功能需要时请求，并可在系统设置中随时调整。",
            symbol: "lock.shield"
        ),
    ]

    @State private var pageIndex: Int = 0

    private var isLastPage: Bool {
        pageIndex >= specs.count - 1
    }

    var body: some View {
        ZStack {
            SwiftAppTheme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer(minLength: 0)
                    Button("跳过") {
                        finishTour()
                    }
                    .font(.body.weight(.medium))
                    .foregroundStyle(SwiftAppTheme.muted)
                    .padding(.trailing, 4)
                }
                .padding(.horizontal, SwiftAppTheme.pagePadding)
                .padding(.top, 8)

                TabView(selection: $pageIndex) {
                    ForEach(specs) { spec in
                        tourPage(spec: spec)
                            .tag(spec.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .animation(reduceMotion ? nil : .default, value: pageIndex)

                VStack(spacing: 12) {
                    if isLastPage {
                        Button(action: finishTour) {
                            Text("开始使用")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(SwiftAppTheme.brand)
                    } else {
                        Button(action: advance) {
                            Text("下一页")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(SwiftAppTheme.brand)
                    }
                }
                .padding(.horizontal, SwiftAppTheme.pagePadding)
                .padding(.bottom, 28)
                .background(SwiftAppTheme.bg)
            }
        }
    }

    @ViewBuilder
    private func tourPage(spec: PageSpec) -> some View {
        VStack(spacing: 24) {
            Spacer(minLength: 12)
            Image(systemName: spec.symbol)
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(SwiftAppTheme.brand)
                .accessibilityHidden(true)
            Text(spec.title)
                .font(.title2.weight(.bold))
                .foregroundStyle(SwiftAppTheme.text)
                .multilineTextAlignment(.center)
            Text(spec.body)
                .font(.body)
                .foregroundStyle(SwiftAppTheme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
        }
        .padding(.horizontal, SwiftAppTheme.pagePadding + 4)
    }

    private func advance() {
        guard pageIndex < specs.count - 1 else { return }
        let next = pageIndex + 1
        if reduceMotion {
            pageIndex = next
        } else {
            withAnimation(.easeInOut(duration: 0.25)) {
                pageIndex = next
            }
        }
    }

    private func finishTour() {
        tourCompleted = true
    }
}
