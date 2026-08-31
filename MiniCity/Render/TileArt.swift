import Foundation

enum Palette {
    // 手つかずの土地は土の色。緑は森・芝生・公園にだけ使い、
    // 「まだ何もない場所」と「人が手を入れた場所」を色で分ける。
    static let land = RGBA(170, 132, 82)
    static let landDark = RGBA(144, 108, 64)
    static let landLight = RGBA(194, 158, 108)

    static let lawn = RGBA(96, 146, 66)
    static let lawnDark = RGBA(76, 122, 52)
    static let lawnLight = RGBA(124, 172, 90)

    static let dirt = RGBA(158, 138, 96)
    static let dirtDark = RGBA(132, 114, 78)
    static let water = RGBA(52, 102, 176)
    static let waterDark = RGBA(38, 82, 150)
    static let waterLight = RGBA(96, 146, 212)
    static let forest = RGBA(50, 118, 46)
    static let forestDark = RGBA(32, 84, 34)
    static let forestLight = RGBA(80, 154, 66)
    static let trunk = RGBA(88, 62, 38)

    static let asphalt = RGBA(80, 80, 86)
    static let asphaltDark = RGBA(58, 58, 64)
    static let roadLine = RGBA(210, 206, 172)

    static let pavement = RGBA(160, 158, 150)
    static let pavementDark = RGBA(132, 130, 124)
    static let gravel = RGBA(146, 132, 108)

    static let wall = RGBA(208, 200, 182)
    static let wallWarm = RGBA(196, 176, 152)
    // 街区ごとに壁の色を散らすための追加。2色だけだと、同じレベルの街区が
    // 並んだときに色までそろってしまい、引きで見て単調になる。
    static let wallCool = RGBA(184, 190, 198)
    static let wallClay = RGBA(198, 166, 148)
    static let concrete = RGBA(176, 174, 168)
    static let brick = RGBA(150, 100, 78)
    static let roofRed = RGBA(162, 66, 54)
    static let roofBrown = RGBA(122, 84, 58)
    static let roofBlue = RGBA(66, 90, 146)
    static let roofGrey = RGBA(106, 106, 112)
    static let glass = RGBA(92, 138, 178)
    static let glassDark = RGBA(66, 104, 140)
    static let glassTeal = RGBA(74, 148, 152)
    static let glassSlate = RGBA(110, 124, 172)
    static let window = RGBA(128, 182, 214)
    static let windowLit = RGBA(236, 216, 142)
    static let steel = RGBA(120, 118, 112)
    static let rubble = RGBA(126, 114, 96)
    static let shadow = RGBA(0, 0, 0, 70)

    static let wire = RGBA(46, 46, 52)
    static let pylon = RGBA(128, 126, 118)

    static let zoneR = RGBA(74, 200, 100)
    static let zoneC = RGBA(84, 154, 232)
    static let zoneI = RGBA(228, 192, 72)
    // 建物が建ったあとも残す枠。目立ちすぎないよう一段落とす。
    static let zoneRLine = RGBA(58, 164, 82)
    static let zoneCLine = RGBA(66, 128, 198)
    static let zoneILine = RGBA(198, 164, 56)
    static let serviceLine = RGBA(170, 170, 176)

    // 渋滞の車。軽い渋滞は控えめな色、詰まっている区間は目立つ色にする。
    static let trafficLight = RGBA(224, 224, 232)
    static let trafficJam = RGBA(220, 74, 58)

    // 高層タワーの頂上に灯る点滅灯。
    static let beacon = RGBA(255, 92, 72)
    static let beaconIndustrial = RGBA(255, 176, 60)
    static let towerAccent = RGBA(214, 180, 90)
}

enum TileArt {

    static let tileSize = 16
    static let zoneSize = 48

    /// 高層タワーは 48px のマスに収まりきらない。専用スプライトを
    /// この高さのキャンバスに描き、マスの上へはみ出させて空に伸ばす。
    /// 足元の 48px が区画の敷地、残りが上へ伸びるぶん。
    static let towerCanvasHeight = 84
    /// このレベル以上の住宅・商業を、上に伸びるタワーとして別スプライトで描く。
    static let towerMinLevel = 6

    // MARK: - 地形

    static func land(variant: Int) -> PixelCanvas {
        var c = PixelCanvas(width: tileSize, height: tileSize, fill: Palette.land)
        c.speckle(seed: UInt64(variant) &* 977 &+ 11, count: 16, color: Palette.landDark)
        c.speckle(seed: UInt64(variant) &* 613 &+ 41, count: 12, color: Palette.landLight)
        return c
    }

    static func water(variant: Int) -> PixelCanvas {
        var c = PixelCanvas(width: tileSize, height: tileSize, fill: Palette.water)
        c.speckle(seed: UInt64(variant) &* 331 &+ 5, count: 18, color: Palette.waterDark)
        var rng = SplitMix64(seed: UInt64(variant) &* 719 &+ 3)
        for _ in 0..<3 {
            let y = Int.random(in: 1..<15, using: &rng)
            let x = Int.random(in: 0..<11, using: &rng)
            c.hLine(x, y, Int.random(in: 3...5, using: &rng), Palette.waterLight)
        }
        return c
    }

    static func forest(variant: Int) -> PixelCanvas {
        var c = PixelCanvas(width: tileSize, height: tileSize, fill: Palette.land)
        c.speckle(seed: UInt64(variant) &* 211 &+ 9, count: 14, color: Palette.landDark)
        var rng = SplitMix64(seed: UInt64(variant) &* 883 &+ 17)
        for _ in 0..<6 {
            let x = Int.random(in: 2..<14, using: &rng)
            let y = Int.random(in: 2..<14, using: &rng)
            tree(&c, x, y, scale: 1)
        }
        return c
    }

    static func rubble() -> PixelCanvas {
        var c = PixelCanvas(width: tileSize, height: tileSize, fill: Palette.rubble)
        c.speckle(seed: 4242, count: 30, color: Palette.rubble.shaded(0.78))
        c.speckle(seed: 7777, count: 14, color: Palette.concrete)
        return c
    }

    static func park() -> PixelCanvas {
        var c = PixelCanvas(width: tileSize, height: tileSize, fill: Palette.lawnLight)
        c.speckle(seed: 99, count: 12, color: Palette.lawn)
        c.rect(0, 7, 16, 2, Palette.land)
        tree(&c, 4, 4, scale: 1)
        tree(&c, 11, 12, scale: 1)
        c.disc(11, 4, 2, Palette.water)
        return c
    }

    // MARK: - 道路

