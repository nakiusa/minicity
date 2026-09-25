import Foundation

/// 画面下のパレットに並ぶ道具。
enum Tool: String, CaseIterable, Identifiable {
    case pan
    case inspect
    case bulldozer
    case road
    case avenue
    case powerLine
    case park
    case bigPark
    case residential
    case commercial
    case industrial
    case coalPlant
    case police
    case fire

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pan: return String(localized: "移動")
        case .inspect: return String(localized: "調べる")
        case .bulldozer: return String(localized: "撤去")
        case .road: return String(localized: "道路")
        case .avenue: return String(localized: "大通り")
        case .powerLine: return String(localized: "送電線")
        case .park: return String(localized: "公園")
        case .bigPark: return String(localized: "大公園")
        case .residential: return String(localized: "住宅地")
        case .commercial: return String(localized: "商業地")
        case .industrial: return String(localized: "工業地")
        case .coalPlant: return String(localized: "発電所")
        case .police: return String(localized: "警察署")
        case .fire: return String(localized: "消防署")
        }
    }

    var symbol: String {
        switch self {
        case .pan: return "hand.draw.fill"
        case .inspect: return "magnifyingglass"
        case .bulldozer: return "hammer.fill"
        case .road: return "road.lanes"
        case .avenue: return "road.lanes.curved.right"
        case .powerLine: return "bolt.fill"
        case .park: return "tree.fill"
        case .bigPark: return "leaf.fill"
        case .residential: return "house.fill"
        case .commercial: return "building.2.fill"
        case .industrial: return "gearshape.fill"
        case .coalPlant: return "flame.fill"
        case .police: return "shield.lefthalf.filled"
        case .fire: return "flame.circle.fill"
        }
    }

    /// 値段。同じジャンルの古い名作と同じ数字（1・5・10・100・500・3000）にならないようにずらしてある。
    var cost: Int {
        switch self {
        case .pan, .inspect: return 0
        case .bulldozer: return 2
        case .road: return 25
        case .avenue: return 90
        case .powerLine: return 6
        case .park: return 15
        case .bigPark: return 400
        case .residential, .commercial, .industrial: return 120
        case .coalPlant: return 2800
        case .police, .fire: return 450
        }
    }

    /// 水面に架ける場合の割増。橋と海底ケーブルは高い。
    var waterCost: Int? {
        switch self {
        case .road: return 120
        case .avenue: return 320
        case .powerLine: return 25
        default: return nil
        }
    }

    /// 触っても都市を書き換えない道具。1本指のドラッグで地図を動かせる。
    var movesCamera: Bool { self == .pan || self == .inspect }

    /// 一辺のタイル数。
    var footprint: Int {
        switch self {
        case .residential, .commercial, .industrial, .coalPlant, .police, .fire, .bigPark: return 3
        default: return 1
        }
    }

    /// なぞって連続で置ける道具か。
    var isDraggable: Bool {
        switch self {
        case .road, .avenue, .powerLine, .bulldozer, .park: return true
        default: return false
        }
    }

    var zoneKind: ZoneKind? {
        switch self {
        case .residential: return .residential
        case .commercial: return .commercial
        case .industrial: return .industrial
        case .coalPlant: return .coalPlant
        case .police: return .police
        case .fire: return .fire
        case .bigPark: return .bigPark
        default: return nil
        }
    }
}

enum BuildResult {
    case built(cost: Int)
    case nothingToDo
    case insufficientFunds(needed: Int)
    case blocked(String)
}

extension Simulation {

    /// 道具をタイルに適用する。3x3 の道具では (x, y) が中心になる。
    @discardableResult
    func apply(_ tool: Tool, atX x: Int, y: Int) -> BuildResult {
        switch tool {
        case .pan, .inspect:
            return .nothingToDo
        case .bulldozer:
            return bulldoze(x, y)
        case .road:
            return buildRoad(x, y, avenue: false)
        case .avenue:
            return buildRoad(x, y, avenue: true)
        case .powerLine:
            return buildWire(x, y)
        case .park:
            return buildPark(x, y)
        default:
            guard let kind = tool.zoneKind else { return .nothingToDo }
            return buildZone(kind, centerX: x, centerY: y, cost: tool.cost)
        }
    }

    // MARK: - 個別の処理

    private func charge(_ amount: Int) -> Bool {
        guard funds >= amount else { return false }
        funds -= amount
        return true
    }

