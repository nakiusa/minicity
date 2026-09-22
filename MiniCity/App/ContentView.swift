import SwiftUI

struct ContentView: View {
    @StateObject private var game = GameState()
    @ObservedObject private var store = Store.shared
    @ObservedObject private var ads = Ads.shared
    @State private var showBudget = false
    @State private var showAchievements = false
    @AppStorage("hasSeenHelp") private var hasSeenHelp = false
    /// 街が動き出すまでの手順の案内を、もう出さなくてよいか。
    @AppStorage("guideDone") private var guideDone = false
    /// 目標の行を消したか。
    @AppStorage("goalsHidden") private var goalsHidden = false
    @State private var showHelp = false
    @State private var showIntro = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            CityCanvas(game: game)
                .ignoresSafeArea()

            VStack(spacing: 8) {
                TopBar(game: game, showBudget: $showBudget)

                HStack(alignment: .top) {
                    DemandIndicator(game: game)
                    Spacer()
                    Button {
                        game.scene?.centerOnCity()
                    } label: {
                        Image(systemName: "scope")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .panel()
                    }
                    .buttonStyle(.plain)
                    Button {
                        showAchievements = true
                    } label: {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .panel()
                    }
                    .buttonStyle(.plain)
                    Button {
                        showHelp = true
                    } label: {
                        Image(systemName: "questionmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .panel()
                    }
                    .buttonStyle(.plain)
                    OverlayPicker(game: game)
                }

                if !guideDone, let step = GuideStep.next(for: game.sim) {
                    GuideBar(game: game, step: step) { guideDone = true }
                } else if guideDone, !goalsHidden, let goal = GoalStep.next(for: game.sim) {
                    GoalBar(achievement: goal.achievement, now: goal.now, goal: goal.goal,
                            onOpen: { showAchievements = true },
                            onDismiss: { goalsHidden = true })
                }

                Spacer()

                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        PanToolButton(game: game)
                        ZoomControls(game: game)
                    }
                }

                if game.tool == .inspect {
                    InspectorPanel(game: game)
                }

                if game.pendingTiles > 0 {
                    ConfirmBar(game: game)
                }

                if let message = game.message {
                    Text(message)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.red.opacity(0.85)))
                        .transition(.opacity)
                }

                ToolPalette(game: game)

                // 「調べる」の一覧を開くと縦が足りず、上の帯が画面の外へ押し出される。その間だけ引っ込める。
                if game.tool != .inspect {
                    AdBanner()
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
            .animation(.easeInOut(duration: 0.15), value: game.message)
            .animation(.easeInOut(duration: 0.15), value: game.pendingTiles)

        }
        .fullScreenCover(isPresented: $showIntro) {
            IntroView {
                hasSeenHelp = true
                showIntro = false
            }
        }
        .onChange(of: showIntro) { _, shown in
            // 案内を読んでいる間に街の時間が進むと、戻ったときに何年も経っている。
            game.speed = shown ? .paused : .x1
        }
        .sheet(isPresented: $showHelp) {
            HelpView(onReplayIntro: { showIntro = true },
                     onResetGuide: { guideDone = false })
        }
        .fullScreenCover(isPresented: .constant(game.needsMapSelection)) {
            // はじめて遊ぶときだけ、地形を選んでから始める。
            // いきなり知らない地形に放り出されると、何を見ているのか分からない。
            MapSelectView(onSelect: { seed, termYears in
                game.finishMapSelection(seed: seed, termYears: termYears)
            }, allowsCancel: false)
        }
        .sheet(isPresented: $showAchievements) {
            AchievementsView(game: game)
        }
        .sheet(isPresented: $showBudget) {
            BudgetView(game: game, store: store)
        }
        .sheet(isPresented: $game.showsResult) {
            ResultView(game: game)
        }
        .statusBarHidden()
        .preferredColorScheme(.dark)
        .onAppear {
            if !hasSeenHelp && !game.needsMapSelection { showIntro = true }
        }
        .onChange(of: game.revision) { _, _ in
            // 人が入ったら手順の案内は終わり。以後は ? から読み直せる。
            if !guideDone, game.sim.residents > 0, GuideStep.next(for: game.sim) == nil {
                guideDone = true
            }
        }
        .task(id: game.needsMapSelection) {
            // 地形を選んでいる最中に追跡の許可が重なると、どちらも読めない。
            guard !game.needsMapSelection else { return }
            // 起動直後に尋ねると、画面がまだ前に出ていなくて許可のダイアログが流れることがある。
            try? await Task.sleep(for: .seconds(1))
            await ads.start()
        }
        .onChange(of: game.adBreaks) { _, _ in
            // 街がひと区切りついたところでだけ、全画面広告を出す。
            guard !store.hasRemovedAds else { return }
            ads.showFullScreen()
        }
        .onChange(of: game.needsMapSelection) { _, needs in
            // 地形を選び終えてから操作説明を出す。
            // 選択画面と重なると、どちらも読めない。
            if !needs && !hasSeenHelp { showIntro = true }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { game.save() }
        }
    }
}

/// なぞった線を敷くかどうかを決めるバー。
/// なぞった時点では敷かず、ここで押して初めて確定する。
struct ConfirmBar: View {
    @ObservedObject var game: GameState

    var body: some View {
        HStack(spacing: 10) {
            Text("\(game.pendingTiles)マスに\(game.tool.title)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)

            Spacer(minLength: 8)

            Button("やめる") { game.cancelPending() }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .buttonStyle(.plain)

            Button {
                game.commitPending()
            } label: {
                Text("決定")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.white))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.black.opacity(0.78)))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
