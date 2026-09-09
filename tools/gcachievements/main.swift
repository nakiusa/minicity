import CryptoKit
import Foundation

// App Store Connect の Game Center に、実績をまとめて登録する。
//
// 実績の定義は MiniCity/Model/Achievement.swift ひとつを出どころにしてある。
// 手で34件入れると、IDの打ち間違いひとつで送信が黙って失敗する。
//
// 使いかた（鍵はこちらの手を通さず、環境変数で渡す）:
//   export ASC_KEY_ID=XXXXXXXXXX
//   export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
//   export ASC_KEY_PATH=~/Downloads/AuthKey_XXXXXXXXXX.p8
//   ./gcachievements                # 何をするかだけ出す（既定）
//   ./gcachievements --apply        # 実際に登録する

let bundleID = "com.shuyafukai.minicity"
let dryRun = !CommandLine.arguments.contains("--apply")

// --list なら、登録用の一覧を Markdown で出して終わる。鍵は要らない。
if CommandLine.arguments.contains("--list") {
    let groups: [AchievementGroup] = AchievementGroup.allCases
    var out = """
    # Game Center の実績一覧

    App Store Connect の「Game Center → 実績」に登録する。
    **実績IDはアプリ側と一致していなければ送信が黙って失敗する。** 一度公開したら変えない。

    この表は `tools/gcachievements --list` が `MiniCity/Model/Achievement.swift` から
    生成する。実績を足したら作り直す。手で書き足さない。

    一括で登録するなら、同じ道具に鍵を渡す。

    ```bash
    export ASC_KEY_ID=XXXXXXXXXX
    export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    export ASC_KEY_PATH=~/Downloads/AuthKey_XXXXXXXXXX.p8
    ./gcachievements            # 何をするかだけ出す
    ./gcachievements --apply    # 実際に登録する
    ```

    | ID | 分類 | 表示名 | 説明 | 点数 |
    | --- | --- | --- | --- | --- |

    """
    for g in groups {
        for a in Achievements.inGroup(g) {
            out += "| `\(a.id)` | \(g.rawValue) | \(a.title) | \(a.detail) | \(a.points) |\n"
        }
    }
    let sum = Achievements.all.reduce(0) { $0 + $1.points }
    out += "\n合計 \(sum) 点（\(Achievements.all.count) 件）。Game Center の上限は 1,000 点。\n"
    print(out)
    exit(0)
}

func env(_ key: String) -> String {
    guard let v = ProcessInfo.processInfo.environment[key], !v.isEmpty else {
        FileHandle.standardError.write("環境変数 \(key) がありません\n".data(using: .utf8)!)
        exit(1)
    }
    return v
}

// MARK: - 認証

/// App Store Connect API の JWT を作る。ES256 の署名は R||S の生の形で入れる。
func makeToken() -> String {
    let keyID = env("ASC_KEY_ID")
    let issuerID = env("ASC_ISSUER_ID")
    let path = (env("ASC_KEY_PATH") as NSString).expandingTildeInPath
    guard let pem = try? String(contentsOfFile: path, encoding: .utf8) else {
        FileHandle.standardError.write("鍵を読めません: \(path)\n".data(using: .utf8)!)
        exit(1)
    }
    guard let key = try? P256.Signing.PrivateKey(pemRepresentation: pem) else {
        FileHandle.standardError.write("鍵の形式が違います（.p8 を渡してください）\n".data(using: .utf8)!)
        exit(1)
    }

    func b64(_ d: Data) -> String {
        d.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    let now = Int(Date().timeIntervalSince1970)
    let header = ["alg": "ES256", "kid": keyID, "typ": "JWT"]
    let payload: [String: Any] = ["iss": issuerID, "iat": now, "exp": now + 900,
                                  "aud": "appstoreconnect-v1"]
    let h = b64(try! JSONSerialization.data(withJSONObject: header))
    let p = b64(try! JSONSerialization.data(withJSONObject: payload))
    let signing = "\(h).\(p)"
    let sig = try! key.signature(for: Data(signing.utf8))
    return "\(signing).\(b64(sig.rawRepresentation))"
}

let token = makeToken()

// MARK: - 通信

enum APIError: Error { case http(Int, String) }

func request(_ method: String, _ path: String, body: [String: Any]? = nil) throws -> [String: Any] {
    let url = URL(string: "https://api.appstoreconnect.apple.com\(path)")!
    var req = URLRequest(url: url)
    req.httpMethod = method
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }

    var result: [String: Any] = [:]
    var thrown: Error?
    let sem = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: req) { data, response, error in
        defer { sem.signal() }
        if let error { thrown = error; return }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        guard (200..<300).contains(code) else {
            thrown = APIError.http(code, text)
            return
        }
        if let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            result = json
        }
    }.resume()
    sem.wait()
    if let thrown { throw thrown }
    return result
}

