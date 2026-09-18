import SwiftUI

// MARK: - はじめの案内

/// 最初の一回だけ、めくって読む案内。何をするゲームか、最初に何を置くか、指の使いかた。
/// 一枚に詰めると読まれないので、4枚に分けて1枚ずつ言う。
struct IntroView: View {
    var onFinish: () -> Void
    @State private var page = 0

    var body: some View {
        ZStack {
            Color(white: 0.09).ignoresSafeArea()
            VStack(spacing: 0) {
                TabView(selection: $page) {
                    introPage(
                        symbol: "building.2.fill",
                        title: "50年で、街はどこまで育つ？",
                        body: "区画を置いて、電気を通す。あとは街が勝手に育つのを眺めるゲームです。\n\n決めた年数が来ると成績表が出て、人口は世界のランキングに載ります。",
                        rows: []
                    ).tag(0)
                    introPage(
                        symbol: "list.number",
                        title: "最初にやること",
                        body: "画面の上に、次にやることが出ます。順に置いていけば、人が入ってきます。",
                        rows: [
                            ("bolt.fill", "発電所を置く", "3×3の大きさ。煙を出すので住宅から離す"),
                            ("road.lanes", "道路を引く", "指でなぞって「決定」。区画は道路に面していないと育たない"),
                            ("house.fill", "住宅区と工業区を置く", "道路の脇に。工業は住宅の反対側に"),
                            ("bolt.horizontal.fill", "送電線でつなぐ", "発電所から区画まで。区画どうしは電気を通す"),
                        ]
                    ).tag(1)
                    introPage(
                        symbol: "hand.tap.fill",
                        title: "指の使いかた",
                        body: "",
                        rows: [
                            ("hand.draw.fill", "1本指", "選んだ道具でマスを塗る。「移動」の道具なら地図が動く"),
                            ("hand.point.up.left.and.text.fill", "2本指", "どの道具でも地図が動く。つまめば拡大縮小"),
                            ("magnifyingglass", "調べる", "マスを叩くと数字が出る。行を押すと地図が色で染まる"),
                            ("arrow.uturn.backward", "やり直し", "道路は「決定」を押すまで確定しない。なぞり戻せば消える"),
                        ]
                    ).tag(2)
                    introPage(
                        symbol: "leaf.fill",
                        title: "育たないときは",
                        body: "家がいつまでも小さいなら、たいてい近くに煙があります。",
                        rows: [
                            ("smoke.fill", "公害", "工場と発電所が出す。土地の値打ちを下げる。公園が吸う"),
                            ("shield.lefthalf.filled", "犯罪", "人が増えると増える。警察署で減る"),
                            ("car.fill", "渋滞", "混んだ道の周りは値打ちが下がる。道を増やして分散させる"),
                            ("yensign.circle.fill", "お金", "税率7％が目安。足りなければ予算から借りられる"),
                        ]
                    ).tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                Button {
                    if page < 3 {
                        withAnimation { page += 1 }
                    } else {
                        onFinish()
                    }
                } label: {
                    Text(page < 3 ? "つぎへ" : "はじめる")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.accentColor))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func introPage(symbol: String, title: LocalizedStringKey, body: LocalizedStringKey,
                           rows: [(String, LocalizedStringKey, LocalizedStringKey)]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: symbol)
                    .font(.system(size: 40))
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 36)
                Text(title)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                Text(body)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HelpRow(symbol: row.0, title: row.1, text: row.2)
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
    }
}

struct HelpRow: View {
    let symbol: String
    let title: LocalizedStringKey
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .bold, design: .rounded))
                Text(text).font(.system(size: 13)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - 遊びながら出す次の一手

/// 街が動き出すまでの手順。いま足りていないものを、上から順に1つだけ言う。
enum GuideStep: CaseIterable {
    case plant, road, residential, industrial, power, connect, wait

    /// いま足りていない最初の手順。人が入ったら nil（案内は終わり）。
    static func next(for sim: Simulation) -> GuideStep? {
        if (sim.zoneCounts[.coalPlant] ?? 0) == 0 { return .plant }
        if sim.roadCount == 0 { return .road }
        if (sim.zoneCounts[.residential] ?? 0) == 0 { return .residential }
        if (sim.zoneCounts[.industrial] ?? 0) == 0 { return .industrial }
        if sim.unpoweredZones > 0 { return .power }
        if sim.disconnectedZones > 0 { return .connect }
        if sim.residents == 0 { return .wait }
        return nil
    }

    var number: Int { GuideStep.allCases.firstIndex(of: self)! + 1 }

    var title: LocalizedStringKey {
        switch self {
        case .plant: return "発電所を置く。住宅から離して"
        case .road: return "道路をなぞって「決定」"
        case .residential: return "道路の脇に住宅区を置く"
        case .industrial: return "工業区を置く。住宅の反対側に"
        case .power: return "送電線で発電所と区画をつなぐ"
        case .connect: return "区画を道路に面させる"
        case .wait: return "▶ で時間を進める。人が入ってくる"
        }
    }

    /// 押したときに選ぶ道具。待つ段では何も選ばない。
    var tool: Tool? {
        switch self {
        case .plant: return .coalPlant
        case .road, .connect: return .road
        case .residential: return .residential
        case .industrial: return .industrial
        case .power: return .powerLine
        case .wait: return nil
        }
    }
}

/// 画面の上に出す一行。押すとその道具に切り替わる。
struct GuideBar: View {
    @ObservedObject var game: GameState
    let step: GuideStep
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("\(step.number)")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor))
            Text(step.title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            if step.tool != nil {
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).opacity(0.6)
            }
            Button(action: onDismiss) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).opacity(0.6)
                    .padding(4)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.72)))
        .onTapGesture {
            if let tool = step.tool { game.tool = tool }
        }
    }
}

