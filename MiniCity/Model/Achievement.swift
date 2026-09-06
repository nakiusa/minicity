import Foundation

/// 集めていく実績ひとつ。
///
/// 達成の判定は `Simulation` の値を見るだけで済ませてある。
/// 途中経過を別に持たないので、都市を読み直しても判定が狂わない。
struct Achievement: Identifiable {
    /// 保存に使う名前。あとで Game Center の実績IDに対応させるので、変えない。
    let id: String
    let title: String
    /// 何をすれば取れるか。まだ取っていないときも見せる。
    let detail: String
    let symbol: String
    /// 達成しているか。1か月ごとに呼ばれる。
    let isMet: (Simulation) -> Bool

    var isEarned: Bool { AchievementStore.shared.isEarned(id) }
}

enum Achievements {

    /// 育った区画のうち、いちばん高い段。
    private static func topLevel(_ sim: Simulation) -> Int {
        var top = 0
        for z in sim.map.zones where z.alive && z.kind.grows { top = max(top, Int(z.level)) }
        return top
    }

    private static func count(_ sim: Simulation, atLeast level: Int) -> Int {
        sim.map.zones.filter { $0.alive && $0.kind.grows && Int($0.level) >= level }.count
    }

    /// 並び順がそのまま一覧の並びになる。やさしいものから先に置く。
    static let all: [Achievement] = [
        Achievement(id: "pop.100", title: "はじめの一歩", detail: "人口 100 人",
                    symbol: "figure.walk") { $0.residents >= 100 },

        Achievement(id: "pop.1000", title: "町になった", detail: "人口 1,000 人",
                    symbol: "house.fill") { $0.residents >= 1_000 },

        Achievement(id: "pop.5000", title: "市になった", detail: "人口 5,000 人",
                    symbol: "building.2.fill") { $0.residents >= 5_000 },

        Achievement(id: "pop.10000", title: "大都市", detail: "人口 10,000 人",
                    symbol: "building.columns.fill") { $0.residents >= 10_000 },

        Achievement(id: "pop.20000", title: "首府", detail: "人口 20,000 人",
                    symbol: "crown.fill") { $0.residents >= 20_000 },

        Achievement(id: "funds.100k", title: "蓄え", detail: "資金 ¥100,000",
                    symbol: "yensign.circle.fill") { $0.funds >= 100_000 },

        Achievement(id: "tower.first", title: "高層のはじまり", detail: "区画を L6 まで育てる",
                    symbol: "building") { topLevel($0) >= 6 },

        Achievement(id: "tower.max", title: "摩天楼", detail: "区画を最上段の L10 まで育てる",
                    symbol: "sparkles") { topLevel($0) >= Zone.maxLevel },

        Achievement(id: "skyline", title: "スカイライン", detail: "L8 以上の区画を 5 つ",
                    symbol: "chart.bar.fill") { count($0, atLeast: 8) >= 5 },

        Achievement(id: "avenue.50", title: "表通り", detail: "大通りを 50 マス敷く",
                    symbol: "road.lanes.curved.right") { $0.avenueCount >= 50 },

        // ここから先は、数を伸ばすだけでは取れない。街の作りが問われる。
        Achievement(id: "clean.air", title: "澄んだ空", detail: "最大公害 100 未満のまま人口 3,000 人",
                    symbol: "wind") { $0.residents >= 3_000 && $0.pollution.maximum < 100 },

        Achievement(id: "safe.city", title: "安全な街", detail: "最大犯罪 50 未満のまま人口 3,000 人",
                    symbol: "shield.lefthalf.filled") { $0.residents >= 3_000 && $0.crime.maximum < 50 },

        Achievement(id: "no.blackout", title: "灯を絶やさない", detail: "停電ゼロのまま人口 5,000 人",
                    symbol: "bolt.fill") { $0.residents >= 5_000 && $0.unpoweredZones == 0 },

        Achievement(id: "balanced", title: "黒字経営", detail: "人口 5,000 人を黒字で保つ",
                    symbol: "chart.line.uptrend.xyaxis") {
            $0.residents >= 5_000 && $0.projectedIncome > $0.projectedExpenses
        },
    ]
}

/// 取った実績を覚えておく。
///
/// 都市を作り直しても消えない。集めたものは遊んだ記録として残る。
final class AchievementStore {
    static let shared = AchievementStore()

    private let key = "earnedAchievements"
    private var earned: Set<String>

    private init() {
        earned = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    func isEarned(_ id: String) -> Bool { earned.contains(id) }

    var earnedCount: Int { earned.count }

    /// まだ取っていないもののうち、条件を満たしたものを記録して返す。
    func claimNewlyEarned(in sim: Simulation) -> [Achievement] {
        var newly: [Achievement] = []
        for a in Achievements.all where !earned.contains(a.id) && a.isMet(sim) {
            earned.insert(a.id)
            newly.append(a)
        }
        if !newly.isEmpty {
            UserDefaults.standard.set(Array(earned), forKey: key)
        }
        return newly
    }
}
