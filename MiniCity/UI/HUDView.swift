import SwiftUI

/// 月の名前は端末の言語に任せる。日本語なら「5月」、英語なら「May」。
private let monthNames = Calendar.current.shortMonthSymbols

/// HUD の下地。半透明にすると地面の色を拾って濁るので、不透明の暗色で塗る。
let panelFill = Color(red: 0.07, green: 0.075, blue: 0.095)

struct PanelBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(panelFill)
            )
    }
}

extension View {
    func panel() -> some View { modifier(PanelBackground()) }
}

/// 日付・資金・人口と、速度の切り替え。
struct TopBar: View {
    @ObservedObject var game: GameState
    @Binding var showBudget: Bool

    var body: some View {
        let sim = game.sim
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    // 月が2桁に変わるたびに、右にある資金や速度のボタンがまとめてずれる。
                    // いちばん長い日付を型紙として敷いておき、幅を固定する。
                    ZStack(alignment: .leading) {
                        Text("0000年 00月", comment: "日付の幅の型紙。いちばん長い月名で").hidden()
                        Text("\(String(sim.year))年 \(monthNames[sim.month - 1])", comment: "年と月。%1$@ が年、%2$@ が月の名前")
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    // 資金が大きな桁になっても、折り返さずに詰めて1行に収める。
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    HStack(spacing: 6) {
                        Text("人口 \(sim.residents)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        // 期限を決めて始めたときだけ、あと何年あるかを添える。
                        if let left = sim.yearsLeft {
                            Text("残り \(left)年")
                                .monospacedDigit()
                                .foregroundStyle(left <= 5 ? Color.orange : Color.secondary)
                        }
                    }
                    .font(.system(size: 11, design: .rounded))
                }

                // 予算画面への入口。ただの数字に見えると押せることに気付けないので、
                // 枠と山括弧を付けてボタンだと分かるようにしてある。
                Button {
                    showBudget = true
                } label: {
                    HStack(spacing: 5) {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("¥\(sim.funds)")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .foregroundStyle(sim.funds < 0 ? Color.red : Color.green)
                            Text("税率 \(sim.taxRate)%")
                                .font(.system(size: 10, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.14))
                    )
                }
                .buttonStyle(.plain)

                Spacer(minLength: 4)

                HStack(spacing: 4) {
                    ForEach(GameSpeed.allCases) { s in
                        Button {
                            game.speed = s
                        } label: {
                            Image(systemName: s.symbol)
                                .font(.system(size: 11, weight: .bold))
                                .frame(width: 26, height: 24)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(game.speed == s ? Color.accentColor : Color.white.opacity(0.12))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .foregroundStyle(.white)

            if !sim.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(sim.warnings, id: \.self) { w in
                        Label(w, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .panel()
    }
}

/// R/C/I の需要を上下に伸びる棒で示す。
struct DemandIndicator: View {
    @ObservedObject var game: GameState

    private let height: CGFloat = 34

    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            bar("R", game.sim.demandR, .green)
            bar("C", game.sim.demandC, .blue)
            bar("I", game.sim.demandI, .yellow)
        }
        .panel()
    }

    private func bar(_ label: String, _ value: Double, _ color: Color) -> some View {
        VStack(spacing: 3) {
            ZStack(alignment: .center) {
                Rectangle()
                    .fill(Color.white.opacity(0.14))
                    .frame(width: 13, height: height)
                Rectangle()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: 13, height: 1)
                Rectangle()
                    .fill(color)
                    .frame(width: 13, height: max(1, CGFloat(abs(value)) * height / 2))
                    .offset(y: value >= 0
                            ? -CGFloat(abs(value)) * height / 4
                            : CGFloat(abs(value)) * height / 4)
            }
            .frame(width: 13, height: height)
            .clipped()
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}

/// 選んだ道具を横スクロールで並べる。
/// 「移動」だけはズームコントロールの上に専用ボタンを置いてあるので、ここには出さない。
struct ToolPalette: View {
    @ObservedObject var game: GameState

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Tool.allCases.filter { $0 != .pan }) { tool in
                    Button {
                        game.tool = tool
                        game.inspected = nil
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: tool.symbol)
                                .font(.system(size: 15, weight: .semibold))
                            // 「Stromleitung」のような長い名前でも切れないよう、入らなければ詰める。
                            Text(tool.title)
                                .font(.system(size: 9, weight: .medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.65)
                                .padding(.horizontal, 2)
                            Text(tool.cost == 0 ? " " : "¥\(tool.cost)")
                                .font(.system(size: 8, design: .rounded))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .frame(width: 54, height: 54)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(game.tool == tool ? Color.accentColor : Color.white.opacity(0.13))
                        )
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .id(tool)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
        }
        // 案内の行から道具が切り替わったとき、画面の外にある道具まで送る。
        .onChange(of: game.tool) { _, tool in
            withAnimation { proxy.scrollTo(tool, anchor: .center) }
        }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(panelFill)
        )
    }
}

/// 「移動」だけは道具パレットから外に出し、ズームコントロールの真上に置く。
/// 地図を動かす操作とズームは役割が近いので、まとめておいたほうが見つけやすい。
struct PanToolButton: View {
    @ObservedObject var game: GameState

    var body: some View {
        Button {
            game.tool = .pan
            game.inspected = nil
        } label: {
            Image(systemName: Tool.pan.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(game.tool == .pan ? Color.accentColor : panelFill)
                )
        }
        .buttonStyle(.plain)
    }
}

/// 拡大縮小のボタン。実機ならピンチでも同じことができる。
struct ZoomControls: View {
    @ObservedObject var game: GameState

    var body: some View {
        VStack(spacing: 0) {
            button("plus.magnifyingglass") { game.scene?.zoomStep(zoomIn: true) }
            Rectangle()
                .fill(Color.white.opacity(0.22))
                .frame(width: 30, height: 1)
            // なぞって連続で寄り引きできるつまみ。指1本で完結する。
            Slider(value: $game.zoomLevel, in: 0...1)
                .rotationEffect(.degrees(-90))
                .frame(width: 130, height: 130)
                .frame(width: 44, height: 130)
                .clipped()
                .tint(.white)
            Rectangle()
                .fill(Color.white.opacity(0.22))
                .frame(width: 30, height: 1)
            button("minus.magnifyingglass") { game.scene?.zoomStep(zoomIn: false) }
        }
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(panelFill)
        )
    }

    private func button(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 40)
        }
        .buttonStyle(.plain)
    }
}

