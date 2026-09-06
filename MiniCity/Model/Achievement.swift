import Foundation

/// 実績の分類。一覧をこの順に並べる。
enum AchievementGroup: String, CaseIterable {
    case population = "人口"
    case growth = "発展"
    case planning = "街づくり"
    case economy = "経営"
    case time = "時代"
}

/// 都市をひと目で測った値。
///
/// 実績が増えるほど、条件ごとにタイルや区画を数え直すのが無駄になる。
/// 1か月に一度だけまとめて数え、条件はこの値を見るだけにする。
struct CityStats {
    let sim: Simulation
    let parkTiles: Int
    let forestTiles: Int
    /// 育った区画の最高の段。
    let topLevel: Int
    /// 段ごとの区画数。添字がそのまま段。
    let levelCounts: [Int]

    init(_ sim: Simulation) {
        self.sim = sim
        var parks = 0, forests = 0
        for t in sim.map.tiles {
            if t.structure == .park { parks += 1 }
            if t.terrain == .forest { forests += 1 }
        }
        parkTiles = parks
        forestTiles = forests

        var counts = [Int](repeating: 0, count: Zone.maxLevel + 1)
        var top = 0
        for z in sim.map.zones where z.alive && z.kind.grows {
            counts[Int(z.level)] += 1
            top = max(top, Int(z.level))
        }
        levelCounts = counts
        topLevel = top
    }

    /// その段以上の区画の数。
    func zones(atLeast level: Int) -> Int {
        guard level <= Zone.maxLevel else { return 0 }
        return levelCounts[level...].reduce(0, +)
    }

    func count(of kind: ZoneKind) -> Int { sim.zoneCounts[kind] ?? 0 }
}

/// 集めていく実績ひとつ。
struct Achievement: Identifiable {
    /// 保存に使う名前。Game Center の実績IDにそのまま対応させるので、変えない。
    let id: String
    let group: AchievementGroup
    let title: String
    /// 何をすれば取れるか。まだ取っていないときも見せる。
    let detail: String
    let symbol: String
    /// Game Center の配点。全実績の合計が 1,000 を超えられない。
    let points: Int
    let isMet: (CityStats) -> Bool

    var isEarned: Bool { AchievementStore.shared.isEarned(id) }
}

enum Achievements {

