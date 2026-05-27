import SwiftUI
import SpriteKit
import AppKit

struct LaunchSequenceView: View {
    @Environment(AppState.self) private var appState

    @State private var scene = LaunchSequenceScene()
    @State private var sceneReady = false   // defer SpriteView until size is known
    @State private var keyMonitor: Any?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                if sceneReady {
                    SpriteView(scene: scene, preferredFramesPerSecond: 60)
                        .frame(width: geo.size.width, height: geo.size.height)

                    GameHUDView(state: scene.gameState)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onAppear {
                // Set scene size and anchor BEFORE SpriteView ever renders.
                scene.size = geo.size
                scene.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                scene.scaleMode = .resizeFill
                scene.backgroundColor = .black
                scene.onExit = { appState.route = .newChat }
                sceneReady = true
                installKeyMonitor()
            }
            .onDisappear {
                removeKeyMonitor()
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
    }

    // MARK: - Keyboard

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak scene] event in
            guard let scene else { return event }
            let down = event.type == .keyDown
            switch event.keyCode {
            case 123: scene.input.leftHeld  = down
            case 124: scene.input.rightHeld = down
            case 49:  if down { scene.fireIfReady() }
            case 53:  if down { scene.requestExit() }
            default: break
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) }
        keyMonitor = nil
    }
}
