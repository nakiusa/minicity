import SwiftUI

/// メニュー画面（予算・実績・ヘルプ・成績表など）の見た目の決まり。
///
/// 標準の設定画面の部品をそのまま並べると、どのアプリにもある灰色の箱になり、
/// ドット絵の街から急に事務的な画面へ切り替わってしまう。夜空の地に、同じドット絵の
/// 街並みを敷き、見出しはドットの書体で揃えて、ゲームの中の続きに見えるようにする。
enum Theme {
    static let skyTop = Color(red: 0.035, green: 0.05, blue: 0.13)
    static let skyBottom = Color(red: 0.13, green: 0.09, blue: 0.25)
    static let ink = Color(red: 0.94, green: 0.93, blue: 0.98)
    static let mute = Color(red: 0.62, green: 0.63, blue: 0.76)
    static let rule = Color.white.opacity(0.12)
    /// 行の下地。夜空が透けるくらいに薄く。
    static let plate = Color(red: 0.10, green: 0.11, blue: 0.22).opacity(0.9)
    static let gain = Color(red: 0.55, green: 0.86, blue: 0.62)
    static let loss = Color(red: 0.98, green: 0.47, blue: 0.43)
    static let gold = Color(red: 0.98, green: 0.80, blue: 0.28)
    static let residential = color(Palette.zoneR)
    static let commercial = color(Palette.zoneC)
    static let industrial = color(Palette.zoneI)

    static func color(_ c: RGBA) -> Color {
        Color(red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255)
    }

    /// 地平に並ぶ街並み。ゲームの高層タワーの絵を暗く沈め、窓の明かりだけを残す。
    /// 作るのに少し時間がかかるので、最初の1回だけ描いて使い回す。
    static let skyline: UIImage? = {
        let w = 360, h = 110
        var c = PixelCanvas(width: w, height: h)
        var rng = SplitMix64(seed: 2026)
        var x = -10
        while x < w {
            let kind: ZoneKind = rng.next() % 2 == 0 ? .residential : .commercial
            let level = TileArt.towerMinLevel + Int(rng.next() % UInt64(Zone.maxLevel - TileArt.towerMinLevel + 1))
            let art = TileArt.towerSprite(kind: kind, level: level, variant: Int(rng.next() % 4))
            let top = h - art.height + Int(rng.next() % 18)
            for sy in 0..<art.height {
                for sx in 0..<art.width {
                    let p = art.get(sx, sy)
                    guard p.a > 0 else { continue }
                    // 窓（青みの強い明るい色）だけを灯りとして残し、壁と屋根は夜の色に沈める。
                    // 明るさだけで見分けると、白っぽい壁まで灯って黄色い塊になる。
                    let window = Int(p.b) > Int(p.r) + 40 && Int(p.b) > 150
                    let lit = window && rng.next() % 3 != 0
                    let px = lit ? RGBA(236, 200, 118) : RGBA(16 + Int(p.r) / 14, 18 + Int(p.g) / 14, 40 + Int(p.b) / 12)
                    c.set(x + sx, top + sy, px)
                }
            }
            x += 30 + Int(rng.next() % 26)
        }
        return c.cgImage().map { UIImage(cgImage: $0) }
    }()
}

extension Font {
    /// ドットの書体。中国語・韓国語など字形のない文字は、標準の書体で補われる。
    static func dot(_ size: CGFloat) -> Font { .custom("DotGothic16-Regular", size: size) }
}

/// 夜空と、地平の街並み。メニュー画面の地に敷く。
struct NightBackground: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [Theme.skyTop, Theme.skyBottom], startPoint: .top, endPoint: .bottom)
            // 星。毎回同じ位置に出るよう、決まった種から撒く。
            Canvas { ctx, size in
                var rng = SplitMix64(seed: 77)
                for _ in 0..<70 {
                    let x = Double(rng.next() % 1000) / 1000 * size.width
                    let y = Double(rng.next() % 1000) / 1000 * size.height * 0.7
                    let s: Double = rng.next() % 5 == 0 ? 2 : 1
                    ctx.fill(Path(CGRect(x: x, y: y, width: s, height: s)),
                             with: .color(.white.opacity(Double(20 + rng.next() % 50) / 100)))
                }
            }
            if let skyline = Theme.skyline {
                Image(uiImage: skyline)
                    .interpolation(.none)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 150)
                    .clipped()
                    .opacity(0.35)
            }
        }
        .ignoresSafeArea()
    }
}

