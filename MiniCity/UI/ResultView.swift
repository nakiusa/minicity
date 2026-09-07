import SwiftUI

/// 決めた年数を遊びきったときに出す成績表。
/// ここで終わりにしたい人と、そのまま育て続けたい人の両方がいるので、どちらも選べるようにしてある。
struct ResultView: View {
    @ObservedObject var game: GameState
    @Environment(\.dismiss) private var dismiss
    @State private var showMapSelect = false

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
                        Text("\(sim.termYears ?? sim.year - 1900)年の記録")
                            .font(.system(size: 24, weight: .heavy, design: .rounded))
                    }

                    VStack(spacing: 0) {
                        // HUD と同じく桁区切りを入れる。ここだけ素の数字だと落ち着かない。
                        row("人口", "\(sim.residents.formatted())人")
                        row("雇用", "\(sim.jobs.formatted())人")
                        row("資金", "¥\(sim.funds.formatted())")
                        row("税率", "\(sim.taxRate)%")
                        row("最高の段", stats.topLevel == 0 ? "なし" : "L\(stats.topLevel)")
                        row("公害の最大", "\(sim.pollution.maximum)")
                        row("犯罪の最大", "\(sim.crime.maximum)")
                        row("実績", "\(game.earnedCount) / \(Achievements.all.count)")
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.07))
                    )

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
        .sheet(isPresented: $showMapSelect) {
            MapSelectView { seed, termYears in
                game.newCity(seed: seed, termYears: termYears)
                dismiss()
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
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
