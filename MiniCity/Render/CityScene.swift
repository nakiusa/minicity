import SpriteKit

enum OverlayMode: String, CaseIterable, Identifiable {
    case none, power, pollution, landValue, crime, traffic, density

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "通常"
        case .power: return "電力"
        case .pollution: return "公害"
        case .landValue: return "土地価値"
        case .crime: return "犯罪"
        case .traffic: return "交通量"
        case .density: return "人口密度"
        }
    }
}

/// マップの描画とカメラ操作を受け持つ。
/// シミュレーションの状態は読むだけで、書き換えは `onPaint` 経由で外に投げる。
final class CityScene: SKScene {

    static let tileSide: CGFloat = CGFloat(TileArt.tileSize)
    static let minScale: CGFloat = 0.4
    static let maxScale: CGFloat = 3.2
    static let defaultScale: CGFloat = 1.5

    private let catalog = TileCatalog()
    private var terrainLayer: SKTileMapNode!
    private var structureLayer: SKTileMapNode!
    private var wireLayer: SKTileMapNode!
    private var trafficLayer: SKTileMapNode!
    private var markerLayer: SKTileMapNode!
    /// 高層タワーを載せる層。タイルの外へはみ出せるよう、スプライトを直接ぶら下げる。
    private var towerLayer: SKNode!
    /// ゾーンごとのタワースプライト。育つ・消えるに合わせて足し引きする。
    private var towerSprites: [Int32: SKSpriteNode] = [:]
    private var overlaySprite: SKSpriteNode!
    private var highlight: SKShapeNode!

    /// いま印を出しているタイル。消す対象を知るために覚えておく。
    private var markedTiles: Set<Int> = []

    /// 道路タイルの添字。渋滞の車を毎か月ぶん見直すのに、道路だけを見れば済むようにする。
    /// タイルの交通量は `dirty` に乗らない（見た目に出ない値の更新として扱っている）ので、
    /// 電力や道路の印と同じく、この集合を自前でたどって直す。
    private var roadTiles: Set<Int> = []
    /// 直前に車を出した渋滞の段階。変化した場所だけ描き直す。
    private var trafficLevels: [Int: Int] = [:]

    let cam = SKCameraNode()

    weak var sim: Simulation?
    /// タイル座標を渡して、そこに道具を適用させる。
    var onPaint: ((Int, Int) -> Void)?
    /// 3x3 の道具のときは 3。カーソルの大きさに使う。
    var footprint: Int = 1 {
        didSet { updateHighlightSize() }
    }
    var overlayMode: OverlayMode = .none {
        didSet { refreshOverlay() }
    }
    /// 倍率が変わったことを UI へ返す。スライダーの位置を合わせるために使う。
    var onZoomChanged: ((CGFloat) -> Void)?
    /// 確定待ちのマス数が変わったときに呼ぶ。0 なら待ちがない。
    var onPreviewChanged: ((Int) -> Void)?

    /// 選んでいる道具が地図を書き換えないとき、1本指のドラッグを移動に使う。
    /// エミュレータやパネル越しの操作では2本指が届かないので、片手で完結させる必要がある。
    var dragMovesCamera: Bool = true

    private var drawingTouch: UITouch?
    private var lastPaintedTile: (Int, Int)?
    /// 移動モードで、指がどれだけ動いたか。動かさずに離したときだけ「調べる」を通す。
    private var dragDistance: CGFloat = 0

    // ダブルタップしてそのまま上下になぞると拡大縮小する。
    // 2本指が届かない環境でも、指1本で寄り引きできるようにするため。
    private var lastTapTime: TimeInterval = 0
    private var lastTapLocation: CGPoint = .zero
    private var isZoomDragging = false
    /// 3x3 の建物は指を離すまで確定しない。実機では2本指の1本目が先に着くので、
    /// 触れた瞬間に建ててしまうと、ピンチを始めただけで発電所が建つ。
    private var pendingPlacement: (Int, Int)?

