import SwiftUI

/// 決めた年数を遊びきったときに出す成績表。
/// ここで終わりにしたい人と、そのまま育て続けたい人の両方がいるので、どちらも選べるようにしてある。
struct ResultView: View {
    @ObservedObject var game: GameState
    /// 期限が来て出す成績表か。途中で見るだけなら「続ける」は閉じるだけで、新しい都市も出さない。
    var isFinal = true
    @Environment(\.dismiss) private var dismiss
    @State private var showMapSelect = false
    /// 世界での順位。Game Center から引けたときだけ出す。
    @State private var rank: Int?
    /// 共有用の1枚絵。開いたときに街を撮って作る。
    @State private var card: UIImage?

    var body: some View {
        let sim = game.sim
        let stats = CityStats(sim)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(isFinal ? "期限まで遊びました" : "いまの成績").font(.dot(20)).foregroundStyle(Theme.gold)
                        Spacer()
                        if !isFinal { CloseButton { dismiss() } }
                    }
                    .padding(.top, 18)
                    Text("1年目から\(String(sim.year - 1))年目まで")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.mute)
                        .padding(.top, 16)
                    Text("\(years)年の記録").font(.dot(30)).foregroundStyle(Theme.ink)
                    // いちばん大きく見せたいのは人口。ランキングもこの数で競う。
                    Text("人口").font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(Theme.mute)
                        .padding(.top, 18)
                    Text(String(localized: "\(sim.residents.formatted())人"))
                        .font(.dot(44)).foregroundStyle(Theme.gold)
                        .minimumScaleFactor(0.6).lineLimit(1)

                    SectionTitle(number: 1, title: "内訳")
                    VStack(spacing: 0) {
                        // HUD と同じく桁区切りを入れる。ここだけ素の数字だと落ち着かない。
                        LedgerRow("雇用", value: String(localized: "jobs.count", defaultValue: "\(sim.jobs.formatted())人"))
                        LedgerRow("資金", value: "¥\(sim.funds.formatted())")
                        LedgerRow("税率", value: "\(sim.taxRate)%")
                        LedgerRow("最高レベル", value: stats.topLevel == 0 ? String(localized: "なし") : "L\(stats.topLevel)")
                        LedgerRow("公害の最大", value: "\(sim.pollution.displayMaximum)")
                        LedgerRow("犯罪の最大", value: "\(sim.crime.displayMaximum)")
                        LedgerRow("実績", value: "\(game.earnedCount) / \(Achievements.all.count)")
                        if let rank, let term = sim.termYears {
                            Button { GameCenter.showLeaderboard(term: term) } label: {
                                LedgerRow("世界ランキング", value: String(localized: "\(rank.formatted())位"), tint: Theme.gold)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    VStack(spacing: 10) {
                        if let card {
                            ShareLink(item: Image(uiImage: card),
                                      preview: SharePreview(Text("\(years)年の記録"), image: Image(uiImage: card))) {
                                Label("記録を共有する", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(PixelButtonStyle())
                        }
                        Button {
                            if isFinal { game.keepPlaying() } else { dismiss() }
                        } label: {
                            Text(isFinal ? "このまま続ける" : "閉じる")
                        }
                        .buttonStyle(PixelButtonStyle(tint: Theme.gold, filled: true))
                        if isFinal {
                            Button { showMapSelect = true } label: { Text("新しい都市を始める") }
                                .buttonStyle(PixelButtonStyle())
                        }
                    }
                    .padding(.top, 24)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 170)
            }
            .background(NightBackground())
            .toolbar(.hidden, for: .navigationBar)
        }
        .interactiveDismissDisabled(isFinal)
        .preferredColorScheme(.dark)
        .task {
            if let city = game.scene?.snapshot() {
                card = ShareCard.make(city: city, population: sim.residents, years: years)
                // 起動引数 -dumpShareCard YES で、共有の絵を書類に書き出す。見た目の確認用。
                if UserDefaults.standard.bool(forKey: "dumpShareCard"),
                   let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? card?.pngData()?.write(to: url.appendingPathComponent("sharecard.png"))
                }
            }
            if let term = sim.termYears { rank = await GameCenter.rank(term: term) }
        }
        .sheet(isPresented: $showMapSelect) {
            MapSelectView { seed, termYears in
                game.newCity(seed: seed, termYears: termYears)
                dismiss()
            }
        }
    }

    /// 遊んだ年数。期限つきなら期限、なければ 1900 年からの経過年。
    private var years: Int { game.sim.termYears ?? game.sim.year - 1 }

}