    /// 接続方向のビット（1:北 2:東 4:南 8:西）から道路タイルを作る。
    /// 背景は透明にしてあるので、下の地形がそのまま見える（水面に架ければ橋になる）。
    static func road(mask: Int) -> PixelCanvas {
        var c = PixelCanvas(width: tileSize, height: tileSize)
        let n = mask & 1, e = mask & 2, s = mask & 4, w = mask & 8

        c.rect(4, 4, 8, 8, Palette.asphalt)
        if n != 0 { c.rect(4, 0, 8, 5, Palette.asphalt) }
        if s != 0 { c.rect(4, 11, 8, 5, Palette.asphalt) }
        if e != 0 { c.rect(11, 4, 5, 8, Palette.asphalt) }
        if w != 0 { c.rect(0, 4, 5, 8, Palette.asphalt) }
        if mask == 0 { c.rect(0, 4, 16, 8, Palette.asphalt) }

        // 路肩。道の縁だけ暗くして、地面との境目を出す。
        let horizontal = (e != 0 || w != 0 || mask == 0)
        let vertical = (n != 0 || s != 0)
        if horizontal {
            let x0 = (w != 0 || mask == 0) ? 0 : 4
            let x1 = (e != 0 || mask == 0) ? 16 : 12
            c.hLine(x0, 4, x1 - x0, Palette.asphaltDark)
            c.hLine(x0, 11, x1 - x0, Palette.asphaltDark)
        }
        if vertical {
            let y0 = (n != 0) ? 0 : 4
            let y1 = (s != 0) ? 16 : 12
            c.vLine(4, y0, y1 - y0, Palette.asphaltDark)
            c.vLine(11, y0, y1 - y0, Palette.asphaltDark)
        }
        if horizontal && vertical {
            // 交差点の角だけ塗り直して、路肩の線が突き抜けないようにする。
            c.rect(5, 5, 6, 6, Palette.asphalt)
        }

        // センターライン。直線のときだけ引く。
        let straightEW = (e != 0 && w != 0 && n == 0 && s == 0) || mask == 0
        let straightNS = (n != 0 && s != 0 && e == 0 && w == 0)
        if straightEW {
            for x in stride(from: 1, to: 16, by: 4) { c.rect(x, 7, 2, 1, Palette.roadLine) }
        } else if straightNS {
            for y in stride(from: 1, to: 16, by: 4) { c.rect(7, y, 1, 2, Palette.roadLine) }
        }
        return c
    }

    // MARK: - 交通量

    /// 渋滞している道路に置く車。`level` 1 は流れている程度、2 は詰まっている状態。
    /// 道路の形（`mask`）から車線の向きを決め、その車線の上に置く。
    /// タイル内をループして流れる走行アニメーションの1コマ。
    /// `frame` を `0..<frameCount` で進めた絵を並べれば、SpriteKit のタイルアニメーションで
    /// マス内を車が流れるように見せられる（マスをまたいだ移動はさせない）。
    static let trafficFrameCount = 2

    static func trafficCars(mask: Int, level: Int, frame: Int = 0) -> PixelCanvas {
        var c = PixelCanvas(width: tileSize, height: tileSize)
        let n = mask & 1, e = mask & 2, s = mask & 4, w = mask & 8
        let horizontal = (e != 0 || w != 0 || mask == 0)
        let vertical = (n != 0 || s != 0)

        let color = level >= 2 ? Palette.trafficJam : Palette.trafficLight
        let count = level >= 2 ? 2 : 1

        // 12px の区間を frameCount コマで割り切れる歩幅にして、
        // 1周したときに継ぎ目なくループするようにする。
        let travel = 12
        let phase = (frame * (travel / trafficFrameCount)) % travel

        if horizontal {
            for lane in [5, 10] {
                for i in 0..<count { car(&c, x: (2 + i * 7 + phase) % travel, y: lane, horizontal: true, color: color) }
            }
        }
        if vertical {
            for lane in [5, 10] {
                for i in 0..<count { car(&c, x: lane, y: (2 + i * 7 + phase) % travel, horizontal: false, color: color) }
            }
        }
        return c
    }

    private static func car(_ c: inout PixelCanvas, x: Int, y: Int, horizontal: Bool, color: RGBA) {
        if horizontal {
            c.rect(x, y, 4, 2, color)
            c.set(x + 3, y, color.shaded(1.35))
        } else {
            c.rect(x, y, 2, 4, color)
            c.set(x, y, color.shaded(1.35))
        }
    }

    // MARK: - 送電線

    static func wire(mask: Int) -> PixelCanvas {
        var c = PixelCanvas(width: tileSize, height: tileSize)
        let n = mask & 1, e = mask & 2, s = mask & 4, w = mask & 8

        if n != 0 { c.vLine(6, 0, 8, Palette.wire); c.vLine(9, 0, 8, Palette.wire) }
        if s != 0 { c.vLine(6, 8, 8, Palette.wire); c.vLine(9, 8, 8, Palette.wire) }
        if e != 0 { c.hLine(8, 6, 8, Palette.wire); c.hLine(8, 9, 8, Palette.wire) }
        if w != 0 { c.hLine(0, 6, 8, Palette.wire); c.hLine(0, 9, 8, Palette.wire) }
        if mask == 0 { c.hLine(0, 6, 16, Palette.wire); c.hLine(0, 9, 16, Palette.wire) }

        // 鉄塔。
        c.rect(7, 4, 2, 9, Palette.pylon)
        c.hLine(5, 5, 6, Palette.pylon)
        c.hLine(5, 10, 6, Palette.pylon)
        c.set(7, 12, Palette.wire)
        return c
    }

    // MARK: - 建物のパーツ

    // 建物は斜投影で描く。奥行きは右上へ45度に伸ばし、
    // 手前の壁・上面・右の側面の3面を見せる。面ごとに明るさを変え、稜線を暗色で締める。
    // 光源は左上に固定する。

    private static func tree(_ c: inout PixelCanvas, _ x: Int, _ y: Int, scale: Int) {
        let r = scale + 1
        c.rect(x + 1, y + 1, 2, r + 2, Palette.shadow)
        c.rect(x, y + r, 1, r, Palette.trunk)
        c.disc(x, y, r, Palette.forest)
        c.disc(x - 1, y - 1, max(0, r - 1), Palette.forestLight)
    }

    /// 建物の輪郭。面の境目をこれで締めると、地面から立ち上がって見える。
    /// 区画ごとの壁の色。variant で 4 通りに散らす。
    /// `main` を主な壁に、`sub` を副えの棟や土台に使う。
    ///
    /// 色を2色に絞ると、同じレベルの街区が並んだときに輪郭だけでなく色まで
    /// そろってしまい、引きで見たときに壁のように見える。
    static func wallPair(kind: ZoneKind, variant: Int) -> (main: RGBA, sub: RGBA) {
        if kind == .commercial {
            switch variant % 4 {
            case 0: return (Palette.glass, Palette.glassDark)
            case 1: return (Palette.glassDark, Palette.glass)
            case 2: return (Palette.glassTeal, Palette.glassDark)
            default: return (Palette.glassSlate, Palette.glass)
            }
        }
        switch variant % 4 {
        case 0: return (Palette.wall, Palette.wallWarm)
        case 1: return (Palette.wallWarm, Palette.wall)
        case 2: return (Palette.wallCool, Palette.wallWarm)
        default: return (Palette.wallClay, Palette.wall)
        }
    }

    static let outline = RGBA(30, 28, 34)

