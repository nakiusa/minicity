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
    /// 借入の残高。古いセーブには入っていない。
    var debt: Int?
    /// 名前を付けて残したときの名前と日時。いま遊んでいる街のセーブには入っていない。
    var name: String?
    var savedAt: Date?

    /// 一覧に出すための要約。地形まで読まずに済ませたいところだが、
    /// 保存の数はたかだか十数件なので、まとめて読んでも間に合う。
    var residents: Int { zones.filter { $0.alive && $0.kind == .residential }.reduce(0) { $0 + $1.capacity } }
    var year: Int { 1900 + monthsElapsed / 12 }
}

enum CityStore {

    private static var url: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("city.save")
    }

    static func payload(_ sim: Simulation) -> CitySave {
        CitySave(tiles: sim.map.tiles,
                 zones: sim.map.zones,
                 funds: sim.funds,
                 taxRate: sim.taxRate,
                 monthsElapsed: sim.monthsElapsed,
                 termYears: sim.termYears,
                 debt: sim.debt)
    }

    static func save(_ sim: Simulation) {
        write(payload(sim), to: url)
    }

    private static func write(_ payload: CitySave, to url: URL) {
        do {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            try encoder.encode(payload).write(to: url, options: .atomic)
        } catch {
            // 保存に失敗しても遊べなくなるわけではないので、落とさずに続ける。
            print("保存に失敗しました: \(error)")
        }
    }

    // MARK: - 名前を付けて残す

    /// 別の街を始めても消えないように取っておく置き場。
    private static var shelf: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("saves", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// いまの街に名前を付けて残す。
    static func shelve(_ sim: Simulation, name: String) {
        var payload = payload(sim)
        payload.name = name
        payload.savedAt = Date()
        write(payload, to: shelf.appendingPathComponent(UUID().uuidString + ".save"))
    }

    /// 残してある街。新しいものから順。
    static func shelved() -> [(url: URL, save: CitySave)] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: shelf, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "save" }
            .compactMap { url in load(at: url).map { (url, $0) } }
            .sorted { ($0.save.savedAt ?? .distantPast) > ($1.save.savedAt ?? .distantPast) }
    }

    static func unshelve(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private static func load(at url: URL) -> CitySave? {
        guard let data = try? Data(contentsOf: url),
              let save = try? PropertyListDecoder().decode(CitySave.self, from: data),
              save.tiles.count == CityMap.width * CityMap.height else { return nil }
        return save
    }

    static func load() -> CitySave? { load(at: url) }

    static func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}

