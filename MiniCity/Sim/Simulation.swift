import Foundation

/// 都市の状態と、1か月ごとの更新をまとめて持つ。
/// 描画も UI も、ここが計算した数値を読むだけにしてある。
final class Simulation {

    let map = CityMap()

    // MARK: - プレイヤーが動かす値

    var funds: Int = 21_000
    /// 税率（%）。10% が目安で、0〜30% の間で動かす。
    /// 1.5 までは 7% が目安の目盛りだった。古いセーブは読み込むときに 10/7 倍して合わせる。
    var taxRate: Int = 10
    private(set) var monthsElapsed: Int = 0
    /// 借入の残高。年度末に利息と元本の一部を返す。
    /// 赤字が続いて手が打てなくなった街の逃げ道。撤去も建て直しも金が要る。
    private(set) var debt: Int = 0

    /// セーブデータから都市を組み立て直す。地形は生成せず、保存されたものを使う。
    convenience init(save: CitySave) {
        self.init(generateTerrain: false)
        map.restore(tiles: save.tiles, zones: save.zones)
        funds = save.funds
        taxRate = save.version >= 2 ? save.taxRate : Int((Double(save.taxRate) * 10 / 7).rounded())
        monthsElapsed = save.monthsElapsed
        termYears = save.termYears
        debt = save.debt ?? 0
        updateLinks()
        census()
        updatePower()
        updateRoadAccess()
        updateRail()
        updateTraffic()
        updateOverlays()
        census()
    }

    /// 何年目か。暦の年（1900年から、など）は使わず、始めてからの年数で数える。
    var year: Int { monthsElapsed / 12 + 1 }
    var month: Int { monthsElapsed % 12 + 1 }

    /// 遊ぶと決めた年数。`nil` なら期限なしで、いつまでも続けられる。
    var termYears: Int?

    /// 期限の最後の年。100年なら 100年目まで遊んで終わる。
    var lastYear: Int? { termYears }

    /// 期限まで残り何年か。最後の1年のあいだは 1 を返す。
    var yearsLeft: Int? {
        termYears.map { max(0, ($0 * 12 - monthsElapsed + 11) / 12) }
    }

    /// 期限に届いたか。届いた月に時間が止まる。
    var isOver: Bool { termYears.map { monthsElapsed >= $0 * 12 } ?? false }

    // MARK: - 集計

    private(set) var residents = 0
    private(set) var jobsCommercial = 0
    private(set) var jobsIndustrial = 0
    private(set) var roadCount = 0
    private(set) var avenueCount = 0
    private(set) var wireCount = 0
    private(set) var railCount = 0
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
    /// 住民と雇用を合わせた「にぎわい」。地価と犯罪の計算に使う。
    var density = CoarseMap()
    var policeCover = CoarseMap()
    var fireCover = CoarseMap()
    /// 火事の起きやすさ。建物が密で高いほど、工場や発電所ほど上がり、消防署の近くで下がる。
    var fireRisk = CoarseMap()

    // 鉄道。Rail.swift が毎月作り直す。
    /// 使える路線ごとの、駅に面した道路のマス。
    var railLineRoads: [[Int]] = []
    /// 駅に面した道路のマスから、その路線の番号。
    var railRoadLine: [Int: Int] = [:]
    /// 使える路線に載っている駅。
    var activeStations: Set<Int32> = []
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
        updateRail()
        updateTraffic()
        updateOverlays()
        census()
        updateDemand()
        growZones()
        updateLinks()
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