    /// 見下ろした箱。屋根（上面）と手前の壁の2面を描く。
    ///
    /// 奥行きは真上へ伸ばす。以前は右上へ 45 度に振っていたが、あの投影だと
    /// 屋根が奥へ行くほど右へずれるので、`x + w + depth` が 48 を超えられない。
    /// 区画は 48x48 なので、縦を埋めようとすると横が痩せ、どう置いても
    /// 建物のまわりに地面が大きく残ってしまう。真上へ伸ばせばその制約が外れ、
    /// 屋根を区画いっぱいに広げられる。
    ///
    /// `x`, `baseY` は手前の壁の左下の角。`height` は壁の高さ、`depth` は屋根の奥行き。
    private static func box(_ c: inout PixelCanvas,
                            x: Int, baseY: Int, w: Int, depth: Int, height: Int,
                            wall: RGBA, roof: RGBA,
                            windows: RGBA? = nil, windowStep: Int = 4,
                            shadow: Int? = nil,
                            rng: inout SplitMix64) {
        let facadeTop = baseY - height
        let roofTop = facadeTop - depth

        // 影。右下へ落とす。長さは呼び出し側から指定できる（高い建物は長く）。
        let shadowLength = max(1, shadow ?? 2)
        for i in 1...shadowLength {
            c.hLine(x + i + 1, baseY + i, w, Palette.shadow)
        }

        // 屋根。奥へ行くほどわずかに暗くして、平らな面が続いていることを示す。
        for i in 0..<depth {
            let t = 1.0 - Double(depth - i) * 0.012
            c.hLine(x, roofTop + i, w, roof.shaded(t))
        }

        // 屋根が広いときは、設備の小さな塊を散らす。
        // 真上から見た大きな屋根が無地のままだと、建物ではなく板に見える。
        if depth >= 10, w >= 12 {
            let count = max(2, (w * depth) / 150)
            for _ in 0..<count {
                let bw = Int.random(in: 3...6, using: &rng)
                let bh = Int.random(in: 2...4, using: &rng)
                let bx = Int.random(in: (x + 2)...(x + w - bw - 2), using: &rng)
                let by = Int.random(in: (roofTop + 2)...(facadeTop - bh - 2), using: &rng)
                c.rect(bx, by, bw, bh, roof.shaded(1.12))
                c.hLine(bx, by + bh, bw, roof.shaded(0.82))
            }
            // 屋根の縁を一周させて、面の輪郭を締める。
            c.frame(x + 1, roofTop + 1, w - 2, depth - 1, roof.shaded(0.9))
        }

        // 手前の壁。
        c.rect(x, facadeTop, w, height, wall)
        // 壁の上端に軒の影を1本入れて、屋根と壁の折れ目をはっきりさせる。
        c.hLine(x, facadeTop, w, wall.shaded(0.72))

        // 輪郭。
        c.frame(x, roofTop, w, depth + height, outline)
        c.hLine(x, facadeTop - 1, w, outline)

        guard let win = windows else { return }
        // 窓は手前の壁に並べる。壁が薄いときは1段だけ。
        var wy = facadeTop + 2
        while wy + 2 <= baseY - 2 {
            var wx = x + 2
            while wx + 2 <= x + w - 2 {
                let lit = Int.random(in: 0..<10, using: &rng) < 3
                c.rect(wx, wy, 2, 2, lit ? Palette.windowLit : win)
                wx += 3
            }
            wy += windowStep
        }
    }

    /// 切妻屋根の家。奥へ向かって棟が伸びる形にして、妻側を手前に向ける。
    private static func house(_ c: inout PixelCanvas,
                              x: Int, baseY: Int, w: Int, depth: Int, height: Int,
                              wall: RGBA, roof: RGBA) {
        let eaveY = baseY - height
        let gable = max(3, w / 3)
        let ridgeY = eaveY - gable

        for i in 1...max(1, depth) {
            c.hLine(x + i + 2, baseY - i + 2, w, Palette.shadow)
        }
        c.rect(x + 2, baseY, w + depth, 2, Palette.shadow)

        // 奥へ伸びる屋根。右斜面は暗く、左斜面は明るく。
        for i in 1...depth {
            let top = ridgeY - i
            c.hLine(x + i, top, w / 2, roof.shaded(1.15))
            c.hLine(x + i + w / 2, top, w - w / 2, roof.shaded(0.72))
            c.hLine(x + i, top + gable, w, roof.shaded(0.72))
        }
        // 右の側面（壁）。
        for i in 1...depth {
            c.vLine(x + w + i - 1, eaveY - i, height, wall.shaded(0.62))
        }

        // 手前の妻壁と切妻の三角。
        c.rect(x, eaveY, w, height, wall)
        for row in 0..<gable {
            let inset = (gable - 1 - row) * w / (gable * 2)
            c.rect(x + inset, ridgeY + row, w - inset * 2, 1, roof)
        }

        // 輪郭。
        c.vLine(x, eaveY, height, outline)
        c.hLine(x, baseY - 1, w, outline)
        c.hLine(x, eaveY, w, outline)
        for row in 0..<gable {
            let inset = (gable - 1 - row) * w / (gable * 2)
            c.set(x + inset, ridgeY + row, outline)
            c.set(x + w - 1 - inset, ridgeY + row, outline)
        }
        for i in 1...depth {
            c.set(x + i + w / 2, ridgeY - i, outline)
            c.set(x + w + i - 1, eaveY - i, outline)
            c.set(x + w + i - 1, baseY - i - 1, outline)
        }

        // 窓とドア。
        c.rect(x + 2, eaveY + 2, 2, 2, Palette.window)
        if w >= 11 { c.rect(x + w - 5, eaveY + 2, 2, 2, Palette.window) }
        c.rect(x + w / 2 - 1, baseY - 4, 3, 3, roof.shaded(0.5))
    }

    /// 円筒のタンク。上面を楕円にして、胴に縦の陰影を入れる。
    private static func tank(_ c: inout PixelCanvas, cx: Int, baseY: Int, r: Int, height: Int) {
        let lid = max(2, r / 2)
        c.rect(cx - r + 3, baseY - 1, r * 2, 2, Palette.shadow)

        // 胴。左から右へ暗くしていく。
        for dx in -r..<r {
            let t = Double(dx + r) / Double(r * 2)
            let shade = 1.22 - t * 0.62
            c.vLine(cx + dx, baseY - height, height, Palette.concrete.shaded(shade))
        }
        // 上面の楕円。
        for i in 0..<lid {
            let inset = ((lid - 1 - i) * r) / (lid + 1)
            c.rect(cx - r + inset, baseY - height - lid + i, (r - inset) * 2, 1,
                   Palette.concrete.shaded(1.32 - Double(i) * 0.04))
        }
        // 輪郭。
        c.vLine(cx - r, baseY - height, height, outline)
        c.vLine(cx + r - 1, baseY - height, height, outline)
        c.hLine(cx - r, baseY - 1, r * 2, outline)
        for i in 0..<lid {
            let inset = ((lid - 1 - i) * r) / (lid + 1)
            c.set(cx - r + inset, baseY - height - lid + i, outline)
            c.set(cx + r - 1 - inset, baseY - height - lid + i, outline)
        }
        c.hLine(cx - r + ((lid - 1) * r) / (lid + 1), baseY - height - lid,
                (r - ((lid - 1) * r) / (lid + 1)) * 2, outline)
    }

    /// 煙突。細い円筒として、縦の陰影と口の楕円を入れる。
    private static func smokestack(_ c: inout PixelCanvas, x: Int, baseY: Int, w: Int, height: Int) {
        for dx in 0..<w {
            let t = Double(dx) / Double(max(1, w - 1))
            c.vLine(x + dx, baseY - height, height, Palette.steel.shaded(1.25 - t * 0.62))
        }
        c.hLine(x, baseY - height, w, Palette.steel.shaded(0.5))
        c.hLine(x, baseY - height + 1, w, Palette.steel.shaded(1.15))
        c.hLine(x, baseY - height + 4, w, Palette.roofRed)
        c.hLine(x, baseY - height + height / 3, w, Palette.roofRed)
        c.vLine(x, baseY - height, height, outline)
        c.vLine(x + w - 1, baseY - height, height, outline)
    }

    /// 先端の点滅灯つきアンテナ。段を重ねた高層タワーの頂上に立てる。
    private static func spire(_ c: inout PixelCanvas, cx: Int, topY: Int, height: Int, blink: RGBA) {
        c.vLine(cx, topY - height, height, Palette.steel)
        c.disc(cx, topY - height, 1, blink)
    }

