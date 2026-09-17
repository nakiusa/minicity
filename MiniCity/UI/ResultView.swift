import SwiftUI

/// 決めた年数を遊びきったときに出す成績表。
/// ここで終わりにしたい人と、そのまま育て続けたい人の両方がいるので、どちらも選べるようにしてある。
struct ResultView: View {
    @ObservedObject var game: GameState
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
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("1900年から\(String(sim.year - 1))年まで")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text("\(years)年の記録")
                            .font(.system(size: 24, weight: .heavy, design: .rounded))
                    }

                    VStack(spacing: 0) {
                        // HUD と同じく桁区切りを入れる。ここだけ素の数字だと落ち着かない。
                        row("人口", String(localized: "\(sim.residents.formatted())人"))
                        row("雇用", String(localized: "jobs.count", defaultValue: "\(sim.jobs.formatted())人"))
                        row("資金", "¥\(sim.funds.formatted())")
                        row("税率", "\(sim.taxRate)%")
                        row("最高の段", stats.topLevel == 0 ? String(localized: "なし") : "L\(stats.topLevel)")
                        row("公害の最大", "\(sim.pollution.maximum)")
                        row("犯罪の最大", "\(sim.crime.maximum)")
                        row("実績", "\(game.earnedCount) / \(Achievements.all.count)")
                        if let rank, let term = sim.termYears {
                            Button { GameCenter.showLeaderboard(term: term) } label: {
                                row("世界の順位", String(localized: "\(rank.formatted())位"))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.07))
                    )

                    if let card {
                        ShareLink(item: Image(uiImage: card),
                                  preview: SharePreview(Text("\(years)年の記録"), image: Image(uiImage: card))) {
                            Label("記録を共有する", systemImage: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.12)))
                                .foregroundStyle(.white)
                        }
                    }

                    Button {
                        game.keepPlaying()
                    } label: {
                        Text("このまま続ける")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.accentColor))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    Button {
                        showMapSelect = true
                    } label: {
                        Text("新しい都市を始める")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.12)))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
                .padding(18)
            }
            .navigationTitle("期限まで遊びました")
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled()
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
    private var years: Int { game.sim.termYears ?? game.sim.year - 1900 }

    private func row(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1).padding(.horizontal, 10)
        }
    }
}