func fail(_ message: String, _ error: Error) -> Never {
    if case let APIError.http(code, text) = error {
        FileHandle.standardError.write("\(message): HTTP \(code)\n\(text.prefix(600))\n".data(using: .utf8)!)
    } else {
        FileHandle.standardError.write("\(message): \(error)\n".data(using: .utf8)!)
    }
    exit(1)
}

// MARK: - 対象のアプリと Game Center の設定を引く

var appID = ""
do {
    let r = try request("GET", "/v1/apps?filter[bundleId]=\(bundleID)&limit=1")
    guard let data = r["data"] as? [[String: Any]], let first = data.first,
          let id = first["id"] as? String else {
        FileHandle.standardError.write("アプリが見つかりません: \(bundleID)\n".data(using: .utf8)!)
        exit(1)
    }
    appID = id
} catch { fail("アプリの取得に失敗", error) }

var detailID = ""
do {
    let r = try request("GET", "/v1/apps/\(appID)/gameCenterDetail")
    if let d = r["data"] as? [String: Any], let id = d["id"] as? String {
        detailID = id
    }
} catch {
    // Game Center が未設定だとここに来る。
}
if detailID.isEmpty {
    // Game Center の土台がないと実績をぶら下げられない。画面から実績を1件手で作っても
    // できるが、それだと ID を手で打つことになる。ここで作ってしまう。
    guard !dryRun else {
        print("Game Center が未設定。--apply のときに有効にしてから登録する。")
        exit(0)
    }
    do {
        let made = try request("POST", "/v1/gameCenterDetails", body: [
            "data": [
                "type": "gameCenterDetails",
                "relationships": [
                    "app": ["data": ["type": "apps", "id": appID]]
                ],
            ]
        ])
        guard let d = made["data"] as? [String: Any], let id = d["id"] as? String else {
            FileHandle.standardError.write("Game Center の有効化の応答が読めません\n".data(using: .utf8)!)
            exit(1)
        }
        detailID = id
        print("Game Center を有効にした")
    } catch { fail("Game Center の有効化に失敗", error) }
}

// MARK: - すでに登録済みのものを調べる

var existing = Set<String>()
/// 実績ID（アプリ側の名前）から、App Store Connect 側の内部IDを引く。絵を載せるときに使う。
var remoteIDs: [String: String] = [:]
do {
    var path = "/v1/gameCenterDetails/\(detailID)/gameCenterAchievements?limit=200"
    while !path.isEmpty {
        let r = try request("GET", path)
        for item in (r["data"] as? [[String: Any]]) ?? [] {
            if let attrs = item["attributes"] as? [String: Any],
               let vendor = attrs["vendorIdentifier"] as? String {
                existing.insert(vendor)
                if let id = item["id"] as? String { remoteIDs[vendor] = id }
            }
        }
        if let links = r["links"] as? [String: Any], let next = links["next"] as? String,
           let range = next.range(of: "/v1/") {
            path = String(next[range.lowerBound...])
        } else {
            path = ""
        }
    }
} catch { fail("登録済みの実績の取得に失敗", error) }

// MARK: - ストアのスクリーンショットを入れ替える

