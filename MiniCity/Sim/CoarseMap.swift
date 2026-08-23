import Foundation

/// 公害・土地価値・犯罪などを保持する粗い解像度のマップ。
/// タイル4マスぶんを1セルにまとめることで、拡散の計算量を1/16に落とす。
struct CoarseMap {
    static let scale = 4
    static let width = CityMap.width / scale
    static let height = CityMap.height / scale

    private(set) var cells: [Int]

    init(_ initial: Int = 0) {
        cells = Array(repeating: initial, count: CoarseMap.width * CoarseMap.height)
    }

    @inline(__always)
    subscript(cx: Int, cy: Int) -> Int {
        get {
            guard cx >= 0, cy >= 0, cx < CoarseMap.width, cy < CoarseMap.height else { return 0 }
            return cells[cy * CoarseMap.width + cx]
        }
        set {
            guard cx >= 0, cy >= 0, cx < CoarseMap.width, cy < CoarseMap.height else { return }
            cells[cy * CoarseMap.width + cx] = newValue
        }
    }

    /// タイル座標で引く。
    @inline(__always)
    func atTile(_ x: Int, _ y: Int) -> Int {
        self[x / CoarseMap.scale, y / CoarseMap.scale]
    }

    @inline(__always)
    mutating func addAtTile(_ x: Int, _ y: Int, _ amount: Int) {
        let cx = x / CoarseMap.scale, cy = y / CoarseMap.scale
        self[cx, cy] = self[cx, cy] + amount
    }

    mutating func clear(_ value: Int = 0) {
        for i in cells.indices { cells[i] = value }
    }

    /// 3x3 の平均で1回ならす。公害や警察の影響が周囲へ染み出す動きを作る。
    mutating func blur() {
        var out = cells
        let w = CoarseMap.width, h = CoarseMap.height
        for cy in 0..<h {
            for cx in 0..<w {
                var sum = 0, count = 0
                for dy in -1...1 {
                    for dx in -1...1 {
                        let nx = cx + dx, ny = cy + dy
                        guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
                        sum += cells[ny * w + nx]
                        count += 1
                    }
                }
                out[cy * w + cx] = sum / count
            }
        }
        cells = out
    }

    mutating func clamp(_ lo: Int, _ hi: Int) {
        for i in cells.indices { cells[i] = min(max(cells[i], lo), hi) }
    }

    var maximum: Int { cells.max() ?? 0 }
}