    /// 段を重ねて先細りにするタワー。上の段ほど幅を絞ることで、
    /// L7 以降の「本当に育った高層ビル」を、壁を伸ばしすぎずに表現する。
    /// 返り値は最上段の屋根の頂点で、アンテナを立てる基準に使う。
    @discardableResult
    private static func steppedTower(_ c: inout PixelCanvas, x: Int, baseY: Int,
                                     widths: [Int], heights: [Int], depths: [Int],
                                     wall: RGBA, roof: RGBA, windows: RGBA?,
                                     rng: inout SplitMix64) -> (cx: Int, topY: Int) {
        // 屋根は右上へ 45 度に伸びる平行四辺形なので、その上に次の段を載せるには、
        // 奥へ入れた量ぶんだけ原点を右へ・上へ同時に送る必要がある。
        // x と y に同じ値を使うのが肝で、ここが食い違うと上の段が屋根の面から
        // 外れて浮いて見える（以前は x を depth / 2、y を depth / 3 でずらしていた）。
        //
        // 各段の depth を独立に持たせているのは、上の段まで同じ奥行きを使うと
        // 高さの合計が 48px の枠をすぐ超えてしまうため（上の段ほど奥行きを浅くする）。
        var frontX = x
        // その段の手前の壁の下端。2段目からは、前の段の屋根の手前の縁を指す。
        var frontBaseY = baseY
        var prevW = widths[0]
        var prevDepth = depths[0]
        var topCenterX = x + widths[0] / 2
        var topY = baseY

        for i in 0..<widths.count {
            let w = widths[i], h = heights[i], depth = depths[i]
            if i > 0 {
                // 前の段の footprint の中で、奥行き方向にも幅方向にも中央へ寄せる。
                let inset = max(1, (prevDepth - depth) / 2)
                frontX += (prevW - w) / 2 + inset
                frontBaseY -= inset
            }
            box(&c, x: frontX, baseY: frontBaseY, w: w, depth: depth, height: h,
                wall: wall, roof: roof, windows: windows, rng: &rng)
            topCenterX = frontX + depth + w / 2
            topY = frontBaseY - h - depth
            // 次の段のために、この段の屋根の手前の縁の高さを持ち越す。
            frontBaseY -= h
            prevW = w
            prevDepth = depth
        }
        return (topCenterX, topY)
    }

    // MARK: - 地面の下地

    private static func grassGround(_ seed: UInt64) -> PixelCanvas {
        var c = PixelCanvas(width: zoneSize, height: zoneSize, fill: Palette.lawn)
        c.speckle(seed: seed, count: 90, color: Palette.lawnDark)
        c.speckle(seed: seed &+ 1, count: 60, color: Palette.lawnLight)
        return c
    }

    /// 建物が建ったあとも残る区画の枠。何の区画かを一目で分かるようにする。
    private static func zoneBorder(_ c: inout PixelCanvas, _ color: RGBA) {
        c.frame(0, 0, zoneSize, zoneSize, color)
    }

    private static func pavementGround(_ seed: UInt64) -> PixelCanvas {
        var c = PixelCanvas(width: zoneSize, height: zoneSize, fill: Palette.pavement)
        c.speckle(seed: seed, count: 80, color: Palette.pavementDark)
        return c
    }

    private static func gravelGround(_ seed: UInt64) -> PixelCanvas {
        var c = PixelCanvas(width: zoneSize, height: zoneSize, fill: Palette.gravel)
        c.speckle(seed: seed, count: 120, color: Palette.dirtDark)
        c.speckle(seed: seed &+ 3, count: 40, color: Palette.rubble)
        return c
    }

    // MARK: - 高層タワー（マスの外へ伸びる）

    /// 高層タワーの足元に敷く、建物ぬきの地面（芝／舗装＋区画枠）。
    /// タワー本体は別スプライトで上に伸びるので、タイル層にはこれだけを置く。
    static func zoneGroundArt(kind: ZoneKind, variant: Int) -> PixelCanvas {
        var c: PixelCanvas
        let border: RGBA
        switch kind {
        case .commercial: c = pavementGround(UInt64(variant &* 11 &+ 2)); border = Palette.zoneCLine
        default: c = grassGround(UInt64(variant &* 7 &+ 1)); border = Palette.zoneRLine
        }
        zoneBorder(&c, border)
        return c
    }

    /// 高層の区画の形。レベルが同じでも variant で別の形になるようにして、
    /// 街が塔の繰り返しにならないようにしている。
    private enum TowerForm {
        /// 1本の塔。土台の中央から素直に伸びる。
        case single
        /// 2本の塔を並べる。1本ずつ高さを変えて、片方を主役にする。
        case twin
        /// 段を重ねて上ほど細くする。足元が広いので、いちばん重く見える。
        case setback
        /// 板状。幅を取って奥行きを薄くした、団地のような塊。
        case slab
    }

    /// レベルと variant から形を決める。同じレベルでも2つの形が出るようにして、
    /// 街を引きで見たときに輪郭が単調にならないようにしてある。
    private static func towerForm(level: Int, variant: Int) -> TowerForm {
        // 形は2通りで足りるので variant の偶奇で選ぶ。色は variant そのもので
        // 4通りに散らすので、形と色の組み合わせは 8 通りになる。
        switch (level, variant % 2) {
        case (6, 0): return .slab
        case (6, _): return .single
        case (7, 0): return .single
        case (7, _): return .slab
        case (8, 0): return .setback
        case (8, _): return .twin
        case (9, 0): return .twin
        case (9, _): return .setback
        case (_, 0): return .setback
        default:     return .twin
        }
    }

