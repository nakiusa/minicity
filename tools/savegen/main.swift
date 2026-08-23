import Foundation

// スクリーンショット用の都市を作って、アプリが読むセーブデータとして書き出す。
// 手で街を建てると何百回もタップすることになるので、同じ計算をここでやってしまう。

let seed: UInt64 = CommandLine.arguments.count > 2 ? (UInt64(CommandLine.arguments[2]) ?? 7) : 7
let sim = Simulation(seed: seed, generateTerrain: true)
sim.funds = 250_000

/// 水面を避けて置く。地形の上に街を敷くので、置けない場所は黙って飛ばす。
@discardableResult
func put(_ tool: Tool, _ x: Int, _ y: Int) -> Bool {
    if case .built = sim.apply(tool, atX: x, y: y) { return true }
    return false
}

// 中心のあたりに碁盤の目を敷く。縦横の幹線を先に通してから区画を埋める。
let x0 = 34, x1 = 86, y0 = 26, y1 = 74
for y in stride(from: y0, through: y1, by: 8) {
    for x in x0...x1 { put(.road, x, y) }
}
for x in stride(from: x0, through: x1, by: 12) {
    for y in y0...y1 { put(.road, x, y) }
}

// 送電線は街路の上に重ねて引く。区画は街路に面しているので、
// 街路さえ通電していればその両側の区画に電気が回る。
// 区画から離れた場所に柱を立てても、あいだが空いて何も届かない。
for roadY in stride(from: y0, through: y1, by: 8) {
    for x in x0...(x1 + 5) { put(.powerLine, x, roadY) }
}
// 横の街路どうしを縦で1本つなぐ。これがないと街路ごとに島が分かれる。
for y in y0...y1 { put(.powerLine, x0, y) }
for y in y0...(y1 + 6) { put(.powerLine, x1 + 5, y) }

// 北を住宅、中央を商業、南を工業にする。工業と住宅のあいだは距離を取る。
func fill(_ tool: Tool, rows: [Int]) {
    for roadY in rows {
        var cx = x0 + 2
        while cx <= x1 - 1 {
            if (cx - x0) % 12 != 0 {
                put(tool, cx, roadY - 2)
                put(tool, cx, roadY + 2)
            }
            cx += 3
        }
    }
}
fill(.residential, rows: [26, 34])
fill(.commercial, rows: [42, 50])
fill(.industrial, rows: [66, 74])

// 街路のあいだの空きを公園にする。緑があると絵として締まるし、地価も上がる。
for y in [30, 38, 46] {
    for x in stride(from: x0 + 1, through: x1 - 1, by: 2) { put(.park, x, y) }
}

// 警察と消防を住宅・商業に行き渡らせる。
for y in stride(from: y0 + 2, through: 54, by: 8) { put(.police, x1 + 3, y) }
for y in stride(from: y0 + 6, through: 54, by: 8) { put(.fire, x1 + 3, y) }
for y in (y0 - 2)...(y1 + 2) { put(.powerLine, x1 + 5, y) }

// 施設の列にも街路を通す。通しておかないと警察と消防が「道路に面していない」
// 扱いになり、HUD に警告が出たままになる。
for y in (y0 - 2)...(y1 + 6) { put(.road, x1 + 1, y) }

// 発電所は工業側の風下へまとめる。
for i in 0..<4 { put(.coalPlant, x1 + 3, 62 + i * 5) }

// 地形の都合で街路に届かなかった住宅・商業・工業を片付ける。
// 残しておくと HUD に警告が出たままになる。
// 消すのは育つ区画だけにする。発電所は街路の外に置いてあるので、
// ここで一緒に消すと街から電気が消える。
sim.updateRoadAccess()
for i in sim.map.zones.indices
where sim.map.zones[i].alive && sim.map.zones[i].kind.grows && !sim.map.zones[i].hasRoad {
    sim.map.removeZone(Int32(i))
}
sim.census()
for _ in 1...700 { sim.tick() }

var counts = Array(repeating: 0, count: Zone.maxLevel + 1)
for z in sim.map.zones where z.alive && z.kind.grows { counts[Int(z.level)] += 1 }
print("人口 \(sim.residents) 雇用 \(sim.jobs) 資金 \(sim.funds) 年 \(sim.year)")
print("停電 \(sim.unpoweredZones) 道路なし \(sim.disconnectedZones) 警告 \(sim.warnings)")
print("レベル分布 " + counts.enumerated().map { "L\($0.offset):\($0.element)" }.joined(separator: " "))

let save = CitySave(tiles: sim.map.tiles, zones: sim.map.zones,
                    funds: sim.funds, taxRate: sim.taxRate, monthsElapsed: sim.monthsElapsed)
let encoder = PropertyListEncoder()
encoder.outputFormat = .binary
try encoder.encode(save).write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("wrote \(CommandLine.arguments[1])")
