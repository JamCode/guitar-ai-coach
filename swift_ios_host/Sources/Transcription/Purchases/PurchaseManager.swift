import Foundation
import StoreKit

/// 扒歌功能（非消耗型内购）授权状态，使用 StoreKit 2。
@MainActor
final class PurchaseManager: ObservableObject {
    static let shared = PurchaseManager()
    static let transcriptionProductId = "com.wanghan.guitarhelper.transcription_unlock"

    private static let userDefaultsUnlockedKey = "com.wanghan.guitarhelper.transcription_unlocked"

    @Published private(set) var isUnlocked: Bool
    @Published private(set) var product: Product?
    @Published private(set) var isPurchaseInFlight = false
    /// 首次 `loadProduct()` 是否已结束（成功或失败），用于购买按钮可用性。
    @Published private(set) var productFetchCompleted = false
    @Published private(set) var isFetchingProduct = false
    @Published var lastErrorMessage: String?

    private var updatesTask: Task<Void, Never>?

    private init() {
        isUnlocked = UserDefaults.standard.bool(forKey: Self.userDefaultsUnlockedKey)
        updatesTask = Task { [weak self] in
            await self?.listenForTransactions()
        }
        Task { await refreshUnlockedState() }
    }

    deinit {
        updatesTask?.cancel()
    }

    func loadProduct() async {
        let requestedProductIDs = [Self.transcriptionProductId]
        print("[StoreKit] loadProduct request productIDs=\(requestedProductIDs)")
        isFetchingProduct = true
        defer {
            isFetchingProduct = false
            productFetchCompleted = true
        }
        do {
            let list = try await Product.products(for: requestedProductIDs)
            print("[StoreKit] loadProduct response count=\(list.count)")
            for item in list {
                print("[StoreKit] product id=\(item.id), price=\(item.displayPrice)")
            }
            product = list.first
            lastErrorMessage = nil
        } catch {
            product = nil
            print("[StoreKit] loadProduct error=\(error.localizedDescription)")
            lastErrorMessage = error.localizedDescription
        }
    }

    private func hasActiveTranscriptionEntitlement(verification: VerificationResult<Transaction>) -> Bool {
        if case .verified(let transaction) = verification {
            guard transaction.productID == Self.transcriptionProductId else { return false }
            return transaction.revocationDate == nil
        }
        return false
    }

    /// 以 `Transaction.currentEntitlements` 为权威，并回写 `UserDefaults` 加速冷启动读显示。
    func refreshUnlockedState() async {
        var found = false
        for await result in Transaction.currentEntitlements {
            if hasActiveTranscriptionEntitlement(verification: result) {
                found = true
                break
            }
        }
        setUnlocked(found, persist: true)
    }

    private func setUnlocked(_ value: Bool, persist: Bool) {
        isUnlocked = value
        if persist {
            UserDefaults.standard.set(value, forKey: Self.userDefaultsUnlockedKey)
        }
    }

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            guard hasActiveTranscriptionEntitlement(verification: result) else { continue }
            if case .verified(let transaction) = result {
                if transaction.revocationDate == nil {
                    setUnlocked(true, persist: true)
                } else {
                    await refreshUnlockedState()
                }
                await transaction.finish()
            }
        }
    }

    func purchase() async {
        isPurchaseInFlight = true
        lastErrorMessage = nil
        defer { isPurchaseInFlight = false }
        if product == nil { await loadProduct() }
        guard let product else {
            lastErrorMessage = "无法加载内购产品，请检查网络后重试。"
            return
        }
        print("[StoreKit] purchase start productID=\(product.id), price=\(product.displayPrice)")
        do {
            let res = try await product.purchase()
            switch res {
            case .success(let verification):
                if case .verified(let transaction) = verification, transaction.productID == Self.transcriptionProductId {
                    if transaction.revocationDate == nil {
                        setUnlocked(true, persist: true)
                    }
                    await transaction.finish()
                } else {
                    lastErrorMessage = "交易验证失败，请重试或联系支持。"
                }
            case .userCancelled:
                print("[StoreKit] purchase userCancelled")
                lastErrorMessage = nil
                break
            case .pending:
                print("[StoreKit] purchase pending")
                lastErrorMessage = "交易处理中，可稍后在系统设置中查看或点击「恢复购买」。"
            @unknown default:
                break
            }
        } catch {
            print("[StoreKit] purchase error=\(error.localizedDescription)")
            if (error as? SKError)?.code == .paymentCancelled {
                lastErrorMessage = nil
            } else {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    func restore() async {
        isPurchaseInFlight = true
        lastErrorMessage = nil
        defer { isPurchaseInFlight = false }
        do {
            try await AppStore.sync()
            await refreshUnlockedState()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

}
