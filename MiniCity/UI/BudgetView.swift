import SwiftUI

/// 税率の調整と、年度末に何が起きるかの内訳。
struct BudgetView: View {
    @ObservedObject var game: GameState
    @ObservedObject var store: Store
    @Environment(\.dismiss) private var dismiss
    /// 都市を捨てる操作は戻せないので、一度確かめる。
    @State private var confirmingNewCity = false
    @State private var showMapSelect = false
    /// 名前を付けて残すときの入力。
    @State private var namingCity = false
    @State private var cityName = ""
    @State private var showReport = false
    @AppStorage("soundOn") private var soundOn = true
    @AppStorage("hapticsOn") private var hapticsOn = true

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
        .sheet(isPresented: $showReport) {
            ResultView(game: game, isFinal: false)
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
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    taxSection
                    forecastSection
                    loanSection
                    lastYearSection
                    citySection
                    settingsSection
                    adsSection
                    actionsSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 170)
            }
            .background(NightBackground())
            .toolbar(.hidden, for: .navigationBar)
            .alert("街の名前", isPresented: $namingCity) {
                TextField("名前", text: $cityName)
                Button("保存") {
                    let name = cityName.trimmingCharacters(in: .whitespaces)
                    game.shelveCity(name: name.isEmpty ? String(localized: "\(game.sim.year)年目の街") : name)
                }
                Button("やめる", role: .cancel) {}
            } message: {
                Text("いまの街を保存します。遊んでいる街はそのまま続きます。")
            }
            .alert("購入", isPresented: Binding(get: { store.failure != nil },
                                              set: { if !$0 { store.failure = nil } })) {
                Button("OK") { store.failure = nil }
            } message: {
                Text(store.failure ?? "")
            }
            .safeAreaInset(edge: .bottom) { AdBanner() }
        }
    }

    private var net: Int { game.sim.projectedIncome - game.sim.projectedExpenses }

    /// 画面の頭。手元の資金を大きく出し、その下に今年の収支を添える。
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("予算").font(.dot(28)).foregroundStyle(Theme.ink)
                Text("\(String(game.sim.year))年目")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.mute)
                Spacer()
                CloseButton { dismiss() }
            }
            .padding(.top, 18)
            Text("資金").font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(Theme.mute)
                .padding(.top, 14)
            Text("¥\(game.sim.funds.formatted())")
                .font(.dot(40))
                .foregroundStyle(game.sim.funds < 0 ? Theme.loss : Theme.ink)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text("年度の見込み").font(.system(size: 12)).foregroundStyle(Theme.mute)
                Text(net >= 0 ? "+¥\(net.formatted())" : "-¥\((-net).formatted())")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(net >= 0 ? Theme.gain : Theme.loss)
            }
        }
    }

    private var taxSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(number: 1, title: "税率")
            HStack(alignment: .firstTextBaseline) {
                Text("\(game.sim.taxRate)%").font(.dot(30)).foregroundStyle(Theme.ink).monospacedDigit()
                Spacer()
                Text(taxAdvice).font(.system(size: 12)).foregroundStyle(Theme.mute)
            }
            Slider(
                value: Binding(
                    get: { Double(game.sim.taxRate) },
                    set: { game.setTaxRate(Int($0.rounded())) }
                ),
                in: 0...30, step: 1
            )
            .tint(Theme.gold)
        }
    }

    /// 年度の見込み。金額の大きさを帯の長さで見せ、収入と支出を色で分ける。
    private var forecastSection: some View {
        let sim = game.sim
        var items: [(LocalizedStringKey, Int)] = [
            ("住民税", sim.incomeFromResidents), ("事業税", sim.incomeFromBusiness),
            ("道路の維持", -sim.roadUpkeep), ("発電所", -sim.plantUpkeep),
            ("警察", -sim.policeUpkeep), ("消防", -sim.fireUpkeep),
        ]
        if sim.railUpkeep > 0 { items.append(("鉄道", -sim.railUpkeep)) }
        if sim.debt > 0 { items += [("借入の利息", -sim.debtInterest), ("借入の返済", -sim.debtRepayment)] }
        let largest = max(1, items.map { abs($0.1) }.max() ?? 1)
        return VStack(alignment: .leading, spacing: 0) {
            SectionTitle(number: 2, title: "年度の見込み")
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                LedgerRow(item.0) {
                    HStack(spacing: 10) {
                        GeometryReader { geo in
                            HStack {
                                Spacer(minLength: 0)
                                Rectangle()
                                    .fill(item.1 >= 0 ? Theme.gain.opacity(0.7) : Theme.loss.opacity(0.55))
                                    .frame(width: max(2, geo.size.width * Double(abs(item.1)) / Double(largest)))
                            }
                        }
                        .frame(width: 90, height: 6)
                        Text(item.1 >= 0 ? "+¥\(item.1.formatted())" : "-¥\((-item.1).formatted())")
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundStyle(Theme.mute)
                            .frame(minWidth: 82, alignment: .trailing)
                    }
                }
            }
            HStack {
                Text("収支").font(.dot(17)).foregroundStyle(Theme.ink)
                Spacer()
                Text(net >= 0 ? "+¥\(net.formatted())" : "-¥\((-net).formatted())")
                    .font(.dot(20))
                    .foregroundStyle(net >= 0 ? Theme.gain : Theme.loss)
            }
            .padding(.top, 12)
        }
    }

    private var loanSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(number: 3, title: "借入")
            LedgerRow("借入の残高", value: "¥\(game.sim.debt.formatted())")
            HStack(spacing: 10) {
                Button { game.borrow() } label: { Text("¥\(Simulation.loanAmount.formatted()) を借りる") }
                    .buttonStyle(PixelButtonStyle(tint: Theme.gold))
                    .disabled(!game.sim.canBorrow)
                if game.sim.debt > 0 {
                    Button { game.repay() } label: { Text("手元の資金で返す") }
                        .buttonStyle(PixelButtonStyle())
                        .disabled(game.sim.funds <= 0)
                }
            }
            Text("年5％の利息。毎年、残高の1割（最低 ¥5,000）と利息を返します。上限は ¥\(Simulation.debtLimit.formatted())。")
                .font(.system(size: 11)).foregroundStyle(Theme.mute)
        }
    }

    private var lastYearSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle(number: 4, title: "前年度の決算")
            if game.sim.lastIncome == 0 && game.sim.lastExpenses == 0 {
                Text("まだ決算がありません").font(.system(size: 14)).foregroundStyle(Theme.mute).padding(.vertical, 8)
            } else {
                LedgerRow("収入", value: "+¥\(game.sim.lastIncome.formatted())", tint: Theme.gain)
                LedgerRow("支出", value: "-¥\(game.sim.lastExpenses.formatted())", tint: Theme.loss)
            }
        }
    }

    /// 都市の状態。数字の並びは、1px の罫線で仕切った升目にする。
    private var citySection: some View {
        let sim = game.sim
        let cells: [(LocalizedStringKey, String)] = [
            ("人口", sim.residents.formatted()),
            ("商業の雇用", sim.jobsCommercial.formatted()),
            ("工業の雇用", sim.jobsIndustrial.formatted()),
            ("道路", String(localized: "\(sim.roadCount) マス")),
            ("送電線", String(localized: "\(sim.wireCount) マス")),
            ("発電所の供給余力", String(localized: "\((sim.zoneCounts[.coalPlant] ?? 0) * Simulation.plantCapacity) 区画ぶん")),
        ]
        return VStack(alignment: .leading, spacing: 0) {
            SectionTitle(number: 5, title: "都市の状態")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 1), GridItem(.flexible(), spacing: 1)], spacing: 1) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(cell.0).font(.system(size: 11)).foregroundStyle(Theme.mute).lineLimit(1).minimumScaleFactor(0.7)
                        Text(cell.1).font(.dot(18)).foregroundStyle(Theme.ink).lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Theme.plate)
                }
            }
            .background(Theme.rule)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle(number: 6, title: "設定")
            LedgerRow("効果音") { Toggle("", isOn: $soundOn).labelsHidden().tint(Theme.gold) }
            LedgerRow("振動") { Toggle("", isOn: $hapticsOn).labelsHidden().tint(Theme.gold) }
        }
    }

    // 商品を引けないときは欄ごと出さない。押せない購入ボタンが残っていると、
    // 壊れているように見えるし、審査でも機能しない課金として扱われる。
    @ViewBuilder
    private var adsSection: some View {
        if store.hasRemovedAds || store.removeAds != nil {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(number: 7, title: "広告")
                if store.hasRemovedAds {
                    Label("広告は消えています", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 14)).foregroundStyle(Theme.gain)
                } else {
                    Button {
                        Task { await store.buy() }
                    } label: {
                        Text("広告を消す  \(store.removeAds?.displayPrice ?? "…")")
                    }
                    .buttonStyle(PixelButtonStyle(tint: Theme.gold, filled: true))
                    .disabled(store.isWorking)
                    Button("購入を復元") { Task { await store.restore() } }
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.mute)
                        .disabled(store.isWorking)
                }
            }
        }
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(number: 8, title: "街")
            Button { showReport = true } label: { Label("いまの成績表を見る", systemImage: "list.clipboard") }
                .buttonStyle(PixelButtonStyle())
            Button {
                cityName = ""
                namingCity = true
            } label: { Label("この街に名前を付けて保存", systemImage: "square.and.arrow.down") }
                .buttonStyle(PixelButtonStyle())
            NavigationLink { ShelvedCitiesView(game: game) } label: { Label("保存した街", systemImage: "archivebox") }
                .buttonStyle(PixelButtonStyle())
            Button { confirmingNewCity = true } label: { Text("新しい都市をはじめる") }
                .buttonStyle(PixelButtonStyle(tint: Theme.loss))
            Text("新しい都市をはじめると、いまの街は消えます。残したい街は、先に名前を付けて保存してください。")
                .font(.system(size: 11)).foregroundStyle(Theme.mute)
        }
    }

    private var taxAdvice: String {
        switch game.sim.taxRate {
        case 0...6: return String(localized: "誰もが喜ぶが、財政は持たない")
        case 7...11: return String(localized: "成長を妨げない範囲")
        case 12...17: return String(localized: "そろそろ嫌がられる")
        default: return String(localized: "高すぎる。人も企業も出ていく")
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


/// 名前を付けて残した街の一覧。呼び出すか、消す。
struct ShelvedCitiesView: View {
    @ObservedObject var game: GameState
    @Environment(\.dismiss) private var dismiss
    @State private var cities = CityStore.shelved()
    @State private var loading: URL?

    var body: some View {
        List {
            if cities.isEmpty {
                Text("まだありません。予算の「この街に名前を付けて保存」で保存できます。")
                    .foregroundStyle(Theme.mute)
                    .listRowBackground(Theme.plate)
            }
            ForEach(cities, id: \.url) { city in
                Button {
                    loading = city.url
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(city.save.name ?? "—")
                            .font(.dot(16))
                            .foregroundStyle(Theme.ink)
                        Text("\(String(city.save.year))年目 · 人口 \(city.save.residents.formatted())人 · ¥\(city.save.funds.formatted())")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.mute)
                        if let at = city.save.savedAt {
                            Text(at, style: .date)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.mute.opacity(0.7))
                        }
                    }
                }
                .listRowBackground(Theme.plate)
            }
            .onDelete { offsets in
                for i in offsets { CityStore.unshelve(cities[i].url) }
                cities = CityStore.shelved()
            }
        }
        .scrollContentBackground(.hidden)
        .background(NightBackground())
        .toolbar(.visible, for: .navigationBar)
        .navigationTitle("保存した街")
        .navigationBarTitleDisplayMode(.inline)
        .alert("この街を読み込む", isPresented: Binding(get: { loading != nil }, set: { if !$0 { loading = nil } })) {
            Button("読み込む") {
                if let url = loading, let city = cities.first(where: { $0.url == url }) {
                    game.loadCity(city.save)
                    dismiss()
                }
                loading = nil
            }
            Button("やめる", role: .cancel) { loading = nil }
        } message: {
            Text("いま遊んでいる街は上書きされます。残したいなら、先に名前を付けて保存してください。")
        }
    }
}
