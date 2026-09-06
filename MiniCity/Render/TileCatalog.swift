import SpriteKit

/// 起動時にタイル絵をすべて作って SKTileSet にまとめておく。
/// 画像アセットを持たず、絵はコードから生成する。
final class TileCatalog {

    let tileSet: SKTileSet
    private var groups: [String: SKTileGroup] = [:]
    /// マスの外へ伸びる高層タワーは、タイルではなく1枚のスプライトとして持つ。
    private var towerTextures: [String: SKTexture] = [:]

    static let landVariants = 4
    static let waterVariants = 3
    static let forestVariants = 3
    /// 区画ごとの見た目の種類。形は2通り、壁の色は4通りなので、
    /// 組み合わせは 8 通りになる。増やすとテクスチャの生成数も比例して増える。
    static let buildingVariants = 4

    init() {
        var all: [SKTileGroup] = []
        var dict: [String: SKTileGroup] = [:]

        func register(_ key: String, _ canvas: PixelCanvas) {
            guard let image = canvas.cgImage() else { return }
            let texture = SKTexture(cgImage: image)
            texture.filteringMode = .nearest
            let definition = SKTileDefinition(texture: texture,
                                              size: CGSize(width: TileArt.tileSize,
                                                           height: TileArt.tileSize))
            let group = SKTileGroup(tileDefinition: definition)
            group.name = key
            dict[key] = group
            all.append(group)
        }

        /// 48x48 の建物を 16x16 の9枚に割って、それぞれ別のタイルとして登録する。
        func registerZone(_ prefix: String, _ canvas: PixelCanvas) {
            for (sub, piece) in canvas.slice(cols: 3, rows: 3).enumerated() {
                register("\(prefix).\(sub)", piece)
            }
        }

        /// 複数コマを1つのタイルにまとめて、SpriteKit にループ再生させる。
        /// タイルを差し替えなくても勝手に動くので、毎フレームの処理は増えない。
        func registerAnimated(_ key: String, _ frames: [PixelCanvas], secondsPerFrame: TimeInterval) {
            let textures = frames.compactMap { canvas -> SKTexture? in
                guard let image = canvas.cgImage() else { return nil }
                let texture = SKTexture(cgImage: image)
                texture.filteringMode = .nearest
                return texture
            }
            guard !textures.isEmpty else { return }
            let definition = SKTileDefinition(textures: textures,
                                              size: CGSize(width: TileArt.tileSize,
                                                           height: TileArt.tileSize),
                                              timePerFrame: secondsPerFrame)
            let group = SKTileGroup(tileDefinition: definition)
            group.name = key
            dict[key] = group
            all.append(group)
        }

        for v in 0..<TileCatalog.landVariants { register("land.\(v)", TileArt.land(variant: v)) }
        for v in 0..<TileCatalog.waterVariants { register("water.\(v)", TileArt.water(variant: v)) }
        for v in 0..<TileCatalog.forestVariants { register("forest.\(v)", TileArt.forest(variant: v)) }
        register("rubble", TileArt.rubble())
        register("park", TileArt.park())
        register("marker.power", TileArt.powerMarker())
        register("marker.road", TileArt.roadMarker())

        for mask in 0..<16 {
            register("road.\(mask)", TileArt.road(mask: mask))
            register("avenue.\(mask)", TileArt.avenue(mask: mask))
            register("wire.\(mask)", TileArt.wire(mask: mask))
            for level in 1...2 {
                let frames = (0..<TileArt.trafficFrameCount).map {
                    TileArt.trafficCars(mask: mask, level: level, frame: $0)
                }
                registerAnimated("traffic.\(mask).\(level)", frames, secondsPerFrame: 0.35)
            }
        }

        for kind in [ZoneKind.residential, .commercial, .industrial] {
            registerZone("z.\(kind.rawValue).0.0", TileArt.emptyLot(kind: kind))
            for level in 1...Zone.maxLevel {
                for variant in 0..<TileCatalog.buildingVariants {
                    registerZone("z.\(kind.rawValue).\(level).\(variant)",
                                 TileArt.zoneArt(kind: kind, level: level, variant: variant))
                }
            }
        }
        for kind in [ZoneKind.coalPlant, .police, .fire] {
            registerZone("z.\(kind.rawValue).0.0", TileArt.zoneArt(kind: kind, level: 0, variant: 0))
        }

        // 高層タワー（住宅・商業の高レベル）。足元の地面はタイルとして、
        // 上へ伸びる本体はスプライト用のテクスチャとして別々に用意する。
        for kind in [ZoneKind.residential, .commercial] {
            for variant in 0..<TileCatalog.buildingVariants {
                registerZone("zg.\(kind.rawValue).\(variant)",
                             TileArt.zoneGroundArt(kind: kind, variant: variant))
                for level in TileArt.towerMinLevel...Zone.maxLevel {
                    let canvas = TileArt.towerSprite(kind: kind, level: level, variant: variant)
                    if let image = canvas.cgImage() {
                        let texture = SKTexture(cgImage: image)
                        texture.filteringMode = .nearest
                        towerTextures["tower.\(kind.rawValue).\(level).\(variant)"] = texture
                    }
                }
            }
        }

        groups = dict
        tileSet = SKTileSet(tileGroups: all, tileSetType: .grid)
    }

