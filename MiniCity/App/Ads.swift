import AppTrackingTransparency
import GoogleMobileAds
import SwiftUI

/// 広告の出し入れ。買い切りの「広告を消す」を持っていれば、何も出さない。
@MainActor
final class Ads: ObservableObject {

    static let shared = Ads()

    private init() {}

    // いまは Google のテスト用 ID。AdMob で本物を作ったら差し替える。
    // 本物の ID を入れる前にテストで踏むと、AdMob の規約違反になる。
    static let bannerUnit = "ca-app-pub-3940256099942544/2934735716"
    static let interstitialUnit = "ca-app-pub-3940256099942544/4411468910"

    /// SDK が動き出したか。バナーはこれが立ってから出す。
    @Published private(set) var isReady = false

    private var interstitial: InterstitialAd?
    private var lastFullScreen = Date.distantPast
    /// 全画面広告の最短の間。区切りが続けて来ても、続けては出さない。
    private let cooldown: TimeInterval = 90

    func start() async {
        // 追跡の許可を先に尋ねる。断られても広告は出る。内容が興味に合わなくなるだけ。
        if ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
            _ = await ATTrackingManager.requestTrackingAuthorization()
        }
        _ = await MobileAds.shared.start()
        isReady = true
        await loadInterstitial()
    }

    private func loadInterstitial() async {
        interstitial = try? await InterstitialAd.load(with: Self.interstitialUnit, request: Request())
    }

    /// 区切りの場面で全画面広告を出す。出せなければ、黙って何もしない。
    func showFullScreen() {
        guard let ad = interstitial,
              Date().timeIntervalSince(lastFullScreen) > cooldown else { return }
        lastFullScreen = Date()
        interstitial = nil
        Task {
            // 成績表などを閉じた直後に呼ばれる。閉じ終わる前に出そうとすると弾かれるので、
            // ひと呼吸おいてから出す。
            try? await Task.sleep(for: .milliseconds(600))
            if let root = Self.topViewController() {
                ad.present(from: root)
            }
            await loadInterstitial()
        }
    }

    static func topViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let root = scene.keyWindow?.rootViewController else { return nil }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        return top
    }
}

/// メニューの下に敷くバナー。
///
/// 街の画面には出さない。遊んでいるあいだずっと見える帯に、こちらで色も形も
/// 決められないものを置くと、画面の作りがそこだけ崩れる。買い切りを持っていれば、
/// メニューでも出さない。
struct AdBanner: View {
    @ObservedObject private var store = Store.shared
    @ObservedObject private var ads = Ads.shared

    var body: some View {
        if !store.hasRemovedAds && ads.isReady {
            // 幅いっぱいの大きな広告も選べるが、メニューの半分が白い箱になる。
            // 出す場所がメニューなので、320x50 の小さいほうで通す。
            BannerAdView()
                .frame(width: AdSizeBanner.size.width, height: AdSizeBanner.size.height)
                .frame(maxWidth: .infinity)
                // 下地を敷かないと、後ろの一覧が広告の脇から透けて宙に浮いて見える。
                .background(.bar)
        }
    }
}

/// 320x50 のバナーひとつ。
struct BannerAdView: UIViewRepresentable {

    func makeUIView(context: Context) -> BannerView {
        let view = BannerView(adSize: AdSizeBanner)
        view.adUnitID = Ads.bannerUnit
        view.rootViewController = Ads.topViewController()
        view.load(Request())
        return view
    }

    func updateUIView(_ view: BannerView, context: Context) {
        if view.rootViewController == nil { view.rootViewController = Ads.topViewController() }
    }
}