    private func bulldoze(_ x: Int, _ y: Int) -> BuildResult {
        guard map.inBounds(x, y) else { return .nothingToDo }
        let t = map.tile(x, y)

        let hasSomething = t.hasZone || t.structure != .none || t.wire || t.terrain == .forest
        guard hasSomething else { return .nothingToDo }
        guard charge(1) else { return .insufficientFunds(needed: 1) }

        if t.hasZone {
            map.removeZone(t.zoneID)
        } else {
            map.mutateTile(x, y) { tile in
                tile.wire = false
                tile.isAvenue = false
                if tile.structure != .none {
                    tile.structure = tile.terrain == .water ? .none : .rubble
                } else if tile.terrain == .forest {
                    tile.terrain = .dirt
                }
            }
        }
        refreshNeighbors(x, y)
        return .built(cost: 1)
    }

    /// 道路を敷く。`avenue` が真なら大通りにする。
    /// すでに道路があるマスに別の等級を指定したときは、敷き直しとして扱う。
    private func buildRoad(_ x: Int, _ y: Int, avenue: Bool) -> BuildResult {
        guard map.inBounds(x, y) else { return .nothingToDo }
        let t = map.tile(x, y)
        guard t.structure != .road || t.isAvenue != avenue else { return .nothingToDo }
        guard !t.hasZone else { return .blocked(String(localized: "区画の上には敷けません")) }
        // 小さな公園の上にはそのまま敷ける。いちいち撤去させるほどのものではない。

        let tool: Tool = avenue ? .avenue : .road
        let cost = t.terrain == .water ? (tool.waterCost ?? tool.cost) : tool.cost
        guard charge(cost) else { return .insufficientFunds(needed: cost) }

        map.mutateTile(x, y) { tile in
            if tile.terrain == .forest { tile.terrain = .dirt }
            tile.structure = .road
            tile.isAvenue = avenue
        }
        refreshNeighbors(x, y)
        return .built(cost: cost)
    }

    private func buildWire(_ x: Int, _ y: Int) -> BuildResult {
        guard map.inBounds(x, y) else { return .nothingToDo }
        let t = map.tile(x, y)
        guard !t.wire else { return .nothingToDo }
        guard !t.hasZone else { return .blocked(String(localized: "区画はもともと電気を通します")) }

        let cost = t.terrain == .water ? (Tool.powerLine.waterCost ?? 25) : Tool.powerLine.cost
        guard charge(cost) else { return .insufficientFunds(needed: cost) }

        map.mutateTile(x, y) { tile in
            if tile.terrain == .forest { tile.terrain = .dirt }
            tile.wire = true
        }
        refreshNeighbors(x, y)
        return .built(cost: cost)
    }

    private func buildPark(_ x: Int, _ y: Int) -> BuildResult {
        guard map.inBounds(x, y) else { return .nothingToDo }
        let t = map.tile(x, y)
        guard t.terrain != .water else { return .blocked(String(localized: "水面には置けません")) }
        guard !t.hasZone, t.structure != .road, t.structure != .park else {
            return .blocked(String(localized: "その場所はふさがっています"))
        }
        guard charge(Tool.park.cost) else { return .insufficientFunds(needed: Tool.park.cost) }

        // 送電線の上に公園を置いても、線は残す。消えると気づきにくく、停電の原因になる。
        map.mutateTile(x, y) { tile in
            tile.terrain = .dirt
            tile.structure = .park
        }
        refreshNeighbors(x, y)
        return .built(cost: Tool.park.cost)
    }

    private func buildZone(_ kind: ZoneKind, centerX: Int, centerY: Int, cost: Int) -> BuildResult {
        let ox = centerX - 1, oy = centerY - 1
        guard map.canPlaceZone(ox: ox, oy: oy) else {
            return .blocked(String(localized: "3x3 の空き地が必要です"))
        }
        guard charge(cost) else { return .insufficientFunds(needed: cost) }

        map.addZone(kind: kind, ox: ox, oy: oy)
        for dy in -1...3 {
            for dx in -1...3 {
                map.markDirty(ox + dx, oy + dy)
            }
        }
        return .built(cost: cost)
    }

    /// 道路と送電線は隣とつながって見た目が変わるので、周囲も描き直させる。
    private func refreshNeighbors(_ x: Int, _ y: Int) {
        map.markDirty(x - 1, y)
        map.markDirty(x + 1, y)
        map.markDirty(x, y - 1)
        map.markDirty(x, y + 1)
    }
}