    /// なぞって置く道具か。道路・送電線・撤去・公園がこれにあたる。
    /// これらは指を離すまで確定させず、半透明の予告だけを見せる。
    var previewsDrag = false
    /// 予告として溜めているマス。指を離した時点でまとめて適用する。
    private var previewTiles: [(Int, Int)] = []
    private var previewNode: SKNode!
    private var zoomDragStartScale: CGFloat = 1
    private var zoomDragStartY: CGFloat = 0

    private var mapWidthPoints: CGFloat { CGFloat(CityMap.width) * CityScene.tileSide }
    private var mapHeightPoints: CGFloat { CGFloat(CityMap.height) * CityScene.tileSide }

    // MARK: - 組み立て

    override func didMove(to view: SKView) {
        // 引ききったときにマップの外が見える。黒帯だと壊れて見えるので、沖合の海にする。
        backgroundColor = SKColor(red: 0.10, green: 0.20, blue: 0.38, alpha: 1)
        scaleMode = .resizeFill
        anchorPoint = CGPoint(x: 0.5, y: 0.5)

        if terrainLayer == nil { buildLayers() }
        if camera == nil {
            addChild(cam)
            camera = cam
            cam.setScale(CityScene.defaultScale)
            updateHighlightSize()
            cam.position = .zero
        }
        fullRefresh()
    }

    private func buildLayers() {
        func makeLayer(_ z: CGFloat) -> SKTileMapNode {
            let node = SKTileMapNode(tileSet: catalog.tileSet,
                                     columns: CityMap.width,
                                     rows: CityMap.height,
                                     tileSize: CGSize(width: CityScene.tileSide,
                                                      height: CityScene.tileSide))
            node.enableAutomapping = false
            node.position = .zero
            node.zPosition = z
            addChild(node)
            return node
        }

        terrainLayer = makeLayer(0)
        structureLayer = makeLayer(1)
        wireLayer = makeLayer(2)
        trafficLayer = makeLayer(3)

        towerLayer = SKNode()
        towerLayer.zPosition = 4
        addChild(towerLayer)

        markerLayer = makeLayer(5)

        overlaySprite = SKSpriteNode(color: .clear,
                                     size: CGSize(width: mapWidthPoints, height: mapHeightPoints))
        overlaySprite.zPosition = 10
        overlaySprite.alpha = 0.62
        overlaySprite.isHidden = true
        addChild(overlaySprite)

        let shoreline = SKShapeNode(rect: CGRect(x: -mapWidthPoints / 2, y: -mapHeightPoints / 2,
                                                 width: mapWidthPoints, height: mapHeightPoints))
        shoreline.strokeColor = SKColor(white: 1, alpha: 0.22)
        shoreline.lineWidth = 2
        shoreline.fillColor = .clear
        shoreline.zPosition = 6
        addChild(shoreline)

        highlight = SKShapeNode(rectOf: CGSize(width: CityScene.tileSide, height: CityScene.tileSide))
        highlight.strokeColor = SKColor(white: 1, alpha: 0.9)
        highlight.lineWidth = 1.5
        highlight.fillColor = SKColor(white: 1, alpha: 0.12)
        highlight.zPosition = 20
        highlight.isHidden = true
        addChild(highlight)

        previewNode = SKNode()
        previewNode.zPosition = 19
        addChild(previewNode)
    }

    /// 照準の形を作り直す。
    ///
    /// マスと同じ大きさの枠だけだと、指の腹に完全に隠れて、どこを塗ろうとしているのか
    /// 見えない。枠の四方へ腕を伸ばして、指の外から狙っているマスを指させる。
    /// 腕の長さは画面上で一定になるよう、拡大率を掛けて決める（指の幅はいつも同じなので）。
    private func updateHighlightSize() {
        guard highlight != nil else { return }
        let side = CityScene.tileSide * CGFloat(footprint)
        let half = side / 2
        // 指の腹はおよそ 44pt。その外へ出るだけの長さを確保する。
        let arm = max(side * 0.7, 30 * cam.xScale)

        let path = CGMutablePath()
        path.addRect(CGRect(x: -half, y: -half, width: side, height: side))
        for (dx, dy) in [(0.0, 1.0), (0.0, -1.0), (1.0, 0.0), (-1.0, 0.0)] {
            let sx = half * CGFloat(dx), sy = half * CGFloat(dy)
            path.move(to: CGPoint(x: sx, y: sy))
            path.addLine(to: CGPoint(x: sx + arm * CGFloat(dx), y: sy + arm * CGFloat(dy)))
        }
        highlight.path = path
    }

