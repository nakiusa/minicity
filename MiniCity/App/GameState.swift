import Combine
import SwiftUI

enum GameSpeed: String, CaseIterable, Identifiable {
    case paused, slow, normal, fast

    var id: String { rawValue }

    var interval: TimeInterval? {
        switch self {
        case .paused: return nil
        case .slow: return 1.2
        case .normal: return 0.5
        case .fast: return 0.15
        }
    }

    var symbol: String {
        switch self {
        case .paused: return "pause.fill"
        case .slow: return "play.fill"
        case .normal: return "forward.fill"
        case .fast: return "forward.end.fill"
        }
    }

    var title: String {
        switch self {
        case .paused: return "停止"
        case .slow: return "ゆっくり"
        case .normal: return "ふつう"
        case .fast: return "はやい"
        }
    }
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
    @Published var speed: GameSpeed = .normal {
        didSet { restartClock() }
    }
    @Published var overlay: OverlayMode = .none {
        didSet { scene?.overlayMode = overlay }
    }
    @Published var message: String?
    @Published var inspected: String?

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
    }

    /// 起動時のマップ選択を終える。
    func finishMapSelection(seed: UInt64) {
        needsMapSelection = false
        newCity(seed: seed)
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
        // 同時にいくつも取ったときは、残りは一覧で見てもらう。
        show("実績「\(first.title)」を達成")
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
            inspected = describeTile(x: x, y: y)
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
            show("資金が足りません（¥\(needed) 必要）")
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
                parts.append(z.level == 0 ? "未開発" : "レベル \(z.level)・\(z.capacity)人")
            }
            parts.append(z.powered ? "通電" : "停電")
            parts.append(z.hasRoad ? "道路あり" : "道路なし")
            if z.kind == .residential && z.level > 0 {
                parts.append(z.hasJobAccess ? "通勤可" : "職場に行けない")
            }
        } else {
            switch t.structure {
            case .road: parts.append("道路（交通量 \(t.traffic)）")
            case .park: parts.append("公園")
            case .rubble: parts.append("更地")
            case .none, .zone:
                switch t.terrain {
                case .water: parts.append("水面")
                case .forest: parts.append("森")
                case .dirt: parts.append("空き地")
                }
            }
            if t.wire { parts.append("送電線") }
        }

        parts.append("土地価値 \(sim.landValue.atTile(x, y))")
        parts.append("公害 \(sim.pollution.atTile(x, y))")
        parts.append("犯罪 \(sim.crime.atTile(x, y))")
        return parts.joined(separator: " / ")
    }

    // MARK: - その他

    /// `seed` を省略すると完全にランダムな地形になる。マップ選択画面から
    /// 呼ぶときは、そこでプレビューした種をそのまま渡して同じ地形を再現する。
    func newCity(seed: UInt64 = UInt64.random(in: 0..<UInt64.max)) {
        speed = .paused
        CityStore.clear()
        sim = Simulation(seed: seed)
        scene?.sim = sim
        scene?.fullRefresh()
        scene?.resetCamera()
        revision &+= 1
        speed = .normal
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
