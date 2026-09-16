import UIKit

/// 成績表を SNS に貼るための1枚絵。街の俯瞰の下に、人口と年数を大きく書く。
enum ShareCard {
    /// 横幅はこれに揃える。SpriteKit から来る絵は画面の倍率ぶん大きいので縮める。
    static let width: CGFloat = 1920

    static func make(city: CGImage, population: Int, years: Int) -> UIImage {
        let w = width, h = (width * CGFloat(city.height) / CGFloat(city.width)).rounded()
        let band: CGFloat = 220
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: w, height: h + band), format: format).image { ctx in
            let g = ctx.cgContext
            g.interpolationQuality = .none
            // SpriteKit の絵は上下が逆なので、CoreGraphics で反転して置く。
            g.saveGState()
            g.translateBy(x: 0, y: h)
            g.scaleBy(x: 1, y: -1)
            g.draw(city, in: CGRect(x: 0, y: 0, width: w, height: h))
            g.restoreGState()

            UIColor(red: 0.07, green: 0.09, blue: 0.14, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: h, width: w, height: band))

            let big = String(localized: "人口 \(population.formatted())人")
            let small = String(localized: "\(years)年で育てた街 · MiniCity")
            let pad: CGFloat = 60
            draw(big, at: CGPoint(x: pad, y: h + 44),
                 font: .systemFont(ofSize: 88, weight: .heavy), color: .white)
            draw(small, at: CGPoint(x: pad, y: h + 150),
                 font: .systemFont(ofSize: 40, weight: .semibold), color: UIColor(white: 1, alpha: 0.7))
        }
    }

    private static func draw(_ text: String, at p: CGPoint, font: UIFont, color: UIColor) {
        let font = UIFont(descriptor: font.fontDescriptor.withDesign(.rounded) ?? font.fontDescriptor, size: font.pointSize)
        (text as NSString).draw(at: p, withAttributes: [.font: font, .foregroundColor: color])
    }
}
