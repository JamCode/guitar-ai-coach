import SwiftUI
import Core

public struct ProfileHomeView: View {
    @State private var versionText = "--"

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                VStack(spacing: 0) {
                    navRow(icon: "questionmark.circle", title: "帮助与反馈", subtitle: nil) {
                        HelpFeedbackView()
                    }
                    Divider().padding(.leading, 52)
                    navRow(icon: "info.circle", title: "关于与版本", subtitle: versionText) {
                        AppVersionView()
                    }
                }
                .appCard()
            }
            .padding(SwiftAppTheme.pagePadding)
        }
        .navigationTitle("我的")
        .appPageBackground()
        .task {
            versionText = AppVersionInfoLoader.load().displayVersion
        }
    }

    private func navRow<Destination: View>(
        icon: String,
        title: String,
        subtitle: String?,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink(destination: TabBarHiddenContainer { destination() }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .frame(width: 24)
                    .foregroundStyle(SwiftAppTheme.brand)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline).foregroundStyle(SwiftAppTheme.text)
                    if let subtitle {
                        Text(subtitle).font(.subheadline).foregroundStyle(SwiftAppTheme.muted)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(SwiftAppTheme.muted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}

public struct HelpFeedbackView: View {
    public init() {}

    public var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                VStack(spacing: 0) {
                    navRow(icon: "ladybug", title: "诊断日志", subtitle: "闪退排查：查看本机记录的异常") {
                        DiagnosticLogsView()
                    }
                    Divider().padding(.leading, 52)
                    staticRow(title: "常见问题", subtitle: "调音器、练习记录、我的谱相关问题")
                    Divider().padding(.leading, 52)
                    staticRow(title: "问题反馈", subtitle: "描述你的问题与复现步骤")
                    Divider().padding(.leading, 52)
                    staticRow(title: "功能建议", subtitle: "告诉我们你希望新增的功能")
                    Divider().padding(.leading, 52)
                    staticRow(title: "关于我们", subtitle: "版本信息与开源说明")
                }
                .appCard()
            }
            .padding(SwiftAppTheme.pagePadding)
        }
        .navigationTitle("帮助与反馈")
        .appPageBackground()
    }

    private func navRow<Destination: View>(
        icon: String,
        title: String,
        subtitle: String,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink(destination: TabBarHiddenContainer { destination() }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .frame(width: 24)
                    .foregroundStyle(SwiftAppTheme.brand)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline).foregroundStyle(SwiftAppTheme.text)
                    Text(subtitle).font(.subheadline).foregroundStyle(SwiftAppTheme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(SwiftAppTheme.muted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    private func staticRow(title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Color.clear.frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(SwiftAppTheme.text)
                Text(subtitle).font(.subheadline).foregroundStyle(SwiftAppTheme.muted)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(SwiftAppTheme.muted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

public struct AppVersionView: View {
    @State private var info = AppVersionInfoLoader.load()
    @State private var copied = false

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                VStack(spacing: 0) {
                    kvRow("应用版本", info.displayVersion)
                    Divider().padding(.leading, 14)
                    kvRow("发布渠道", info.releaseChannel)
                    Divider().padding(.leading, 14)
                    kvRow("系统平台", info.platformLabel)
                }
                .appCard()

                Button {
                    AppVersionInfoLoader.copySummary(info)
                    copied = true
                } label: {
                    HStack {
                        Image(systemName: "doc.on.doc")
                        Text("复制版本信息")
                    }
                }
                .appPrimaryButton()
            }
            .padding(SwiftAppTheme.pagePadding)
        }
        .navigationTitle("关于与版本")
        .appPageBackground()
        .alert("版本信息已复制", isPresented: $copied) {
            Button("确定", role: .cancel) {}
        }
    }

    private func kvRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(SwiftAppTheme.text)
            Spacer()
            Text(value).foregroundStyle(SwiftAppTheme.muted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

public struct AccountSecurityView: View {
    public init() {}

    public var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                infoRow("当前模式", "离线模式（无需登录，无网络依赖）")
                infoRow("数据存储位置", "练习记录和曲谱仅保存在本机应用沙箱内")
                infoRow("云同步", "当前版本未启用云端同步与账号恢复")
            }
            .padding(SwiftAppTheme.pagePadding)
        }
        .navigationTitle("隐私与本地数据")
        .appPageBackground()
    }

    private func infoRow(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline).foregroundStyle(SwiftAppTheme.text)
            Text(subtitle).font(.subheadline).foregroundStyle(SwiftAppTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }
}

public struct DiagnosticLogsView: View {
    @State private var loading = true
    @State private var pathText = "（未初始化或当前平台不支持）"
    @State private var bytes: Int = 0
    @State private var showClearConfirm = false
    @State private var toastText: String?

    public init() {}

    public var body: some View {
        ScrollView {
            if loading {
                ProgressView("加载中…")
                    .tint(SwiftAppTheme.brand)
                    .padding(.top, 24)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("说明").appSectionTitle()
                        Text("Dart/Swift 层未捕获异常会追加写入下方路径。原生崩溃需查看 Xcode 设备日志。")
                            .foregroundStyle(SwiftAppTheme.muted)
                    }
                    .appCard()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("日志文件").appSectionTitle()
                        Text(pathText)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                            .foregroundStyle(SwiftAppTheme.text)
                        Text("约 \((Double(bytes) / 1024.0).formatted(.number.precision(.fractionLength(1)))) KB")
                            .font(.caption)
                            .foregroundStyle(SwiftAppTheme.muted)
                    }
                    .appCard()

                    VStack(spacing: 8) {
                        ShareLink(item: URL(fileURLWithPath: pathText), preview: SharePreview("AI吉他 诊断日志")) {
                            Label("分享日志文件", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .appPrimaryButton()
                        .disabled(!pathText.hasPrefix("/"))

                        Button {
#if canImport(UIKit)
                            UIPasteboard.general.string = pathText
#endif
                            toastText = "路径已复制"
                        } label: {
                            Label("复制路径", systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .appSecondaryButton()

                        Button {
                            showClearConfirm = true
                        } label: {
                            Label("清空日志", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .appSecondaryButton()
                    }
                }
                .padding(SwiftAppTheme.pagePadding)
            }
        }
        .navigationTitle("诊断日志")
        .appPageBackground()
        .task { await reload() }
        .alert("清空诊断日志？", isPresented: $showClearConfirm) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                Task {
                    await DiagnosticLogStore.shared.clear()
                    await reload()
                    toastText = "已清空"
                }
            }
        } message: {
            Text("将删除本机已记录的错误文本（不可恢复）。")
        }
        .alert(toastText ?? "", isPresented: Binding(
            get: { toastText != nil },
            set: { if !$0 { toastText = nil } }
        )) {
            Button("确定", role: .cancel) {}
        }
    }

    @MainActor
    private func reload() async {
        loading = true
        await DiagnosticLogStore.shared.ensureInitialized()
        let url = await DiagnosticLogStore.shared.fileURL()
        let n = await DiagnosticLogStore.shared.byteLength()
        pathText = url?.path ?? "（未初始化或当前平台不支持）"
        bytes = n
        loading = false
    }
}
