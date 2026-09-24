import Foundation

/// 実績の分類。一覧をこの順に並べる。
enum AchievementGroup: String, CaseIterable {
    case population = "人口"
    case growth = "発展"
    case planning = "街づくり"
    case economy = "経営"
    case time = "時代"

    /// 画面に出す名前。rawValue は保存や道具の側で使うので、訳さない。
    var title: String {
        switch self {
        case .population: return String(localized: "人口")
        case .growth: return String(localized: "発展")
        case .planning: return String(localized: "街づくり")
        case .economy: return String(localized: "経営")
        case .time: return String(localized: "時代")
        }
    }
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
    /// Game Center の配点。全実績の合計が 1,000 を超えられず、公開後は変えられない。
    /// 0点の実績は、1,000点を使い切ったあとに足した難しいもの。
    let points: Int
    let isMet: (CityStats) -> Bool

    var isEarned: Bool { AchievementStore.shared.isEarned(id) }
}

enum Achievements {

    /// 並び順がそのまま一覧の並びになる。分類ごとに、やさしいものから置く。
    static let all: [Achievement] = [

        // MARK: 人口

        Achievement(id: "pop.100", group: .population, title: String(localized: "はじめの一歩"),
                    detail: String(localized: "人口 100 人"), symbol: "figure.walk", points: 10) { $0.sim.residents >= 100 },

        Achievement(id: "pop.1000", group: .population, title: String(localized: "町になった"),
                    detail: String(localized: "人口 1,000 人"), symbol: "house.fill", points: 15) { $0.sim.residents >= 1_000 },

        Achievement(id: "pop.5000", group: .population, title: String(localized: "市になった"),
                    detail: String(localized: "人口 5,000 人"), symbol: "building.2.fill", points: 20) { $0.sim.residents >= 5_000 },

        Achievement(id: "pop.10000", group: .population, title: String(localized: "大都市"),
                    detail: String(localized: "人口 10,000 人"), symbol: "building.columns.fill", points: 35) { $0.sim.residents >= 10_000 },

        Achievement(id: "pop.20000", group: .population, title: String(localized: "首都"),
                    detail: String(localized: "人口 20,000 人"), symbol: "crown.fill", points: 55) { $0.sim.residents >= 20_000 },

        Achievement(id: "jobs.balanced", group: .population, title: String(localized: "職住のつり合い"),
                    detail: String(localized: "人口 5,000 人で、雇用が住民の半分を上回る"),
                    symbol: "arrow.left.arrow.right", points: 20) {
            $0.sim.residents >= 5_000 && $0.sim.jobs * 2 >= $0.sim.residents
        },

        Achievement(id: "commercial.city", group: .population, title: String(localized: "商都"),
                    detail: String(localized: "商業の雇用が工業を上回ったまま人口 5,000 人"),
                    symbol: "bag.fill", points: 25) {
            $0.sim.residents >= 5_000 && $0.sim.jobsCommercial > $0.sim.jobsIndustrial
        },

        Achievement(id: "industrial.city", group: .population, title: String(localized: "工都"),
                    detail: String(localized: "工業の雇用 3,000"), symbol: "gearshape.fill", points: 25) {
            $0.sim.jobsIndustrial >= 3_000
        },

        Achievement(id: "pop.50000", group: .population, title: String(localized: "メガロポリス"),
                    detail: String(localized: "人口 50,000 人"), symbol: "building.2.crop.circle.fill", points: 0) { $0.sim.residents >= 50_000 },

        Achievement(id: "pop.100000", group: .population, title: String(localized: "十万都市"),
                    detail: String(localized: "人口 100,000 人"), symbol: "globe.asia.australia.fill", points: 0) { $0.sim.residents >= 100_000 },

        Achievement(id: "pop.150000", group: .population, title: String(localized: "超巨大都市"),
                    detail: String(localized: "人口 150,000 人"), symbol: "star.fill", points: 0) { $0.sim.residents >= 150_000 },

        Achievement(id: "rush.50000", group: .population, title: String(localized: "急成長"),
                    detail: String(localized: "1950 年になる前に人口 50,000 人"), symbol: "hare.fill", points: 0) { $0.sim.year < 1950 && $0.sim.residents >= 50_000 },

        Achievement(id: "jobs.50000", group: .population, title: String(localized: "働く街"),
                    detail: String(localized: "雇用 50,000"), symbol: "briefcase.fill", points: 0) { $0.sim.jobs >= 50_000 },

        // MARK: 発展

        Achievement(id: "tower.first", group: .growth, title: String(localized: "高層のはじまり"),
                    detail: String(localized: "区画を L6 まで育てる"), symbol: "building", points: 15) { $0.topLevel >= 6 },

        Achievement(id: "tower.max", group: .growth, title: String(localized: "摩天楼"),
                    detail: String(localized: "区画を最高レベルの L10 まで育てる"), symbol: "sparkles", points: 55) {
            $0.topLevel >= Zone.maxLevel
        },

        Achievement(id: "skyline", group: .growth, title: String(localized: "スカイライン"),
                    detail: String(localized: "L8 以上の区画を 5 個"), symbol: "chart.bar.fill", points: 35) {
            $0.zones(atLeast: 8) >= 5
        },

        Achievement(id: "downtown", group: .growth, title: String(localized: "都心"),
                    detail: String(localized: "L9 以上の区画を 10 個"), symbol: "building.2", points: 45) {
            $0.zones(atLeast: 9) >= 10
        },

        Achievement(id: "three.kinds", group: .growth, title: String(localized: "三業種"),
                    detail: String(localized: "住宅・商業・工業のすべてを L6 以上に育てる"),
                    symbol: "square.grid.3x1.below.line.grid.1x2", points: 25) { s in
            [ZoneKind.residential, .commercial, .industrial].allSatisfy { kind in
                s.sim.map.zones.contains { $0.alive && $0.kind == kind && $0.level >= 6 }
            }
        },

        Achievement(id: "zones.200", group: .growth, title: String(localized: "びっしり"),
                    detail: String(localized: "区画を 200 置く"), symbol: "square.grid.3x3.fill", points: 20) {
            $0.sim.map.zones.filter { $0.alive }.count >= 200
        },

        Achievement(id: "landvalue.max", group: .growth, title: String(localized: "一等地"),
                    detail: String(localized: "地価を上限まで押し上げる"), symbol: "arrow.up.right", points: 30) {
            $0.sim.landValue.maximum >= 255
        },

        Achievement(id: "l10.10", group: .growth, title: String(localized: "摩天楼街"),
                    detail: String(localized: "L10 の区画を 10 個"), symbol: "building.fill", points: 0) { $0.levelCounts[Zone.maxLevel] >= 10 },

        Achievement(id: "l10.50", group: .growth, title: String(localized: "天空都市"),
                    detail: String(localized: "L10 の区画を 50 個"), symbol: "cloud.fill", points: 0) { $0.levelCounts[Zone.maxLevel] >= 50 },

        Achievement(id: "link.first", group: .growth, title: String(localized: "連結"),
                    detail: String(localized: "街区を連結する"), symbol: "link", points: 0) { !$0.sim.linkedZones.isEmpty },

        Achievement(id: "link.4", group: .growth, title: String(localized: "巨大建築群"),
                    detail: String(localized: "連結した街区を 4 組"), symbol: "square.grid.2x2.fill", points: 0) { $0.sim.linkedZones.count >= 16 },

        Achievement(id: "triple.crown", group: .growth, title: String(localized: "三冠"),
                    detail: String(localized: "住宅・商業・工業のすべてを L10 まで育てる"), symbol: "rosette", points: 0) { s in [ZoneKind.residential, .commercial, .industrial].allSatisfy { kind in s.sim.map.zones.contains { $0.alive && $0.kind == kind && $0.level >= Zone.maxLevel } } },

        Achievement(id: "zones.500", group: .growth, title: String(localized: "埋め尽くす"),
                    detail: String(localized: "区画を 500 置く"), symbol: "square.grid.4x3.fill", points: 0) { $0.sim.map.zones.filter { $0.alive }.count >= 500 },

        // MARK: 街づくり

        Achievement(id: "avenue.50", group: .planning, title: String(localized: "表通り"),
                    detail: String(localized: "大通りを 50 マス敷く"), symbol: "road.lanes.curved.right", points: 15) {
            $0.sim.avenueCount >= 50
        },

        Achievement(id: "park.200", group: .planning, title: String(localized: "緑の街"),
                    detail: String(localized: "公園を 200 マス置く"), symbol: "tree.fill", points: 20) { $0.parkTiles >= 200 },

        Achievement(id: "keep.forest", group: .planning, title: String(localized: "森を残す"),
                    detail: String(localized: "森を 2,000 マス残したまま人口 5,000 人"), symbol: "leaf.fill", points: 40) {
            $0.sim.residents >= 5_000 && $0.forestTiles >= 2_000
        },

        Achievement(id: "clean.air", group: .planning, title: String(localized: "澄んだ空"),
                    detail: String(localized: "最大公害 40 未満のまま人口 3,000 人"), symbol: "wind", points: 30) {
            $0.sim.residents >= 3_000 && $0.sim.pollution.displayMaximum < 40
        },

        Achievement(id: "safe.city", group: .planning, title: String(localized: "安全な街"),
                    detail: String(localized: "最大犯罪 20 未満のまま人口 3,000 人"),
                    symbol: "shield.lefthalf.filled", points: 30) {
            $0.sim.residents >= 3_000 && $0.sim.crime.displayMaximum < 20
        },

        Achievement(id: "no.blackout", group: .planning, title: String(localized: "灯を絶やさない"),
                    detail: String(localized: "停電ゼロのまま人口 5,000 人"), symbol: "bolt.fill", points: 25) {
            $0.sim.residents >= 5_000 && $0.sim.unpoweredZones == 0
        },

        Achievement(id: "all.connected", group: .planning, title: String(localized: "行き止まりなし"),
                    detail: String(localized: "区画 100 以上で、停電も道路なしもゼロ"),
                    symbol: "point.topleft.down.curvedto.point.bottomright.up", points: 40) {
            $0.sim.map.zones.filter { $0.alive }.count >= 100
                && $0.sim.unpoweredZones == 0 && $0.sim.disconnectedZones == 0
        },

        Achievement(id: "no.jam", group: .planning, title: String(localized: "渋滞知らず"),
                    detail: String(localized: "交通量の平均を 25 未満に抑えたまま人口 8,000 人"),
                    symbol: "car.fill", points: 45) {
            $0.sim.residents >= 8_000 && CoarseMap.display($0.sim.congestion) < 25
        },

        Achievement(id: "services", group: .planning, title: String(localized: "備えあり"),
                    detail: String(localized: "警察署と消防署を 5 つずつ"), symbol: "cross.case.fill", points: 15) {
            $0.count(of: .police) >= 5 && $0.count(of: .fire) >= 5
        },

        Achievement(id: "ideal.city", group: .planning, title: String(localized: "理想都市"),
                    detail: String(localized: "公害 40 未満・犯罪 20 未満のまま人口 10,000 人"),
                    symbol: "star.circle.fill", points: 80) {
            $0.sim.residents >= 10_000 && $0.sim.pollution.displayMaximum < 40 && $0.sim.crime.displayMaximum < 20
        },

        Achievement(id: "bigpark.20", group: .planning, title: String(localized: "公園都市"),
                    detail: String(localized: "大公園を 20 置く"), symbol: "tree.circle.fill", points: 0) { $0.count(of: .bigPark) >= 20 },

        Achievement(id: "clean.30000", group: .planning, title: String(localized: "青空の大都市"),
                    detail: String(localized: "最大公害 40 未満のまま人口 30,000 人"), symbol: "cloud.sun.fill", points: 0) { $0.sim.residents >= 30_000 && $0.sim.pollution.displayMaximum < 40 },

        Achievement(id: "safe.30000", group: .planning, title: String(localized: "安心の大都市"),
                    detail: String(localized: "最大犯罪 20 未満のまま人口 30,000 人"), symbol: "lock.shield.fill", points: 0) { $0.sim.residents >= 30_000 && $0.sim.crime.displayMaximum < 20 },

        Achievement(id: "fire.safe", group: .planning, title: String(localized: "火の用心"),
                    detail: String(localized: "最大火災リスク 15 未満のまま人口 20,000 人"), symbol: "flame.circle.fill", points: 0) { $0.sim.residents >= 20_000 && $0.sim.fireRisk.displayMaximum < 15 },

        Achievement(id: "flow.50000", group: .planning, title: String(localized: "流れる街"),
                    detail: String(localized: "交通量の平均を 25 未満に抑えたまま人口 50,000 人"), symbol: "arrow.triangle.branch", points: 0) { $0.sim.residents >= 50_000 && CoarseMap.display($0.sim.congestion) < 25 },

        Achievement(id: "bright.100000", group: .planning, title: String(localized: "不夜城"),
                    detail: String(localized: "停電ゼロのまま人口 100,000 人"), symbol: "lightbulb.fill", points: 0) { $0.sim.residents >= 100_000 && $0.sim.unpoweredZones == 0 },

        Achievement(id: "paradise", group: .planning, title: String(localized: "楽園"),
                    detail: String(localized: "公害 40 未満・犯罪 20 未満・火災リスク 20 未満のまま人口 50,000 人"), symbol: "sun.max.fill", points: 0) { $0.sim.residents >= 50_000 && $0.sim.pollution.displayMaximum < 40 && $0.sim.crime.displayMaximum < 20 && $0.sim.fireRisk.displayMaximum < 20 },

        // MARK: 経営

        Achievement(id: "funds.100k", group: .economy, title: String(localized: "蓄え"),
                    detail: String(localized: "資金 ¥100,000"), symbol: "yensign.circle.fill", points: 15) {
            $0.sim.funds >= 100_000
        },

        Achievement(id: "funds.500k", group: .economy, title: String(localized: "金庫番"),
                    detail: String(localized: "資金 ¥500,000"), symbol: "banknote.fill", points: 30) {
            $0.sim.funds >= 500_000
        },

        Achievement(id: "balanced", group: .economy, title: String(localized: "黒字経営"),
                    detail: String(localized: "人口 5,000 人を黒字で保つ"), symbol: "chart.line.uptrend.xyaxis", points: 25) {
            $0.sim.residents >= 5_000 && $0.sim.projectedIncome > $0.sim.projectedExpenses
        },

        Achievement(id: "low.tax", group: .economy, title: String(localized: "軽い税"),
                    detail: String(localized: "税率 5% 以下で人口 5,000 人"), symbol: "arrow.down.circle", points: 40) {
            $0.sim.residents >= 5_000 && $0.sim.taxRate <= 5
        },

        Achievement(id: "high.tax", group: .economy, title: String(localized: "重税に耐える"),
                    detail: String(localized: "税率 15% 以上で人口 3,000 人"), symbol: "arrow.up.circle", points: 40) {
            $0.sim.residents >= 3_000 && $0.sim.taxRate >= 15
        },

        Achievement(id: "power.5", group: .economy, title: String(localized: "電力自給"),
                    detail: String(localized: "発電所を 5 つ動かす"), symbol: "flame.fill", points: 20) {
            $0.count(of: .coalPlant) >= 5
        },

        Achievement(id: "surplus.20000", group: .economy, title: String(localized: "大黒字"),
                    detail: String(localized: "年収支 ¥20,000 以上の黒字"), symbol: "chart.bar.xaxis", points: 0) { $0.sim.projectedIncome - $0.sim.projectedExpenses >= 20_000 },

        Achievement(id: "funds.1m", group: .economy, title: String(localized: "百万長者"),
                    detail: String(localized: "資金 ¥1,000,000"), symbol: "yensign.square.fill", points: 0) { $0.sim.funds >= 1_000_000 },

        Achievement(id: "funds.5m", group: .economy, title: String(localized: "大富豪"),
                    detail: String(localized: "資金 ¥5,000,000"), symbol: "crown", points: 0) { $0.sim.funds >= 5_000_000 },

        Achievement(id: "no.debt", group: .economy, title: String(localized: "無借金"),
                    detail: String(localized: "借入なしで人口 50,000 人"), symbol: "checkmark.seal.fill", points: 0) { $0.sim.residents >= 50_000 && $0.sim.debt == 0 },

        Achievement(id: "low.tax.big", group: .economy, title: String(localized: "ほぼ無税"),
                    detail: String(localized: "税率 3% 以下で人口 50,000 人"), symbol: "arrow.down.to.line", points: 0) { $0.sim.residents >= 50_000 && $0.sim.taxRate <= 3 },

        Achievement(id: "high.tax.big", group: .economy, title: String(localized: "重税都市"),
                    detail: String(localized: "税率 20% で人口 10,000 人"), symbol: "exclamationmark.triangle.fill", points: 0) { $0.sim.residents >= 10_000 && $0.sim.taxRate >= 20 },

        // MARK: 時代

        Achievement(id: "year.1950", group: .time, title: String(localized: "半世紀"),
                    detail: String(localized: "1950 年まで街を保つ"), symbol: "clock.fill", points: 10) { $0.sim.year >= 1950 },

        Achievement(id: "year.2000", group: .time, title: String(localized: "世紀を越えて"),
                    detail: String(localized: "2000 年まで街を保つ"), symbol: "hourglass", points: 20) { $0.sim.year >= 2000 },

        Achievement(id: "year.2100", group: .time, title: String(localized: "次の百年"),
                    detail: String(localized: "2100 年まで街を保つ"), symbol: "infinity", points: 30) { $0.sim.year >= 2100 },

        Achievement(id: "year.2200", group: .time, title: String(localized: "三百年"),
                    detail: String(localized: "2200 年まで街を保つ"), symbol: "clock.arrow.circlepath", points: 0) { $0.sim.year >= 2200 },

        Achievement(id: "year.2400", group: .time, title: String(localized: "悠久"),
                    detail: String(localized: "2400 年まで街を保つ"), symbol: "tortoise.fill", points: 0) { $0.sim.year >= 2400 },
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