/// `--screenshots <ディレクトリ>` で、審査中でない版の 6.5 インチの絵を丸ごと差し替える。
/// 並び順はファイル名の順。手で4枚入れ替えるより速い。
if let i = CommandLine.arguments.firstIndex(of: "--screenshots"), i + 1 < CommandLine.arguments.count {
    let dir = (CommandLine.arguments[i + 1] as NSString).expandingTildeInPath
    let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [])
        .filter { $0.hasSuffix(".png") }.sorted()
    guard !files.isEmpty else {
        FileHandle.standardError.write("PNG がありません: \(dir)\n".data(using: .utf8)!)
        exit(1)
    }

    func upload(_ operation: [String: Any], _ data: Data) throws {
        guard let urlString = operation["url"] as? String, let url = URL(string: urlString),
              let method = operation["method"] as? String else { return }
        let offset = operation["offset"] as? Int ?? 0
        let length = operation["length"] as? Int ?? data.count
        var req = URLRequest(url: url)
        req.httpMethod = method
        for header in (operation["requestHeaders"] as? [[String: Any]]) ?? [] {
            if let name = header["name"] as? String, let value = header["value"] as? String {
                req.setValue(value, forHTTPHeaderField: name)
            }
        }
        req.httpBody = data.subdata(in: offset..<(offset + length))
        var thrown: Error?
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { _, response, error in
            defer { sem.signal() }
            if let error { thrown = error; return }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if !(200..<300).contains(code) { thrown = APIError.http(code, "アップロードに失敗") }
        }.resume()
        sem.wait()
        if let thrown { throw thrown }
    }

    do {
        // 編集できる版（提出準備中）を選ぶ。公開済みの版は触れない。
        let versions = try request("GET", "/v1/apps/\(appID)/appStoreVersions?limit=5&fields[appStoreVersions]=versionString,appStoreState")
        var versionID = ""
        for v in (versions["data"] as? [[String: Any]]) ?? [] {
            if let a = v["attributes"] as? [String: Any],
               (a["appStoreState"] as? String) == "PREPARE_FOR_SUBMISSION",
               let id = v["id"] as? String { versionID = id }
        }
        guard !versionID.isEmpty else {
            FileHandle.standardError.write("編集できる版がありません\n".data(using: .utf8)!)
            exit(1)
        }

        let locs = try request("GET", "/v1/appStoreVersions/\(versionID)/appStoreVersionLocalizations?limit=10")
        guard let locID = (locs["data"] as? [[String: Any]])?.first?["id"] as? String else {
            FileHandle.standardError.write("言語の欄がありません\n".data(using: .utf8)!)
            exit(1)
        }

        let sets = try request("GET", "/v1/appStoreVersionLocalizations/\(locID)/appScreenshotSets?limit=10&include=appScreenshots")
        var setID = ""
        var oldIDs: [String] = []
        for s in (sets["data"] as? [[String: Any]]) ?? [] {
            guard let a = s["attributes"] as? [String: Any],
                  (a["screenshotDisplayType"] as? String) == "APP_IPHONE_65",
                  let id = s["id"] as? String else { continue }
            setID = id
            let rel = (s["relationships"] as? [String: Any])?["appScreenshots"] as? [String: Any]
            for item in (rel?["data"] as? [[String: Any]]) ?? [] {
                if let oid = item["id"] as? String { oldIDs.append(oid) }
            }
        }
        guard !setID.isEmpty else {
            FileHandle.standardError.write("6.5インチの枠がありません\n".data(using: .utf8)!)
            exit(1)
        }

        print("入れ替え \(oldIDs.count) 枚 → \(files.count) 枚")
        for f in files { print("  \(f)") }
        guard !dryRun else { print("（下見。実際に入れ替えるには --apply）"); exit(0) }

        for id in oldIDs { _ = try request("DELETE", "/v1/appScreenshots/\(id)") }

        for name in files {
            guard let data = FileManager.default.contents(atPath: "\(dir)/\(name)") else { continue }
            let made = try request("POST", "/v1/appScreenshots", body: [
                "data": [
                    "type": "appScreenshots",
                    "attributes": ["fileName": name, "fileSize": data.count],
                    "relationships": [
                        "appScreenshotSet": ["data": ["type": "appScreenshotSets", "id": setID]]
                    ],
                ]
            ])
            guard let d = made["data"] as? [String: Any], let id = d["id"] as? String,
                  let attrs = d["attributes"] as? [String: Any],
                  let ops = attrs["uploadOperations"] as? [[String: Any]] else {
                FileHandle.standardError.write("受け口を作れません: \(name)\n".data(using: .utf8)!)
                continue
            }
            for op in ops { try upload(op, data) }
            _ = try request("PATCH", "/v1/appScreenshots/\(id)", body: [
                "data": ["type": "appScreenshots", "id": id, "attributes": ["uploaded": true]]
            ])
            print("入れた: \(name)")
        }
    } catch { fail("スクリーンショットの入れ替えに失敗", error) }
    exit(0)
}