/// 番号つきの見出し。「01 ─ 年度の見込み ────」の形。
struct SectionTitle: View {
    let number: Int
    let title: LocalizedStringKey
    /// 罫線の右端に添える小さな数字（「3 / 7」など）。
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            Text(String(format: "%02d", number))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.gold)
            Text(title)
                .font(.dot(17))
                .foregroundStyle(Theme.ink)
            Rectangle().fill(Theme.rule).frame(height: 1)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.mute)
            }
        }
        .padding(.top, 22)
        .padding(.bottom, 6)
    }
}

/// 罫線で区切った1行。左に項目、右に数字。
struct LedgerRow<Trailing: View>: View {
    let label: LocalizedStringKey
    let trailing: Trailing

    init(_ label: LocalizedStringKey, @ViewBuilder trailing: () -> Trailing) {
        self.label = label
        self.trailing = trailing()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(label).font(.system(size: 15)).foregroundStyle(Theme.ink)
                Spacer(minLength: 12)
                trailing
            }
            .padding(.vertical, 11)
            Rectangle().fill(Theme.rule).frame(height: 1)
        }
    }
}

extension LedgerRow where Trailing == AnyView {
    init(_ label: LocalizedStringKey, value: String, tint: Color = Theme.mute) {
        self.init(label) { AnyView(Text(value).font(.system(size: 15, design: .monospaced)).foregroundStyle(tint)) }
    }
}

/// 角の立った、枠線だけのボタン。ドット絵に合わせて角丸を小さくする。
struct PixelButtonStyle: ButtonStyle {
    var tint: Color = Theme.ink
    var filled = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.dot(15))
            .foregroundStyle(filled ? Theme.skyTop : tint)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    // 下の街並みが透けて文字が読めなくならないよう、枠線だけでも下地は塗る。
                    .fill(filled ? tint : (configuration.isPressed ? Theme.plate.opacity(1) : Theme.skyTop.opacity(0.92)))
            )
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(tint.opacity(filled ? 0 : 0.55), lineWidth: 1.5))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// 閉じるボタン。どのメニュー画面でも右上の同じ位置に置く。
struct CloseButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text("閉じる")
                .font(.dot(14))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.rule, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}

/// ドットを並べた進み具合の帯。`count` 個の升のうち、`filled` 個を塗る。
struct PixelProgress: View {
    let value: Double
    var count = 30

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<count, id: \.self) { i in
                Rectangle()
                    .fill(Double(i) < value * Double(count) ? Theme.gold : Color.white.opacity(0.10))
                    .frame(height: 8)
            }
        }
    }
}

/// 道具の絵。ヘルプでは記号ではなく、街に置いたときと同じ絵を見せる。
enum ToolArt {
    private static var cache: [Tool: UIImage] = [:]

    static func image(_ tool: Tool) -> UIImage? {
        if let hit = cache[tool] { return hit }
        var c: PixelCanvas
        func over(_ top: PixelCanvas) {
            for y in 0..<top.height { for x in 0..<top.width where top.get(x, y).a > 0 { c.set(x, y, top.get(x, y)) } }
        }
        switch tool {
        case .road, .avenue, .rail, .powerLine, .park, .bulldozer:
            c = TileArt.land(variant: 1)
            switch tool {
            case .road: over(TileArt.road(mask: 10))
            case .avenue: over(TileArt.avenue(mask: 10))
            case .rail: over(TileArt.rail(mask: 10, crossing: false))
            case .powerLine: over(TileArt.wire(mask: 10))
            case .park: over(TileArt.park())
            default: over(TileArt.rubble())
            }
        default:
            guard let kind = tool.zoneKind else { return nil }
            c = TileArt.zoneArt(kind: kind, level: kind.grows ? 4 : 0, variant: 1)
        }
        let image = c.cgImage().map { UIImage(cgImage: $0) }
        cache[tool] = image
        return image
    }
}
