import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

// スクリーンショットに見出しを載せる。
// App Store のスクショは1枚ずつ何を見せているかを言わないと、
// スワイプする人には4枚の違いが伝わらない。
//
// 使いかた: shotframe <入力.png> <出力.png> <見出し> <説明>

let args = CommandLine.arguments
guard args.count == 5 else {
    FileHandle.standardError.write("usage: shotframe <in.png> <out.png> <headline> <subline>\n".data(using: .utf8)!)
    exit(1)
}
let (inPath, outPath, headline, subline) = (args[1], args[2], args[3], args[4])

let W = 1284, H = 2778
// 端末画像の幅と、見出しに割く高さ。合計が H に収まるよう決めてある。
let shotW = 1028
let shotH = Int((Double(shotW) * Double(H) / Double(W)).rounded())
let headerH = 420
let shotX = (W - shotW) / 2
let shotY = headerH

guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: inPath) as CFURL, nil),
      let shot = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
    FileHandle.standardError.write("読めない: \(inPath)\n".data(using: .utf8)!)
    exit(1)
}

guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8,
                          bytesPerRow: W * 4, space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { exit(1) }

// 背景。アイコンと同じ夜空の色を上から下へ。
for y in 0..<H {
    let t = Double(y) / Double(H)
    ctx.setFillColor(CGColor(red: (18 + 26 * t) / 255, green: (26 + 38 * t) / 255,
                             blue: (48 + 58 * t) / 255, alpha: 1))
    ctx.fill(CGRect(x: 0, y: H - y - 1, width: W, height: 1))
}

// CoreGraphics の原点は左下なので、上下を反転してから端末画像を置く。
let shotRect = CGRect(x: shotX, y: H - shotY - shotH, width: shotW, height: shotH)
let rounded = CGPath(roundedRect: shotRect, cornerWidth: 40, cornerHeight: 40, transform: nil)
ctx.saveGState()
ctx.addPath(rounded)
ctx.clip()
ctx.draw(shot, in: shotRect)
ctx.restoreGState()
ctx.addPath(rounded)
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.16))
ctx.setLineWidth(3)
ctx.strokePath()

/// 中央そろえで1行引く。y は上端からの距離で受ける。
func drawCentered(_ text: String, fontName: String, size: CGFloat, topY: CGFloat, alpha: CGFloat) {
    // AppKit を持ち込まないので、属性キーは CoreText のものを直接使う。
    let font = CTFontCreateWithName(fontName as CFString, size, nil)
    let attrs: [CFString: Any] = [
        kCTFontAttributeName: font,
        kCTForegroundColorAttributeName: CGColor(red: 1, green: 1, blue: 1, alpha: alpha),
    ]
    let attributed = CFAttributedStringCreate(nil, text as CFString, attrs as CFDictionary)!
    let line = CTLineCreateWithAttributedString(attributed)
    var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
    let width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
    ctx.textPosition = CGPoint(x: (CGFloat(W) - CGFloat(width)) / 2,
                               y: CGFloat(H) - topY - ascent)
    CTLineDraw(line, ctx)
}

drawCentered(headline, fontName: "HiraginoSans-W6", size: 76, topY: 150, alpha: 1.0)
drawCentered(subline, fontName: "HiraginoSans-W3", size: 40, topY: 268, alpha: 0.72)

guard let out = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outPath) as CFURL,
                                                 UTType.png.identifier as CFString, 1, nil) else { exit(1) }
CGImageDestinationAddImage(dest, out, nil)
CGImageDestinationFinalize(dest)
print("wrote \(outPath) (\(W)x\(H))")
