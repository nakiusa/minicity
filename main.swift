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
