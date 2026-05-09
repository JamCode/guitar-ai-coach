import SwiftUI
import Core

public struct ProfileHomeView: View {
    @State private var versionText = "--"

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                VStack(spacing: 0) {
                    navRow(icon: "questionmark.circle", title: AppL10n.t("support_feedback_title"), subtitle: nil) {
                        HelpFeedbackView()
                    }
                    Divider().padding(.leading, 52)
                    navRow(icon: "info.circle", title: AppL10n.t("about_version_title"), subtitle: versionText) {
                        AppVersionView()
                    }
                }
                .appCard()
            }
            .padding(SwiftAppTheme.pagePadding)
        }
        .navigationTitle(Text(LocalizedStringResource("profile_nav_title", bundle: .main)))
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
                    navRow(icon: "ladybug", title: AppL10n.t("help_diag_title"), subtitle: AppL10n.t("help_diag_subtitle")) {
                        DiagnosticLogsView()
                    }
                    Divider().padding(.leading, 52)
                    staticRow(title: AppL10n.t("help_faq_title"), subtitle: AppL10n.t("help_faq_subtitle"))
                    Divider().padding(.leading, 52)
                    staticRow(title: AppL10n.t("help_bug_title"), subtitle: AppL10n.t("help_bug_subtitle"))
                    Divider().padding(.leading, 52)
                    staticRow(title: AppL10n.t("help_suggest_title"), subtitle: AppL10n.t("help_suggest_subtitle"))
                    Divider().padding(.leading, 52)
                    staticRow(title: AppL10n.t("help_about_row_title"), subtitle: AppL10n.t("help_about_row_subtitle"))
                }
                .appCard()
            }
            .padding(SwiftAppTheme.pagePadding)
        }
        .navigationTitle(Text(LocalizedStringResource("support_feedback_title", bundle: .main)))
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
                    kvRow(AppL10n.t("about_kv_version"), info.displayVersion)
                    Divider().padding(.leading, 14)
                    kvRow(AppL10n.t("about_kv_channel"), info.releaseChannel)
                    Divider().padding(.leading, 14)
                    kvRow(AppL10n.t("about_kv_platform"), info.platformLabel)
                }
                .appCard()

                Button {
                    AppVersionInfoLoader.copySummary(info)
                    copied = true
                } label: {
                    HStack {
                        Image(systemName: "doc.on.doc")
                        Text(LocalizedStringResource("about_copy_version", bundle: .main))
                    }
                }
                .appPrimaryButton()
            }
            .padding(SwiftAppTheme.pagePadding)
        }
        .navigationTitle(Text(LocalizedStringResource("about_version_title", bundle: .main)))
        .appPageBackground()
        .alert(Text(LocalizedStringResource("about_copied_alert", bundle: .main)), isPresented: $copied) {
            Button(AppL10n.t("button_ok"), role: .cancel) {}
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
                infoRow(AppL10n.t("privacy_mode_title"), AppL10n.t("privacy_mode_subtitle"))
                infoRow(AppL10n.t("privacy_storage_title"), AppL10n.t("privacy_storage_subtitle"))
                infoRow(AppL10n.t("privacy_sync_title"), AppL10n.t("privacy_sync_subtitle"))
            }
            .padding(SwiftAppTheme.pagePadding)
        }
        .navigationTitle(Text(LocalizedStringResource("privacy_local_nav_title", bundle: .main)))
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
    @State private var pathText: String = AppL10n.t("diag_path_unavailable")
    @State private var bytes: Int = 0
    @State private var showClearConfirm = false
    @State private var toastText: String?

    public init() {}

    public var body: some View {
        ScrollView {
            if loading {
                ProgressView {
                    Text(LocalizedStringResource("diag_loading", bundle: .main))
                }
                    .tint(SwiftAppTheme.brand)
                    .padding(.top, 24)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(LocalizedStringResource("diag_notes_title", bundle: .main)).appSectionTitle()
                        Text(LocalizedStringResource("diag_notes_body", bundle: .main))
                            .foregroundStyle(SwiftAppTheme.muted)
                    }
                    .appCard()

                    VStack(alignment: .leading, spacing: 8) {
                        Text(LocalizedStringResource("diag_file_title", bundle: .main)).appSectionTitle()
                        Text(pathText)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                            .foregroundStyle(SwiftAppTheme.text)
                        Text(String(format: AppL10n.t("diag_size_kb_format"), (Double(bytes) / 1024.0).formatted(.number.precision(.fractionLength(1)))))
                            .font(.caption)
                            .foregroundStyle(SwiftAppTheme.muted)
                    }
                    .appCard()

                    VStack(spacing: 8) {
                        ShareLink(item: URL(fileURLWithPath: pathText), preview: SharePreview(AppL10n.t("diag_share_preview"))) {
                            Label {
                                Text(LocalizedStringResource("diag_share_button", bundle: .main))
                            } icon: {
                                Image(systemName: "square.and.arrow.up")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .appPrimaryButton()
                        .disabled(!pathText.hasPrefix("/"))

                        Button {
#if canImport(UIKit)
                            UIPasteboard.general.string = pathText
#endif
                            toastText = AppL10n.t("diag_toast_path_copied")
                        } label: {
                            Label {
                                Text(LocalizedStringResource("diag_copy_path", bundle: .main))
                            } icon: {
                                Image(systemName: "doc.on.doc")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .appSecondaryButton()

                        Button {
                            showClearConfirm = true
                        } label: {
                            Label {
                                Text(LocalizedStringResource("diag_clear_logs", bundle: .main))
                            } icon: {
                                Image(systemName: "trash")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .appSecondaryButton()
                    }
                }
                .padding(SwiftAppTheme.pagePadding)
            }
        }
        .navigationTitle(Text(LocalizedStringResource("diag_nav_title", bundle: .main)))
        .appPageBackground()
        .task { await reload() }
        .alert(Text(LocalizedStringResource("diag_clear_confirm_title", bundle: .main)), isPresented: $showClearConfirm) {
            Button(AppL10n.t("button_cancel"), role: .cancel) {}
            Button(AppL10n.t("diag_clear_action"), role: .destructive) {
                Task {
                    await DiagnosticLogStore.shared.clear()
                    await reload()
                    toastText = AppL10n.t("diag_toast_cleared")
                }
            }
        } message: {
            Text(LocalizedStringResource("diag_clear_message", bundle: .main))
        }
        .alert(toastText ?? "", isPresented: Binding(
            get: { toastText != nil },
            set: { if !$0 { toastText = nil } }
        )) {
            Button(AppL10n.t("button_ok"), role: .cancel) {}
        }
    }

    @MainActor
    private func reload() async {
        loading = true
        await DiagnosticLogStore.shared.ensureInitialized()
        let url = await DiagnosticLogStore.shared.fileURL()
        let n = await DiagnosticLogStore.shared.byteLength()
        pathText = url?.path ?? AppL10n.t("diag_path_unavailable")
        bytes = n
        loading = false
    }
}