        map.forEachZone { id, z in
            counts[z.kind, default: 0] += 1
            let cap = headcount(z, id: id)
            switch z.kind {
            case .residential: res += cap
            case .commercial: com += cap
            case .industrial: ind += cap
            default: break
            }
            // 発電所は自前で動き、道路も要らない。それ以外は更地の段階から
            // 電気と道路を待っているので、育つ前でも足りなければ知らせる。
            if z.kind.needsUtilities {
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

        var roads = 0, avenues = 0, wires = 0, rails = 0
        for t in map.tiles {
            if t.structure == .road {
                roads += 1
                if t.isAvenue { avenues += 1 }
            }
            if t.wire { wires += 1 }
            if t.rail { rails += 1 }
        }
        roadCount = roads
        avenueCount = avenues
        wireCount = wires
        railCount = rails
    }

    /// 区画が抱える人数。住宅なら住民、商業と工業なら雇用。
    /// 結ばれた街区は、ひとつの大きな建物として抱える数が跳ね上がる。
    func headcount(_ z: Zone, id: Int32) -> Int {
        guard linkedZones[id] != nil else { return z.capacity }
        return z.kind == .residential ? z.capacity * 2 : z.capacity * 3 / 2
    }

    /// そのマスが属する区画の人数と種類。区画の外なら nil。
    /// 粗い格子で引くと、隣の区画の人数が混ざったり自分の人数が隣へ行ったりするので、区画から直接引く。
    func headcount(atX x: Int, y: Int) -> (count: Int, kind: ZoneKind)? {
        let id = map.tile(x, y).zoneID
        guard let z = map.zone(id), z.kind.grows else { return nil }
        return (headcount(z, id: id), z.kind)
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

        let taxPenalty = Double(taxRate - 10) * 0.0315
        r -= taxPenalty
        c -= taxPenalty
        i -= taxPenalty

        // 急に振れると挙動が読めないので、前の値へ寄せながら動かす。
        demandR += (min(max(r, -1), 1) - demandR) * 0.2
        demandC += (min(max(c, -1), 1) - demandC) * 0.2
        demandI += (min(max(i, -1), 1) - demandI) * 0.2
    }

    /// L7 以降のしきい値の積み上げ分。段が上がるほど1段の重みを増やす。
    private static func towerExtra(_ level: Int, steps: [Double]) -> Double {
        guard level > 6 else { return 0 }
        return steps.prefix(min(level - 6, steps.count)).reduce(0, +)
    }

    // MARK: - ゾーンの成長と衰退

    private func growZones() {
        recentUpgrades.removeAll(keepingCapacity: true)
        map.forEachZone { id, z in
            guard z.kind.grows else { return }

            let cx = Int(z.ox) + 1, cy = Int(z.oy) + 1
            let lv = landValue.atTile(cx, cy)
            let pol = pollution.atTile(cx, cy)
            let cri = crime.atTile(cx, cy)

            // 何を嫌い何を求めるかは業種で違う。住宅は土地の良し悪しに敏感で、
            // 工業は煙や地価をほとんど気にせず、注文があるかどうかで決まる。
            let linked = linkedZones[id] != nil
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

            // 段が上がるほど、次の段まで待つ月が長くなる。条件が揃いっぱなしでも
            // L10 までおよそ30年かかる刻み。序盤の1段目だけは数か月で建つ。
            let growChance = 0.14 / pow(Double(level + 1), 1.55)
            var newLevel = level
            if level < Zone.maxLevel, score > growThreshold, Double.random(in: 0..<1, using: &rng) < growChance {
                newLevel = level + 1
            } else if linked ? (CoarseMap.display(pol) >= Simulation.linkBreakPollution || !z.powered || !z.hasRoad)
                                  && Double.random(in: 0..<1, using: &rng) < 0.05
                             : score < shrinkThreshold && Double.random(in: 0..<1, using: &rng) < 0.15 {
                // 連結した建物は、需要の波や犯罪では崩れない。公害がひどいときと、電気か道路を失ったときだけ崩れる。
                // 絶対に崩れないことにしていたころは、隣に工業地を並べても、停電しても L9 のまま居座った。
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

    // MARK: - 街区の結び

    /// 2×2 に並んだ同業種の区画が全部 L9 以上になると、ひとつの大きな建物として結ばれる。
    /// 結ばれた区画は抱える数が跳ね上がり、レベルが下がりにくくなる。値は左上（親）の区画の番号。
    /// 段から毎月計算し直すだけなので、セーブには入れない。
    private(set) var linkedZones: [Int32: Int32] = [:]
    static let linkLevel: UInt8 = 9
    /// 連結した建物が崩れはじめる公害（画面の 0...100 で）。
    static let linkBreakPollution = 40

    /// (x, y) を左上とする区画の番号。そこが区画の左上でなければ nil。
    private func zoneAnchored(atX x: Int, y: Int) -> Int32? {
        guard x >= 0, y >= 0, x < CityMap.width, y < CityMap.height else { return nil }
        let t = map.tile(x, y)
        guard t.zoneID >= 0, t.sub == 0, let z = map.zone(t.zoneID) else { return nil }
        return z.kind.grows && z.level >= Simulation.linkLevel ? t.zoneID : nil
    }

    func updateLinks() {
        var links: [Int32: Int32] = [:]
        // forEachZone は inout で回すので、中から別の区画を読めない。番号で回す。
        for i in map.zones.indices {
            let z = map.zones[i]
            guard z.alive, z.kind.grows, z.level >= Simulation.linkLevel else { continue }
            let id = Int32(i), ox = Int(z.ox), oy = Int(z.oy)
            guard let r = zoneAnchored(atX: ox + 3, y: oy),
                  let d = zoneAnchored(atX: ox, y: oy + 3),
                  let rd = zoneAnchored(atX: ox + 3, y: oy + 3),
                  map.zone(r)?.kind == z.kind, map.zone(d)?.kind == z.kind, map.zone(rd)?.kind == z.kind
            else { continue }
            // すでに別の親に結ばれている区画は取らない。重なった 2×2 を二重に数えないため。
            for m in [id, r, d, rd] where links[m] == nil { links[m] = id }
        }
        linkedZones = links
    }

    // MARK: - 会計

    private func settleAnnualBudget() {
        let income = projectedIncome
        let expenses = projectedExpenses
        let repayment = debtRepayment

        lastIncome = income
        lastExpenses = expenses
        funds += income - expenses
        debt -= repayment
    }

    // MARK: - 借入

    static let loanAmount = 50_000
    static let debtLimit = 300_000

    /// 年5%の利息。残高に対して毎年払う。
    var debtInterest: Int { debt * 5 / 100 }
    /// 元本の返済。毎年1割、ただし最低 5,000。残りが少なければ残り全部。
    var debtRepayment: Int { min(debt, max(debt / 10, 5_000)) }

    var canBorrow: Bool { debt + Simulation.loanAmount <= Simulation.debtLimit }

    /// 5万円を借りる。上限に達していれば何もしない。
    func borrow() {
        guard canBorrow else { return }
        debt += Simulation.loanAmount
        funds += Simulation.loanAmount
    }

    /// 手元の金で返せるだけ返す。
    func repay() {
        let amount = min(debt, funds)
        guard amount > 0 else { return }
        debt -= amount
        funds -= amount
    }

    /// 年度が変わる前でも、いま決算したらどうなるかを予算画面に出す。
    // 係数は、目盛りを 7% 目安から 10% 目安に変えたときに 0.7 倍して、収入が変わらないようにしてある。
    var incomeFromResidents: Int { Int(Double(residents) * Double(taxRate) * 0.0455) }
    var incomeFromBusiness: Int { Int(Double(jobs) * Double(taxRate) * 0.0266) }

    var projectedIncome: Int { incomeFromResidents + incomeFromBusiness }

    /// 道路の維持費。街が広がるほど効いてくるよう、1マスあたりを重くしてある。
    /// 大通りは通しただけで地価を押し上げるので、そのぶん維持費も高い。
    var roadUpkeep: Int { (roadCount - avenueCount) * 6 + avenueCount * 20 }
    var plantUpkeep: Int { (zoneCounts[.coalPlant] ?? 0) * 200 }
    var policeUpkeep: Int { (zoneCounts[.police] ?? 0) * 400 }
    var fireUpkeep: Int { (zoneCounts[.fire] ?? 0) * 400 }
    /// 線路1マスと駅の維持費。
    var railUpkeep: Int { railCount * 5 + (zoneCounts[.station] ?? 0) * 300 }

    var projectedExpenses: Int { roadUpkeep + plantUpkeep + policeUpkeep + fireUpkeep + railUpkeep + debtInterest + debtRepayment }

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
            list.append(String(localized: "財政が赤字です。予算から借りられます"))
        }
        if unpoweredZones > 0 {
            list.append(String(localized: "電力が届いていない区画が \(unpoweredZones) あります"))
        }
        if disconnectedZones > 0 {
            list.append(String(localized: "道路に面していない区画が \(disconnectedZones) あります"))
        }
        if list.count < 3, congestion > 150 {
            list.append(String(localized: "渋滞が発生しています"))
        }
        if list.count < 3, residents > 400, (zoneCounts[.police] ?? 0) == 0, crime.maximum > 90 {
            list.append(String(localized: "犯罪が増えています"))
        }
        if list.count < 3, residents > 400, fireRisk.maximum > 80 {
            list.append(String(localized: "火災の危険が高まっています"))
        }
        warnings = Array(list.prefix(3))
    }
}