    // MARK: - 描き直し

    func fullRefresh() {
        guard let sim else { return }
        roadTiles.removeAll(keepingCapacity: true)
        trafficLevels.removeAll(keepingCapacity: true)
        // 都市を作り直すとゾーン番号も振り直されるので、タワーは一度すべて捨てる。
        towerLayer?.removeAllChildren()
        towerSprites.removeAll()
        for y in 0..<CityMap.height {
            for x in 0..<CityMap.width { refreshTile(x: x, y: y, sim: sim) }
        }
        sim.map.clearDirty()
        refreshMarkers()
        refreshTraffic()
        refreshTowers()
        refreshOverlay()
    }

    /// 上に伸びる高層タワーを、育ったゾーンの上に立てる。
    /// スプライトの足元をゾーンの手前下端に合わせ、そこから空へ伸ばす。
    /// 手前（南）のタワーが奥（北）のタワーを隠すよう、`oy` で前後関係を付ける。
    func refreshTowers() {
        guard let sim, let towerLayer else { return }
        var live = Set<Int32>()

        for i in sim.map.zones.indices {
            let z = sim.map.zones[i]
            guard z.alive, TileCatalog.isTowerZone(z.kind, level: Int(z.level)) else { continue }
            let id = Int32(i)
            let key = "tower.\(z.kind.rawValue).\(z.level).\(z.variant)"
            guard let texture = catalog.towerTexture(key) else { continue }
            live.insert(id)

            let node: SKSpriteNode
            if let existing = towerSprites[id] {
                node = existing
            } else {
                node = SKSpriteNode(texture: texture)
                node.anchorPoint = CGPoint(x: 0.5, y: 0)
                towerLayer.addChild(node)
                towerSprites[id] = node
            }
            node.texture = texture
            node.size = CGSize(width: CGFloat(TileArt.zoneSize),
                               height: CGFloat(TileArt.towerCanvasHeight))
            // 足元＝ゾーン手前の中央タイルの下端。
            let foot = point(forTile: Int(z.ox) + 1, Int(z.oy) + 2)
            node.position = CGPoint(x: foot.x, y: foot.y - CityScene.tileSide / 2)
            node.zPosition = CGFloat(z.oy)
        }

        for (id, node) in towerSprites where !live.contains(id) {
            node.removeFromParent()
            towerSprites[id] = nil
        }
    }

    /// 電気や道路が足りない区画の中央に印を出す。
    /// 電力や道路の状態はタイル自体を書き換えないので、毎回すべての区画を見て決める。
    func refreshMarkers() {
        guard let sim, markerLayer != nil else { return }
        var next = Set<Int>()

        for z in sim.map.zones where z.alive && z.kind != .coalPlant {
            let key: String
            if !z.powered {
                key = "marker.power"
            } else if !z.hasRoad {
                key = "marker.road"
            } else {
                continue
            }
            let x = Int(z.ox) + 1, y = Int(z.oy) + 1
            guard sim.map.inBounds(x, y) else { continue }
            next.insert(y * CityMap.width + x)
            markerLayer.setTileGroup(catalog.group(key),
                                     forColumn: x, row: CityMap.height - 1 - y)
        }

        for i in markedTiles.subtracting(next) {
            markerLayer.setTileGroup(nil,
                                     forColumn: i % CityMap.width,
                                     row: CityMap.height - 1 - i / CityMap.width)
        }
        markedTiles = next
    }

