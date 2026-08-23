import CoreGraphics
import Foundation

struct RGBA {
    var r: UInt8, g: UInt8, b: UInt8, a: UInt8

    init(_ r: Int, _ g: Int, _ b: Int, _ a: Int = 255) {
        self.r = UInt8(clamping: r)
        self.g = UInt8(clamping: g)
        self.b = UInt8(clamping: b)
        self.a = UInt8(clamping: a)
    }

    static let clear = RGBA(0, 0, 0, 0)

    /// 1.0 より小さければ暗く、大きければ明るくする。
    func shaded(_ f: Double) -> RGBA {
        RGBA(Int(Double(r) * f), Int(Double(g) * f), Int(Double(b) * f), Int(a))
    }
}

/// ドット絵を1ピクセルずつ置くための小さなキャンバス。
/// SpriteKit のテクスチャに変換して使う。
struct PixelCanvas {
    let width: Int
    let height: Int
    private var bytes: [UInt8]

    init(width: Int, height: Int, fill: RGBA = .clear) {
        self.width = width
        self.height = height
        bytes = [UInt8](repeating: 0, count: width * height * 4)
        if fill.a > 0 { self.fill(fill) }
    }

    mutating func fill(_ c: RGBA) {
        for y in 0..<height {
            for x in 0..<width { set(x, y, c) }
        }
    }

    @inline(__always)
    mutating func set(_ x: Int, _ y: Int, _ c: RGBA) {
        guard x >= 0, y >= 0, x < width, y < height, c.a > 0 else { return }
        let i = (y * width + x) * 4
        if c.a == 255 {
            bytes[i] = c.r; bytes[i + 1] = c.g; bytes[i + 2] = c.b; bytes[i + 3] = 255
        } else {
            // 前景色を alpha で載せる。事前乗算のまま扱えるよう単純合成にする。
            let a = Double(c.a) / 255.0
            let inv = 1 - a
            bytes[i] = UInt8(Double(c.r) * a + Double(bytes[i]) * inv)
            bytes[i + 1] = UInt8(Double(c.g) * a + Double(bytes[i + 1]) * inv)
            bytes[i + 2] = UInt8(Double(c.b) * a + Double(bytes[i + 2]) * inv)
            bytes[i + 3] = UInt8(max(Double(c.a), Double(bytes[i + 3])))
        }
    }

    @inline(__always)
    func get(_ x: Int, _ y: Int) -> RGBA {
        guard x >= 0, y >= 0, x < width, y < height else { return .clear }
        let i = (y * width + x) * 4
        return RGBA(Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]), Int(bytes[i + 3]))
    }

    mutating func rect(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: RGBA) {
        guard w > 0, h > 0 else { return }
        for yy in y..<(y + h) {
            for xx in x..<(x + w) { set(xx, yy, c) }
        }
    }

    mutating func frame(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: RGBA) {
        rect(x, y, w, 1, c)
        rect(x, y + h - 1, w, 1, c)
        rect(x, y, 1, h, c)
        rect(x + w - 1, y, 1, h, c)
    }

    mutating func hLine(_ x: Int, _ y: Int, _ w: Int, _ c: RGBA) { rect(x, y, w, 1, c) }
    mutating func vLine(_ x: Int, _ y: Int, _ h: Int, _ c: RGBA) { rect(x, y, 1, h, c) }

    mutating func disc(_ cx: Int, _ cy: Int, _ r: Int, _ c: RGBA) {
        for dy in -r...r {
            for dx in -r...r where dx * dx + dy * dy <= r * r {
                set(cx + dx, cy + dy, c)
            }
        }
    }

    /// 決まった種から同じ模様を散らす。地面のざらつきに使う。
    mutating func speckle(seed: UInt64, count: Int, color: RGBA) {
        var rng = SplitMix64(seed: seed)
        for _ in 0..<count {
            let x = Int.random(in: 0..<width, using: &rng)
            let y = Int.random(in: 0..<height, using: &rng)
            set(x, y, color)
        }
    }

    // MARK: - 書き出し

    func cgImage() -> CGImage? {
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        var data = bytes
        // premultipliedLast として渡すので、半透明部分の色を alpha で畳んでおく。
        for i in stride(from: 0, to: data.count, by: 4) {
            let a = Double(data[i + 3]) / 255.0
            if a < 1 {
                data[i] = UInt8(Double(data[i]) * a)
                data[i + 1] = UInt8(Double(data[i + 1]) * a)
                data[i + 2] = UInt8(Double(data[i + 2]) * a)
            }
        }
        guard let provider = CGDataProvider(data: Data(data) as CFData) else { return nil }
        return CGImage(width: width, height: height,
                       bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4,
                       space: space, bitmapInfo: info,
                       provider: provider, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)
    }

    /// 48x48 の絵を 16x16 の9枚に切り出す。3x3 ゾーンの描画に使う。
    func slice(cols: Int, rows: Int) -> [PixelCanvas] {
        let tw = width / cols, th = height / rows
        var out: [PixelCanvas] = []
        for ry in 0..<rows {
            for rx in 0..<cols {
                var piece = PixelCanvas(width: tw, height: th)
                for y in 0..<th {
                    for x in 0..<tw {
                        piece.set(x, y, get(rx * tw + x, ry * th + y))
                    }
                }
                out.append(piece)
            }
        }
        return out
    }
}
