import SwiftUI
import Core

/// 扒歌买断解锁购买页（`sheet` 呈现）。文案与按钮格式面向 App Store 审核与截图。
struct PurchaseView: View {
    @EnvironmentObject private var purchase: PurchaseManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(AppL10n.t("purchase_sheet_title"))
                            .font(.title2.weight(.bold))
                            .foregroundStyle(SwiftAppTheme.text)
                        Text(AppL10n.t("purchase_sheet_subtitle"))
                            .font(.subheadline)
                            .foregroundStyle(SwiftAppTheme.muted)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        featureLine(AppL10n.t("purchase_sheet_feature_1"), icon: "waveform.badge.magnifyingglass")
                        featureLine(AppL10n.t("purchase_sheet_feature_2"), icon: "film")
                        featureLine(AppL10n.t("purchase_sheet_feature_3"), icon: "lock.shield")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(SwiftAppTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: SwiftAppTheme.cardRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: SwiftAppTheme.cardRadius, style: .continuous)
                            .stroke(SwiftAppTheme.line, lineWidth: 1)
                    )
                    if purchase.productFetchCompleted, purchase.product == nil, purchase.lastErrorMessage == nil {
                        Text(AppL10n.t("purchase_sheet_product_unavailable"))
                            .font(.footnote)
                            .foregroundStyle(SwiftAppTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let err = purchase.lastErrorMessage, !err.isEmpty {
                        Text(err)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(spacing: 14) {
                        Button {
                            Task { await purchase.purchase() }
                        } label: {
                            HStack(spacing: 10) {
                                if purchase.isFetchingProduct || purchase.isPurchaseInFlight {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Text(primaryButtonTitle)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .font(.headline)
                        .appPrimaryButton()
                        .disabled(isPrimaryPurchaseDisabled)

                        Button {
                            Task { await purchase.restore() }
                        } label: {
                            Text(AppL10n.t("purchase_sheet_restore"))
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(SwiftAppTheme.muted)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .disabled(purchase.isPurchaseInFlight)
                    }
                }
                .padding(SwiftAppTheme.pagePadding)
            }
            .background(SwiftAppTheme.bg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(AppL10n.t("purchase_sheet_close")) { dismiss() }
                }
            }
        }
        .tint(SwiftAppTheme.brand)
        .task { await purchase.loadProduct() }
        .onChange(of: purchase.isUnlocked) { _, unlocked in
            if unlocked { dismiss() }
        }
    }

    /// 主按钮文案：有 `Product.displayPrice` 时为「购买 $x.xx」/「Buy $x.xx」；加载中或处理中显示状态；否则为无价格短文案（不出现占位符「一」或「—」）。
    private var primaryButtonTitle: String {
        if purchase.isFetchingProduct {
            return AppL10n.t("purchase_sheet_loading")
        }
        if purchase.isPurchaseInFlight {
            return AppL10n.t("purchase_sheet_processing")
        }
        if let product = purchase.product {
            return String(format: AppL10n.t("purchase_sheet_primary_with_price"), product.displayPrice)
        }
        return AppL10n.t("purchase_sheet_primary_no_price")
    }

    /// 未拿到 `Product` 且已完成拉取、或正在拉取/购买中时禁用购买，避免无效点击。
    private var isPrimaryPurchaseDisabled: Bool {
        if purchase.isFetchingProduct || purchase.isPurchaseInFlight { return true }
        if purchase.productFetchCompleted, purchase.product == nil { return true }
        return false
    }

    private func featureLine(_ text: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(SwiftAppTheme.brand)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(SwiftAppTheme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
