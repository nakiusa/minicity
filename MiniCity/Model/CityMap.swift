import Foundation

/// 都市のマップ本体。タイル配列とゾーン一覧を持ち、変更されたタイルを描画側に伝える。
final class CityMap {
    static let width = 120
    static let height = 100

    private(set) var tiles: [Tile]
    private(set) var zones: [Zone]

    /// 前回の描画以降に書き換わったタイルの添字。
    private(set) var dirty: [Int] = []

    init() {
        tiles = Array(repeating: Tile(), count: CityMap.width * CityMap.height)
        zones = []
    }

    // MARK: - タイルへのアクセス

    @inline(__always)
    func index(_ x: Int, _ y: Int) -> Int { y * CityMap.width + x }

    @inline(__always)
    func inBounds(_ x: Int, _ y: Int) -> Bool {
        x >= 0 && y >= 0 && x < CityMap.width && y < CityMap.height
    }

    @inline(__always)
    func tile(_ x: Int, _ y: Int) -> Tile {
        guard inBounds(x, y) else { return Tile(terrain: .water) }
        return tiles[index(x, y)]
    }

    func setTile(_ x: Int, _ y: Int, _ t: Tile) {
        guard inBounds(x, y) else { return }
        let i = index(x, y)
        tiles[i] = t
        dirty.append(i)
    }

    /// タイルをその場で書き換える。書き換えた時点で描画対象になる。
    func mutateTile(_ x: Int, _ y: Int, _ body: (inout Tile) -> Void) {
        guard inBounds(x, y) else { return }
        let i = index(x, y)
        body(&tiles[i])
        dirty.append(i)
    }

    /// 描画に反映しない更新（電力・交通など、見た目に出ない値）用。
    @inline(__always)
    func mutateTileQuietly(_ i: Int, _ body: (inout Tile) -> Void) {
        body(&tiles[i])
    }

    func markDirty(_ x: Int, _ y: Int) {
        guard inBounds(x, y) else { return }
        dirty.append(index(x, y))
    }

    func clearDirty() { dirty.removeAll(keepingCapacity: true) }

    /// セーブデータからマップを丸ごと差し替える。
    func restore(tiles newTiles: [Tile], zones newZones: [Zone]) {
        guard newTiles.count == tiles.count else { return }
        tiles = newTiles
        zones = newZones
        markAllDirty()
    }

    func markAllDirty() {
        dirty = Array(0..<tiles.count)
    }

    // MARK: - ゾーン

    func zone(_ id: Int32) -> Zone? {
        let i = Int(id)
        guard i >= 0, i < zones.count, zones[i].alive else { return nil }
        return zones[i]
    }

    func updateZone(_ id: Int32, _ body: (inout Zone) -> Void) {
        let i = Int(id)
        guard i >= 0, i < zones.count else { return }
        body(&zones[i])
    }

    func forEachZone(_ body: (Int32, inout Zone) -> Void) {
        for i in zones.indices where zones[i].alive {
            body(Int32(i), &zones[i])
        }
    }

    /// 左上を (ox, oy) とする 3x3 のゾーンを置く。呼び出し側で用地を検査しておくこと。
    @discardableResult
    func addZone(kind: ZoneKind, ox: Int, oy: Int) -> Int32 {
        let id = Int32(zones.count)
        // 見た目のばらつきは置いた場所から決める。同じ都市を読み直しても絵が変わらない。
        // 4 通りに散らして、隣り合った同じレベルの区画が同じ絵にならないようにする。
        zones.append(Zone(kind: kind, ox: Int16(ox), oy: Int16(oy),
                          variant: UInt8(abs(ox &* 7 &+ oy &* 13) % Zone.variantCount)))
        for dy in 0..<3 {
            for dx in 0..<3 {
                mutateTile(ox + dx, oy + dy) { t in
                    t.terrain = .dirt
                    t.structure = .zone
                    t.zoneID = id
                    t.sub = UInt8(dy * 3 + dx)
                    t.wire = false
                }
            }
        }
        return id
    }

    /// ゾーンを消して更地に戻す。
    func removeZone(_ id: Int32) {
        let i = Int(id)
        guard i >= 0, i < zones.count, zones[i].alive else { return }
        let z = zones[i]
        zones[i].alive = false
        for dy in 0..<3 {
            for dx in 0..<3 {
                mutateTile(Int(z.ox) + dx, Int(z.oy) + dy) { t in
                    t.structure = .rubble
                    t.zoneID = -1
                    t.sub = 0
                    t.powered = false
                }
            }
        }
    }

    /// 3x3 のゾーンを置ける用地か。水面と既存の建造物を弾く。
    func canPlaceZone(ox: Int, oy: Int) -> Bool {
        guard inBounds(ox, oy), inBounds(ox + 2, oy + 2) else { return false }
        for dy in 0..<3 {
            for dx in 0..<3 {
                let t = tile(ox + dx, oy + dy)
                if t.terrain == .water { return false }
                if t.isOccupied { return false }
                if t.hasZone { return false }
            }
        }
        return true
    }

    /// 上下左右のうち道路がつながっている向きをビットで返す（1:北 2:東 4:南 8:西）。
    func roadMask(_ x: Int, _ y: Int) -> Int {
        var m = 0
        if tile(x, y - 1).structure == .road { m |= 1 }
        if tile(x + 1, y).structure == .road { m |= 2 }
        if tile(x, y + 1).structure == .road { m |= 4 }
        if tile(x - 1, y).structure == .road { m |= 8 }
        return m
    }

    /// 送電線の接続方向。発電所やゾーンの敷地も接続先として数える。
    func wireMask(_ x: Int, _ y: Int) -> Int {
        var m = 0
        if tile(x, y - 1).conducts { m |= 1 }
        if tile(x + 1, y).conducts { m |= 2 }
        if tile(x, y + 1).conducts { m |= 4 }
        if tile(x - 1, y).conducts { m |= 8 }
        return m
    }
}
