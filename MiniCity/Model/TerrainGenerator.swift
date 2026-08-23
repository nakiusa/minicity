import Foundation

/// 決定的な擬似乱数。同じ種から同じ地形を作れるようにする。
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// 格子点に乱数を置いて補間する、いわゆる value noise。地形の起伏と森の分布に使う。
struct ValueNoise {
    private let seed: UInt64

    init(seed: UInt64) { self.seed = seed }

    private func hash(_ x: Int, _ y: Int) -> Double {
        var h = UInt64(bitPattern: Int64(x &* 374_761_393 &+ y &* 668_265_263)) ^ seed
        h = (h ^ (h >> 13)) &* 1_274_126_177
        h ^= h >> 16
        return Double(h & 0xFFFF) / 65535.0
    }

    private func smooth(_ t: Double) -> Double { t * t * (3 - 2 * t) }

    func value(_ x: Double, _ y: Double) -> Double {
        let xi = Int(floor(x)), yi = Int(floor(y))
        let xf = smooth(x - floor(x)), yf = smooth(y - floor(y))
        let a = hash(xi, yi), b = hash(xi + 1, yi)
        let c = hash(xi, yi + 1), d = hash(xi + 1, yi + 1)
        let top = a + (b - a) * xf
        let bottom = c + (d - c) * xf
        return top + (bottom - top) * yf
    }

    /// 複数の周波数を重ねて、細部と大きな起伏を両立させる。
    func fbm(_ x: Double, _ y: Double, octaves: Int = 4) -> Double {
        var sum = 0.0, amp = 1.0, freq = 1.0, norm = 0.0
        for _ in 0..<octaves {
            sum += amp * value(x * freq, y * freq)
            norm += amp
            amp *= 0.5
            freq *= 2.0
        }
        return sum / norm
    }
}

enum TerrainGenerator {

    /// 川と湖と森を持つ地形を生成する。
    static func generate(into map: CityMap, seed: UInt64) {
        var rng = SplitMix64(seed: seed)
        let noise = ValueNoise(seed: seed)
        let forestNoise = ValueNoise(seed: seed &* 31 &+ 7)

        let w = CityMap.width, h = CityMap.height

        for y in 0..<h {
            for x in 0..<w {
                map.setTile(x, y, Tile(terrain: .dirt))
            }
        }

        carveRiver(map: map, rng: &rng, noise: noise)
        carveLakes(map: map, rng: &rng, noise: noise)

        // 森は水辺に寄せると、川沿いに緑が残る自然な絵になる。
        for y in 0..<h {
            for x in 0..<w {
                guard map.tile(x, y).terrain == .dirt else { continue }
                let n = forestNoise.fbm(Double(x) * 0.055, Double(y) * 0.055, octaves: 4)
                if n > 0.56 {
                    map.mutateTile(x, y) { $0.terrain = .forest }
                }
            }
        }

        map.markAllDirty()
    }

    /// 上端から下端へ蛇行する川を1本掘る。
    private static func carveRiver(map: CityMap, rng: inout SplitMix64, noise: ValueNoise) {
        let h = CityMap.height
        var cx = Double(Int.random(in: (CityMap.width / 4)..<(CityMap.width * 3 / 4), using: &rng))
        let phase = Double.random(in: 0..<6.28, using: &rng)

        for y in 0..<h {
            let t = Double(y)
            let meander = sin(t * 0.07 + phase) * 2.2 + (noise.fbm(t * 0.06, 11.0, octaves: 3) - 0.5) * 6.0
            cx += meander * 0.35
            cx = min(max(cx, 6), Double(CityMap.width - 7))

            let width = 3.0 + noise.fbm(t * 0.05, 3.0, octaves: 2) * 4.0
            let half = Int((width / 2).rounded())
            let center = Int(cx.rounded())
            for dx in -half...half {
                map.mutateTile(center + dx, y) { $0.terrain = .water }
            }
        }
    }

    /// 湖をいくつか置く。fbm を丸くマスクして輪郭をぼかす。
    private static func carveLakes(map: CityMap, rng: inout SplitMix64, noise: ValueNoise) {
        let lakeCount = Int.random(in: 1...3, using: &rng)
        for _ in 0..<lakeCount {
            let lx = Int.random(in: 10..<(CityMap.width - 10), using: &rng)
            let ly = Int.random(in: 10..<(CityMap.height - 10), using: &rng)
            let radius = Double(Int.random(in: 6...13, using: &rng))

            let ir = Int(radius) + 3
            for dy in -ir...ir {
                for dx in -ir...ir {
                    let d = (Double(dx * dx) / (radius * radius)) + (Double(dy * dy) / (radius * radius * 0.6))
                    guard d < 1.4 else { continue }
                    let wobble = noise.fbm(Double(lx + dx) * 0.12, Double(ly + dy) * 0.12, octaves: 3)
                    if d + (wobble - 0.5) * 0.9 < 1.0 {
                        map.mutateTile(lx + dx, ly + dy) { $0.terrain = .water }
                    }
                }
            }
        }
    }
}