    /// 前回以降に書き換わったタイルだけを描き直す。
    func applyDirty() {
        guard let sim else { return }
        let dirty = sim.map.dirty
        guard !dirty.isEmpty else { return }
        var seen = Set<Int>(minimumCapacity: dirty.count)
        for i in dirty where seen.insert(i).inserted {
            refreshTile(x: i % CityMap.width, y: i / CityMap.width, sim: sim)
        }
        sim.map.clearDirty()
    }

    private func refreshTile(x: Int, y: Int, sim: Simulation) {
        let tile = sim.map.tile(x, y)
        let row = CityMap.height - 1 - y

        terrainLayer.setTileGroup(catalog.group(catalog.terrainKey(tile, x: x, y: y)),
                                  forColumn: x, row: row)

        if let key = catalog.structureKey(tile, x: x, y: y, map: sim.map) {
            structureLayer.setTileGroup(catalog.group(key), forColumn: x, row: row)
        } else {
            structureLayer.setTileGroup(nil, forColumn: x, row: row)
        }

        if let key = catalog.wireKey(tile, x: x, y: y, map: sim.map) {
            wireLayer.setTileGroup(catalog.group(key), forColumn: x, row: row)
        } else {
            wireLayer.setTileGroup(nil, forColumn: x, row: row)
        }

        // 道路でなくなった（撤去された）マスは、渋滞の車も消して集合から外す。
        let i = sim.map.index(x, y)
        if tile.structure == .road {
            roadTiles.insert(i)
        } else if roadTiles.remove(i) != nil {
            trafficLevels.removeValue(forKey: i)
            trafficLayer.setTileGroup(nil, forColumn: x, row: row)
        }
    }

    /// 渋滞している道路にだけ車を置く。交通量はタイルの見た目に出ない値として
    /// 毎か月更新されるので（`dirty` を通らない）、道路だけを自前でたどって見直す。
    func refreshTraffic() {
        guard let sim, trafficLayer != nil else { return }
        for i in roadTiles {
            let x = i % CityMap.width, y = i / CityMap.width
            let level = TileCatalog.trafficLevel(Int(sim.map.tiles[i].traffic))
            guard trafficLevels[i] != level else { continue }

            let row = CityMap.height - 1 - y
            if level == 0 {
                trafficLevels.removeValue(forKey: i)
                trafficLayer.setTileGroup(nil, forColumn: x, row: row)
            } else {
                trafficLevels[i] = level
                let key = "traffic.\(sim.map.roadMask(x, y)).\(level)"
                trafficLayer.setTileGroup(catalog.group(key), forColumn: x, row: row)
            }
        }
    }

    // MARK: - オーバーレイ

    func refreshOverlay() {
        guard let sim, overlaySprite != nil else { return }
        guard overlayMode != .none else {
            overlaySprite.isHidden = true
            return
        }
        overlaySprite.isHidden = false
        overlaySprite.texture = overlayTexture(for: sim)
        overlaySprite.size = CGSize(width: mapWidthPoints, height: mapHeightPoints)
    }

    private func overlayTexture(for sim: Simulation) -> SKTexture? {
        var canvas: PixelCanvas
        var smooth = true

        switch overlayMode {
        case .none:
            return nil
        case .power:
            smooth = false
            canvas = PixelCanvas(width: CityMap.width, height: CityMap.height)
            for y in 0..<CityMap.height {
                for x in 0..<CityMap.width {
                    let t = sim.map.tile(x, y)
                    if t.hasZone, let z = sim.map.zone(t.zoneID) {
                        canvas.set(x, y, z.powered ? RGBA(60, 220, 120, 150) : RGBA(230, 60, 60, 190))
                    } else if t.wire {
                        canvas.set(x, y, t.powered ? RGBA(240, 220, 90, 170) : RGBA(120, 120, 120, 150))
                    }
                }
            }
        case .pollution:
            canvas = heatCanvas(sim.pollution)
        case .landValue:
            canvas = heatCanvas(sim.landValue)
        case .crime:
            canvas = heatCanvas(sim.crime)
        case .traffic:
            canvas = heatCanvas(sim.trafficMap)
        case .density:
            canvas = heatCanvas(sim.density, divisor: 3)
        }

        guard let image = canvas.cgImage() else { return nil }
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = smooth ? .linear : .nearest
        return texture
    }

