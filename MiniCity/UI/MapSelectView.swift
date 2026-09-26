import SwiftUI

/// 新しい都市を始める前に、候補の地形をいくつか見てから選べる画面。
/// `GameState` には触れず、選んだ種（シード）を `onSelect` で返すだけにしてある。
struct MapSelectView: View {
    /// 選んだ地形と、遊ぶ年数（`nil` は期限なし）を返す。
    let onSelect: (UInt64, Int?) -> Void
    /// はじめて遊ぶときは、戻る先がないのでキャンセルを出さない。
    var allowsCancel = true
    @Environment(\.dismiss) private var dismiss

    @State private var candidates: [UInt64] = []
    /// 遊ぶ年数。0 は期限なしのしるし。
    @State private var termYears = 100
    @State private var thumbnails: [UInt64: Image] = [:]

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("マップを選ぶ").font(.dot(26)).foregroundStyle(Theme.ink)
                        Spacer()
                        Button { reroll() } label: {
                            Image(systemName: "arrow.clockwise")
                                .foregroundStyle(Theme.ink)
                                .padding(8)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.rule, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                        if allowsCancel {
                            Button { dismiss() } label: {
                                Text("キャンセル").font(.dot(14)).foregroundStyle(Theme.ink)
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.rule, lineWidth: 1.5))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 18)

                    SectionTitle(number: 1, title: "遊ぶ年数")
                    // 年数の切り替え。標準の切り替えの部品ではなく、角の立った札を並べる。
                    HStack(spacing: 6) {
                        ForEach([(50, "50年"), (100, "100年"), (200, "200年"), (0, "期限なし")], id: \.0) { value, label in
                            Button { termYears = value } label: {
                                Text(LocalizedStringKey(label))
                                    .font(.dot(14))
                                    .foregroundStyle(termYears == value ? Theme.skyTop : Theme.ink)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 9)
                                    .background(RoundedRectangle(cornerRadius: 4).fill(termYears == value ? Theme.gold : Theme.plate))
                                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.rule, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Group {
                        if termYears == 0 {
                            Text("終わりはない。好きなだけ育てられる。")
                        } else {
                            // 年に桁区切りが入らないよう、数のままにしない。
                            Text("\(termYears)年遊ぶ。最後の年を越えると成績が出る（そのあとも続けられる）。")
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.mute)
                    .padding(.top, 8)

                    SectionTitle(number: 2, title: "地形を選ぶ")
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(Array(candidates.enumerated()), id: \.element) { index, seed in
                            Button {
                                onSelect(seed, termYears == 0 ? nil : termYears)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    thumbnailView(for: seed)
                                        .aspectRatio(CGFloat(CityMap.width) / CGFloat(CityMap.height),
                                                    contentMode: .fit)
                                        .frame(maxWidth: .infinity)
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.rule, lineWidth: 1.5))
                                    HStack(spacing: 6) {
                                        Text(String(format: "%02d", index + 1))
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(Theme.gold)
                                        Text("この地形ではじめる")
                                            .font(.dot(12))
                                            .foregroundStyle(Theme.ink)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 170)
            }
            .background(NightBackground())
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) { AdBanner() }
            .onAppear {
                if candidates.isEmpty { reroll() }
            }
        }
        .preferredColorScheme(.dark)
    }

    /// 候補を作り直す。川や湖の出方はシードで決まるので、
    /// 毎回違う地形の組み合わせが見える。
    private func reroll() {
        candidates = (0..<6).map { _ in UInt64.random(in: 0..<UInt64.max) }
        thumbnails.removeAll(keepingCapacity: true)
        for seed in candidates {
            guard let image = MapPreview.thumbnail(seed: seed).cgImage() else { continue }
            thumbnails[seed] = Image(decorative: image, scale: 1, orientation: .up)
        }
    }

    @ViewBuilder
    private func thumbnailView(for seed: UInt64) -> some View {
        if let image = thumbnails[seed] {
            image
                .resizable()
                .interpolation(.none)
        } else {
            Rectangle().fill(Color.white.opacity(0.08))
        }
    }
}
