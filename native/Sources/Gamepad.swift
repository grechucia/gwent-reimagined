// Game controller input: focus-based navigation (no cursor) with D-pad / left stick and A/B/X/Menu buttons.
import GameController
import simd

/// Polls the active game controller every frame and turns its input into UI actions.
@MainActor final class Gamepad {
    weak var scene: Scene?
    var prev: [String: Bool] = [:]
    var repeatT: [String: Float] = [:]

    init() { GCController.startWirelessControllerDiscovery {} }

    /// Reads the controller state and moves focus or triggers actions.
    func update(_ dt: Float) {
        guard let activeScene = scene, let controller = (GCController.current ?? GCController.controllers().first)?.extendedGamepad else { return }
        let leftX = controller.leftThumbstick.xAxis.value, ly = controller.leftThumbstick.yAxis.value
        let stick: [(String, Bool, SIMD2<Float>)] = [("su", ly > 0.6, SIMD2(0, -1)), ("sd", ly < -0.6, SIMD2(0, 1)),
                                                      ("sl", leftX < -0.6, SIMD2(-1, 0)), ("sr", leftX > 0.6, SIMD2(1, 0))]
        for (n, on, d) in stick { press(n, on, dt, repeats: true) { if activeScene.padWake() { return }; activeScene.padFocus(d) } }
        let rightY = controller.rightThumbstick.yAxis.value
        if abs(rightY) > 0.2 { if activeScene.padWake() { return }; activeScene.scroll(rightY * 1100 * dt) }
        press("a", controller.buttonA.isPressed, dt, repeats: false) { if activeScene.padWake() { return }; activeScene.click(activeScene.mouse) }
        press("b", controller.buttonB.isPressed, dt, repeats: false) { if activeScene.padWake() { return }; activeScene.keyDown(53) }
        press("x", controller.buttonX.isPressed, dt, repeats: false) { if activeScene.padWake() { return }; activeScene.rightClick() }
        press("menu", controller.buttonMenu.isPressed, dt, repeats: false) { activeScene.optionsOpen.toggle(); activeScene.game?.paused = activeScene.optionsOpen }
        let dirs: [(String, Bool, SIMD2<Float>)] = [("up", controller.dpad.up.isPressed, SIMD2(0, -1)), ("down", controller.dpad.down.isPressed, SIMD2(0, 1)),
                                                     ("left", controller.dpad.left.isPressed, SIMD2(-1, 0)), ("right", controller.dpad.right.isPressed, SIMD2(1, 0))]
        for (n, on, d) in dirs { press(n, on, dt, repeats: true) { if activeScene.padWake() { return }; activeScene.padFocus(d) } }
    }

    /// Edge-detects a button; held directions repeat after 0.4 s, then every 0.12 s.
    func press(_ name: String, _ on: Bool, _ dt: Float, repeats: Bool, _ action: () -> Void) {
        let wasPressed = prev[name] ?? false
        prev[name] = on
        if on && !wasPressed { action(); repeatT[name] = 0.4; return }
        guard on, repeats else { return }
        repeatT[name, default: 0.4] -= dt
        if repeatT[name]! <= 0 { action(); repeatT[name] = 0.12 }
    }
}

/// Focus navigation helpers for the scene.
extension Scene {
    /// First gamepad input only activates focus mode; returns true if the input was consumed.
    func padWake() -> Bool {
        if padCursor { return false }
        padCursor = true; mouse = SIMD2(-1, -1)
        return true
    }
    var focusTargets: [R] { clicks.map { $0.0 }.filter { target in target.w < virtualWidth * 0.9 && target.h < virtualHeight * 0.9 && !padNoFocus.contains { $0 == target } } }

    /// Element focused automatically: the screen's primary element, otherwise the one nearest the centre.
    func autoTarget(_ targets: [R]) -> R? {
        if let primary = padPrimary, targets.contains(where: { $0 == primary }) { return primary }
        let pool = targets.filter { target in !padNoAuto.contains { $0 == target } }
        return (pool.isEmpty ? targets : pool).min { simd_length($0.mid - SIMD2(virtualWidth / 2, virtualHeight / 2)) < simd_length($1.mid - SIMD2(virtualWidth / 2, virtualHeight / 2)) }
    }

    /// Moves focus to the nearest interactive element in the given direction.
    func padFocus(_ direction: SIMD2<Float>) {
        let targets = focusTargets
        guard !targets.isEmpty else { return }
        guard let current = focusedRect(targets) else { if let fallback = autoTarget(targets) { mouseMoved(fallback.mid) }; return }
        let origin = current.mid
        var best: (Float, R)?
        for target in targets where target.mid != origin {
            let offset = target.mid - origin
            let along = offset.x * direction.x + offset.y * direction.y
            if along <= 4 { continue }
            let score = along + abs(offset.x * direction.y - offset.y * direction.x) * 2.5
            if best == nil || score < best!.0 { best = (score, target) }
        }
        if let nearest = best { mouseMoved(nearest.1.mid) }
    }

    /// The interactive element under the focus point.
    func focusedRect(_ targets: [R]) -> R? {
        guard mouse.x >= 0 else { return nil }
        return targets.filter { $0.contains(mouse) }.min { $0.w * $0.h < $1.w * $1.h }
    }

    /// Draws the highlight around the focused element.
    func drawPadCursor() {
        guard padCursor else { return }
        let targets = focusTargets
        guard !targets.isEmpty else { return }
        guard let focused = focusedRect(targets) else {
            if let target = autoTarget(targets) { mouseMoved(target.mid) }
            return
        }
        let pulse = 0.75 + 0.25 * sin(time * 5)
        renderer.rect(focused.inset(-4), RGBA(r: 1, g: 0.8, b: 0.35, a: 0.10 * pulse))
        renderer.frame(focused.inset(-4), RGBA(r: 1, g: 0.84, b: 0.4, a: pulse), 3)
        renderer.frame(focused.inset(-9), RGBA(r: 1, g: 0.75, b: 0.3, a: 0.35 * pulse), 2)
    }
}