    private func heatCanvas(_ map: CoarseMap, divisor: Int = 1) -> PixelCanvas {
        var canvas = PixelCanvas(width: CoarseMap.width, height: CoarseMap.height)
        for cy in 0..<CoarseMap.height {
            for cx in 0..<CoarseMap.width {
                let v = min(255, max(0, map[cx, cy] / divisor))
                canvas.set(cx, cy, CityScene.heatColor(v))
            }
        }
        return canvas
    }

    /// 0（青）から 255（赤）までの色。値が小さいところは薄く出す。
    static func heatColor(_ v: Int) -> RGBA {
        let t = Double(v) / 255.0
        let stops: [(Double, (Int, Int, Int))] = [
            (0.00, (40, 70, 190)),
            (0.35, (40, 190, 140)),
            (0.65, (240, 210, 60)),
            (1.00, (225, 50, 40)),
        ]
        var color = stops[0].1
        for i in 0..<(stops.count - 1) {
            let (t0, c0) = stops[i], (t1, c1) = stops[i + 1]
            if t >= t0 && t <= t1 {
                let f = (t1 - t0) == 0 ? 0 : (t - t0) / (t1 - t0)
                color = (Int(Double(c0.0) + (Double(c1.0) - Double(c0.0)) * f),
                         Int(Double(c0.1) + (Double(c1.1) - Double(c0.1)) * f),
                         Int(Double(c0.2) + (Double(c1.2) - Double(c0.2)) * f))
                break
            }
        }
        let alpha = Int(30 + t * 200)
        return RGBA(color.0, color.1, color.2, alpha)
    }

    // MARK: - カメラ

    var currentScale: CGFloat { cam.xScale }

    /// スライダー用。0 が引ききった状態、1 が寄りきった状態。
    func applyZoom(level: CGFloat) {
        cam.removeAllActions()
        cam.setScale(CityScene.scale(forLevel: level))
        updateHighlightSize()
        clampCamera()
    }

    /// 倍率は比で効くので、スライダーとの対応も対数でとる。
    static func scale(forLevel level: CGFloat) -> CGFloat {
        let t = min(max(level, 0), 1)
        return maxScale * pow(minScale / maxScale, t)
    }

    static func level(forScale scale: CGFloat) -> CGFloat {
        let t = log(scale / maxScale) / log(minScale / maxScale)
        return min(max(t, 0), 1)
    }

    /// ピンチ用。指の広がりをそのまま倍率にする。
    func zoom(by factor: CGFloat) {
        cam.removeAllActions()
        let next = min(max(cam.xScale / factor, CityScene.minScale), CityScene.maxScale)
        cam.setScale(next)
        updateHighlightSize()
        clampCamera()
        onZoomChanged?(next)
    }

    /// ボタン用。1段ぶん寄る／引く。
    /// パネル越しの操作ではピンチが届かないので、こちらが主な拡大縮小の手段になる。
    func zoomStep(zoomIn: Bool) {
        let step: CGFloat = zoomIn ? 1 / 1.4 : 1.4
        let next = min(max(cam.xScale * step, CityScene.minScale), CityScene.maxScale)
        guard abs(next - cam.xScale) > 0.001 else { return }
        cam.removeAllActions()
        cam.run(.scale(to: next, duration: 0.18))
        onZoomChanged?(next)
    }

    override func update(_ currentTime: TimeInterval) {
        // 引いていく途中でマップの外が見えないように、動いているあいだは毎フレーム引き戻す。
        if cam.hasActions() { clampCamera() }
    }

