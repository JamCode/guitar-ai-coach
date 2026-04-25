import SwiftUI
import Core

/// 扒歌买断解锁购页（`sheet` 呈现）。
struct PurchaseView: View {
    @EnvironmentObject private var purchase: PurchaseManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("解锁扒歌功能")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(SwiftAppTheme.text)
                        Text("一次购买，永久使用")
                            .font(.subheadline)
                            .foregroundStyle(SwiftAppTheme.muted)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        featureLine("从音频识别和弦", icon: "waveform.badge.magnifyingglass")
                        featureLine("支持常见视频格式", icon: "film")
                        featureLine("本地处理，保护隐私", icon: "lock.shield")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(SwiftAppTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: SwiftAppTheme.cardRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: SwiftAppTheme.cardRadius, style: .continuous)
                            .stroke(SwiftAppTheme.line, lineWidth: 1)
                    )
                    if let err = purchase.lastErrorMessage, !err.isEmpty {
                        Text(err)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(spacing: 12) {
                        Button {
                            Task { await purchase.purchase() }
                        } label: {
                            if purchase.isPurchaseInFlight {
                                HStack {
                                    ProgressView()
                                    Text("处理中…")
                                }
                            } else {
                                Text("购买（\(primaryPriceText)）")
                            }
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .appPrimaryButton()
                        .disabled(purchase.isPurchaseInFlight)

                        Button("恢复购买") {
                            Task { await purchase.restore() }
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .appSecondaryButton()
                        .disabled(purchase.isPurchaseInFlight)
                    }
                }
                .padding(SwiftAppTheme.pagePadding)
            }
            .background(SwiftAppTheme.bg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .tint(SwiftAppTheme.brand)
        .task { await purchase.loadProduct() }
        .onChange(of: purchase.isUnlocked) { _, v in
            if v { dismiss() }
        }
    }

    private var primaryPriceText: String {
        if let p = purchase.product { return p.displayPrice }
        return "—"
    }

    private func featureLine(_ text: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(SwiftAppTheme.brand)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(SwiftAppTheme.text)
        }
    }
}
