import Foundation

// まともな都市計画（住宅・商業・工業を離し、幹線道路と送電線を通し、警察と消防も置く）で
// 長期の推移を見る。区画が育ち続けるか、途中で固定点に落ちないかを確かめる。
let sim = Simulation(seed: 1, generateTerrain: false)
sim.funds = 300_000

let spineX = 12
let left = 12, zoneRight = 46, roadRight = 54
let feederX = 48

func district(_ tool: Tool, roadRows: [Int]) {
    for roadY in roadRows {
        for x in left...roadRight { sim.apply(.road, atX: x, y: roadY) }
        var cx = left + 2
        while cx + 1 <= zoneRight {
            sim.apply(tool, atX: cx, y: roadY - 2)
            sim.apply(tool, atX: cx, y: roadY + 2)
            cx += 3
        }
    }
}

// 南北の幹線と、その上を走る送電線。
for y in 4...78 {
    sim.apply(.road, atX: spineX, y: y)
    sim.apply(.powerLine, atX: spineX, y: y)
}

district(.residential, roadRows: [8, 16, 24, 32])
district(.commercial, roadRows: [44, 52])
district(.industrial, roadRows: [64, 72])

// 東側の送電線と、幹線への渡り。
for y in 4...78 { sim.apply(.powerLine, atX: feederX, y: y) }
for x in (spineX + 1)...(feederX - 1) { sim.apply(.powerLine, atX: x, y: 58) }

// 発電所は工業側に寄せる。
for i in 0..<4 { sim.apply(.coalPlant, atX: 50, y: 60 + i * 5) }

// 治安と消防。良い都市経営が高層につながるかを見る。
sim.apply(.police, atX: 50, y: 10)
sim.apply(.police, atX: 50, y: 26)
sim.apply(.fire, atX: 50, y: 18)
sim.apply(.fire, atX: 50, y: 34)

sim.census()

func histogram(_ kind: ZoneKind) -> String {
    var counts = Array(repeating: 0, count: Zone.maxLevel + 1)
    for z in sim.map.zones where z.alive && z.kind == kind { counts[Int(z.level)] += 1 }
    return counts.enumerated().map { "L\($0.offset):\($0.element)" }.joined(separator: " ")
}

print("建設後の残高: \(sim.funds)")
print("区画 R=\(sim.zoneCounts[.residential] ?? 0) C=\(sim.zoneCounts[.commercial] ?? 0) I=\(sim.zoneCounts[.industrial] ?? 0) 発電所=\(sim.zoneCounts[.coalPlant] ?? 0) 警察=\(sim.zoneCounts[.police] ?? 0) 消防=\(sim.zoneCounts[.fire] ?? 0)")
print("")
print("  年 |    人口 | 商業雇用 | 工業雇用 |      資金 | 年収支 |     R     C     I | 公害 土地 犯罪 交通 | 停電")
print(String(repeating: "-", count: 116))

func line(_ sim: Simulation) -> String {
    func f(_ v: Double) -> String { String(format: "%5.2f", v) }
    return String(format: "%4d | %7d | %8d | %8d | %9d | %6d | %@ %@ %@ | %4d %4d %4d %4d | %4d",
                  sim.year, sim.residents, sim.jobsCommercial, sim.jobsIndustrial, sim.funds,
                  sim.projectedIncome - sim.projectedExpenses,
                  f(sim.demandR), f(sim.demandC), f(sim.demandI),
                  sim.pollution.maximum, sim.landValue.maximum, sim.crime.maximum,
                  sim.trafficMap.maximum, sim.unpoweredZones)
}

let clock = Date()
for month in 1...1200 {
    sim.tick()
    if month % 120 == 0 { print(line(sim)) }
}
print("")
print("1200か月の計算に \(String(format: "%.2f", -clock.timeIntervalSinceNow)) 秒（1か月あたり \(String(format: "%.2f", -clock.timeIntervalSinceNow / 1200 * 1000)) ミリ秒）")
print("住宅の内訳 \(histogram(.residential))")
print("商業の内訳 \(histogram(.commercial))")
print("工業の内訳 \(histogram(.industrial))")
print("警告: \(sim.warnings)")

