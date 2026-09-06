import GameKit

/// Game Center への橋渡し。
///
/// 実績の正はあくまで端末に持っている記録（`AchievementStore`）で、
/// ここはその写しを送るだけにしてある。サインインしていなくても、
/// 通信できなくても、集めた実績は端末の中で完結する。
enum GameCenter {

    private(set) static var isAuthenticated = false

    /// サインインを求める。断られても、そのまま遊べる。
    static func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { viewController, error in
            if let viewController {
                present(viewController)
                return
            }
            isAuthenticated = GKLocalPlayer.local.isAuthenticated
            if let error {
                // 圏外やサインイン拒否はここに来る。遊びは止めない。
                print("Game Center のサインインに失敗: \(error.localizedDescription)")
                return
            }
            guard isAuthenticated else { return }
            // サインインする前に取っていたぶんを、まとめて送る。
            report(AchievementStore.shared.allEarnedIDs)
        }
    }

    /// 取った実績を Game Center に送る。達成済みとして 100% で報告する。
    static func report(_ ids: [String]) {
        guard isAuthenticated, !ids.isEmpty else { return }
        let achievements = ids.map { id -> GKAchievement in
            let a = GKAchievement(identifier: id)
            a.percentComplete = 100
            a.showsCompletionBanner = true
            return a
        }
        GKAchievement.report(achievements) { error in
            if let error {
                // App Store Connect 側に同じIDの実績がないとここに来る。
                print("実績の送信に失敗: \(error.localizedDescription)")
            }
        }
    }

    /// 実績の一覧を Game Center の画面で開く。
    static func showDashboard() {
        guard isAuthenticated else { return }
        let vc = GKGameCenterViewController(state: .achievements)
        vc.gameCenterDelegate = Delegate.shared
        present(vc)
    }

    private static func present(_ viewController: UIViewController) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
            let root = scene.keyWindow?.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        top.present(viewController, animated: true)
    }

    private final class Delegate: NSObject, GKGameCenterControllerDelegate {
        static let shared = Delegate()
        func gameCenterViewControllerDidFinish(_ vc: GKGameCenterViewController) {
            vc.dismiss(animated: true)
        }
    }
}
