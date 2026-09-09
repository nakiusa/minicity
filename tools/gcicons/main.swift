import AppKit
import Foundation
import ImageIO

// Game Center の達成項目に載せる絵を、実績の定義から34枚作る。
//
// 記号はアプリの一覧で使っているものをそのまま使う。画面で見ている絵と、
// Game Center で見る絵が食い違わないようにするため。
//
//   swiftc -O -o gcicons MiniCity/Model/*.swift MiniCity/Sim/*.swift tools/gcicons/main.swift
//   ./gcicons out/            # 512x512 の PNG を書き出す

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "gcicons"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let side = 512
/// 背景。アプリの暗い画面に合わせる。
let backTop = NSColor(srgbRed: 0.13, green: 0.14, blue: 0.17, alpha: 1)
let backBottom = NSColor(srgbRed: 0.06, green: 0.07, blue: 0.09, alpha: 1)
/// 取った実績の色。一覧の金色と揃える。
let gold = NSColor(srgbRed: 0.98, green: 0.80, blue: 0.28, alpha: 1)

/// 512x512 の絵を1枚描く。
///
/// 透明を含まない並び（noneSkipLast）で描く。`NSBitmapImageRep` の
/// 3成分・アルファなしでは描画文脈を作れず、真っ黒な絵ができあがる。
func render(symbol: String) -> CGImage? {
    guard let ctx = CGContext(data: nil, width: side, height: side,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    defer { NSGraphicsContext.restoreGraphicsState() }

    let full = NSRect(x: 0, y: 0, width: side, height: side)
    NSGradient(starting: backTop, ending: backBottom)?.draw(in: full, angle: -90)

    // 金の輪。記号だけだと画面の中で沈む。
    let ringInset = CGFloat(side) * 0.13
    let ring = NSBezierPath(ovalIn: full.insetBy(dx: ringInset, dy: ringInset))
    gold.withAlphaComponent(0.14).setFill()
    ring.fill()
    gold.withAlphaComponent(0.55).setStroke()
    ring.lineWidth = CGFloat(side) * 0.012
    ring.stroke()

    guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) else {
        return nil
    }
    let config = NSImage.SymbolConfiguration(pointSize: CGFloat(side) * 0.34, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [gold]))
    guard let glyph = image.withSymbolConfiguration(config) else { return nil }

    // 記号は真ん中に。縦横の比が違っても、はみ出さないように収める。
    let maxSide = CGFloat(side) * 0.44
    var size = glyph.size
    let scale = min(maxSide / size.width, maxSide / size.height)
    size = NSSize(width: size.width * scale, height: size.height * scale)
    let origin = NSPoint(x: (CGFloat(side) - size.width) / 2, y: (CGFloat(side) - size.height) / 2)
    glyph.draw(in: NSRect(origin: origin, size: size))

    return ctx.makeImage()
}

func writePNG(_ image: CGImage, to path: String) -> Bool {
    guard let dest = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil) else { return false }
    CGImageDestinationAddImage(dest, image, nil)
    return CGImageDestinationFinalize(dest)
}

var missing: [String] = []
var wrote = 0
for a in Achievements.all {
    guard let image = render(symbol: a.symbol) else {
        missing.append("\(a.id)（\(a.symbol)）")
        continue
    }
    if writePNG(image, to: "\(outDir)/\(a.id).png") {
        wrote += 1
    } else {
        FileHandle.standardError.write("\(a.id).png を書けません\n".data(using: .utf8)!)
    }
}

print("\(wrote) 枚を \(outDir)/ に書き出した")
if !missing.isEmpty {
    FileHandle.standardError.write("記号が見つからない: \(missing.joined(separator: ", "))\n".data(using: .utf8)!)
    exit(1)
}