// MARK: - 生の応答を見る

/// `--get <パス>` で応答をそのまま出す。API の形を調べるための逃げ道。
if let i = CommandLine.arguments.firstIndex(of: "--get"), i + 1 < CommandLine.arguments.count {
    do {
        let r = try request("GET", CommandLine.arguments[i + 1])
        let data = try JSONSerialization.data(withJSONObject: r, options: [.prettyPrinted, .sortedKeys])
        print(String(data: data, encoding: .utf8) ?? "")
    } catch { fail("取得に失敗", error) }
    exit(0)
}

// MARK: - 審査に載せる

/// `--submit` で、登録済みの実績を審査に回す（画面の「審査用に追加」と同じ）。
if CommandLine.arguments.contains("--submit") {
    // すでに回してあるものを調べる。二重に作ると弾かれる。
    var released = Set<String>()
    do {
        var path = "/v1/gameCenterDetails/\(detailID)/achievementReleases?limit=200&include=gameCenterAchievement"
        while !path.isEmpty {
            let r = try request("GET", path)
            for item in (r["included"] as? [[String: Any]]) ?? [] {
                if let attrs = item["attributes"] as? [String: Any],
                   let vendor = attrs["vendorIdentifier"] as? String {
                    released.insert(vendor)
                }
            }
            if let links = r["links"] as? [String: Any], let next = links["next"] as? String,
               let range = next.range(of: "/v1/") {
                path = String(next[range.lowerBound...])
            } else {
                path = ""
            }
        }
    } catch { fail("審査待ちの取得に失敗", error) }

    var sent = 0, done = 0
    for a in Achievements.all {
        if released.contains(a.id) { done += 1; continue }
        guard let achID = remoteIDs[a.id] else {
            print("見つからない: \(a.id)")
            continue
        }
        guard !dryRun else { print("回す予定: \(a.id)"); sent += 1; continue }
        do {
            _ = try request("POST", "/v1/gameCenterAchievementReleases", body: [
                "data": [
                    "type": "gameCenterAchievementReleases",
                    "relationships": [
                        "gameCenterAchievement": [
                            "data": ["type": "gameCenterAchievements", "id": achID]
                        ],
                        "gameCenterDetail": [
                            "data": ["type": "gameCenterDetails", "id": detailID]
                        ],
                    ],
                ]
            ])
            print("回した: \(a.id)")
            sent += 1
        } catch { fail("  \(a.id) を審査に回せません", error) }
    }
    print("")
    print(dryRun ? "回す予定 \(sent) 件 / すでに済み \(done) 件"
                 : "回した \(sent) 件 / すでに済んでいた \(done) 件")
    exit(0)
}

// MARK: - 生の削除

/// `--delete <パス>` で消す。中途半端に残った資産を片付けるための逃げ道。
if let i = CommandLine.arguments.firstIndex(of: "--delete"), i + 1 < CommandLine.arguments.count {
    do {
        _ = try request("DELETE", CommandLine.arguments[i + 1])
        print("消した: \(CommandLine.arguments[i + 1])")
    } catch { fail("削除に失敗", error) }
    exit(0)
}

