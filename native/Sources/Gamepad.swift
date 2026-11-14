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
        guard let s = scene, let pad = (GCController.current ?? GCController.controllers().first)?.extendedGamepad else { return }
        let leftX = pad.leftThumbstick.xAxis.value, ly = pad.leftThumbstick.yAxis.value
        let stick: [(String, Bool, SIMD2<Float>)] = [("su", ly > 0.6, SIMD2(0, -1)), ("sd", ly < -0.6, SIMD2(0, 1)),
                                                      ("sl", leftX < -0.6, SIMD2(-1, 0)), ("sr", leftX > 0.6, SIMD2(1, 0))]
        for (n, on, d) in stick { press(n, on, dt, repeats: true) { if s.padWake() { return }; s.padFocus(d) } }
        let rightY = pad.rightThumbstick.yAxis.value
        if abs(rightY) > 0.2 { if s.padWake() { return }; s.scroll(rightY * 1100 * dt) }
        press("a", pad.buttonA.isPressed, dt, repeats: false) { if s.padWake() { return }; s.click(s.mouse) }
        press("b", pad.buttonB.isPressed, dt, repeats: false) { if s.padWake() { return }; s.keyDown(53) }
        press("x", pad.buttonX.isPressed, dt, repeats: false) { if s.padWake() { return }; s.rightClick() }
        press("menu", pad.buttonMenu.isPressed, dt, repeats: false) { s.optionsOpen.toggle(); s.game?.paused = s.optionsOpen }
        let dirs: [(String, Bool, SIMD2<Float>)] = [("up", pad.dpad.up.isPressed, SIMD2(0, -1)), ("down", pad.dpad.down.isPressed, SIMD2(0, 1)),
                                                     ("left", pad.dpad.left.isPressed, SIMD2(-1, 0)), ("right", pad.dpad.right.isPressed, SIMD2(1, 0))]
        for (n, on, d) in dirs { press(n, on, dt, repeats: true) { if s.padWake() { return }; s.padFocus(d) } }
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
    var focusTargets: [R] { clicks.map { $0.0 }.filter { t in t.w < virtualWidth * 0.9 && t.h < virtualHeight * 0.9 && !padNoFocus.contains { $0 == t } } }

    /// Element focused automatically: the screen's primary element, otherwise the one nearest the centre.
    func autoTarget(_ targets: [R]) -> R? {
        if let primary = padPrimary, targets.contains(where: { $0 == primary }) { return primary }
        let pool = targets.filter { t in !padNoAuto.contains { $0 == t } }
        return (pool.isEmpty ? targets : pool).min { simd_length($0.mid - SIMD2(virtualWidth / 2, virtualHeight / 2)) < simd_length($1.mid - SIMD2(virtualWidth / 2, virtualHeight / 2)) }
    }

    /// Moves focus to the nearest interactive element in the given direction.
    func padFocus(_ d: SIMD2<Float>) {
        let targets = focusTargets
        guard !targets.isEmpty else { return }
        guard let current = focusedRect(targets) else { if let a = autoTarget(targets) { mouseMoved(a.mid) }; return }
        let origin = current.mid
        var best: (Float, R)?
        for target in targets where target.mid != origin {
            let offset = target.mid - origin
            let along = offset.x * d.x + offset.y * d.y
            if along <= 4 { continue }
            let score = along + abs(offset.x * d.y - offset.y * d.x) * 2.5
            if best == nil || score < best!.0 { best = (score, target) }
        }
        if let b = best { mouseMoved(b.1.mid) }
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