/// 地図の見方（公害や土地価値）の切り替え。
struct OverlayPicker: View {
    @ObservedObject var game: GameState

    var body: some View {
        Menu {
            ForEach(OverlayMode.allCases) { mode in
                Button {
                    game.overlay = mode
                } label: {
                    if game.overlay == mode {
                        Label(mode.title, systemImage: "checkmark")
                    } else {
                        Text(mode.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "map.fill").font(.system(size: 11))
                Text(game.overlay.title).font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.white)
            .panel()
        }
    }
}

/// 「調べる」の一覧。叩いたマスの数値を並べつつ、行そのものが地図の切り替えになる。
/// 数字だけ読ませても土地の良し悪しは掴めないので、同じ行から色分けの地図へ渡す。
struct InspectorPanel: View {
    @ObservedObject var game: GameState
    /// 一覧を畳んで、地図の下半分を見えるようにする。別のマスを叩くと開き直す。
    @State private var collapsed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(game.inspected.map { LocalizedStringKey($0.summary) }
                     ?? "マスを軽く叩くとその場所の数値が出ます。行を押すと地図が色分けされます")
                    .font(.system(size: 11))
                    .foregroundStyle(game.inspected == nil ? Color.white.opacity(0.55) : .white)
                    .lineLimit(collapsed ? 1 : nil)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if collapsed, game.overlay != .none {
                    Label(game.overlay.title, systemImage: game.overlay.symbol)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { collapsed.toggle() }
                } label: {
                    Image(systemName: collapsed ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 28, height: 22)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, collapsed ? 0 : 2)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { collapsed.toggle() } }

            if !collapsed {
                ForEach(OverlayMode.readable) { mode in
                    row(mode)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(panelFill)
        )
        .onChange(of: game.inspected?.x ?? -1 &* 31 &+ (game.inspected?.y ?? -1)) { _, _ in
            // 新しいマスを叩いたということは数字を見たいということなので、開く。
            if game.inspected != nil { withAnimation(.easeInOut(duration: 0.15)) { collapsed = false } }
        }
    }

    private func row(_ mode: OverlayMode) -> some View {
        let selected = game.overlay == mode
        let reading = game.inspected.flatMap { mode.reading(atX: $0.x, y: $0.y, in: game.sim) }
        let note = game.inspected.flatMap { mode.note(atX: $0.x, y: $0.y, in: game.sim) }
        return Button {
            // もう一度押すと元の見た目に戻る。切り替えと取り消しを同じ場所で済ませる。
            game.overlay = selected ? .none : mode
        } label: {
            HStack(spacing: 8) {
                Image(systemName: mode.symbol)
                    .font(.system(size: 10))
                    .frame(width: 14)
                // 言語によって名前の長さがかなり違う（「公害」と「Verschmutzung」）。
                // 幅は広めに取り、入りきらないときだけ字を詰める。
                Text(mode.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: 84, alignment: .leading)

                // 帯の色は地図と同じ配色にして、行と地図が同じものを指していると分かるようにする。
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.10))
                        if let reading {
                            Capsule()
                                .fill(heatSwatch(reading.heat))
                                .frame(width: max(3, geo.size.width * Double(reading.heat) / 255))
                        }
                    }
                }
                .frame(height: 6)

                Text(reading.map { "\($0.value)" } ?? note ?? "—")
                    .font(.system(size: 11, design: .rounded))
                    .monospacedDigit()
                    .frame(width: 38, alignment: .trailing)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.75) : Color.white.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
    }
}

/// 地図の色分けと同じ配色を、帯にも使う。地図側は薄い値を透かすが、帯は細いので不透明で塗る。
private func heatSwatch(_ v: Int) -> Color {
    let c = CityScene.heatColor(v)
    return Color(red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255)
}