// MARK: - ヘルプ

/// ? から開く。遊びかたを最初から最後まで、節に分けて置いてある。
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    var onReplayIntro: () -> Void
    var onResetGuide: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("目標") {
                    HelpRow(symbol: "flag.checkered", title: "決めた年数まで街を育てる",
                            text: "50年・100年・200年・期限なしから選びます。期限が来ると時間が止まり、成績表が出ます。人口は Game Center のランキングに送られます。")
                    HelpRow(symbol: "square.and.arrow.up", title: "記録を共有する",
                            text: "成績表から、街全体の絵に人口と年数を添えた1枚の画像を作れます。")
                    HelpRow(symbol: "trophy.fill", title: "実績を集める",
                            text: "34種類。人口や資金だけでなく、公害を抑えたまま育てるなど、作りかたを問うものがあります。")
                }

                Section("置けるもの") {
                    HelpRow(symbol: "bolt.fill", title: "発電所", text: "3×3。電気の元。容量に限りがあり、街が広がると足りなくなる。煙を出す。")
                    HelpRow(symbol: "road.lanes", title: "道路", text: "区画は道路に面していないと育たない。住民は道路で職場に通う。")
                    HelpRow(symbol: "road.lanes.curved.right", title: "大通り", text: "面した土地の値打ちを押し上げる。敷く値段も維持費も高い。")
                    HelpRow(symbol: "bolt.horizontal.fill", title: "送電線", text: "発電所と区画をつなぐ。区画どうしは電気を通すので、隣り合っていればつなぎ直さなくてよい。")
                    HelpRow(symbol: "house.fill", title: "住宅区", text: "人が住む。土地の値打ちに敏感で、公害と犯罪を嫌う。")
                    HelpRow(symbol: "bag.fill", title: "商業区", text: "店と事務所。人が住んでから需要が立ち上がる。住宅の近くに。")
                    HelpRow(symbol: "gearshape.fill", title: "工業区", text: "工場。注文があれば地価が低くても育つ。煙を出すので住宅から離す。")
                    HelpRow(symbol: "tree.fill", title: "公園", text: "周りの公害を吸い、土地の値打ちを上げる。工場と住宅の間に。")
                    HelpRow(symbol: "shield.lefthalf.filled", title: "警察署", text: "周りの犯罪を減らす。維持費がかかる。")
                    HelpRow(symbol: "flame.fill", title: "消防署", text: "周りの土地の値打ちを少し上げる。維持費がかかる。")
                    HelpRow(symbol: "hammer.fill", title: "撤去", text: "何でも消す。¥1。")
                }

                Section("街が育つ仕組み") {
                    HelpRow(symbol: "arrow.up.right", title: "区画は10段階まで育つ",
                            text: "電気と道路があり、需要があり、土地の値打ちが高いほど上の段へ進みます。段が上がるほど次まで時間がかかります。")
                    HelpRow(symbol: "yensign.circle.fill", title: "土地の値打ち",
                            text: "水辺と森と公園で上がり、街の中心とにぎわいで上がり、公害と犯罪と渋滞で下がります。住宅はこれに強く反応します。")
                    HelpRow(symbol: "chart.bar.fill", title: "需要（R・C・I）",
                            text: "左上の3本の棒。住宅・商業・工業それぞれの需要です。上に伸びていれば置けば育ち、下なら置いても埋まりません。職と住のつり合いで動きます。")
                    HelpRow(symbol: "smoke.fill", title: "公害",
                            text: "工場と発電所が出し、風に流れず周りに広がります。家が育たないときは、まずこれを疑ってください。")
                }

                Section("数字の読みかた") {
                    HelpRow(symbol: "magnifyingglass", title: "調べる",
                            text: "マスを叩くと、土地価値・公害・犯罪・交通量・人口密度・活気・電力が出ます。行を押すと、その指標が街全体に色で載ります。")
                    HelpRow(symbol: "map.fill", title: "地図の切り替え",
                            text: "右上のメニューからも同じ色分けに切り替えられます。停電している区画は「電力」で分かります。")
                }

                Section("お金") {
                    HelpRow(symbol: "percent", title: "税率",
                            text: "7％が目安。上げると収入は増えますが需要が下がり、街が縮みます。下げると育ちますが赤字になります。")
                    HelpRow(symbol: "banknote.fill", title: "年度末の決算",
                            text: "12月に1年ぶんの税収が入り、道路・発電所・警察・消防の維持費が引かれます。予算画面に見込みが出ます。")
                    HelpRow(symbol: "creditcard.fill", title: "借入",
                            text: "資金が尽きたら予算画面から5万円ずつ借りられます。年5％の利息と残高の1割を毎年返します。")
                }

                Section("操作") {
                    HelpRow(symbol: "hand.draw.fill", title: "1本指", text: "選んだ道具でマスを塗る。「移動」の道具を選べば地図が動く。")
                    HelpRow(symbol: "hand.point.up.left.and.text.fill", title: "2本指", text: "どの道具でも地図が動く。つまめば拡大縮小。")
                    HelpRow(symbol: "arrow.uturn.backward", title: "やり直し", text: "道路・送電線・公園・撤去は「決定」を押すまで確定しない。なぞり戻せば消える。")
                    HelpRow(symbol: "forward.fill", title: "速度", text: "等倍・2倍・4倍。等倍で1年が24秒。成績表や予算を開いている間は止まる。")
                }

                Section {
                    Button("はじめの案内をもう一度見る") {
                        dismiss()
                        onReplayIntro()
                    }
                    Button("次にやることの案内を出し直す") {
                        dismiss()
                        onResetGuide()
                    }
                }
            }
            .navigationTitle("遊びかた")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
