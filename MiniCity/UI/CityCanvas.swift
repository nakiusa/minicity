import SpriteKit
import SwiftUI

/// SpriteKit のマップを SwiftUI に載せる。
/// 1本指はタイルを塗る操作、2本指はカメラ操作に割り当ててある。
struct CityCanvas: UIViewRepresentable {

    @ObservedObject var game: GameState

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SKView {
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        view.ignoresSiblingOrder = true
        view.isMultipleTouchEnabled = true
        view.preferredFramesPerSecond = 60

        let scene = CityScene(size: view.bounds.size)
        scene.sim = game.sim
        scene.footprint = game.tool.footprint
        scene.dragMovesCamera = game.tool.movesCamera
        scene.previewsDrag = game.tool.isDraggable
        scene.overlayMode = game.overlay
        scene.onPaint = { [weak game] x, y in
            game?.paint(x: x, y: y)
        }
        scene.onZoomChanged = { [weak game] scale in
            game?.syncZoom(scale: scale)
        }
        scene.onPreviewChanged = { [weak game] count in
            game?.pendingTiles = count
        }
        view.presentScene(scene)
        game.scene = scene
        context.coordinator.scene = scene

        let pinch = UIPinchGestureRecognizer(target: context.coordinator,
                                             action: #selector(Coordinator.handlePinch(_:)))
        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handlePan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        pinch.delegate = context.coordinator
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pinch)
        view.addGestureRecognizer(pan)

        return view
    }

    func updateUIView(_ uiView: SKView, context: Context) {}

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var scene: CityScene?

        @objc func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            guard recognizer.state == .changed else {
                recognizer.scale = 1
                return
            }
            scene?.zoom(by: recognizer.scale)
            recognizer.scale = 1
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard let view = recognizer.view else { return }
            let translation = recognizer.translation(in: view)
            scene?.pan(by: translation)
            recognizer.setTranslation(.zero, in: view)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
