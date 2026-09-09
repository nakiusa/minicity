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
// 見出しに割く高さと、下の余白から端末画像の大きさを決める。
// 画像の縦横比は端末のままなので、幅は高さから逆算する。
let headerH = 430
let bottomMargin = 96
let shotH = H - headerH - bottomMargin
let shotW = Int((Double(shotH) * Double(W) / Double(H)).rounded())
let shotX = (W - shotW) / 2
let shotY = headerH
/// 見出しの下に引く短い線の色。アイコンの窓明かりと同じ金色。
let accent = CGColor(red: 0.96, green: 0.78, blue: 0.25, alpha: 1)

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
let radius = CGFloat(shotW) * 0.052
let rounded = CGPath(roundedRect: shotRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
// 影を落として、背景から浮かせる。地の色が近いので、これがないと絵が沈む。
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -22), blur: 48,
              color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.55))
ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
ctx.addPath(rounded)
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(rounded)
ctx.clip()
ctx.draw(shot, in: shotRect)
ctx.restoreGState()
ctx.addPath(rounded)
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.14))
ctx.setLineWidth(3)
ctx.strokePath()

/// 中央そろえで1行引く。y は上端からの距離で受ける。返すのは描いた幅。
@discardableResult
func drawCentered(_ text: String, fontName: String, size: CGFloat, topY: CGFloat, alpha: CGFloat) -> Double {
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
    return width
}

/// 収まらない説明文を2行に折る。読点か句点で切れる場所を探し、なければ真ん中で割る。
func wrap(_ text: String, fontName: String, size: CGFloat, limit: Double) -> [String] {
    let font = CTFontCreateWithName(fontName as CFString, size, nil)
    func measure(_ s: String) -> Double {
        let a = CFAttributedStringCreate(nil, s as CFString,
                                         [kCTFontAttributeName: font] as CFDictionary)!
        return CTLineGetTypographicBounds(CTLineCreateWithAttributedString(a), nil, nil, nil)
    }
    guard measure(text) > limit else { return [text] }
    let chars = Array(text)
    let middle = chars.count / 2
    var cut = middle
    var best = chars.count
    for (i, c) in chars.enumerated() where c == "、" || c == "。" {
        if abs(i - middle) < best { best = abs(i - middle); cut = i + 1 }
    }
    return [String(chars[..<cut]), String(chars[cut...])]
}

drawCentered(headline, fontName: "HiraginoSans-W6", size: 74, topY: 132, alpha: 1.0)

// 見出しと説明のあいだの短い線。二つの役割の違いを、余白だけより早く伝える。
ctx.setFillColor(accent)
ctx.fill(CGRect(x: CGFloat(W) / 2 - 48, y: CGFloat(H) - 252, width: 96, height: 6))

let lines = wrap(subline, fontName: "HiraginoSans-W3", size: 38, limit: 1060)
for (i, line) in lines.enumerated() {
    drawCentered(line, fontName: "HiraginoSans-W3", size: 38,
                 topY: 300 + CGFloat(i) * 56, alpha: 0.74)
}

guard let out = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outPath) as CFURL,
                                                 UTType.png.identifier as CFString, 1, nil) else { exit(1) }
CGImageDestinationAddImage(dest, out, nil)
CGImageDestinationFinalize(dest)
print("wrote \(outPath) (\(W)x\(H))")
