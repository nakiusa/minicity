import Foundation

extension Simulation {

    /// 公害・土地価値・犯罪と、警察と消防の効き具合をまとめて計算する。
    func updateOverlays() {
        updateServiceCoverage()
        updatePollution()
        updateLandValue()
        updateCrime()
    }

    // MARK: - 警察と消防

    private func updateServiceCoverage() {
        policeCover.clear()
        fireCover.clear()

        let radius = 5.0
        for z in map.zones where z.alive && z.powered {
            guard z.kind == .police || z.kind == .fire else { continue }
            let cx = (Int(z.ox) + 1) / CoarseMap.scale
            let cy = (Int(z.oy) + 1) / CoarseMap.scale
            let r = Int(radius)
            for dy in -r...r {
                for dx in -r...r {
                    let d = (Double(dx * dx + dy * dy)).squareRoot()
                    guard d <= radius else { continue }
                    let strength = Int(120 * (1 - d / (radius + 0.5)))
                    if z.kind == .police {
                        policeCover[cx + dx, cy + dy] += strength
                    } else {
                        fireCover[cx + dx, cy + dy] += strength
                    }
                }
            }
        }
        policeCover.clamp(0, 255)
        fireCover.clamp(0, 255)
    }

    // MARK: - 公害

    private func updatePollution() {
        pollution.clear()

        for z in map.zones where z.alive {
            switch z.kind {
            case .industrial where z.level > 0:
                // 段が増えたぶん1段あたりの煙は控えめにする。
                // 小さな工業地でも街全体が飽和すると、住宅がどこにも建たなくなる。
                emit(&pollution, tileX: Int(z.ox) + 1, tileY: Int(z.oy) + 1,
                     strength: 18 + Int(z.level) * 20,
                     radius: 2 + Int(z.level) / 2)
            case .coalPlant:
                emit(&pollution, tileX: Int(z.ox) + 1, tileY: Int(z.oy) + 1,
                     strength: z.powered ? 140 : 20, radius: 4)
            default:
                break
            }
        }

        // 車も煙を出す。
        for cy in 0..<CoarseMap.height {
            for cx in 0..<CoarseMap.width {
                pollution[cx, cy] += trafficMap[cx, cy] / 3
            }
        }

        // 公園は緑地として周囲の公害を吸収する。都市に置ける、数少ない
        // 「公害を直接減らす」手段はこれだけにしてある。
        for y in 0..<CityMap.height {
            for x in 0..<CityMap.width where map.tile(x, y).structure == .park {
                emit(&pollution, tileX: x, tileY: y, strength: -26, radius: 2)
            }
        }

        pollution.blur()
        pollution.clamp(0, 255)
    }

    /// 発生源から距離に応じて弱まる形で値を撒く。煙も警察の目も、こう広がる。
    private func emit(_ map: inout CoarseMap, tileX: Int, tileY: Int, strength: Int, radius: Int) {
        let cx = tileX / CoarseMap.scale, cy = tileY / CoarseMap.scale
        let r = Double(radius)
        for dy in -radius...radius {
            for dx in -radius...radius {
                let d = Double(dx * dx + dy * dy).squareRoot()
                guard d <= r else { continue }
                map[cx + dx, cy + dy] += Int(Double(strength) * (1 - d / (r + 0.5)))
            }
        }
    }

    // MARK: - 土地価値

    private func updateLandValue() {
        // 水辺と緑は、それだけで土地の値打ちになる。公園は植えた森と同じ扱いだが、
        // 自分で選んで置いた場所なので、野放しの森より少しだけ効かせる。
        var amenity = CoarseMap()
        let s = CoarseMap.scale
        for cy in 0..<CoarseMap.height {
            for cx in 0..<CoarseMap.width {
                var water = 0, forest = 0, park = 0
                for dy in 0..<s {
                    for dx in 0..<s {
                        let t = map.tile(cx * s + dx, cy * s + dy)
                        switch t.terrain {
                        case .water: water += 1
                        case .forest: forest += 1
                        case .dirt: break
                        }
                        if t.structure == .park { park += 1 }
                    }
                }
                amenity[cx, cy] = water * 5 + forest * 4 + park * 5
            }
        }
        amenity.blur()

        let maxDistance = 45.0
        for cy in 0..<CoarseMap.height {
            for cx in 0..<CoarseMap.width {
                let tx = Double(cx * s + s / 2)
                let ty = Double(cy * s + s / 2)
                let d = ((tx - centerX) * (tx - centerX) + (ty - centerY) * (ty - centerY)).squareRoot()
                let centerBonus = max(0.0, 1.0 - d / maxDistance) * 110.0

                // 栄えた場所ほど土地は高くなる。この折り返しがないと、
                // どの区画も最初のレベルで頭打ちになって都市が動かなくなる。
                var v = 35.0 + centerBonus + Double(amenity[cx, cy])
                v += min(80.0, Double(density[cx, cy]) / 4.0)
                v -= Double(pollution[cx, cy]) / 3.0
                v -= Double(crime[cx, cy]) / 4.0
                v += Double(fireCover[cx, cy]) / 8.0
                // 渋滞している街区は住みたくない。
                v -= Double(trafficMap[cx, cy]) / 8.0

                landValue[cx, cy] = Int(v)
            }
        }
        // ここでならすと山が削れて高層まで届かなくなるので、ならさない。
        landValue.clamp(0, 255)
    }

    // MARK: - 犯罪

    private func updateCrime() {
        for cy in 0..<CoarseMap.height {
            for cx in 0..<CoarseMap.width {
                var c = density[cx, cy] / 3
                c += max(0, 120 - landValue[cx, cy]) / 2
                c -= policeCover[cx, cy]
                crime[cx, cy] = max(0, c)
            }
        }
        crime.blur()
        crime.clamp(0, 255)
    }
}
