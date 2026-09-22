import AVFoundation
import UIKit

/// 効果音と振動。音は素材を持たず、起動時に短い波形をこしらえて鳴らす。
/// 「置いた」「育った」「区切り」の3つだけ。数を増やすより、この3つがいつも同じ音で鳴るほうが手触りになる。
final class Feedback {
    static let shared = Feedback()

    /// 設定で切れる。既定はオン。
    var soundOn: Bool {
        get { UserDefaults.standard.object(forKey: "soundOn") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "soundOn") }
    }

    /// 振動も同じく切れる。既定はオン。
    var hapticsOn: Bool {
        get { UserDefaults.standard.object(forKey: "hapticsOn") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "hapticsOn") }
    }

    private var players: [String: AVAudioPlayer] = [:]
    private let tap = UIImpactFeedbackGenerator(style: .light)
    private let thud = UINotificationFeedbackGenerator()
    private var lastGrow = Date.distantPast

    private init() {
        // ほかのアプリの音楽を止めない。
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        players["place"] = player(Feedback.tone([(880, 0.03, 0.5), (660, 0.04, 0.35)]))
        players["grow"] = player(Feedback.tone([(523, 0.05, 0.4), (659, 0.05, 0.4), (784, 0.09, 0.45)]))
        players["result"] = player(Feedback.tone([(523, 0.12, 0.4), (659, 0.12, 0.4), (784, 0.12, 0.4), (1046, 0.35, 0.5)]))
        players["deny"] = player(Feedback.tone([(220, 0.08, 0.35)]))
    }

    /// 何かを置いた。
    func placed() {
        if hapticsOn { tap.impactOccurred() }
        play("place")
    }

    /// 置けなかった、金が足りない。
    func denied() {
        if hapticsOn { thud.notificationOccurred(.warning) }
        play("deny")
    }

    /// 区画が育った。毎月鳴ると耳に残るので、2秒に1回まで。
    func grew() {
        guard Date().timeIntervalSince(lastGrow) > 2 else { return }
        lastGrow = Date()
        play("grow")
    }

    /// 成績表が出た。
    func finished() {
        if hapticsOn { thud.notificationOccurred(.success) }
        play("result")
    }

    private func play(_ name: String) {
        guard soundOn, let p = players[name] else { return }
        p.currentTime = 0
        p.play()
    }

    private func player(_ data: Data) -> AVAudioPlayer? {
        let p = try? AVAudioPlayer(data: data)
        p?.prepareToPlay()
        return p
    }

    /// 音程（Hz）、長さ（秒）、音量の並びを、頭とお尻をなだらかにした矩形波っぽい音にして WAV に包む。
    /// 矩形波にサイン波を少し混ぜると、ドット絵に合う古いゲーム機の音になる。
    private static func tone(_ notes: [(Double, Double, Double)]) -> Data {
        let rate = 22_050.0
        var samples: [Int16] = []
        for (freq, length, volume) in notes {
            let n = Int(rate * length)
            for i in 0..<n {
                let t = Double(i) / rate
                let env = min(1, Double(i) / (rate * 0.005)) * min(1, Double(n - i) / (rate * 0.02))
                let square: Double = sin(2 * .pi * freq * t) >= 0 ? 1 : -1
                let sine = sin(2 * .pi * freq * t)
                let v = (square * 0.4 + sine * 0.6) * env * volume
                samples.append(Int16(max(-1, min(1, v)) * 32_000))
            }
        }
        var data = Data()
        func put32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func put16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        let bytes = samples.count * 2
        data.append(contentsOf: Array("RIFF".utf8)); put32(UInt32(36 + bytes))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); put32(16); put16(1); put16(1)
        put32(UInt32(rate)); put32(UInt32(rate) * 2); put16(2); put16(16)
        data.append(contentsOf: Array("data".utf8)); put32(UInt32(bytes))
        samples.withUnsafeBufferPointer { data.append(Data(buffer: $0)) }
        return data
    }
}