// --- 都市計画の良し悪しが効くか。区画の数は同じまま、工業を住宅の真隣に並べ、
// --- 警察も消防も置かない都市を、同じ年数だけ回して人口を比べる。
let sprawl = Simulation(seed: 1, generateTerrain: false)
sprawl.funds = 300_000
for y in 4...78 {
    sprawl.apply(.road, atX: spineX, y: y)
    sprawl.apply(.powerLine, atX: spineX, y: y)
}
// 住宅と工業を交互に、同じ街路ぞいに並べる。
for roadY in [8, 16, 24, 32, 44, 52, 64, 72] {
    for x in left...roadRight { sprawl.apply(.road, atX: x, y: roadY) }
    var cx = left + 2
    while cx + 1 <= zoneRight {
        sprawl.apply(.residential, atX: cx, y: roadY - 2)
        sprawl.apply(.industrial, atX: cx, y: roadY + 2)
        cx += 3
    }
}
for y in 4...78 { sprawl.apply(.powerLine, atX: feederX, y: y) }
for x in (spineX + 1)...(feederX - 1) { sprawl.apply(.powerLine, atX: x, y: 58) }
for i in 0..<4 { sprawl.apply(.coalPlant, atX: 50, y: 60 + i * 5) }
sprawl.census()
for _ in 1...1200 { sprawl.tick() }

// --- 高層タワーが実際に立つか。同じ区画の並びに、街路のあいだの公園と、
// --- 住宅・商業ぜんたいに行き渡る警察・消防を足した都市を回す。
// --- 公害と犯罪を削りきったときだけ L10 に届く、という想定を確かめる。
let serviced = Simulation(seed: 1, generateTerrain: false)
serviced.funds = 3_000_000
for y in 4...78 {
    serviced.apply(.road, atX: spineX, y: y)
    serviced.apply(.powerLine, atX: spineX, y: y)
}
func servicedDistrict(_ tool: Tool, roadRows: [Int]) {
    for roadY in roadRows {
        for x in left...roadRight { serviced.apply(.road, atX: x, y: roadY) }
        var cx = left + 2
        while cx + 1 <= zoneRight {
            serviced.apply(tool, atX: cx, y: roadY - 2)
            serviced.apply(tool, atX: cx, y: roadY + 2)
            cx += 3
        }
    }
}
servicedDistrict(.residential, roadRows: [8, 16, 24, 32])
servicedDistrict(.commercial, roadRows: [44, 52])
servicedDistrict(.industrial, roadRows: [64, 72])
for y in 4...78 { serviced.apply(.powerLine, atX: feederX, y: y) }
for x in (spineX + 1)...(feederX - 1) { serviced.apply(.powerLine, atX: x, y: 58) }
for i in 0..<4 { serviced.apply(.coalPlant, atX: 50, y: 60 + i * 5) }
for y in [12, 20, 28, 36, 40, 48, 56] {
    for x in left...zoneRight { serviced.apply(.park, atX: x, y: y) }
}
for y in stride(from: 6, through: 54, by: 8) { serviced.apply(.police, atX: 50, y: y) }
for y in stride(from: 10, through: 54, by: 8) { serviced.apply(.fire, atX: 50, y: y) }
serviced.census()
// 最良の都市で、何年で何段まで届くかの推移。段が早く上がりすぎないかを見る。
print("")
print("== 最良の都市の推移（年 / 人口 / 資金 / 最高段 / L8以上の数） ==")
var firstReached = [Int: Int]()
for month in 1...1200 {
    serviced.tick()
    let levels = serviced.map.zones.filter { $0.alive && $0.kind.grows }.map { Int($0.level) }
    let top = levels.max() ?? 0
    for l in [6, 8, 10] where top >= l && firstReached[l] == nil { firstReached[l] = serviced.year }
    if month % 60 == 0 {
        print("  \(serviced.year) | \(serviced.residents) | \(serviced.funds) | L\(top) | \(levels.filter { $0 >= 8 }.count)")
    }
}
print("  初到達 L6:\(firstReached[6].map(String.init) ?? "-") L8:\(firstReached[8].map(String.init) ?? "-") L10:\(firstReached[10].map(String.init) ?? "-")")

