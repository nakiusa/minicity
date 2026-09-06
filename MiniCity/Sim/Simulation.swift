import Foundation

/// 都市の状態と、1か月ごとの更新をまとめて持つ。
/// 描画も UI も、ここが計算した数値を読むだけにしてある。
final class Simulation {

    let map = CityMap()

    // MARK: - プレイヤーが動かす値

    var funds: Int = 20_000
    var taxRate: Int = 7
    private(set) var monthsElapsed: Int = 0

    /// セーブデータから都市を組み立て直す。地形は生成せず、保存されたものを使う。
    convenience init(save: CitySave) {
        self.init(generateTerrain: false)
        map.restore(tiles: save.tiles, zones: save.zones)
        funds = save.funds
        taxRate = save.taxRate
        monthsElapsed = save.monthsElapsed
        census()
        updatePower()
        updateRoadAccess()
        updateTraffic()
        updateOverlays()
        census()
    }

    var year: Int { 1900 + monthsElapsed / 12 }
    var month: Int { monthsElapsed % 12 + 1 }

    // MARK: - 集計

    private(set) var residents = 0
    private(set) var jobsCommercial = 0
    private(set) var jobsIndustrial = 0
    private(set) var roadCount = 0
    private(set) var avenueCount = 0
    private(set) var wireCount = 0
    private(set) var zoneCounts: [ZoneKind: Int] = [:]
    private(set) var unpoweredZones = 0
    private(set) var disconnectedZones = 0

    var jobs: Int { jobsCommercial + jobsIndustrial }

    // MARK: - 需要（-1...1）

    private(set) var demandR = 0.0
    private(set) var demandC = 0.0
    private(set) var demandI = 0.0

    // MARK: - 粗いマップ

    // 更新は Overlays.swift と Traffic.swift の拡張が行う。
    var pollution = CoarseMap()
    var landValue = CoarseMap(64)
    var crime = CoarseMap()
    var density = CoarseMap()
    var policeCover = CoarseMap()
    var fireCover = CoarseMap()
    var trafficMap = CoarseMap()

    /// 直近の会計年度の内訳。予算画面が読む。
    private(set) var lastIncome = 0
    private(set) var lastExpenses = 0

    /// この1か月で1段上がった区画の中心タイル。描画側が演出に使う。
    private(set) var recentUpgrades: [(Int, Int)] = []

    /// HUD に出す警告。多すぎても読まれないので3件までに絞る。
    private(set) var warnings: [String] = []

    /// 都市の重心。土地価値の中心バイアスに使う。
    private(set) var centerX = Double(CityMap.width) / 2
    private(set) var centerY = Double(CityMap.height) / 2

    /// 成長判定の乱数。地形と同じ種から作るので、同じ種の都市は同じように育つ。
    /// ヘッドレスの検証をやり直しても数字が揃うのは、これがあるため。
    private var rng: SplitMix64

    init(seed: UInt64 = UInt64.random(in: 0..<UInt64.max), generateTerrain: Bool = true) {
        rng = SplitMix64(seed: seed ^ 0xA5A5_A5A5_A5A5_A5A5)
        if generateTerrain {
            TerrainGenerator.generate(into: map, seed: seed)
        }
        census()
    }

    // MARK: - 1か月の更新

    func tick() {
        monthsElapsed += 1

        updatePower()
        updateRoadAccess()
        updateTraffic()
        updateOverlays()
        census()
        updateDemand()
        growZones()
        census()

        if monthsElapsed % 12 == 0 {
            settleAnnualBudget()
        }
        updateWarnings()
    }

    // MARK: - 集計

