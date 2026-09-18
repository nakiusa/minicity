import Combine
import SwiftUI

enum GameSpeed: String, CaseIterable, Identifiable {
    case paused, x1, x2, x4

    var id: String { rawValue }

    /// 1か月にかける秒数。等倍で1年が24秒、50年で20分。
    var interval: TimeInterval? {
        switch self {
        case .paused: return nil
        case .x1: return 2.0
        case .x2: return 1.0
        case .x4: return 0.5
        }
    }

    var symbol: String {
        switch self {
        case .paused: return "pause.fill"
        case .x1: return "play.fill"
        case .x2: return "forward.fill"
        case .x4: return "forward.end.fill"
        }
    }

    var title: String {
        switch self {
        case .paused: return String(localized: "停止")
        case .x1: return String(localized: "等倍")
        case .x2: return String(localized: "2倍")
        case .x4: return String(localized: "4倍")
        }
    }
}

/// 「調べる」で叩いたマス。数値は時間とともに変わるので持たず、位置だけ覚えておく。
struct InspectedTile {
    let x: Int
    let y: Int
    /// そこに何があるか。数値は含めない。
    let summary: String
}

/// SwiftUI と SpriteKit の橋渡し。時間を進め、道具の適用結果を画面に返す。
final class GameState: ObservableObject {

    @Published private(set) var sim: Simulation
    /// 画面を描き直させるための世代番号。数値そのものに意味はない。
    @Published private(set) var revision = 0

    @Published var tool: Tool = .pan {
        didSet {
            scene?.footprint = tool.footprint
            scene?.dragMovesCamera = tool.movesCamera
            scene?.previewsDrag = tool.isDraggable
            // 道具を持ち替えたら、確定待ちの線は捨てる。
            scene?.cancelPreview()
        }
    }
    @Published var speed: GameSpeed = .x1 {
        didSet { restartClock() }
    }
    @Published var overlay: OverlayMode = .none {
        didSet { scene?.overlayMode = overlay }
    }
    @Published var message: String?
    @Published var inspected: InspectedTile?

    /// 0 が引ききった状態、1 が寄りきった状態。スライダーと双方向に結ぶ。
    @Published var zoomLevel: Double = Double(CityScene.level(forScale: CityScene.defaultScale)) {
        didSet {
            guard !isSyncingZoom else { return }
            scene?.applyZoom(level: CGFloat(zoomLevel))
        }
    }
    /// 画面から倍率を戻すときに、押し返しが起きないようにする。
    private var isSyncingZoom = false

    /// ピンチやボタンで倍率が変わったとき、スライダーの位置を合わせる。
    func syncZoom(scale: CGFloat) {
        isSyncingZoom = true
        zoomLevel = Double(CityScene.level(forScale: scale))
        isSyncingZoom = false
    }

    var scene: CityScene?
    private var clock: Timer?
    private var messageClearWork: DispatchWorkItem?

    /// はじめて遊ぶとき（保存された都市がないとき）に立てる。
    /// いきなり知らない地形で始まらないよう、最初にマップを選ばせる。
    @Published private(set) var needsMapSelection = false

    init() {
        if let save = CityStore.load() {
            sim = Simulation(save: save)
        } else {
            // 選ぶまでのあいだ画面に出しておく地形。選べばそのまま作り直す。
            sim = Simulation()
            needsMapSelection = true
        }
        restartClock()

        // スクリーンショットを撮るときの逃げ道。起動時の引数 `-screenshotInspect x,y` で
        // 「調べる」を選んだ状態にし、公害の地図を載せる。言語ごとに8回撮るので、
        // 手で叩かずに済むようにしてある。
        if let spec = UserDefaults.standard.string(forKey: "screenshotInspect") {
            let parts = spec.split(separator: ",").compactMap { Int($0) }
            if parts.count == 2 {
                tool = .inspect
                inspected = InspectedTile(x: parts[0], y: parts[1],
                                          summary: describeTile(x: parts[0], y: parts[1]))
                overlay = .pollution
            }
        }
    }

    /// 遊ぶ期限が来たときに出す成績表。開いているあいだ時間は止まる。
    @Published var showsResult = false

    /// 街がひと区切りついた回数。全画面広告を出す合図に使う。
    /// 遊びの最中に割り込まないよう、区切りの場面でしか増やさない。
    @Published private(set) var adBreaks = 0

    /// 起動時のマップ選択を終える。
    func finishMapSelection(seed: UInt64, termYears: Int?) {
        needsMapSelection = false
        newCity(seed: seed, termYears: termYears)
    }

    /// 期限が来たあとも、そのまま続ける。以後は期限なしになる。
    func keepPlaying() {
        sim.termYears = nil
        showsResult = false
        save()
        speed = .x1
        adBreaks += 1
        revision &+= 1
    }

    func save() {
        CityStore.save(sim)
    }

    // MARK: - 時間

