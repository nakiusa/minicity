import Foundation

/// マップ選択のための下見。実際に置くタイル画像は使わず、
/// 地形の種類だけを色分けした縮小画像にする（衛星写真のような見た目）。
enum MapPreview {
    static func thumbnail(seed: UInt64) -> PixelCanvas {
        let map = CityMap()
        TerrainGenerator.generate(into: map, seed: seed)

        var canvas = PixelCanvas(width: CityMap.width, height: CityMap.height)
        for y in 0..<CityMap.height {
            for x in 0..<CityMap.width {
                let color: RGBA
                switch map.tile(x, y).terrain {
                case .water: color = Palette.water
                case .forest: color = Palette.forest
                case .dirt: color = Palette.land
                }
                canvas.set(x, y, color)
            }
        }
        return canvas
    }
}