    func census() {
        var res = 0, com = 0, ind = 0
        var counts: [ZoneKind: Int] = [:]
        var unpowered = 0, disconnected = 0
        var sumX = 0.0, sumY = 0.0, weight = 0.0

        density.clear()

        map.forEachZone { _, z in
            counts[z.kind, default: 0] += 1
            let cap = z.capacity
            switch z.kind {
            case .residential: res += cap
            case .commercial: com += cap
            case .industrial: ind += cap
            default: break
            }
            // 発電所は自前で動き、道路も要らない。それ以外は更地の段階から
            // 電気と道路を待っているので、育つ前でも足りなければ知らせる。
            if z.kind != .coalPlant {
                if !z.powered { unpowered += 1 }
                if !z.hasRoad { disconnected += 1 }
            }
            if cap > 0 {
                let cx = Double(z.ox) + 1, cy = Double(z.oy) + 1
                sumX += cx * Double(cap)
                sumY += cy * Double(cap)
                weight += Double(cap)
                density.addAtTile(Int(cx), Int(cy), cap)
            }
        }

        residents = res
        jobsCommercial = com
        jobsIndustrial = ind
        zoneCounts = counts
        unpoweredZones = unpowered
        disconnectedZones = disconnected

        if weight > 0 {
            centerX = sumX / weight
            centerY = sumY / weight
        }

        var roads = 0, avenues = 0, wires = 0
        for t in map.tiles {
            if t.structure == .road {
                roads += 1
                if t.isAvenue { avenues += 1 }
            }
            if t.wire { wires += 1 }
        }
        roadCount = roads
        avenueCount = avenues
        wireCount = wires
    }

    // MARK: - 需要

    private func updateDemand() {
        // 住民の半分が働きに出るものとして、職と住のつり合いから需要を作る。
        let workers = Double(residents) * 0.5
        let totalJobs = Double(jobs)
        let scale = max(300.0, Double(residents) * 0.35)

        // 定数項は「外から来る需要」。まっさらな都市でも最初の一歩が踏み出せる。
        var r = (totalJobs + 90 - workers) / scale
        var c = (Double(residents) * 0.30 - Double(jobsCommercial)) / scale
        var i = (Double(residents) * 0.34 + 140 - Double(jobsIndustrial)) / scale

        let taxPenalty = Double(taxRate - 7) * 0.045
        r -= taxPenalty
        c -= taxPenalty
        i -= taxPenalty

        // 急に振れると挙動が読めないので、前の値へ寄せながら動かす。
        demandR += (min(max(r, -1), 1) - demandR) * 0.35
        demandC += (min(max(c, -1), 1) - demandC) * 0.35
        demandI += (min(max(i, -1), 1) - demandI) * 0.35
    }

    /// L7 以降のしきい値の積み上げ分。段が上がるほど1段の重みを増やす。
    private static func towerExtra(_ level: Int, steps: [Double]) -> Double {
        guard level > 6 else { return 0 }
        return steps.prefix(min(level - 6, steps.count)).reduce(0, +)
    }

    // MARK: - ゾーンの成長と衰退

