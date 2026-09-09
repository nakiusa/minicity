import SwiftUI

/// 税率の調整と、年度末に何が起きるかの内訳。
struct BudgetView: View {
    @ObservedObject var game: GameState
    @ObservedObject var store: Store
    @Environment(\.dismiss) private var dismiss
    /// 都市を捨てる操作は戻せないので、一度確かめる。
    @State private var confirmingNewCity = false
    @State private var showMapSelect = false

    var body: some View {
        ZStack {
            budgetForm

            // システムの .alert ではなく自前のオーバーレイにしてある。
            // 内容自体は同じ確認ダイアログだが、アプリの画面と同じ階層で
            // 描くことで、この画面の他のボタンと同じ手順で確実に押せるようにするため。
            if confirmingNewCity {
                ConfirmNewCityOverlay(
                    onCancel: { confirmingNewCity = false },
                    onConfirm: {
                        confirmingNewCity = false
                        showMapSelect = true
                    }
                )
            }
        }
        .sheet(isPresented: $showMapSelect) {
            MapSelectView { seed, termYears in
                game.newCity(seed: seed, termYears: termYears)
                dismiss()
            }
        }
    }

    private var budgetForm: some View {
        NavigationStack {
            Form {
                Section("税率") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("\(game.sim.taxRate)%")
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .monospacedDigit()
                            Spacer()
                            Text(taxAdvice)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { Double(game.sim.taxRate) },
                                set: { game.setTaxRate(Int($0.rounded())) }
                            ),
                            in: 0...20, step: 1
                        )
                    }
                }

                Section("年度の見込み") {
                    row("住民税", "+¥\(game.sim.incomeFromResidents)")
                    row("事業税", "+¥\(game.sim.incomeFromBusiness)")
                    row("道路の維持", "-¥\(game.sim.roadUpkeep)")
                    row("発電所", "-¥\(game.sim.plantUpkeep)")
                    row("警察", "-¥\(game.sim.policeUpkeep)")
                    row("消防", "-¥\(game.sim.fireUpkeep)")
                    let net = game.sim.projectedIncome - game.sim.projectedExpenses
                    HStack {
                        Text("収支").fontWeight(.semibold)
                        Spacer()
                        Text(net >= 0 ? "+¥\(net)" : "-¥\(-net)")
                            .fontWeight(.bold)
                            .monospacedDigit()
                            .foregroundStyle(net >= 0 ? .green : .red)
                    }
                }

                Section("前年度の決算") {
                    if game.sim.lastIncome == 0 && game.sim.lastExpenses == 0 {
                        Text("まだ決算がありません").foregroundStyle(.secondary)
                    } else {
                        row("収入", "+¥\(game.sim.lastIncome)")
                        row("支出", "-¥\(game.sim.lastExpenses)")
                    }
                }

                Section("都市の状態") {
                    row("人口", "\(game.sim.residents)")
                    row("商業の雇用", "\(game.sim.jobsCommercial)")
                    row("工業の雇用", "\(game.sim.jobsIndustrial)")
                    row("道路", "\(game.sim.roadCount) マス")
                    row("送電線", "\(game.sim.wireCount) マス")
                    row("発電所の供給余力",
                        "\((game.sim.zoneCounts[.coalPlant] ?? 0) * Simulation.plantCapacity) 区画ぶん")
                }

                // 商品を引けないときは欄ごと出さない。押せない購入ボタンが残っていると、
                // 壊れているように見えるし、審査でも機能しない課金として扱われる。
                if store.hasRemovedAds || store.removeAds != nil {
                Section("広告") {
                    if store.hasRemovedAds {
                        Label("広告は消えています", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button {
                            Task { await store.buy() }
                        } label: {
                            HStack {
                                Text("広告を消す")
                                Spacer()
                                Text(store.removeAds?.displayPrice ?? "…")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .disabled(store.isWorking)
                        Button("購入を復元") {
                            Task { await store.restore() }
                        }
                        .disabled(store.isWorking)
                    }
                }
                }

                Section {
                    Button(role: .destructive) {
                        confirmingNewCity = true
                    } label: {
                        Text("新しい都市をはじめる")
                    }
                } footer: {
                    Text("地形を選び直して、最初の1900年に戻ります。")
                }
            }
            .alert("購入", isPresented: Binding(get: { store.failure != nil },
                                              set: { if !$0 { store.failure = nil } })) {
                Button("OK") { store.failure = nil }
            } message: {
                Text(store.failure ?? "")
            }
            .safeAreaInset(edge: .bottom) { AdBanner() }
            .navigationTitle("予算")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    private var taxAdvice: String {
        switch game.sim.taxRate {
        case 0...4: return "誰もが喜ぶが、財政は持たない"
        case 5...8: return "成長を妨げない範囲"
        case 9...12: return "そろそろ嫌がられる"
        default: return "高すぎる。人も企業も出ていく"
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).monospacedDigit().foregroundStyle(.secondary)
        }
    }
}

/// 「新しい都市をはじめる」の確認オーバーレイ。見た目はシステムのアラートに寄せてあるが、
/// 中身はただの SwiftUI ビュー。
private struct ConfirmNewCityOverlay: View {
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(spacing: 14) {
                VStack(spacing: 6) {
                    Text("いまの都市を捨てますか")
                        .font(.system(size: 16, weight: .bold))
                    Text("建てたものも地形も消えます。元には戻せません。")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 4)

                VStack(spacing: 8) {
                    Button(action: onConfirm) {
                        Text("地形を選ぶ")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.1)))
                            // 背景の角丸矩形はデフォルトではタップ判定に含まれない。
                            // 明示しないと文字の実サイズしか反応せず、余白を押すと
                            // 背後の全画面タップ（キャンセル）に流れてしまう。
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button(action: onCancel) {
                        Text("キャンセル")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.1)))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .frame(maxWidth: 300)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(white: 0.15)))
            .foregroundStyle(.white)
        }
    }
}
