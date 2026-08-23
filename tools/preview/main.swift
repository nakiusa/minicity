import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func writePNG(_ canvas: PixelCanvas, zoom: Int, to path: String) {
    let width = canvas.width * zoom, height = canvas.height * zoom
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<canvas.height {
        for x in 0..<canvas.width {
            let color = canvas.get(x, y)
            for dy in 0..<zoom {
                for dx in 0..<zoom {
                    let i = ((y * zoom + dy) * width + x * zoom + dx) * 4
                    bytes[i] = color.r; bytes[i + 1] = color.g; bytes[i + 2] = color.b; bytes[i + 3] = 255
                }
            }
        }
    }
    let space = CGColorSpaceCreateDeviceRGB()
    let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                        bytesPerRow: width * 4, space: space, bitmapInfo: info,
                        provider: provider, decode: nil, shouldInterpolate: false,
                        intent: .defaultIntent)!
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL,
                                               UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    print("wrote \(path) (\(width)x\(height))")
}

func blit(_ dst: inout PixelCanvas, _ src: PixelCanvas, x: Int, y: Int) {
    for sy in 0..<src.height {
        for sx in 0..<src.width {
            let color = src.get(sx, sy)
            if color.a > 0 { dst.set(x + sx, y + sy, color) }
        }
    }
}

// レベルの見本。1から10まで横に並べて、段が上がるごとに背がどれだけ伸びるかを見る。
// 高層タワーはマスの上へはみ出すので、行の間を広めに取ってある。
let tilesX = 34, tilesY = 22
var scene = PixelCanvas(width: tilesX * 16, height: tilesY * 16)

for ty in 0..<tilesY {
    for tx in 0..<tilesX {
        let h = abs(tx &* 7 &+ ty &* 13 &+ tx &* ty)
        blit(&scene, TileArt.land(variant: h % 4), x: tx * 16, y: ty * 16)
    }
}

/// アプリと同じ描き分けをする。住宅と商業の高レベルだけは、
/// 敷地の地面と、上へ伸びるタワーの2枚に分かれる。
func placeZone(kind: ZoneKind, level: Int, variant: Int, tx: Int, ty: Int) {
    let isTower = (kind == .residential || kind == .commercial) && level >= TileArt.towerMinLevel
    if isTower {
        blit(&scene, TileArt.zoneGroundArt(kind: kind, variant: variant), x: tx * 16, y: ty * 16)
        let overhang = TileArt.towerCanvasHeight - TileArt.zoneSize
        blit(&scene, TileArt.towerSprite(kind: kind, level: level, variant: variant),
             x: tx * 16, y: ty * 16 - overhang)
    } else {
        blit(&scene, TileArt.zoneArt(kind: kind, level: level, variant: variant), x: tx * 16, y: ty * 16)
    }
}

/// 1段ずつ横に並べた1行。左が更地で、右へ行くほど育つ。
func ladder(_ kind: ZoneKind, ty: Int) {
    for level in 0...Zone.maxLevel {
        placeZone(kind: kind, level: level, variant: level % 2, tx: level * 3, ty: ty)
    }
}

ladder(.residential, ty: 3)
ladder(.commercial, ty: 9)
ladder(.industrial, ty: 15)

// 施設と地面の見本。道路ぞいに並べて、隣り合ったときの見え方も確かめる。
for tx in 0..<tilesX {
    blit(&scene, TileArt.road(mask: 2 | 8), x: tx * 16, y: 18 * 16)
}
blit(&scene, TileArt.zoneArt(kind: .coalPlant, level: 0, variant: 0), x: 0, y: 19 * 16)
blit(&scene, TileArt.zoneArt(kind: .police, level: 0, variant: 0), x: 3 * 16, y: 19 * 16)
blit(&scene, TileArt.zoneArt(kind: .fire, level: 0, variant: 0), x: 6 * 16, y: 19 * 16)
for tx in 9..<13 {
    blit(&scene, TileArt.wire(mask: 2 | 8), x: tx * 16, y: 20 * 16)
}
blit(&scene, TileArt.park(), x: 13 * 16, y: 20 * 16)
blit(&scene, TileArt.park(), x: 14 * 16, y: 20 * 16)
blit(&scene, TileArt.rubble(), x: 16 * 16, y: 20 * 16)
blit(&scene, TileArt.forest(variant: 0), x: 18 * 16, y: 20 * 16)
blit(&scene, TileArt.water(variant: 0), x: 19 * 16, y: 20 * 16)
blit(&scene, TileArt.trafficCars(mask: 2 | 8, level: 2), x: 21 * 16, y: 18 * 16)

writePNG(scene, zoom: 3, to: CommandLine.arguments[1])