    private func growZones() {
        recentUpgrades.removeAll(keepingCapacity: true)
        map.forEachZone { _, z in
            guard z.kind.grows else { return }

            let cx = Int(z.ox) + 1, cy = Int(z.oy) + 1
            let lv = landValue.atTile(cx, cy)
            let pol = pollution.atTile(cx, cy)
            let cri = crime.atTile(cx, cy)

            // 何を嫌い何を求めるかは業種で違う。住宅は土地の良し悪しに敏感で、
            // 工業は煙や地価をほとんど気にせず、注文があるかどうかで決まる。
            var score: Double
            switch z.kind {
            case .residential:
                score = demandR * 110 + Double(lv) * 0.62 - Double(pol) * 0.30 - Double(cri) * 0.22
            case .commercial:
                score = demandC * 120 + Double(lv) * 0.58 - Double(pol) * 0.22 - Double(cri) * 0.20
            default:
                score = demandI * 185 + Double(lv) * 0.25 - Double(pol) * 0.05 - Double(cri) * 0.10 + 42
            }

            if !z.hasRoad { score -= 250 }
            if !z.powered { score -= 250 }
            if z.kind == .residential && !z.hasJobAccess && z.level > 0 { score -= 90 }

            // 育つには段ごとに高い点が要り、保つには低い点で足りる。
            // この差があるおかげで、需要が少し揺れただけで建て直しが起きない。
            // 工業は地価の階段を登れない（自分の煙で地価を潰すため）ので、
            // 別の、低いしきい値を使う。そうしないと永久に中規模で止まる。
            // レベル6までは元の刻みのまま。そこから先（高層タワー）は段を追うごとに
            // 要求を強める。ヘッドレスで確かめたところ、最良の地価は現実的には
            // 200前後で頭打ちになるので、L8 以降のしきい値をそれより高く置くと
            // 理屈のうえで永久に届かなくなる。届く余地を残しつつ、L10 は
            // 好条件が重なった一瞬でしか超えられない高さに置く。
            let level = Int(z.level)
            let growThreshold: Double
            let shrinkThreshold: Double
            if z.kind == .industrial {
                let base = min(level, 6)
                growThreshold = 10.0 + Double(base) * 13.0
                    + Simulation.towerExtra(level, steps: [5, 7, 9, 11])
                shrinkThreshold = Double(level) * 8.0 - 8.0
            } else {
                let base = min(level, 6)
                growThreshold = 18.0 + Double(base) * 20.0
                    + Simulation.towerExtra(level, steps: [6, 8, 10, 12])
                shrinkThreshold = Double(level) * 12.0 - 10.0
            }

            var newLevel = level
            if level < Zone.maxLevel, score > growThreshold, Double.random(in: 0..<1, using: &rng) < 0.22 {
                newLevel = level + 1
            } else if score < shrinkThreshold, Double.random(in: 0..<1, using: &rng) < 0.15 {
                newLevel = level - 1
            }

            if newLevel != level {
                z.level = UInt8(max(0, newLevel))
                if newLevel > level {
                    recentUpgrades.append((Int(z.ox) + 1, Int(z.oy) + 1))
                }
                for dy in 0..<3 {
                    for dx in 0..<3 {
                        map.markDirty(Int(z.ox) + dx, Int(z.oy) + dy)
                    }
                }
            }
        }
    }

    // MARK: - 会計

    private func settleAnnualBudget() {
        let income = projectedIncome
        let expenses = projectedExpenses

        lastIncome = income
        lastExpenses = expenses
        funds += income - expenses
    }

    /// 年度が変わる前でも、いま決算したらどうなるかを予算画面に出す。
    var incomeFromResidents: Int { Int(Double(residents) * Double(taxRate) * 0.065) }
    var incomeFromBusiness: Int { Int(Double(jobs) * Double(taxRate) * 0.038) }

    var projectedIncome: Int { incomeFromResidents + incomeFromBusiness }

    /// 道路の維持費。街が広がるほど効いてくるよう、1マスあたりを重くしてある。
    /// 大通りは通しただけで地価を押し上げるので、そのぶん維持費も高い。
    var roadUpkeep: Int { (roadCount - avenueCount) * 6 + avenueCount * 20 }
    var plantUpkeep: Int { (zoneCounts[.coalPlant] ?? 0) * 100 }
    var policeUpkeep: Int { (zoneCounts[.police] ?? 0) * 180 }
    var fireUpkeep: Int { (zoneCounts[.fire] ?? 0) * 180 }

    var projectedExpenses: Int { roadUpkeep + plantUpkeep + policeUpkeep + fireUpkeep }

    /// 道路のある街区に限った平均の混み具合。
    /// 幹線が1本詰まっているだけで警告を出しても仕方がないので、最大値では測らない。
    var congestion: Int {
        var sum = 0, count = 0
        for cy in 0..<CoarseMap.height {
            for cx in 0..<CoarseMap.width where trafficMap[cx, cy] > 0 {
                sum += trafficMap[cx, cy]
                count += 1
            }
        }
        return count > 0 ? sum / count : 0
    }

    // MARK: - 警告

    private func updateWarnings() {
        var list: [String] = []
        if funds < 0 {
            list.append("財政が赤字です")
        }
        if unpoweredZones > 0 {
            list.append("電力が届いていない区画が \(unpoweredZones) あります")
        }
        if disconnectedZones > 0 {
            list.append("道路に面していない区画が \(disconnectedZones) あります")
        }
        if list.count < 3, congestion > 150 {
            list.append("渋滞が発生しています")
        }
        if list.count < 3, residents > 400, (zoneCounts[.police] ?? 0) == 0, crime.maximum > 90 {
            list.append("犯罪が増えています")
        }
        warnings = Array(list.prefix(3))
    }
}
