import Foundation

extension Simulation {

    /// 線路でつながった駅どうしを調べる。
    ///
    /// 電気と道路のある駅だけを数え、同じ線路に2つ以上の駅がある路線だけを使える路線にする。
    /// 通勤ではこの路線を使って駅から駅へ移り、駅の周りは地価が上がって道路が空く。
    func updateRail() {
        let w = CityMap.width, h = CityMap.height
        var line = [Int32](repeating: -1, count: w * h)
        var count: Int32 = 0
        var queue: [Int] = []
        for start in 0..<(w * h) where map.tiles[start].rail && line[start] < 0 {
            line[start] = count
            queue.removeAll(keepingCapacity: true)
            queue.append(start)
            var head = 0
            while head < queue.count {
                let i = queue[head]; head += 1
                let x = i % w, y = i / w
                for (nx, ny) in [(x, y - 1), (x + 1, y), (x, y + 1), (x - 1, y)] where map.inBounds(nx, ny) {
                    let j = ny * w + nx
                    if map.tiles[j].rail && line[j] < 0 { line[j] = count; queue.append(j) }
                }
            }
            count += 1
        }

        var stationsOnLine: [Int32: [Int32]] = [:]
        for id in map.zones.indices {
            let z = map.zones[id]
            guard z.alive, z.kind == .station, z.powered, z.hasRoad else { continue }
            var lines = Set<Int32>()
            forEachAround(z) { i in if line[i] >= 0 { lines.insert(line[i]) } }
            for l in lines { stationsOnLine[l, default: []].append(Int32(id)) }
        }

        var lineRoads: [[Int]] = []
        var roadLine: [Int: Int] = [:]
        var active = Set<Int32>()
        for stations in stationsOnLine.values where stations.count >= 2 {
            let n = lineRoads.count
            var roads: [Int] = []
            for sid in stations {
                active.insert(sid)
                forEachAround(map.zones[Int(sid)]) { i in
                    guard map.tiles[i].structure == .road else { return }
                    roads.append(i)
                    roadLine[i] = n
                }
            }
            lineRoads.append(roads)
        }
        railLineRoads = lineRoads
        railRoadLine = roadLine
        activeStations = active
    }

    /// 3×3 の敷地を囲む1周のマス。
    func forEachAround(_ z: Zone, _ body: (Int) -> Void) {
        let ox = Int(z.ox), oy = Int(z.oy)
        func visit(_ x: Int, _ y: Int) { if map.inBounds(x, y) { body(map.index(x, y)) } }
        for dx in -1...3 { visit(ox + dx, oy - 1); visit(ox + dx, oy + 3) }
        for dy in 0..<3 { visit(ox - 1, oy + dy); visit(ox + 3, oy + dy) }
    }
}
