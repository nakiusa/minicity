import Foundation
import StoreKit

/// 買い切りの「広告を消す」を扱う。
///
/// 権利の正は App Store 側にあるが、圏外でも広告が戻らないように、
/// 一度買えたことは端末にも控えておく。
@MainActor
final class Store: ObservableObject {

    /// App Store Connect で作る商品の ID。買い切り（非消耗型）。
    static let removeAdsID = "com.shuyafukai.minicity.removeads"

    @Published private(set) var removeAds: Product?
    @Published private(set) var hasRemovedAds: Bool
    @Published private(set) var isWorking = false
    /// 買えなかったときに一度だけ出す言葉。
    @Published var failure: String?

    private let cacheKey = "hasRemovedAds"
    private var updates: Task<Void, Never>?

    init() {
        hasRemovedAds = UserDefaults.standard.bool(forKey: cacheKey)
        // 別の端末で買った、あとから返金された、といった変化はここに届く。
        updates = Task { [weak self] in
            for await update in Transaction.updates {
                guard case .verified(let transaction) = update else { continue }
                await transaction.finish()
                await self?.refresh()
            }
        }
        Task {
            await refresh()
            await loadProduct()
        }
    }

    deinit { updates?.cancel() }

    func loadProduct() async {
        removeAds = try? await Product.products(for: [Self.removeAdsID]).first
    }

    /// いま権利を持っているかを見直す。
    func refresh() async {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == Self.removeAdsID && transaction.revocationDate == nil {
                setRemoved(true)
                return
            }
        }
        // 権利が見つからないときは、控えを消さない。
        // 起動直後や圏外では currentEntitlements が空で返ることがある。
        if !hasRemovedAds { setRemoved(false) }
    }

    func buy() async {
        guard let product = removeAds, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    setRemoved(true)
                }
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            failure = "購入できませんでした（\(error.localizedDescription)）"
        }
    }

    /// 機種変更や入れ直しのあとに、買ったものを取り戻す。
    func restore() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        try? await AppStore.sync()
        await refresh()
        if !hasRemovedAds { failure = "購入の記録が見つかりませんでした" }
    }

    private func setRemoved(_ value: Bool) {
        hasRemovedAds = value
        UserDefaults.standard.set(value, forKey: cacheKey)
    }
}