    static func towerSprite(kind: ZoneKind, level: Int, variant: Int) -> PixelCanvas {
        var c = PixelCanvas(width: zoneSize, height: towerCanvasHeight)
        let seed = UInt64(Int(kind.rawValue) * 1000 + level * 10 + variant + 77)
        var rng = SplitMix64(seed: seed)
        let baseY = towerCanvasHeight - 1

        let walls = wallPair(kind: kind, variant: variant)
        let mainWall = walls.main
        let podiumWall = walls.sub
        let roof = Palette.roofGrey

        // 塔の高さ。ここがレベルごとに大きく伸びる部分。土台は含まない。
        //
        // 区画の敷地は縦48px（3マスぶん）。塔をそのまま伸ばすと隣のマスの
        // 中身に容赦なく覆いかぶさってしまう。敷地の外へ出るぶんが最大でも
        // 1.5マス（24px）に収まるよう、L6〜7 は敷地の中に収め、
        // L8 以降だけ少しずつ隣へ顔を出す。
        let towerHeights: [Int] = [0, 0, 0, 0, 0, 0, 14, 24, 34, 44, 53]
        let towerHeight = towerHeights[min(max(level, 0), towerHeights.count - 1)]

        // 土台。区画いっぱいに広く、背は低いまま据え置く。
        // 屋根を真上へ伸ばす投影にしたので、幅と奥行きの両方を大きく取れる。
        let podiumW = 40, podiumH = 7, podiumDepth = 26
        let podiumX = 4
        let podiumFacadeTop = baseY - podiumH

        /// 地面に落ちる影の長さ。塔まで含めた高さで伸ばす。
        /// この影が、塊がそこに立っていることを一番わかりやすく示す。
        ///
        /// ただし影は右上へ伸びるので、伸ばしすぎるとスプライトの右端（48px）で
        /// 断ち切られて、不自然な縦の切り口が出る。枠に収まる長さで頭打ちにする。
        func groundShadow(x: Int, w: Int, height: Int, depth: Int) -> Int {
            min(2 + height / 5, max(1, zoneSize - x - w))
        }

        /// 低く広い土台を建てる。単塔・板状・セットバックはこの上に載る。
        func drawPodium() {
            box(&c, x: podiumX, baseY: baseY, w: podiumW, depth: podiumDepth, height: podiumH,
                wall: podiumWall, roof: roof, windows: Palette.window,
                shadow: groundShadow(x: podiumX, w: podiumW,
                                     height: podiumH + towerHeight, depth: podiumDepth),
                rng: &rng)
        }

        /// 土台の屋根の上に箱を1つ置く。
        ///
        /// 屋根は真上へ伸びるので、奥へ inset だけ入れた場所は、
        /// 手前の壁の面から見て「上へ inset」だけずれる。横にはずれない。
        /// `offsetX` は土台の左端からのずれ。
        func onPodium(offsetX: Int, w: Int, depth: Int, height: Int,
                      wall: RGBA) -> (cx: Int, topY: Int, x: Int, baseY: Int) {
            let inset = max(2, (podiumDepth - depth) / 2)
            let x = podiumX + offsetX
            let base = podiumFacadeTop - inset
            // 屋根の上に落ちる影は、屋根からはみ出さない長さに抑える。
            box(&c, x: x, baseY: base, w: w, depth: depth, height: height,
                wall: wall, roof: roof, windows: Palette.window,
                shadow: min(2 + height / 6, max(1, podiumDepth - inset - depth)), rng: &rng)
            return (x + w / 2, base - height - depth, x, base)
        }

        switch towerForm(level: level, variant: variant) {
        case .single:
            drawPodium()
            let w = 20, depth = 12
            let t = onPodium(offsetX: (podiumW - w) / 2, w: w, depth: depth,
                             height: towerHeight, wall: mainWall)
            if level >= 7 {
                spire(&c, cx: t.cx, topY: t.topY, height: level >= 9 ? 8 : 5, blink: Palette.beacon)
            }
            if level >= 8 {
                c.vLine(t.x, t.baseY - towerHeight + 3, towerHeight - 6, Palette.towerAccent)
            }

        case .slab:
            drawPodium()
            // 幅を取って奥行きを薄くする。塔というより壁のような塊になる。
            let w = 34, depth = 8
            let t = onPodium(offsetX: (podiumW - w) / 2, w: w, depth: depth,
                             height: towerHeight * 4 / 5, wall: mainWall)
            // 板の面を縦線で割って、のっぺりさせない。
            let h = towerHeight * 4 / 5
            c.vLine(t.x + w / 3, t.baseY - h + 2, h - 4, Palette.towerAccent)
            c.vLine(t.x + w * 2 / 3, t.baseY - h + 2, h - 4, Palette.towerAccent)
            if level >= 9 {
                spire(&c, cx: t.cx, topY: t.topY, height: 4, blink: Palette.beacon)
            }

        case .twin:
            // 2本を地面から直接立てる。土台は置かない。
            // 1つの低層部を2本で共有する建物は現実にはほとんどなく、
            // 載せると「大きな箱の上に塔が2本刺さっている」ようにしか見えない。
            // 土台のぶんの高さは塔の側に足して、他の形と背丈をそろえる。
            let w = 15, depth = 14, gap = 6
            let tallH = towerHeight + podiumH
            let shortH = tallH * 7 / 10
            let span = w * 2 + gap
            let leftX = (zoneSize - span) / 2

            // 奥から手前ではなく、左から右の順に描く。奥行きが右上へ伸びるので、
            // 右の棟があとに来ないと重なりの前後が逆になる。
            box(&c, x: leftX, baseY: baseY, w: w, depth: depth, height: shortH,
                wall: mainWall.shaded(0.92), roof: roof, windows: Palette.window,
                shadow: groundShadow(x: leftX, w: w, height: shortH, depth: depth), rng: &rng)

            let rightX = leftX + w + gap
            box(&c, x: rightX, baseY: baseY, w: w, depth: depth, height: tallH,
                wall: mainWall, roof: roof, windows: Palette.window,
                shadow: groundShadow(x: rightX, w: w, height: tallH, depth: depth), rng: &rng)

            let tallTopY = baseY - tallH - depth
            let tallCX = rightX + w / 2
            spire(&c, cx: tallCX, topY: tallTopY, height: level >= 9 ? 6 : 4, blink: Palette.beacon)
            if level >= 9 {
                c.vLine(rightX, baseY - tallH + 3, tallH - 6, Palette.towerAccent)
            }

        case .setback:
            drawPodium()
            // 段を重ねて上ほど細くする。各段の footprint は下の段の内側に収める。
            let stages = level >= 10 ? 3 : 2
            var widths: [Int] = []
            var heights: [Int] = []
            var depths: [Int] = []
            if stages == 3 {
                widths = [32, 22, 13]
                heights = [towerHeight * 9 / 20, towerHeight * 7 / 20, towerHeight * 4 / 20]
                depths = [18, 12, 7]
            } else {
                widths = [30, 19]
                heights = [towerHeight * 3 / 5, towerHeight * 2 / 5]
                depths = [18, 11]
            }
            // 1段目は土台の屋根の上に置き、2段目からは前の段の屋根の上に積む。
            let first = onPodium(offsetX: (podiumW - widths[0]) / 2, w: widths[0],
                                 depth: depths[0], height: heights[0], wall: mainWall)
            var frontX = first.x
            var frontBaseY = first.baseY - heights[0]
            var prevW = widths[0]
            var prevDepth = depths[0]
            var topCX = first.cx
            var topY = first.topY
            for i in 1..<stages {
                let w = widths[i], h = heights[i], d = depths[i]
                let inset = max(2, (prevDepth - d) / 2)
                frontX += (prevW - w) / 2
                frontBaseY -= inset
                box(&c, x: frontX, baseY: frontBaseY, w: w, depth: d, height: h,
                    wall: mainWall, roof: roof, windows: Palette.window,
                    shadow: max(1, 2 + h / 6), rng: &rng)
                topCX = frontX + w / 2
                topY = frontBaseY - h - d
                frontBaseY -= h
                prevW = w
                prevDepth = d
            }
            spire(&c, cx: topCX, topY: topY, height: level >= 9 ? 6 : 4, blink: Palette.beacon)
        }

        return c
    }

    // MARK: - 空き区画

    /// 区画は指定しただけでまだ何も建っていない状態。
    /// 下地は整地しただけの土のままにして、育った区画（芝・舗装・砂利）と見分けられるようにする。
    static func emptyLot(kind: ZoneKind) -> PixelCanvas {
        var c = PixelCanvas(width: zoneSize, height: zoneSize, fill: Palette.land.shaded(1.06))
        c.speckle(seed: 31, count: 70, color: Palette.landDark)
        c.speckle(seed: 32, count: 40, color: Palette.landLight)

        let color: RGBA
        switch kind {
        case .residential: color = Palette.zoneR
        case .commercial: color = Palette.zoneC
        default: color = Palette.zoneI
        }
        for x in stride(from: 0, to: zoneSize, by: 4) {
            c.rect(x, 1, 2, 1, color)
            c.rect(x, zoneSize - 2, 2, 1, color)
        }
        for y in stride(from: 0, to: zoneSize, by: 4) {
            c.rect(1, y, 1, 2, color)
            c.rect(zoneSize - 2, y, 1, 2, color)
        }
        return c
    }

    // MARK: - 住宅

    // 配置の決まりごと：奥行きは右上へ伸びるので、`x + w + depth` が 48 を超えると
    // 側面が切り落とされる。どの建物もこの中に収める。
    //
    // レベルの差は「高さ」で見せる。棟数や細部を変えても縮小すると読めないが、
    // 背の高さは小さく描いても一目でわかる。