    private func restartClock() {
        clock?.invalidate()
        clock = nil
        guard let interval = speed.interval else { return }
        clock = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.step()
        }
    }

    private func step() {
        sim.tick()
        if sim.monthsElapsed % 12 == 0 { save() }
        // 決めた年数まで来たら時間を止めて、成績表を出す。
        if sim.isOver && !showsResult {
            speed = .paused
            save()
            showsResult = true
            if let term = sim.termYears { GameCenter.submit(population: sim.residents, term: term) }
        }
        scene?.applyDirty()
        // 一度に大量に光ると何も読めないので、数を絞る。
        for (x, y) in sim.recentUpgrades.prefix(10) {
            scene?.flashUpgrade(x: x, y: y)
        }
        scene?.refreshMarkers()
        scene?.refreshTraffic()
        scene?.refreshTowers()
        if overlay != .none { scene?.refreshOverlay() }
        checkAchievements()
        revision &+= 1
    }

    // MARK: - 実績

    /// 直前に取った実績。取った瞬間だけ画面に出す。
    @Published var justEarned: Achievement?
    /// 一覧の見出しに出す「取った数」。
    @Published var earnedCount = AchievementStore.shared.earnedCount

    private func checkAchievements() {
        let newly = AchievementStore.shared.claimNewlyEarned(in: sim)
        guard let first = newly.first else { return }
        earnedCount = AchievementStore.shared.earnedCount
        justEarned = first
        GameCenter.report(newly.map(\.id))
        // 同時にいくつも取ったときは、残りは一覧で見てもらう。
        show(String(localized: "実績「\(first.title)」を達成"))
    }

    // MARK: - 建設

    /// 指を離したあと、確定を待っているマスの数。0 なら待ちがない。
    @Published var pendingTiles = 0

    /// なぞった線をまとめて敷く。
    func commitPending() {
        scene?.commitPreview()
    }

    /// なぞった線を捨てる。
    func cancelPending() {
        scene?.cancelPreview()
    }

    func paint(x: Int, y: Int) {
        switch tool {
        case .pan:
            return
        case .inspect:
            inspected = InspectedTile(x: x, y: y, summary: describeTile(x: x, y: y))
            return
        default:
            break
        }

        switch sim.apply(tool, atX: x, y: y) {
        case .built:
            // 止めているあいだでも、電気や道路がつながったことはすぐ見せる。
            sim.updatePower()
            sim.updateRoadAccess()
            sim.census()
        case .insufficientFunds(let needed):
            show(String(localized: "資金が足りません（¥\(needed) 必要）"))
        case .blocked(let reason):
            show(reason)
        case .nothingToDo:
            break
        }
        scene?.applyDirty()
        scene?.refreshMarkers()
        scene?.refreshTowers()
        if overlay != .none { scene?.refreshOverlay() }
        checkAchievements()
        revision &+= 1
    }

    private func describeTile(x: Int, y: Int) -> String {
        let t = sim.map.tile(x, y)
        var parts: [String] = ["(\(x), \(y))"]

        if let z = sim.map.zone(t.zoneID) {
            parts.append(z.kind.name)
            if z.kind.grows {
                parts.append(z.level == 0 ? String(localized: "未開発") : String(localized: "レベル \(z.level)・\(z.capacity)人"))
            }
            parts.append(z.powered ? String(localized: "通電") : String(localized: "停電"))
            parts.append(z.hasRoad ? String(localized: "道路あり") : String(localized: "道路なし"))
            if z.kind == .residential && z.level > 0 {
                parts.append(z.hasJobAccess ? String(localized: "通勤可") : String(localized: "職場に行けない"))
            }
        } else {
            switch t.structure {
            case .road: parts.append(String(localized: "道路（交通量 \(t.traffic)）"))
            case .park: parts.append(String(localized: "公園"))
            case .rubble: parts.append(String(localized: "更地"))
            case .none, .zone:
                switch t.terrain {
                case .water: parts.append(String(localized: "水面"))
                case .forest: parts.append(String(localized: "森"))
                case .dirt: parts.append(String(localized: "空き地"))
                }
            }
            if t.wire { parts.append(String(localized: "送電線")) }
        }

        // 土地価値や公害の数値はここには混ぜない。見る側で帯付きの一覧として出す。
        return parts.joined(separator: " / ")
    }

    // MARK: - その他

    /// `seed` を省略すると完全にランダムな地形になる。マップ選択画面から
    /// 呼ぶときは、そこでプレビューした種をそのまま渡して同じ地形を再現する。
    func newCity(seed: UInt64 = UInt64.random(in: 0..<UInt64.max), termYears: Int? = nil) {
        speed = .paused
        showsResult = false
        CityStore.clear()
        sim = Simulation(seed: seed)
        sim.termYears = termYears
        scene?.sim = sim
        scene?.fullRefresh()
        scene?.resetCamera()
        adBreaks += 1
        revision &+= 1
        speed = .x1
    }

    func borrow() {
        sim.borrow()
        save()
        revision &+= 1
    }

    func repay() {
        sim.repay()
        save()
        revision &+= 1
    }

    func setTaxRate(_ rate: Int) {
        sim.taxRate = min(max(rate, 0), 20)
        revision &+= 1
    }

    private func show(_ text: String) {
        message = text
        messageClearWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.message = nil }
        messageClearWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: work)
    }
}