// MARK: - 生の書き込み

/// `--send <メソッド> <パス> <JSONのファイル>` で書き込む。API の形を試すための逃げ道。
if let i = CommandLine.arguments.firstIndex(of: "--send"), i + 3 < CommandLine.arguments.count {
    let method = CommandLine.arguments[i + 1]
    let path = CommandLine.arguments[i + 2]
    let file = (CommandLine.arguments[i + 3] as NSString).expandingTildeInPath
    guard let data = FileManager.default.contents(atPath: file),
          let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        FileHandle.standardError.write("JSON を読めません: \(file)\n".data(using: .utf8)!)
        exit(1)
    }
    do {
        let r = try request(method, path, body: body)
        let out = try JSONSerialization.data(withJSONObject: r, options: [.prettyPrinted, .sortedKeys])
        print(String(data: out, encoding: .utf8) ?? "")
    } catch { fail("送信に失敗", error) }
    exit(0)
}

// MARK: - 絵を載せる

/// `--images <ディレクトリ>` で、実績IDと同じ名前の PNG を Game Center に載せる。
if let i = CommandLine.arguments.firstIndex(of: "--images") {
    guard i + 1 < CommandLine.arguments.count else {
        FileHandle.standardError.write("--images のあとに PNG の置き場所を渡してください\n".data(using: .utf8)!)
        exit(1)
    }
    let dir = (CommandLine.arguments[i + 1] as NSString).expandingTildeInPath

    /// 受け取った URL へそのまま本体を送る。App Store Connect の外（S3）宛てなので、
    /// JSON を期待する `request` とは別に用意する。
    func upload(_ operation: [String: Any], _ data: Data) throws {
        guard let urlString = operation["url"] as? String, let url = URL(string: urlString),
              let method = operation["method"] as? String else { return }
        let offset = operation["offset"] as? Int ?? 0
        let length = operation["length"] as? Int ?? data.count
        var req = URLRequest(url: url)
        req.httpMethod = method
        for header in (operation["requestHeaders"] as? [[String: Any]]) ?? [] {
            if let name = header["name"] as? String, let value = header["value"] as? String {
                req.setValue(value, forHTTPHeaderField: name)
            }
        }
        req.httpBody = data.subdata(in: offset..<(offset + length))

        var thrown: Error?
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { _, response, error in
            defer { sem.signal() }
            if let error { thrown = error; return }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if !(200..<300).contains(code) { thrown = APIError.http(code, "アップロードに失敗") }
        }.resume()
        sem.wait()
        if let thrown { throw thrown }
    }

    var loaded = 0, already = 0
    for a in Achievements.all {
        guard let achID = remoteIDs[a.id] else {
            print("見つからない（先に登録が要る）: \(a.id)")
            continue
        }
        let path = "\(dir)/\(a.id).png"
        guard let data = FileManager.default.contents(atPath: path) else {
            print("絵がない: \(path)")
            continue
        }

        do {
            // 日本語の欄に載せる。欄そのものは実績を作ったときに作ってある。
            let locs = try request("GET", "/v1/gameCenterAchievements/\(achID)/localizations?limit=50")
            var localizationID = ""
            for item in (locs["data"] as? [[String: Any]]) ?? [] {
                if let attrs = item["attributes"] as? [String: Any],
                   (attrs["locale"] as? String) == "ja", let id = item["id"] as? String {
                    localizationID = id
                }
            }
            guard !localizationID.isEmpty else {
                print("日本語の欄がない: \(a.id)")
                continue
            }

            let current = try request("GET", "/v1/gameCenterAchievementLocalizations/\(localizationID)/gameCenterAchievementImage")
            if let d = current["data"] as? [String: Any], let existingID = d["id"] as? String {
                let attrs = d["attributes"] as? [String: Any]
                let state = (attrs?["assetDeliveryState"] as? [String: Any])?["state"] as? String
                if state == "COMPLETE" {
                    already += 1
                    continue
                }
                // 送りかけで止まった絵は、審査に出す邪魔になる。捨ててから入れ直す。
                print("送りかけを捨てる: \(a.id)（\(state ?? "不明")）")
                if !dryRun { _ = try request("DELETE", "/v1/gameCenterAchievementImages/\(existingID)") }
            }

            guard !dryRun else {
                print("載せる予定: \(a.id)")
                loaded += 1
                continue
            }

            let made = try request("POST", "/v1/gameCenterAchievementImages", body: [
                "data": [
                    "type": "gameCenterAchievementImages",
                    "attributes": ["fileName": "\(a.id).png", "fileSize": data.count],
                    "relationships": [
                        "gameCenterAchievementLocalization": [
                            "data": ["type": "gameCenterAchievementLocalizations", "id": localizationID]
                        ]
                    ],
                ]
            ])
            guard let d = made["data"] as? [String: Any],
                  let imageID = d["id"] as? String,
                  let attrs = d["attributes"] as? [String: Any],
                  let operations = attrs["uploadOperations"] as? [[String: Any]] else {
                print("受け口を作れない: \(a.id)")
                continue
            }
            for operation in operations { try upload(operation, data) }

            // 送り終えたことを伝える。ここまでやらないと絵は反映されない。
            _ = try request("PATCH", "/v1/gameCenterAchievementImages/\(imageID)", body: [
                "data": [
                    "type": "gameCenterAchievementImages",
                    "id": imageID,
                    "attributes": ["uploaded": true],
                ]
            ])
            print("載せた: \(a.id)")
            loaded += 1
        } catch { fail("  \(a.id) の絵で失敗", error) }
    }

    print("")
    print(dryRun ? "載せる予定 \(loaded) 件 / すでにある \(already) 件"
                 : "載せた \(loaded) 件 / すでにあった \(already) 件")
    exit(0)
}