    static func residential(level: Int, variant: Int) -> PixelCanvas {
        var rng = SplitMix64(seed: UInt64(level &* 100 &+ variant &+ 500))
        var c = grassGround(UInt64(variant &* 7 &+ 1))
        let roofs = [Palette.roofRed, Palette.roofBrown, Palette.roofBlue]
        let walls = wallPair(kind: .residential, variant: variant)

        switch level {
        case 1...3:
            // 低層。空き地の残り具合と棟数で、集落の育ち方を見せる。
            let w: Int, depth: Int, height: Int, rows: [(Int, [Int])]
            switch (level, variant) {
            case (1, 0): (w, depth, height, rows) = (12, 4, 4, [(26, [5]), (46, [24])])
            case (1, _): (w, depth, height, rows) = (12, 4, 4, [(24, [21]), (46, [6])])
            case (2, 0): (w, depth, height, rows) = (12, 5, 5, [(24, [3, 19]), (46, [10, 26])])
            case (2, _): (w, depth, height, rows) = (12, 5, 5, [(23, [6, 22]), (46, [2, 18])])
            case (3, 0): (w, depth, height, rows) = (10, 4, 6, [(17, [2, 13, 24, 34]), (32, [7, 18, 29]), (47, [13, 24])])
            default:     (w, depth, height, rows) = (10, 4, 6, [(17, [4, 15, 26, 34]), (32, [2, 13, 24, 34]), (47, [9, 20])])
            }
            var i = 0
            for (baseY, xs) in rows {
                for x in xs {
                    house(&c, x: x, baseY: baseY, w: w, depth: depth, height: height,
                          wall: i % 2 == 0 ? walls.main : walls.sub,
                          roof: roofs[i % roofs.count])
                    i += 1
                }
            }
            if level == 1 {
                tree(&c, 34, 12, scale: 1); tree(&c, 40, 20, scale: 1); tree(&c, 8, 36, scale: 1)
            } else if level == 2 {
                tree(&c, 41, 14, scale: 1); tree(&c, 38, 34, scale: 1)
            }

        case 4:
            // 低層の集合住宅。ここから1棟が区画をほぼ埋める。
            // 屋根を大きく取って、見下ろした絵として読ませる。
            let inset = variant % 2 == 0 ? 3 : 4
            box(&c, x: inset, baseY: 45, w: 48 - inset * 2, depth: 24, height: 6,
                wall: walls.main, roof: Palette.roofGrey, windows: Palette.window, rng: &rng)

        case 5:
            // 中層。壁を高くして、屋根はそのまま広く保つ。
            let inset = variant % 2 == 0 ? 2 : 3
            box(&c, x: inset, baseY: 45, w: 48 - inset * 2, depth: 25, height: 10,
                wall: walls.main, roof: Palette.roofGrey, windows: Palette.window, rng: &rng)
            c.hLine(inset + 2, 45 - 10 - 25 + 4, 48 - inset * 2 - 4, walls.sub.shaded(0.9))

        case 6:
            // 高層の手前。棟を2つに割って、片方を高くする。
            box(&c, x: 2, baseY: 45, w: 26, depth: 24, height: 13,
                wall: walls.main, roof: Palette.roofGrey, windows: Palette.window, rng: &rng)
            box(&c, x: 29, baseY: 45, w: 17, depth: 18, height: 9,
                wall: walls.sub, roof: Palette.roofGrey, windows: Palette.window, rng: &rng)

        default:
            // L7 以降は棟の集合ではなく、段を重ねた1本のタワーが主役になる。
            // 段ごとに絞り込むことで、壁を伸ばしすぎずに「本当に高い」ことを見せる。
            let mainWall = variant == 0 ? walls.main : walls.sub
            let sideWall = variant == 0 ? walls.sub : walls.main

            switch level {
            case 7:
                let top = steppedTower(&c, x: 2, baseY: 47, widths: [19, 12], heights: [10, 7],
                                       depths: [8, 4], wall: mainWall, roof: Palette.roofGrey,
                                       windows: Palette.window, rng: &rng)
                spire(&c, cx: top.cx, topY: top.topY, height: 5, blink: Palette.beacon)
                box(&c, x: 25, baseY: 28, w: 14, depth: 7, height: 8,
                    wall: sideWall, roof: Palette.roofGrey, windows: Palette.window, rng: &rng)

            case 8:
                let top = steppedTower(&c, x: 1, baseY: 47, widths: [20, 13], heights: [13, 9],
                                       depths: [9, 5], wall: mainWall, roof: Palette.roofGrey,
                                       windows: Palette.window, rng: &rng)
                spire(&c, cx: top.cx, topY: top.topY, height: 6, blink: Palette.beacon)
                box(&c, x: 24, baseY: 30, w: 15, depth: 8, height: 10,
                    wall: sideWall, roof: Palette.roofGrey, windows: Palette.window, rng: &rng)

            case 9:
                let top = steppedTower(&c, x: 1, baseY: 47, widths: [21, 14, 8], heights: [12, 8, 6],
                                       depths: [9, 6, 4], wall: mainWall, roof: Palette.roofGrey,
                                       windows: Palette.window, rng: &rng)
                spire(&c, cx: top.cx, topY: top.topY, height: 4, blink: Palette.beacon)
                c.vLine(6, 40, 6, Palette.towerAccent)
                box(&c, x: 25, baseY: 27, w: 14, depth: 8, height: 9,
                    wall: sideWall, roof: Palette.roofGrey, windows: Palette.window, rng: &rng)

            default:
                // L10。街でいちばん高い、街のランドマーク。
                let top = steppedTower(&c, x: 1, baseY: 47, widths: [22, 15, 9], heights: [15, 9, 6],
                                       depths: [9, 6, 4], wall: mainWall, roof: Palette.roofGrey,
                                       windows: Palette.window, rng: &rng)
                spire(&c, cx: top.cx, topY: top.topY, height: 4, blink: Palette.beacon)
                c.vLine(7, 34, 10, Palette.towerAccent)
                c.vLine(15, 44, 3, Palette.towerAccent)
                let small = steppedTower(&c, x: 26, baseY: 30, widths: [13, 8], heights: [8, 5],
                                         depths: [6, 3], wall: sideWall, roof: Palette.roofGrey,
                                         windows: Palette.window, rng: &rng)
                spire(&c, cx: small.cx, topY: small.topY, height: 3, blink: Palette.beacon)
            }
        }
        zoneBorder(&c, Palette.zoneRLine)
        return c
    }

    // MARK: - 商業