func servicedHistogram(_ kind: ZoneKind) -> String {
    var counts = Array(repeating: 0, count: Zone.maxLevel + 1)
    for z in serviced.map.zones where z.alive && z.kind == kind { counts[Int(z.level)] += 1 }
    return counts.enumerated().map { "L\($0.offset):\($0.element)" }.joined(separator: " ")
}
print("")
print("== 公園と警察・消防を厚く配置した都市 ==")
print("人口 \(serviced.residents), 最大地価 \(serviced.landValue.maximum), 最大犯罪 \(serviced.crime.maximum)")
print("住宅の内訳 \(servicedHistogram(.residential))")
print("商業の内訳 \(servicedHistogram(.commercial))")
print("工業の内訳 \(servicedHistogram(.industrial))")
let topLevel = serviced.map.zones.filter { $0.alive && $0.kind.grows }.map { Int($0.level) }.max() ?? 0
print("到達した最高レベル: L\(topLevel)\(topLevel >= Zone.maxLevel ? "（最上段）" : "")")

print("")
print("== 都市計画の比較（同じ年数・同じ区画数） ==")
print("  分けて建てた都市: 人口 \(sim.residents), 最大公害 \(sim.pollution.maximum), 最大地価 \(sim.landValue.maximum)")
print("  混ぜて建てた都市: 人口 \(sprawl.residents), 最大公害 \(sprawl.pollution.maximum), 最大地価 \(sprawl.landValue.maximum)")

// --- 序盤の資金繰り。初期資金2万で、ふつうに始めた都市が続けられるか。 ---
print("")
print("== 序盤（初期資金 20,000、税率7%） ==")
let s2 = Simulation(seed: 7, generateTerrain: false)
for x in 20...44 { s2.apply(.road, atX: x, y: 30) }
for cx in stride(from: 22, through: 32, by: 3) {
    s2.apply(.residential, atX: cx, y: 28)
    s2.apply(.industrial, atX: cx, y: 32)
}
s2.apply(.coalPlant, atX: 40, y: 28)
for x in 33...38 { s2.apply(.powerLine, atX: x, y: 28) }
for y in 28...32 { s2.apply(.powerLine, atX: 33, y: y) }
// 電力と道路の判定は tick の中で走るので、着工直後の姿を報告するには自分で一度回す。
// これを省くと、つないだばかりの区画がぜんぶ「停電・道路なし」に見えてしまう。
s2.updatePower()
s2.updateRoadAccess()
s2.census()
print("建設直後の残高 \(s2.funds), 区画 \(s2.map.zones.count), 停電 \(s2.unpoweredZones), 道路なし \(s2.disconnectedZones)")
for year in 1...40 {
    for _ in 1...12 { s2.tick() }
    if year % 5 == 0 {
        print("  \(s2.year)年: 人口 \(s2.residents), 雇用 \(s2.jobs), 資金 \(s2.funds), 年収支 \(s2.projectedIncome - s2.projectedExpenses)")
    }
}

// --- 借入。借りた額が手元に入り、年度末に利息と元本の一割が引かれ、返しきれる。 ---
print("")
print("== 借入 ==")
let s3 = Simulation(seed: 3, generateTerrain: false)
s3.funds = 1_000
s3.borrow()
assert(s3.funds == 51_000 && s3.debt == 50_000, "借りた額が合わない")
let before = s3.funds
for _ in 1...12 { s3.tick() }
// 区画がないので税収も維持費もゼロ。引かれるのは利息 2,500 と元本 5,000 だけ。
assert(s3.debt == 45_000, "元本が減っていない: \(s3.debt)")
assert(before - s3.funds == 7_500, "返済額が合わない: \(before - s3.funds)")
for _ in 0..<6 { s3.borrow() }
assert(s3.debt == 300_000, "上限を越えて借りられる: \(s3.debt)")
s3.funds = 1_000_000
s3.repay()
assert(s3.debt == 0 && s3.funds == 700_000, "返しきれない")
print("  借入 5万 → 1年後の残高 \(45_000)、上限 30万、一括返済 OK")

