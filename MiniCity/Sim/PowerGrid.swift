import Foundation

extension Simulation {

    /// 発電所1つがまかなえる区画数。
    static let plantCapacity = 60

    /// 送電線とゾーン敷地をたどって、どの区画に電気が届くかを決める。
    ///
    /// 送電網は複数の島に分かれうるので、連結成分ごとに
    /// 「その島にある発電所の合計容量」と「その島の需要」を突き合わせる。
    /// 容量が足りない島では、たどり着いた順に電気が行き渡り、あとは停電する。
    func updatePower() {
        map.forEachZone { _, z in z.powered = false }

        let w = CityMap.width, h = CityMap.height
        var visited = [Bool](repeating: false, count: w * h)
        var queue: [Int] = []
        queue.reserveCapacity(512)

        for start in 0..<(w * h) {
            guard !visited[start], map.tiles[start].conducts else { continue }

            // ひとつの連結成分を洗い出す。
            var component: [Int] = []
            var zoneOrder: [Int32] = []
            var seenZones = Set<Int32>()

            visited[start] = true
            queue.removeAll(keepingCapacity: true)
            queue.append(start)
            var head = 0

            while head < queue.count {
                let i = queue[head]; head += 1
                component.append(i)

                let zid = map.tiles[i].zoneID
                if zid >= 0, seenZones.insert(zid).inserted {
                    zoneOrder.append(zid)
                }

                let x = i % w, y = i / w
                if x > 0 { visit(i - 1, &visited, &queue) }
                if x < w - 1 { visit(i + 1, &visited, &queue) }
                if y > 0 { visit(i - w, &visited, &queue) }
                if y < h - 1 { visit(i + w, &visited, &queue) }
            }

            // この島の供給量。
            var capacity = 0
            for zid in zoneOrder where map.zone(zid)?.kind == .coalPlant {
                capacity += Simulation.plantCapacity
            }

            // 発電所は自前で動く。残りを先着順に配る。
            var remaining = capacity
            for zid in zoneOrder {
                guard let z = map.zone(zid) else { continue }
                if z.kind == .coalPlant {
                    map.updateZone(zid) { $0.powered = true }
                    continue
                }
                // 更地のゾーンは電気を食わないが、電気が来ていることは記録する。
                let consumes = z.kind.grows ? (z.level > 0) : true
                if !consumes {
                    map.updateZone(zid) { $0.powered = capacity > 0 }
                    continue
                }
                if remaining > 0 {
                    remaining -= 1
                    map.updateZone(zid) { $0.powered = true }
                }
            }

            // 電力オーバーレイのために、通電している島のタイルに印を付ける。
            let energized = capacity > 0
            for i in component {
                map.mutateTileQuietly(i) { $0.powered = energized }
            }
        }
    }

    @inline(__always)
    private func visit(_ i: Int, _ visited: inout [Bool], _ queue: inout [Int]) {
        guard !visited[i], map.tiles[i].conducts else { return }
        visited[i] = true
        queue.append(i)
    }
}
