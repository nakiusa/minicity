import SwiftUI

/// 新しい都市を始める前に、候補の地形をいくつか見てから選べる画面。
/// `GameState` には触れず、選んだ種（シード）を `onSelect` で返すだけにしてある。
struct MapSelectView: View {
    let onSelect: (UInt64) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var candidates: [UInt64] = []
    @State private var thumbnails: [UInt64: Image] = [:]

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(candidates, id: \.self) { seed in
                        Button {
                            onSelect(seed)
                            dismiss()
                        } label: {
                            VStack(spacing: 6) {
                                thumbnailView(for: seed)
                                    .aspectRatio(CGFloat(CityMap.width) / CGFloat(CityMap.height),
                                                contentMode: .fit)
                                    .frame(maxWidth: .infinity)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(Color.white.opacity(0.25))
                                    )
                                Text("この地形ではじめる")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .navigationTitle("マップを選ぶ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        reroll()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
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