    static func commercial(level: Int, variant: Int) -> PixelCanvas {
        var rng = SplitMix64(seed: UInt64(level &* 200 &+ variant &+ 900))
        var c = pavementGround(UInt64(variant &* 11 &+ 2))
        let walls = wallPair(kind: .commercial, variant: variant)

        /// 入口の日よけ。低層の店にだけ付ける。
        func awning(_ x: Int, _ baseY: Int, _ w: Int) {
            c.rect(x + 1, baseY - 5, w - 2, 3, Palette.roofRed)
            for stripe in stride(from: 0, to: w - 2, by: 4) {
                c.rect(x + 1 + stripe, baseY - 5, 2, 3, Palette.wall)
            }
        }

        switch level {
        case 1:
            let x = variant == 0 ? 4 : 20
            box(&c, x: x, baseY: 40, w: 18, depth: 5, height: 5,
                wall: Palette.wall, roof: Palette.roofRed, windows: Palette.window, rng: &rng)
            awning(x, 40, 18)
            for y in stride(from: 42, to: 47, by: 3) { c.hLine(4, y, 40, Palette.pavementDark) }

        case 2:
            let rows = variant == 0 ? [(22, [2, 24]), (46, [12])] : [(21, [4, 24]), (46, [2])]
            var i = 0
            for (baseY, xs) in rows {
                for x in xs {
                    box(&c, x: x, baseY: baseY, w: 19, depth: 5, height: 6,
                        wall: Palette.wall,
                        roof: i % 2 == 0 ? Palette.roofRed : Palette.roofBlue,
                        windows: Palette.window, rng: &rng)
                    awning(x, baseY, 19)
                    i += 1
                }
            }

        case 3:
            box(&c, x: 26, baseY: 23, w: 16, depth: 6, height: 6,
                wall: Palette.wallWarm, roof: Palette.roofRed, windows: Palette.window, rng: &rng)
            box(&c, x: 2, baseY: 24, w: 22, depth: 6, height: 7,
                wall: Palette.wall, roof: Palette.roofBlue, windows: Palette.window, rng: &rng)
            box(&c, x: 3, baseY: 47, w: 21, depth: 6, height: 7,
                wall: Palette.wall, roof: Palette.roofBlue, windows: Palette.window, rng: &rng)
            awning(3, 47, 21)
            for y in stride(from: 32, to: 46, by: 4) { c.hLine(28, y, 16, Palette.pavementDark) }

        case 4:
            // 中規模の店舗。1棟が区画をほぼ埋める。
            let inset = variant % 2 == 0 ? 3 : 4
            box(&c, x: inset, baseY: 45, w: 48 - inset * 2, depth: 24, height: 7,
                wall: walls.main, roof: Palette.roofGrey, windows: Palette.window, rng: &rng)

        case 5:
            let inset = variant % 2 == 0 ? 2 : 3
            box(&c, x: inset, baseY: 45, w: 48 - inset * 2, depth: 25, height: 11,
                wall: walls.main, roof: Palette.roofGrey, windows: Palette.window, rng: &rng)
            c.hLine(inset + 2, 45 - 11 - 25 + 4, 48 - inset * 2 - 4, walls.sub.shaded(0.9))

        case 6:
            box(&c, x: 2, baseY: 45, w: 27, depth: 24, height: 14,
                wall: walls.main, roof: Palette.roofGrey, windows: Palette.window, rng: &rng)
            box(&c, x: 30, baseY: 45, w: 16, depth: 18, height: 10,
                wall: walls.sub, roof: Palette.roofGrey, windows: Palette.window, rng: &rng)

        default:
            // L7 以降はオフィスタワー1本が主役。ガラス張りで、住宅より少しとがった印象にする。
            let mainWall = variant == 0 ? walls.main : walls.sub
            let sideWall = variant == 0 ? walls.sub : walls.main

            switch level {
            case 7:
                let top = steppedTower(&c, x: 2, baseY: 47, widths: [19, 12], heights: [11, 7],
                                       depths: [8, 4], wall: mainWall, roof: Palette.roofGrey,
                                       windows: Palette.window, rng: &rng)
                spire(&c, cx: top.cx, topY: top.topY, height: 5, blink: Palette.beacon)
                box(&c, x: 25, baseY: 28, w: 14, depth: 7, height: 9,
                    wall: sideWall, roof: Palette.roofGrey, windows: Palette.window, rng: &rng)

            case 8:
                let top = steppedTower(&c, x: 1, baseY: 47, widths: [20, 13], heights: [14, 9],
                                       depths: [9, 5], wall: mainWall, roof: Palette.roofGrey,
                                       windows: Palette.window, rng: &rng)
                spire(&c, cx: top.cx, topY: top.topY, height: 6, blink: Palette.beacon)
                box(&c, x: 24, baseY: 30, w: 15, depth: 8, height: 11,
                    wall: sideWall, roof: Palette.roofGrey, windows: Palette.window, rng: &rng)

            case 9:
                let top = steppedTower(&c, x: 1, baseY: 47, widths: [21, 14, 8], heights: [13, 8, 6],
                                       depths: [9, 6, 4], wall: mainWall, roof: Palette.roofGrey,
                                       windows: Palette.window, rng: &rng)
                spire(&c, cx: top.cx, topY: top.topY, height: 4, blink: Palette.beacon)
                c.vLine(21, 25, 6, Palette.towerAccent)
                box(&c, x: 25, baseY: 27, w: 14, depth: 8, height: 10,
                    wall: sideWall, roof: Palette.roofGrey, windows: Palette.window, rng: &rng)

            default:
                // L10。街いちばんの摩天楼。
                let top = steppedTower(&c, x: 1, baseY: 47, widths: [22, 15, 9], heights: [16, 10, 6],
                                       depths: [9, 6, 4], wall: mainWall, roof: Palette.roofGrey,
                                       windows: Palette.window, rng: &rng)
                spire(&c, cx: top.cx, topY: top.topY, height: 5, blink: Palette.beacon)
                c.vLine(23, 20, 12, Palette.towerAccent)
                c.vLine(11, 40, 3, Palette.towerAccent)
                let small = steppedTower(&c, x: 26, baseY: 30, widths: [13, 8], heights: [9, 5],
                                         depths: [6, 3], wall: sideWall, roof: Palette.roofGrey,
                                         windows: Palette.window, rng: &rng)
                spire(&c, cx: small.cx, topY: small.topY, height: 3, blink: Palette.beacon)
            }
        }
        zoneBorder(&c, Palette.zoneCLine)
        return c
    }

    // MARK: - 工業