    /// 並び順がそのまま一覧の並びになる。分類ごとに、やさしいものから置く。
    static let all: [Achievement] = [

        // MARK: 人口

        Achievement(id: "pop.100", group: .population, title: "はじめの一歩",
                    detail: "人口 100 人", symbol: "figure.walk", points: 10) { $0.sim.residents >= 100 },

        Achievement(id: "pop.1000", group: .population, title: "町になった",
                    detail: "人口 1,000 人", symbol: "house.fill", points: 15) { $0.sim.residents >= 1_000 },

        Achievement(id: "pop.5000", group: .population, title: "市になった",
                    detail: "人口 5,000 人", symbol: "building.2.fill", points: 20) { $0.sim.residents >= 5_000 },

        Achievement(id: "pop.10000", group: .population, title: "大都市",
                    detail: "人口 10,000 人", symbol: "building.columns.fill", points: 35) { $0.sim.residents >= 10_000 },

        Achievement(id: "pop.20000", group: .population, title: "首府",
                    detail: "人口 20,000 人", symbol: "crown.fill", points: 55) { $0.sim.residents >= 20_000 },

        Achievement(id: "jobs.balanced", group: .population, title: "職住のつり合い",
                    detail: "人口 5,000 人で、雇用が住民の半分を上回る",
                    symbol: "arrow.left.arrow.right", points: 20) {
            $0.sim.residents >= 5_000 && $0.sim.jobs * 2 >= $0.sim.residents
        },

        Achievement(id: "commercial.city", group: .population, title: "商都",
                    detail: "商業の雇用が工業を上回ったまま人口 5,000 人",
                    symbol: "bag.fill", points: 25) {
            $0.sim.residents >= 5_000 && $0.sim.jobsCommercial > $0.sim.jobsIndustrial
        },

        Achievement(id: "industrial.city", group: .population, title: "工都",
                    detail: "工業の雇用 3,000", symbol: "gearshape.fill", points: 25) {
            $0.sim.jobsIndustrial >= 3_000
        },

        // MARK: 発展

        Achievement(id: "tower.first", group: .growth, title: "高層のはじまり",
                    detail: "区画を L6 まで育てる", symbol: "building", points: 15) { $0.topLevel >= 6 },

        Achievement(id: "tower.max", group: .growth, title: "摩天楼",
                    detail: "区画を最上段の L10 まで育てる", symbol: "sparkles", points: 55) {
            $0.topLevel >= Zone.maxLevel
        },

        Achievement(id: "skyline", group: .growth, title: "スカイライン",
                    detail: "L8 以上の区画を 5 つ", symbol: "chart.bar.fill", points: 35) {
            $0.zones(atLeast: 8) >= 5
        },

        Achievement(id: "downtown", group: .growth, title: "都心",
                    detail: "L9 以上の区画を 10 つ", symbol: "building.2", points: 45) {
            $0.zones(atLeast: 9) >= 10
        },

        Achievement(id: "three.kinds", group: .growth, title: "三業種",
                    detail: "住宅・商業・工業のすべてを L6 以上に育てる",
                    symbol: "square.grid.3x1.below.line.grid.1x2", points: 25) { s in
            [ZoneKind.residential, .commercial, .industrial].allSatisfy { kind in
                s.sim.map.zones.contains { $0.alive && $0.kind == kind && $0.level >= 6 }
            }
        },

        Achievement(id: "zones.200", group: .growth, title: "びっしり",
                    detail: "区画を 200 置く", symbol: "square.grid.3x3.fill", points: 20) {
            $0.sim.map.zones.filter { $0.alive }.count >= 200
        },

        Achievement(id: "landvalue.max", group: .growth, title: "一等地",
                    detail: "土地価値を上限まで押し上げる", symbol: "arrow.up.right", points: 30) {
            $0.sim.landValue.maximum >= 255
        },

        // MARK: 街づくり

        Achievement(id: "avenue.50", group: .planning, title: "表通り",
                    detail: "大通りを 50 マス敷く", symbol: "road.lanes.curved.right", points: 15) {
            $0.sim.avenueCount >= 50
        },

        Achievement(id: "park.200", group: .planning, title: "緑の街",
                    detail: "公園を 200 マス置く", symbol: "tree.fill", points: 20) { $0.parkTiles >= 200 },

        Achievement(id: "keep.forest", group: .planning, title: "森を残す",
                    detail: "森を 2,000 マス残したまま人口 5,000 人", symbol: "leaf.fill", points: 40) {
            $0.sim.residents >= 5_000 && $0.forestTiles >= 2_000
        },

        Achievement(id: "clean.air", group: .planning, title: "澄んだ空",
                    detail: "最大公害 100 未満のまま人口 3,000 人", symbol: "wind", points: 30) {
            $0.sim.residents >= 3_000 && $0.sim.pollution.maximum < 100
        },

        Achievement(id: "safe.city", group: .planning, title: "安全な街",
                    detail: "最大犯罪 50 未満のまま人口 3,000 人",
                    symbol: "shield.lefthalf.filled", points: 30) {
            $0.sim.residents >= 3_000 && $0.sim.crime.maximum < 50
        },

        Achievement(id: "no.blackout", group: .planning, title: "灯を絶やさない",
                    detail: "停電ゼロのまま人口 5,000 人", symbol: "bolt.fill", points: 25) {
            $0.sim.residents >= 5_000 && $0.sim.unpoweredZones == 0
        },

        Achievement(id: "all.connected", group: .planning, title: "行き止まりなし",
                    detail: "区画 100 以上で、停電も道路なしもゼロ",
                    symbol: "point.topleft.down.curvedto.point.bottomright.up", points: 40) {
            $0.sim.map.zones.filter { $0.alive }.count >= 100
                && $0.sim.unpoweredZones == 0 && $0.sim.disconnectedZones == 0
        },

        Achievement(id: "no.jam", group: .planning, title: "渋滞知らず",
                    detail: "混みぐあいを 60 未満に抑えたまま人口 8,000 人",
                    symbol: "car.fill", points: 45) {
            $0.sim.residents >= 8_000 && $0.sim.congestion < 60
        },

        Achievement(id: "services", group: .planning, title: "備えあり",
                    detail: "警察署と消防署を 5 つずつ", symbol: "cross.case.fill", points: 15) {
            $0.count(of: .police) >= 5 && $0.count(of: .fire) >= 5
        },

        Achievement(id: "ideal.city", group: .planning, title: "理想都市",
                    detail: "公害 100 未満・犯罪 50 未満のまま人口 10,000 人",
                    symbol: "star.circle.fill", points: 80) {
            $0.sim.residents >= 10_000 && $0.sim.pollution.maximum < 100 && $0.sim.crime.maximum < 50
        },

        // MARK: 経営

        Achievement(id: "funds.100k", group: .economy, title: "蓄え",
                    detail: "資金 ¥100,000", symbol: "yensign.circle.fill", points: 15) {
            $0.sim.funds >= 100_000
        },

        Achievement(id: "funds.500k", group: .economy, title: "金庫番",
                    detail: "資金 ¥500,000", symbol: "banknote.fill", points: 30) {
            $0.sim.funds >= 500_000
        },

        Achievement(id: "balanced", group: .economy, title: "黒字経営",
                    detail: "人口 5,000 人を黒字で保つ", symbol: "chart.line.uptrend.xyaxis", points: 25) {
            $0.sim.residents >= 5_000 && $0.sim.projectedIncome > $0.sim.projectedExpenses
        },

        Achievement(id: "low.tax", group: .economy, title: "軽い税",
                    detail: "税率 5% 以下で人口 5,000 人", symbol: "arrow.down.circle", points: 40) {
            $0.sim.residents >= 5_000 && $0.sim.taxRate <= 5
        },

        Achievement(id: "high.tax", group: .economy, title: "重税に耐える",
                    detail: "税率 15% 以上で人口 3,000 人", symbol: "arrow.up.circle", points: 40) {
            $0.sim.residents >= 3_000 && $0.sim.taxRate >= 15
        },

        Achievement(id: "power.5", group: .economy, title: "電力自給",
                    detail: "発電所を 5 つ動かす", symbol: "flame.fill", points: 20) {
            $0.count(of: .coalPlant) >= 5
        },

        // MARK: 時代

        Achievement(id: "year.1950", group: .time, title: "半世紀",
                    detail: "1950 年まで街を保つ", symbol: "clock.fill", points: 10) { $0.sim.year >= 1950 },

        Achievement(id: "year.2000", group: .time, title: "世紀を越えて",
                    detail: "2000 年まで街を保つ", symbol: "hourglass", points: 20) { $0.sim.year >= 2000 },

        Achievement(id: "year.2100", group: .time, title: "次の百年",
                    detail: "2100 年まで街を保つ", symbol: "infinity", points: 30) { $0.sim.year >= 2100 },
    ]

    static func inGroup(_ group: AchievementGroup) -> [Achievement] {
        all.filter { $0.group == group }
    }
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

    /// これまでに取ったすべての名前。Game Center へまとめて送るときに使う。
    var allEarnedIDs: [String] { Array(earned) }

    /// まだ取っていないもののうち、条件を満たしたものを記録して返す。
    func claimNewlyEarned(in sim: Simulation) -> [Achievement] {
        let stats = CityStats(sim)
        var newly: [Achievement] = []
        for a in Achievements.all where !earned.contains(a.id) && a.isMet(stats) {
            earned.insert(a.id)
            newly.append(a)
        }
        if !newly.isEmpty {
            UserDefaults.standard.set(Array(earned), forKey: key)
        }
        return newly
    }
}
