import SwiftUI

struct ContentView: View {
    @StateObject private var game = GameState()
    @State private var showBudget = false
    @State private var showAchievements = false
    @AppStorage("hasSeenHelp") private var hasSeenHelp = false
    @State private var showHelp = false
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

                Spacer()

                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        PanToolButton(game: game)
                        ZoomControls(game: game)
                    }
                }

                if let text = game.inspected, game.tool == .inspect {
                    Text(text)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .panel()
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
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
            .animation(.easeInOut(duration: 0.15), value: game.message)
            .animation(.easeInOut(duration: 0.15), value: game.pendingTiles)

            if showHelp {
                HelpOverlay(isPresented: $showHelp, hasSeenHelp: $hasSeenHelp)
            }
        }
        .fullScreenCover(isPresented: .constant(game.needsMapSelection)) {
            // はじめて遊ぶときだけ、地形を選んでから始める。
            // いきなり知らない地形に放り出されると、何を見ているのか分からない。
            MapSelectView(onSelect: { seed in
                game.finishMapSelection(seed: seed)
            }, allowsCancel: false)
        }
        .sheet(isPresented: $showAchievements) {
            AchievementsView(game: game)
        }
        .sheet(isPresented: $showBudget) {
            BudgetView(game: game)
        }
        .statusBarHidden()
        .preferredColorScheme(.dark)
        .onAppear {
            if !hasSeenHelp && !game.needsMapSelection { showHelp = true }
        }
        .onChange(of: game.needsMapSelection) { _, needs in
            // 地形を選び終えてから操作説明を出す。
            // 選択画面と重なると、どちらも読めない。
            if !needs && !hasSeenHelp { showHelp = true }
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

/// 最初の一回だけ、操作と最短の立ち上げ手順を出す。
struct HelpOverlay: View {
    @Binding var isPresented: Bool
    @Binding var hasSeenHelp: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.78).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                Text("ミニシティ")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))

                VStack(alignment: .leading, spacing: 7) {
                    line("移動", "この道具を選ぶと、1本指のドラッグで地図が動く")
                    line("拡大縮小", "右下のつまみを上下になぞる。⊕ ⊖ を押せば1段ずつ動く")
                    line("調べる", "同じくドラッグで地図が動く。軽く叩くとそのマスの土地価値や公害を読む")
                    line("その他", "1本指でマスを塗る（道路や送電線はなぞれる）")
                    line("2本指", "どの道具でも地図を動かせる。つまめば拡大縮小")
                }

                Divider().overlay(Color.white.opacity(0.2))

                Text("はじめかた")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                VStack(alignment: .leading, spacing: 7) {
                    line("1", "発電所を1つ置く")
                    line("2", "道路を引き、その脇に住宅区と工業区を並べる")
                    line("3", "送電線で発電所と区画をつなぐ（区画どうしは電気を通す）")
                    line("4", "時間を進める。人が入れば商業の需要が立ち上がる")
                }

                Button {
                    hasSeenHelp = true
                    isPresented = false
                } label: {
                    Text("はじめる")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.accentColor))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .foregroundStyle(.white)
            .padding(22)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(white: 0.13))
            )
            .padding(24)
        }
    }

    private func line(_ head: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text(head)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .frame(width: 46, alignment: .center)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.16)))
            Text(body)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