    static func industrial(level: Int, variant: Int) -> PixelCanvas {
        var rng = SplitMix64(seed: UInt64(level &* 300 &+ variant &+ 1300))
        var c = gravelGround(UInt64(variant &* 13 &+ 4))

        switch level {
        case 1:
            let x = variant == 0 ? 5 : 18
            box(&c, x: x, baseY: 38, w: 20, depth: 5, height: 5,
                wall: Palette.wallWarm, roof: Palette.roofGrey, rng: &rng)

        case 2:
            tank(&c, cx: 37, baseY: 26, r: 6, height: 6)
            box(&c, x: 3, baseY: 26, w: 22, depth: 5, height: 6,
                wall: Palette.wallWarm, roof: Palette.roofGrey, rng: &rng)
            box(&c, x: 24, baseY: 46, w: 17, depth: 5, height: 6,
                wall: Palette.wallWarm, roof: Palette.roofGrey, rng: &rng)

        case 3:
            tank(&c, cx: 38, baseY: 25, r: 7, height: 7)
            box(&c, x: 2, baseY: 26, w: 26, depth: 6, height: 7,
                wall: Palette.concrete, roof: Palette.roofGrey,
                windows: Palette.window, rng: &rng)
            tank(&c, cx: 37, baseY: 47, r: 7, height: 7)
            box(&c, x: 3, baseY: 47, w: 21, depth: 5, height: 7,
                wall: Palette.wallWarm, roof: Palette.roofGrey, rng: &rng)

        case 4:
            smokestack(&c, x: 9, baseY: 30, w: 5, height: 13)
            tank(&c, cx: 39, baseY: 30, r: 7, height: 7)
            box(&c, x: 2, baseY: 32, w: 27, depth: 7, height: 8,
                wall: Palette.concrete, roof: Palette.roofGrey,
                windows: Palette.window, rng: &rng)
            box(&c, x: 31, baseY: 47, w: 11, depth: 5, height: 6,
                wall: Palette.wallWarm, roof: Palette.roofGrey, rng: &rng)
            c.rect(2, 45, 28, 2, Palette.steel)

        case 5:
            smokestack(&c, x: 6, baseY: 33, w: 5, height: 15)
            smokestack(&c, x: 16, baseY: 33, w: 5, height: 13)
            tank(&c, cx: 39, baseY: 32, r: 7, height: 8)
            box(&c, x: 1, baseY: 36, w: 29, depth: 7, height: 8,
                wall: Palette.concrete, roof: Palette.roofGrey,
                windows: Palette.window, rng: &rng)
            box(&c, x: 32, baseY: 47, w: 10, depth: 5, height: 6,
                wall: Palette.wallWarm, roof: Palette.roofGrey, rng: &rng)
            c.rect(1, 44, 30, 2, Palette.steel)

        case 6:
            smokestack(&c, x: 5, baseY: 36, w: 5, height: 18)
            smokestack(&c, x: 14, baseY: 36, w: 5, height: 15)
            smokestack(&c, x: 23, baseY: 36, w: 4, height: 17)
            tank(&c, cx: 39, baseY: 34, r: 8, height: 9)
            box(&c, x: 1, baseY: 39, w: 30, depth: 8, height: 10,
                wall: Palette.concrete, roof: Palette.roofGrey,
                windows: Palette.window, rng: &rng)
            box(&c, x: 33, baseY: 47, w: 9, depth: 5, height: 6,
                wall: Palette.wallWarm, roof: Palette.roofGrey, rng: &rng)
            c.rect(1, 45, 32, 3, Palette.steel)

        default:
            // L7 以降は複合プラント。煙突とタンクが増え、最上位では炎（フレア）が立つ。
            let stackCount = min(5, level)
            let stackBaseY = 37
            let spanW = 26
            let spacing = stackCount > 1 ? spanW / (stackCount - 1) : 0
            for i in 0..<stackCount {
                let x = 3 + i * spacing
                let h = 16 + (i % 2 == 0 ? 6 : 0) + (level - 7) * 2
                smokestack(&c, x: x, baseY: stackBaseY, w: 4, height: h)
            }
            if level >= 9 {
                // いちばん奥の煙突にフレア（燃焼ガスの炎）を立てる。
                let flareX = 3
                let flareTopY = stackBaseY - (16 + 6 + (level - 7) * 2) - 3
                c.disc(flareX + 2, flareTopY, 3, Palette.beaconIndustrial)
                c.disc(flareX + 2, flareTopY - 2, 2, RGBA(255, 224, 140))
            }
            tank(&c, cx: 40, baseY: 33, r: 8, height: 9 + (level - 7))
            if level >= 8 { tank(&c, cx: 40, baseY: 47, r: 7, height: 8 + (level - 8)) }
            box(&c, x: 1, baseY: 39, w: 30, depth: 8, height: 10 + (level - 7),
                wall: Palette.concrete, roof: Palette.roofGrey,
                windows: Palette.window, rng: &rng)
            box(&c, x: level >= 8 ? 1 : 32, baseY: 47, w: level >= 8 ? 20 : 10,
                depth: level >= 8 ? 6 : 5, height: 7,
                wall: Palette.wallWarm, roof: Palette.roofGrey, rng: &rng)
            c.rect(1, 45, 32, 3, Palette.steel)
        }
        zoneBorder(&c, Palette.zoneILine)
        return c
    }

    // MARK: - 施設

    static func coalPlant() -> PixelCanvas {
        var rng = SplitMix64(seed: 5150)
        var c = gravelGround(77)

        smokestack(&c, x: 23, baseY: 34, w: 7, height: 16)
        smokestack(&c, x: 34, baseY: 36, w: 7, height: 18)
        c.disc(26, 15, 4, RGBA(214, 214, 214, 130))
        c.disc(37, 15, 5, RGBA(214, 214, 214, 150))
        c.disc(32, 19, 3, RGBA(214, 214, 214, 90))

        tank(&c, cx: 39, baseY: 46, r: 7, height: 7)
        box(&c, x: 1, baseY: 40, w: 29, depth: 8, height: 9,
            wall: Palette.concrete, roof: Palette.roofGrey,
            windows: Palette.window, rng: &rng)
        c.rect(1, 46, 30, 2, Palette.steel)
        zoneBorder(&c, Palette.serviceLine)
        return c
    }

    static func police() -> PixelCanvas {
        var rng = SplitMix64(seed: 911)
        var c = pavementGround(88)
        box(&c, x: 4, baseY: 42, w: 34, depth: 9, height: 9,
            wall: Palette.wall, roof: Palette.roofBlue,
            windows: Palette.window, rng: &rng)
        // 屋根の上の赤色灯。
        c.rect(20, 18, 2, 6, Palette.steel)
        c.disc(21, 17, 2, RGBA(90, 160, 250))
        c.set(20, 16, RGBA(190, 220, 255))
        c.rect(4, 45, 34, 1, Palette.pavementDark)
        zoneBorder(&c, Palette.serviceLine)
        return c
    }

    static func fireStation() -> PixelCanvas {
        var rng = SplitMix64(seed: 119)
        var c = pavementGround(99)
        box(&c, x: 3, baseY: 42, w: 36, depth: 9, height: 9,
            wall: Palette.roofRed, roof: Palette.roofRed.shaded(0.72), rng: &rng)
        // 車庫の扉を2つ。低い壁に収まる高さにする。
        c.rect(8, 34, 11, 7, Palette.wall)
        c.rect(23, 34, 11, 7, Palette.wall)
        for y in stride(from: 35, to: 41, by: 2) {
            c.hLine(8, y, 11, Palette.pavementDark)
            c.hLine(23, y, 11, Palette.pavementDark)
        }
        c.frame(8, 34, 11, 7, outline)
        c.frame(23, 34, 11, 7, outline)
        // 屋根の上の望楼。
        c.rect(19, 16, 3, 8, Palette.steel)
        c.rect(18, 14, 5, 3, Palette.steel.shaded(1.2))
        c.rect(3, 45, 36, 1, Palette.pavementDark)
        zoneBorder(&c, Palette.serviceLine)
        return c
    }

    // MARK: - 足りないものを知らせる印

    /// 電気が来ていない区画に出す稲妻。
    static func powerMarker() -> PixelCanvas {
        var c = PixelCanvas(width: tileSize, height: tileSize)
        c.disc(8, 8, 6, RGBA(18, 18, 24, 200))
        let bolt: [(Int, [Int])] = [
            (3, [9, 10]), (4, [8, 9]), (5, [7, 8]),
            (6, [6, 7, 8, 9, 10]), (7, [8, 9]),
            (8, [7, 8]), (9, [6, 7]), (10, [5, 6]),
        ]
        for (y, xs) in bolt {
            for x in xs { c.set(x, y, RGBA(250, 220, 70)) }
        }
        return c
    }

    /// 道路に面していない区画に出す印。
    static func roadMarker() -> PixelCanvas {
        var c = PixelCanvas(width: tileSize, height: tileSize)
        c.disc(8, 8, 6, RGBA(18, 18, 24, 200))
        for i in 0..<7 {
            c.set(5 + i, 5 + i, RGBA(250, 150, 60))
            c.set(11 - i, 5 + i, RGBA(250, 150, 60))
        }
        return c
    }

    // MARK: - 3x3 の建物をまとめて引く

    static func zoneArt(kind: ZoneKind, level: Int, variant: Int) -> PixelCanvas {
        switch kind {
        case .residential:
            return level == 0 ? emptyLot(kind: .residential) : residential(level: level, variant: variant)
        case .commercial:
            return level == 0 ? emptyLot(kind: .commercial) : commercial(level: level, variant: variant)
        case .industrial:
            return level == 0 ? emptyLot(kind: .industrial) : industrial(level: level, variant: variant)
        case .coalPlant:
            return coalPlant()
        case .police:
            return police()
        case .fire:
            return fireStation()
        }
    }
}