// MARK: - 足りないものを作る

let total = Achievements.all.reduce(0) { $0 + $1.points }
print("アプリ \(bundleID) / 実績 \(Achievements.all.count) 件 / 合計 \(total) 点")
if total > 1000 {
    FileHandle.standardError.write("合計が 1,000 点を超えています。配点を見直してください。\n".data(using: .utf8)!)
    exit(1)
}
print("登録済み \(existing.count) 件")
if dryRun { print("（下見。実際に登録するには --apply を付ける）") }
print("")

var created = 0, skipped = 0
for a in Achievements.all {
    if existing.contains(a.id) {
        skipped += 1
        continue
    }
    print("追加: \(a.id)  \(a.title)（\(a.points)点）")
    guard !dryRun else { created += 1; continue }

    do {
        let made = try request("POST", "/v1/gameCenterAchievements", body: [
            "data": [
                "type": "gameCenterAchievements",
                "attributes": [
                    "referenceName": a.title,
                    "vendorIdentifier": a.id,
                    "points": a.points,
                    "showBeforeEarned": true,
                    "repeatable": false,
                ],
                "relationships": [
                    "gameCenterDetail": [
                        "data": ["type": "gameCenterDetails", "id": detailID]
                    ]
                ],
            ]
        ])
        guard let d = made["data"] as? [String: Any], let newID = d["id"] as? String else {
            FileHandle.standardError.write("  作成の応答が読めません\n".data(using: .utf8)!)
            continue
        }
        _ = try request("POST", "/v1/gameCenterAchievementLocalizations", body: [
            "data": [
                "type": "gameCenterAchievementLocalizations",
                "attributes": [
                    "locale": "ja",
                    "name": a.title,
                    "beforeEarnedDescription": a.detail,
                    "afterEarnedDescription": a.detail,
                ],
                "relationships": [
                    "gameCenterAchievement": [
                        "data": ["type": "gameCenterAchievements", "id": newID]
                    ]
                ],
            ]
        ])
        created += 1
    } catch { fail("  \(a.id) の登録に失敗", error) }
}

print("")
print(dryRun ? "追加する予定 \(created) 件 / すでにある \(skipped) 件"
             : "追加した \(created) 件 / すでにあった \(skipped) 件")
