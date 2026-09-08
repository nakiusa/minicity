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
                VStack(spacing: 10) {
                    HStack {
                        Text("\(earned) / \(total)")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("達成")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 4)

                    ForEach(AchievementGroup.allCases, id: \.self) { group in
                        let items = Achievements.inGroup(group)
                        if !items.isEmpty {
                            HStack {
                                Text(group.rawValue)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(items.filter { $0.isEarned }.count) / \(items.count)")
                                    .font(.system(size: 11, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 4)
                            .padding(.top, 8)

                            ForEach(items) { item in
                                row(item)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .safeAreaInset(edge: .bottom) { AdBanner() }
            .navigationTitle("実績")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
                // Game Center にサインインしているときだけ、あちらの一覧も開けるようにする。
                if GameCenter.isAuthenticated {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                            GameCenter.showDashboard()
                        } label: {
                            Image(systemName: "gamecontroller.fill")
                        }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func row(_ item: Achievement) -> some View {
        let earned = item.isEarned
        return HStack(spacing: 12) {
            Image(systemName: earned ? item.symbol : "lock.fill")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 34, height: 34)
                .foregroundStyle(earned ? Color.yellow : Color.white.opacity(0.35))
                .background(
                    Circle().fill(earned ? Color.yellow.opacity(0.18) : Color.white.opacity(0.07))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(earned ? .white : .white.opacity(0.55))
                Text(item.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            if earned {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(earned ? 0.10 : 0.05))
        )
    }
}
