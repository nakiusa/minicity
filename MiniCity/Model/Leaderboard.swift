import Foundation

/// 期限つきで遊んだ街の人口を競うランキング。期限の年数ごとに1本ずつある。
/// 「期限なし」や、期限が来たあと続けた街は対象にしない。
enum Leaderboards {
    static let terms = [50, 100, 200]

    static func id(term: Int) -> String { "population.\(term)" }

    static func isRanked(term: Int?) -> Bool { term.map(terms.contains) ?? false }

    /// Game Center に出す名前。
    static func title(term: Int) -> String {
        String(localized: "\(term)年後の人口")
    }
}