    func pan(by delta: CGPoint) {
        cam.position = CGPoint(x: cam.position.x - delta.x * cam.xScale,
                               y: cam.position.y + delta.y * cam.yScale)
        clampCamera()
    }

    /// マップの外に出過ぎないようにカメラを引き戻す。
    private func clampCamera() {
        let halfW = size.width / 2 * cam.xScale
        let halfH = size.height / 2 * cam.yScale
        let limitX = max(0, mapWidthPoints / 2 - halfW)
        let limitY = max(0, mapHeightPoints / 2 - halfH)
        cam.position = CGPoint(x: min(max(cam.position.x, -limitX), limitX),
                               y: min(max(cam.position.y, -limitY), limitY))
    }

    /// 新しい都市を始めたときに、寄り引きの具合も最初の状態へ戻す。
    func resetCamera() {
        cam.removeAllActions()
        cam.setScale(CityScene.defaultScale)
        updateHighlightSize()
        centerOnCity()
        onZoomChanged?(CityScene.defaultScale)
    }

    func centerOnCity() {
        guard let sim else { return }
        let x = (CGFloat(sim.centerX) - CGFloat(CityMap.width) / 2) * CityScene.tileSide
        let y = (CGFloat(CityMap.height) / 2 - CGFloat(sim.centerY)) * CityScene.tileSide
        cam.position = CGPoint(x: x, y: y)
        clampCamera()
    }

    // MARK: - 入力

    private func tileCoordinate(at point: CGPoint) -> (Int, Int)? {
        let local = convert(point, to: terrainLayer)
        let column = terrainLayer.tileColumnIndex(fromPosition: local)
        let row = terrainLayer.tileRowIndex(fromPosition: local)
        guard column >= 0, row >= 0, column < CityMap.width, row < CityMap.height else { return nil }
        return (column, CityMap.height - 1 - row)
    }

    /// タイルの中心のシーン座標。
    private func point(forTile x: Int, _ y: Int) -> CGPoint {
        CGPoint(x: (CGFloat(x) + 0.5 - CGFloat(CityMap.width) / 2) * CityScene.tileSide,
                y: (CGFloat(CityMap.height) / 2 - CGFloat(y) - 0.5) * CityScene.tileSide)
    }

    private func showHighlight(at tile: (Int, Int)) {
        highlight.position = point(forTile: tile.0, tile.1)
        highlight.isHidden = false
    }