// --- 街区の結び。2×2 の同業種が L9 以上で結ばれ、住民が倍になる。1つ欠けると結ばれない。 ---
print("")
print("== 街区の結び ==")
let s4 = Simulation(seed: 4, generateTerrain: false)
s4.funds = 1_000_000
for x in 8...20 { s4.apply(.road, atX: x, y: 10) }
for (ox, oy) in [(10, 11), (13, 11), (10, 14), (13, 14)] { s4.apply(.residential, atX: ox + 1, y: oy + 1) }
for x in 10...15 { s4.apply(.road, atX: x, y: 17) }
s4.apply(.coalPlant, atX: 20, y: 13)
for x in 16...18 { s4.apply(.powerLine, atX: x, y: 12) }
s4.census()
let ids = s4.map.zones.indices.filter { s4.map.zones[$0].kind == .residential }.map { Int32($0) }
assert(ids.count == 4, "区画が4つでない: \(ids.count)")
for id in ids { s4.map.updateZone(id) { $0.level = 9 } }
s4.tick()
let single = 4 * 680
assert(s4.linkedZones.count == 4, "結ばれていない: \(s4.linkedZones)")
assert(s4.residents == single * 2, "住民が倍になっていない: \(s4.residents)")
s4.map.updateZone(ids[3]) { $0.level = 8 }
s4.tick()
assert(s4.linkedZones.isEmpty, "1つ欠けても結ばれている")
print("  4つ L9 → 結び 4 / 住民 \(single * 2)、1つ L8 → 結びなし")

// --- 大公園。工場の脇に置いたとき、小さな公園を9つ並べるより公害を減らし、地価を上げる。 ---
print("")
print("== 大公園 ==")
func parkTest(big: Bool) -> (pollution: Int, land: Int) {
    let s = Simulation(seed: 5, generateTerrain: false)
    s.funds = 1_000_000
    for x in 20...40 { s.apply(.road, atX: x, y: 30) }
    for cx in stride(from: 22, through: 31, by: 3) { s.apply(.industrial, atX: cx, y: 32) }
    s.apply(.coalPlant, atX: 38, y: 33)
    for x in 33...36 { s.apply(.powerLine, atX: x, y: 32) }
    s.apply(.residential, atX: 26, y: 26)
    if big {
        s.apply(.bigPark, atX: 30, y: 26)
    } else {
        for dy in -1...1 { for dx in -1...1 { s.apply(.park, atX: 30 + dx, y: 26 + dy) } }
    }
    for i in s.map.zones.indices where s.map.zones[i].kind == .industrial { s.map.updateZone(Int32(i)) { $0.level = 5 } }
    for _ in 1...24 { s.tick() }
    return (s.pollution.atTile(26, 26), s.landValue.atTile(26, 26))
}
let small = parkTest(big: false), large = parkTest(big: true)
print("  住宅のマス: 小公園×9 → 公害 \(small.pollution) 地価 \(small.land) / 大公園 → 公害 \(large.pollution) 地価 \(large.land)")
assert(large.pollution < small.pollution, "大公園のほうが公害が減っていない")
assert(large.land > small.land, "大公園のほうが地価が上がっていない")

// --- 上書き。公園の上に道路と区画を置ける。送電線の上に公園を置いても線は残る。 ---
print("")
print("== 上書き ==")
let s5 = Simulation(seed: 6, generateTerrain: false)
s5.funds = 100_000
for x in 10...14 { s5.apply(.powerLine, atX: x, y: 10) }
s5.apply(.park, atX: 12, y: 10)
assert(s5.map.tile(12, 10).wire && s5.map.tile(12, 10).structure == .park, "公園で送電線が消えた")
if case .built = s5.apply(.road, atX: 12, y: 10) {} else { assertionFailure("公園の上に道路が敷けない") }
assert(s5.map.tile(12, 10).structure == .road && s5.map.tile(12, 10).wire, "道路で送電線が消えた")
for dy in 0..<3 { for dx in 0..<3 { s5.apply(.park, atX: 20 + dx, y: 20 + dy) } }
if case .built = s5.apply(.residential, atX: 21, y: 21) {} else { assertionFailure("公園の上に区画が置けない") }
print("  公園→道路 OK、送電線が残る OK、公園×9→区画 OK")
