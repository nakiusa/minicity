import SwiftUI

/// 集めた実績の一覧。まだ取っていないものも、条件を添えて並べる。
/// 何を目指せばいいのかが分かるほうが、集める気になる。
struct AchievementsView: View {
    @ObservedObject var game: GameState
    @Environment(\.dismiss) private var dismiss

    private var earned: Int { game.earnedCount }
    private var total: Int { Achievements.all.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    ForEach(Array(AchievementGroup.allCases.enumerated()), id: \.element) { index, group in
                        let items = Achievements.inGroup(group)
                        if !items.isEmpty {
                            SectionTitle(number: index + 1, title: LocalizedStringKey(group.title),
                                         trailing: "\(items.filter { $0.isEarned }.count) / \(items.count)")
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                                ForEach(items) { tile($0) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 170)
            }
            .background(NightBackground())
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) { AdBanner() }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("実績").font(.dot(28)).foregroundStyle(Theme.ink)
                Spacer()
                // Game Center にサインインしているときだけ、あちらの一覧も開けるようにする。
                if GameCenter.isAuthenticated {
                    Button {
                        dismiss()
                        GameCenter.showDashboard()
                    } label: {
                        Image(systemName: "gamecontroller.fill")
                            .foregroundStyle(Theme.ink)
                            .padding(8)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.rule, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
                CloseButton { dismiss() }
            }
            .padding(.top, 18)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(earned)").font(.dot(44)).foregroundStyle(Theme.gold)
                Text("/ \(total)").font(.dot(20)).foregroundStyle(Theme.mute)
                Text("達成").font(.system(size: 12)).foregroundStyle(Theme.mute)
            }
            .padding(.top, 12)
            PixelProgress(value: Double(earned) / Double(max(1, total)))
        }
    }

    /// 実績ひとつの升。取ったものは金の縁で光らせ、まだのものは鍵をかけて沈める。
    private func tile(_ item: Achievement) -> some View {
        let earned = item.isEarned
        return VStack(alignment: .leading, spacing: 8) {
            Image(systemName: earned ? item.symbol : "lock.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(earned ? Theme.gold : Theme.mute.opacity(0.6))
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 3).fill(earned ? Theme.gold.opacity(0.14) : Color.white.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(earned ? Theme.gold.opacity(0.8) : Theme.rule, lineWidth: 1.5))
                .shadow(color: earned ? Theme.gold.opacity(0.45) : .clear, radius: 6)
            Text(item.title)
                .font(.dot(14))
                .foregroundStyle(earned ? Theme.ink : Theme.ink.opacity(0.55))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text(item.detail)
                .font(.system(size: 11))
                .foregroundStyle(Theme.mute)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 4).fill(Theme.plate))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(earned ? Theme.gold.opacity(0.35) : Theme.rule, lineWidth: 1))
    }
}
