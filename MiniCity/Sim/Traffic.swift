import Foundation

extension Simulation {

    /// 道路をたどる探索の打ち切り（たどる道路のマス数）。職場が近くで埋まっても
    /// 街の反対側まで通えるだけの広さにし、それより遠い通勤は諦めさせる。
    static let commuteSearchLimit = 2_000

    /// 各ゾーンが道路に面しているかを調べる。
    func updateRoadAccess() {
        for id in map.zones.indices {
            guard map.zones[id].alive else { continue }
            let z = map.zones[id]
            let touches = zoneTouchesRoad(ox: Int(z.ox), oy: Int(z.oy))
            map.updateZone(Int32(id)) { $0.hasRoad = touches }
        }
    }

    /// 3x3 の外周のどこかに道路が接しているか。
    private func zoneTouchesRoad(ox: Int, oy: Int) -> Bool {
        for dx in -1...3 {
            if map.tile(ox + dx, oy - 1).structure == .road { return true }
            if map.tile(ox + dx, oy + 3).structure == .road { return true }
        }
        for dy in 0..<3 {
            if map.tile(ox - 1, oy + dy).structure == .road { return true }
            if map.tile(ox + 3, oy + dy).structure == .road { return true }
        }
        return false
    }

    /// 住宅の働き手を、道路をたどって近い職場から順に割り振り、通った道に交通量を積む。
    ///
    /// 職場ごとに雇える数（区画の雇用）に限りがあり、近い職場が埋まれば、残りは遠くまで通う。
    /// 住宅から遠い工業地しかなければ、その間の道に通勤の車が集まって混む。
    /// 職場にひとつも届かない住宅は職に就けず、成長が止まる。
    func updateTraffic() {
        let w = CityMap.width, h = CityMap.height
        let cellCount = w * h

        for i in 0..<cellCount {
            map.mutateTileQuietly(i) { $0.traffic = 0 }
        }

        // 職場ごとの空き。
        var jobsLeft = [Int](repeating: 0, count: map.zones.count)
        for id in map.zones.indices {
            let z = map.zones[id]
            guard z.alive, z.kind == .commercial || z.kind == .industrial else { continue }
            jobsLeft[id] = headcount(z, id: Int32(id))
        }

        var stamp = [Int32](repeating: 0, count: cellCount)
        var parent = [Int32](repeating: -1, count: cellCount)
        var queue = [Int]()
        queue.reserveCapacity(Simulation.commuteSearchLimit + 8)
        var generation: Int32 = 0

        // ponytail: 区画の番号順に割り振るので、先に建った住宅ほど近い職場を取る。偏りが目立てば順番を毎月まわす。
        for id in map.zones.indices {
            let z = map.zones[id]
            guard z.alive, z.kind == .residential, z.level > 0 else { continue }
            guard z.hasRoad else {
                map.updateZone(Int32(id)) { $0.hasJobAccess = false }
                continue
            }

            generation += 1
            queue.removeAll(keepingCapacity: true)

            // 敷地に接している道路を出発点にする。
            let ox = Int(z.ox), oy = Int(z.oy)
            for dx in -1...3 {
                seedRoad(ox + dx, oy - 1, generation, &stamp, &parent, &queue)
                seedRoad(ox + dx, oy + 3, generation, &stamp, &parent, &queue)
            }
            for dy in 0..<3 {
                seedRoad(ox - 1, oy + dy, generation, &stamp, &parent, &queue)
                seedRoad(ox + 3, oy + dy, generation, &stamp, &parent, &queue)
            }

            // 住民の半分が働きに出る。需要の計算と同じ割合。
            var workers = headcount(z, id: Int32(id)) / 2
            var reached = false
            var head = 0

            while head < queue.count && head < Simulation.commuteSearchLimit && workers > 0 {
                let i = queue[head]; head += 1

                for zid in workplaces(touching: i) {
                    reached = true
                    let take = min(workers, jobsLeft[zid])
                    guard take > 0 else { continue }
                    workers -= take
                    jobsLeft[zid] -= take
                    // 6人で1台ぶん。遠い職場ほど長い道のりに車が並ぶ。
                    let load = max(1, take / 6)
                    var cur = i
                    while cur >= 0 {
                        map.mutateTileQuietly(cur) {
                            $0.traffic = UInt8(min(255, Int($0.traffic) + load))
                        }
                        cur = Int(parent[cur])
                    }
                    if workers == 0 { break }
                }

                let x = i % w, y = i / w
                if x > 0 { pushRoad(i - 1, from: i, generation, &stamp, &parent, &queue) }
                if x < w - 1 { pushRoad(i + 1, from: i, generation, &stamp, &parent, &queue) }
                if y > 0 { pushRoad(i - w, from: i, generation, &stamp, &parent, &queue) }
                if y < h - 1 { pushRoad(i + w, from: i, generation, &stamp, &parent, &queue) }
            }

            map.updateZone(Int32(id)) { $0.hasJobAccess = reached }
        }

        // 街区ごとの混み具合は、道路の本数ではなく1本あたりの混雑で測る。
        // 合計にすると幹線が1本あるだけで振り切れてしまい、差が読めなくなる。
        trafficMap.clear()
        var roadCells = CoarseMap()
        for y in 0..<h {
            for x in 0..<w {
                guard map.tiles[y * w + x].structure == .road else { continue }
                trafficMap.addAtTile(x, y, Int(map.tiles[y * w + x].traffic))
                roadCells.addAtTile(x, y, 1)
            }
        }
        for cy in 0..<CoarseMap.height {
            for cx in 0..<CoarseMap.width {
                let n = roadCells[cx, cy]
                trafficMap[cx, cy] = n > 0 ? trafficMap[cx, cy] / n : 0
            }
        }
        trafficMap.clamp(0, 255)
    }

    // MARK: - 探索の小道具

    @inline(__always)
    private func seedRoad(_ x: Int, _ y: Int, _ gen: Int32,
                          _ stamp: inout [Int32], _ parent: inout [Int32], _ queue: inout [Int]) {
        guard map.inBounds(x, y) else { return }
        let i = map.index(x, y)
        guard map.tiles[i].structure == .road, stamp[i] != gen else { return }
        stamp[i] = gen
        parent[i] = -1
        queue.append(i)
    }

    @inline(__always)
    private func pushRoad(_ i: Int, from: Int, _ gen: Int32,
                          _ stamp: inout [Int32], _ parent: inout [Int32], _ queue: inout [Int]) {
        guard map.tiles[i].structure == .road, stamp[i] != gen else { return }
        stamp[i] = gen
        parent[i] = Int32(from)
        queue.append(i)
    }

    /// この道路タイルの隣にある、育った商業か工業の区画の番号。
    private func workplaces(touching i: Int) -> [Int] {
        let w = CityMap.width
        let x = i % w, y = i / w
        var found: [Int] = []
        for (dx, dy) in [(0, -1), (1, 0), (0, 1), (-1, 0)] {
            let nx = x + dx, ny = y + dy
            guard map.inBounds(nx, ny) else { continue }
            let zid = Int(map.tiles[map.index(nx, ny)].zoneID)
            guard zid >= 0, !found.contains(zid) else { continue }
            let z = map.zones[zid]
            guard z.alive, z.level > 0, z.kind == .commercial || z.kind == .industrial else { continue }
            found.append(zid)
        }
        return found
    }
}