    /// 区画が1段育ったことを知らせる、一瞬の光。
    /// 建物の絵は次の描き直しで入れ替わるが、それだけだと変化に気付けない。
    func flashUpgrade(x: Int, y: Int) {
        let side = CityScene.tileSide * 3
        let node = SKShapeNode(rectOf: CGSize(width: side, height: side), cornerRadius: 2)
        node.position = point(forTile: x, y)
        node.strokeColor = SKColor(red: 1.0, green: 0.94, blue: 0.55, alpha: 1)
        node.fillColor = SKColor(red: 1.0, green: 0.94, blue: 0.55, alpha: 0.30)
        node.lineWidth = 2
        node.zPosition = 18
        node.setScale(0.75)
        addChild(node)
        node.run(.sequence([
            .group([.scale(to: 1.3, duration: 0.5), .fadeOut(withDuration: 0.5)]),
            .removeFromParent(),
        ]))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // 2本指はカメラ操作に譲る。
        if (event?.allTouches?.count ?? 1) > 1 {
            drawingTouch = nil
            pendingPlacement = nil
            previewTiles.removeAll()
            previewNode.removeAllChildren()
            highlight.isHidden = true
            return
        }
        guard let touch = touches.first else { return }
        drawingTouch = touch
        lastPaintedTile = nil
        dragDistance = 0
        isZoomDragging = false
        previewTiles.removeAll()
        previewNode.removeAllChildren()

        // 直前のタップとほぼ同じ場所をすぐに触り直したら、2回目は拡大縮小のつまみになる。
        if dragMovesCamera, let view {
            let point = touch.location(in: view)
            let elapsed = CACurrentMediaTime() - lastTapTime
            let gap = ((point.x - lastTapLocation.x) * (point.x - lastTapLocation.x)
                       + (point.y - lastTapLocation.y) * (point.y - lastTapLocation.y)).squareRoot()
            if elapsed < 0.4, gap < 44 {
                isZoomDragging = true
                zoomDragStartScale = cam.xScale
                zoomDragStartY = point.y
                cam.removeAllActions()
                return
            }
        }

        // 移動モードでは、離すまで何をするか決まらない。
        guard !dragMovesCamera else { return }
        // どの道具も、触れた瞬間には確定しない。指が動き出すか離すまで待つ。
        // ピンチの1本目が着いた時点で建ててしまうと、拡大しようとしただけで
        // 区画が潰れる（撤去のときは3x3ごと消える）。
        pendingPlacement = aim(at: touch)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = drawingTouch, touches.contains(touch), let view else { return }

        if isZoomDragging {
            // 上へなぞると寄り、下へなぞると引く。160pt で倍率が2倍動く。
            let dy = zoomDragStartY - touch.location(in: view).y
            dragDistance = abs(dy)
            let factor = pow(2, dy / 160)
            let next = min(max(zoomDragStartScale / factor, CityScene.minScale), CityScene.maxScale)
            cam.setScale(next)
            updateHighlightSize()
            clampCamera()
            onZoomChanged?(next)
            return
        }

        if dragMovesCamera {
            let now = touch.location(in: view)
            let before = touch.previousLocation(in: view)
            let delta = CGPoint(x: now.x - before.x, y: now.y - before.y)
            dragDistance += (delta.x * delta.x + delta.y * delta.y).squareRoot()
            pan(by: delta)
            return
        }

        let now = touch.location(in: view)
        let before = touch.previousLocation(in: view)
        dragDistance += ((now.x - before.x) * (now.x - before.x)
                         + (now.y - before.y) * (now.y - before.y)).squareRoot()

        // 3x3 の建物は位置を選び直せるよう、離すまで動かし続ける。
        if footprint > 1 {
            pendingPlacement = aim(at: touch)
            return
        }

        // 1マスの道具は、はっきり動き出した時点からなぞりとして扱う。
        if pendingPlacement != nil {
            guard dragDistance > 6 else {
                _ = aim(at: touch)
                return
            }
            // 指を置いた場所（ずらす前の位置）は線に含めない。
            // なぞり始めると狙いが指の上へ移るので、その1マスだけ線から
            // 外れた場所に取り残されてしまう。
            pendingPlacement = nil
            lastPaintedTile = nil
        }
        paint(at: touch)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isZoomDragging {
            // なぞらずに離したなら、ただのダブルタップ。1段だけ寄る。
            if dragDistance < 8 { zoomStep(zoomIn: true) }
            isZoomDragging = false
            lastTapTime = 0
        } else if let touch = drawingTouch, let view {
            // 指を置いてほとんど動かさずに離したなら、地図を動かすつもりはなかったとみなす。
            if dragMovesCamera, dragDistance < 8 {
                paint(at: touch)
                lastTapTime = CACurrentMediaTime()
                lastTapLocation = touch.location(in: view)
            } else {
                lastTapTime = 0
            }
        }
        if let tile = pendingPlacement {
            onPaint?(tile.0, tile.1)
            pendingPlacement = nil
        }
        // 指を離しても、まだ敷かない。確定ボタンを押すまで予告のまま残す。
        onPreviewChanged?(previewTiles.count)
        drawingTouch = nil
        highlight.isHidden = true
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        drawingTouch = nil
        previewTiles.removeAll()
        previewNode.removeAllChildren()
        pendingPlacement = nil
        isZoomDragging = false
        lastTapTime = 0
        highlight.isHidden = true
    }