    func group(_ key: String) -> SKTileGroup? { groups[key] }
    func towerTexture(_ key: String) -> SKTexture? { towerTextures[key] }

    /// 上に伸びるタワーとして描く区画か（住宅・商業の高レベルだけ）。
    static func isTowerZone(_ kind: ZoneKind, level: Int) -> Bool {
        (kind == .residential || kind == .commercial) && level >= TileArt.towerMinLevel
    }

    // MARK: - タイルからキーを引く

    func terrainKey(_ tile: Tile, x: Int, y: Int) -> String {
        let h = abs(x &* 7 &+ y &* 13 &+ x &* y)
        switch tile.terrain {
        case .dirt: return "land.\(h % TileCatalog.landVariants)"
        case .water: return "water.\(h % TileCatalog.waterVariants)"
        case .forest: return "forest.\(h % TileCatalog.forestVariants)"
        }
    }

    func structureKey(_ tile: Tile, x: Int, y: Int, map: CityMap) -> String? {
        if tile.hasZone, let z = map.zone(tile.zoneID) {
            // 高層タワーはタイルには地面だけ置き、本体はスプライト層が描く。
            if TileCatalog.isTowerZone(z.kind, level: Int(z.level)) {
                return "zg.\(z.kind.rawValue).\(z.variant).\(tile.sub)"
            }
            let level = z.kind.grows ? Int(z.level) : 0
            let variant = (z.kind.grows && z.level > 0) ? Int(z.variant) : 0
            return "z.\(z.kind.rawValue).\(level).\(variant).\(tile.sub)"
        }
        switch tile.structure {
        case .road:
            return "\(tile.isAvenue ? "avenue" : "road").\(map.roadMask(x, y))"
        case .park: return "park"
        case .rubble: return "rubble"
        case .none, .zone: return nil
        }
    }

    func wireKey(_ tile: Tile, x: Int, y: Int, map: CityMap) -> String? {
        guard tile.wire else { return nil }
        return "wire.\(map.wireMask(x, y))"
    }

    /// 渋滞していない道路には車を出さない（0）。
    /// しきい値はヘッドレスの検証都市で、道路タイルのだいたい下3分の1が
    /// 混みはじめ・上1割弱が詰まる、くらいの分布になるよう選んだ。
    static func trafficLevel(_ raw: Int) -> Int {
        if raw >= 40 { return 2 }
        if raw >= 8 { return 1 }
        return 0
    }

    func trafficKey(_ tile: Tile, x: Int, y: Int, map: CityMap) -> String? {
        guard tile.structure == .road else { return nil }
        let level = TileCatalog.trafficLevel(Int(tile.traffic))
        guard level > 0 else { return nil }
        return "traffic.\(map.roadMask(x, y)).\(level)"
    }
}
