import Foundation

/// 地形。建物を置ける・置けないの判定と、土地価値の下地になる。
enum Terrain: UInt8, Codable {
    case dirt = 0
    case water = 1
    case forest = 2

    var isBuildable: Bool { self != .water }
}

/// タイルの上に載っているもの。ゾーンの一部かどうかは `Tile.zoneID` で見る。
enum Structure: UInt8, Codable {
    case none = 0
    case rubble = 1
    case road = 2
    case park = 3
    case zone = 4
}

/// ゾーンの種類。R/C/I は成長し、残りは施設として置くだけ。
enum ZoneKind: UInt8, CaseIterable, Codable {
    case residential = 0
    case commercial = 1
    case industrial = 2
    case coalPlant = 3
    case police = 4
    case fire = 5

    /// 需要に応じて育つゾーンか。
    var grows: Bool {
        self == .residential || self == .commercial || self == .industrial
    }

    var name: String {
        switch self {
        case .residential: return "住宅"
        case .commercial: return "商業"
        case .industrial: return "工業"
        case .coalPlant: return "火力発電所"
        case .police: return "警察署"
        case .fire: return "消防署"
        }
    }
}

/// マップ1マス。3x3 ゾーンに属する場合は `zoneID` と `sub`（0..8）で位置がわかる。
struct Tile: Codable {
    var terrain: Terrain = .dirt
    var structure: Structure = .none
    var wire: Bool = false
    var sub: UInt8 = 0
    var traffic: UInt8 = 0
    var powered: Bool = false
    var zoneID: Int32 = -1

    var hasZone: Bool { zoneID >= 0 }

    /// 電気を通すか。送電線と、ゾーンの敷地そのもの。
    var conducts: Bool { wire || zoneID >= 0 }

    /// 何か建っているか（更地でないか）。
    var isOccupied: Bool { structure != .none && structure != .rubble }
}

/// 3x3 の区画ひとつ。左上を原点として持つ。
struct Zone: Codable {
    var kind: ZoneKind
    var ox: Int16
    var oy: Int16
    /// 0 は更地。1...Zone.maxLevel が建物のグレード。
    var level: UInt8 = 0
    var variant: UInt8 = 0
    var powered: Bool = false
    var hasRoad: Bool = false
    /// 道路をたどって職場（C/I）に届くか。住宅ゾーンでのみ意味を持つ。
    var hasJobAccess: Bool = false
    var alive: Bool = true

    /// 建物の段階。0 は更地で、1 から順に大きくなる。
    /// 段を細かくしてあるのは、育ったことが見た目でわかるようにするため。
    static let maxLevel = 10

    /// 区画ごとの見た目の種類。描画側の `TileCatalog.buildingVariants` と揃える。
    /// モデル側にも持たせてあるのは、セーブデータに入る値の範囲を決めるのが
    /// ここだからで、描画を読み込まないヘッドレスの検証でも同じ値になる。
    static let variantCount = 4

    /// このゾーンが抱える住民または雇用の数。
    var capacity: Int {
        guard level > 0 else { return 0 }
        let i = Int(level)
        switch kind {
        case .residential: return [0, 8, 18, 36, 70, 120, 190, 300, 460, 680, 980][i]
        case .commercial: return [0, 6, 14, 28, 52, 88, 140, 220, 330, 480, 680][i]
        case .industrial: return [0, 8, 18, 36, 70, 118, 185, 290, 440, 650, 930][i]
        default: return 0
        }
    }
}
