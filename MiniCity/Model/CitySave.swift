import Foundation

/// セーブデータ。地形も含めて丸ごと持つので、続きから同じ都市を再開できる。
struct CitySave: Codable {
    var version: Int = 1
    var tiles: [Tile]
    var zones: [Zone]
    var funds: Int
    var taxRate: Int
    var monthsElapsed: Int
    /// 遊ぶと決めた年数。古いセーブには入っていないので、その場合は期限なしになる。
    var termYears: Int?
}

enum CityStore {

    private static var url: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("city.save")
    }

    static func save(_ sim: Simulation) {
        let payload = CitySave(tiles: sim.map.tiles,
                               zones: sim.map.zones,
                               funds: sim.funds,
                               taxRate: sim.taxRate,
                               monthsElapsed: sim.monthsElapsed,
                               termYears: sim.termYears)
        do {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            try encoder.encode(payload).write(to: url, options: .atomic)
        } catch {
            // 保存に失敗しても遊べなくなるわけではないので、落とさずに続ける。
            print("保存に失敗しました: \(error)")
        }
    }

    static func load() -> CitySave? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let save = try? PropertyListDecoder().decode(CitySave.self, from: data) else { return nil }
        guard save.tiles.count == CityMap.width * CityMap.height else { return nil }
        return save
    }

    static func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}