    /// 触れている場所にカーソルを合わせるだけ。まだ何も建てない。
    @discardableResult
    /// 触っている場所から狙うマスを決める。
    ///
    /// なぞっている間は、指の少し上を狙う。真下のマスは指の腹に隠れて見えないため。
    /// タップ（単発の設置）はずらさない。押した場所と違うところに建つと驚くので、
    /// ずらすのは「なぞっている」とはっきりした後だけにしてある。
    private func aim(at touch: UITouch) -> (Int, Int)? {
        var aimed = touch.location(in: self)
        // 建てる道具は、触れた瞬間から指の少し上を狙う。真下のマスは指の腹に
        // 隠れて見えないため。ずらす量を触っている間ずっと同じにしておくと、
        // なぞり始めても狙いが飛ばない。
        //
        // 「調べる」と「移動」はずらさない。こちらは照準を出さないので、
        // ずらすと何を読んだのか分からなくなる。
        if !dragMovesCamera {
            aimed.y += CityScene.aimLift * cam.yScale
        }
        guard let tile = tileCoordinate(at: aimed) else { return nil }
        showHighlight(at: tile)
        return tile
    }

    /// 指の腹はおよそ 44pt。その外へ狙いを出すためのずらし幅（画面上の点数）。
    private static let aimLift: CGFloat = 34

    /// 予告のマスを描き直す。
    private func refreshPreview() {
        previewNode.removeAllChildren()
        let side = CityScene.tileSide
        for (x, y) in previewTiles {
            let mark = SKShapeNode(rectOf: CGSize(width: side, height: side))
            mark.position = point(forTile: x, y)
            mark.fillColor = SKColor(white: 1, alpha: 0.35)
            mark.strokeColor = SKColor(white: 1, alpha: 0.6)
            mark.lineWidth = 1
            previewNode.addChild(mark)
        }
    }

    /// 溜めた予告をまとめて適用する。確定ボタンから呼ぶ。
    func commitPreview() {
        let tiles = previewTiles
        previewTiles.removeAll()
        previewNode.removeAllChildren()
        for (x, y) in tiles { onPaint?(x, y) }
        onPreviewChanged?(0)
    }

    /// 溜めた予告を捨てる。やめるボタンと、道具を持ち替えたときに呼ぶ。
    func cancelPreview() {
        previewTiles.removeAll()
        previewNode?.removeAllChildren()
        onPreviewChanged?(0)
    }

    /// 2つのマスのあいだを直線で埋める（始点は含まない）。
    /// `from` が nil なら `to` だけを返す。
    private func tilesBetween(_ from: (Int, Int)?, _ to: (Int, Int)) -> [(Int, Int)] {
        guard let from else { return [to] }
        var x0 = from.0, y0 = from.1
        let x1 = to.0, y1 = to.1
        let dx = abs(x1 - x0), dy = -abs(y1 - y0)
        let sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1
        var err = dx + dy
        var out: [(Int, Int)] = []
        while x0 != x1 || y0 != y1 {
            let e2 = 2 * err
            if e2 >= dy { err += dy; x0 += sx }
            if e2 <= dx { err += dx; y0 += sy }
            out.append((x0, y0))
            if out.count > 256 { break }
        }
        return out
    }

    private func paint(at touch: UITouch) {
        let last = lastPaintedTile
        guard let tile = aim(at: touch) else { return }
        if let last, last == tile { return }
        lastPaintedTile = tile
        if previewsDrag {
            // すでに引いたマスへ戻ったら、そこから先を取り消す。
            // 行きすぎたときに、指を離さずその場で引き直せる。
            if let index = previewTiles.firstIndex(where: { $0 == tile }) {
                previewTiles.removeSubrange((index + 1)...)
                refreshPreview()
                return
            }
            // 指が速いと touch の間隔が飛び、そのままではマスが抜けて線が途切れる。
            // 前に置いたマスとのあいだを直線で埋める。
            for step in tilesBetween(last, tile) where !previewTiles.contains(where: { $0 == step }) {
                previewTiles.append(step)
            }
            refreshPreview()
            return
        }
        onPaint?(tile.0, tile.1)
    }
}
