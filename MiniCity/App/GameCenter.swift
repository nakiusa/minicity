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

    /// 期限が来た街の人口をランキングに送る。過去の最高だけが残る。
    static func submit(population: Int, term: Int) {
        guard isAuthenticated, Leaderboards.isRanked(term: term) else { return }
        GKLeaderboard.submitScore(population, context: 0, player: GKLocalPlayer.local,
                                  leaderboardIDs: [Leaderboards.id(term: term)]) { error in
            if let error { print("ランキングの送信に失敗: \(error.localizedDescription)") }
        }
    }

    /// 自分の順位を引く。サインインしていない、圏外、まだ順位がついていないときは nil。
    static func rank(term: Int) async -> Int? {
        guard isAuthenticated, Leaderboards.isRanked(term: term) else { return nil }
        guard let board = try? await GKLeaderboard.loadLeaderboards(IDs: [Leaderboards.id(term: term)]).first,
              let entries = try? await board.loadEntries(for: .global, timeScope: .allTime,
                                                         range: NSRange(location: 1, length: 1)),
              let mine = entries.0 else { return nil }
        return mine.rank
    }

    /// ランキングを Game Center の画面で開く。
    static func showLeaderboard(term: Int) {
        guard isAuthenticated else { return }
        let vc = GKGameCenterViewController(leaderboardID: Leaderboards.id(term: term),
                                            playerScope: .global, timeScope: .allTime)
        vc.gameCenterDelegate = Delegate.shared
        present(vc)
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
