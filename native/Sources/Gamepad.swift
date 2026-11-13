// Game controller input: virtual cursor, D-pad focus navigation, A/B/X/Menu buttons.
import GameController
import simd

@MainActor final class Gamepad {
    weak var scene: Scene?
    private var prev: [String: Bool] = [:]
    private var repeatT: [String: Float] = [:]

    init() { GCController.startWirelessControllerDiscovery {} }

    func update(_ dt: Float) {
        guard let s = scene, let pad = (GCController.current ?? GCController.controllers().first)?.extendedGamepad else { return }
        let lx = pad.leftThumbstick.xAxis.value, ly = pad.leftThumbstick.yAxis.value
        let stick: [(String, Bool, SIMD2<Float>)] = [("su", ly > 0.6, SIMD2(0, -1)), ("sd", ly < -0.6, SIMD2(0, 1)),
                                                      ("sl", lx < -0.6, SIMD2(-1, 0)), ("sr", lx > 0.6, SIMD2(1, 0))]
        for (n, on, d) in stick { press(n, on, dt, repeats: true) { if s.padWake() { return }; s.padFocus(d) } }
        let ry = pad.rightThumbstick.yAxis.value
        if abs(ry) > 0.2 { if s.padWake() { return }; s.scroll(ry * 1100 * dt) }
        press("a", pad.buttonA.isPressed, dt, repeats: false) { if s.padWake() { return }; s.click(s.mouse) }
        press("b", pad.buttonB.isPressed, dt, repeats: false) { if s.padWake() { return }; s.keyDown(53) }
        press("x", pad.buttonX.isPressed, dt, repeats: false) { if s.padWake() { return }; s.rightClick() }
        press("menu", pad.buttonMenu.isPressed, dt, repeats: false) { s.optionsOpen.toggle(); s.game?.paused = s.optionsOpen }
        let dirs: [(String, Bool, SIMD2<Float>)] = [("up", pad.dpad.up.isPressed, SIMD2(0, -1)), ("down", pad.dpad.down.isPressed, SIMD2(0, 1)),
                                                     ("left", pad.dpad.left.isPressed, SIMD2(-1, 0)), ("right", pad.dpad.right.isPressed, SIMD2(1, 0))]
        for (n, on, d) in dirs { press(n, on, dt, repeats: true) { if s.padWake() { return }; s.padFocus(d) } }
    }

    private func press(_ name: String, _ on: Bool, _ dt: Float, repeats: Bool, _ action: () -> Void) {
        let was = prev[name] ?? false
        prev[name] = on
        if on && !was { action(); repeatT[name] = 0.4; return }
        guard on, repeats else { return }
        repeatT[name, default: 0.4] -= dt
        if repeatT[name]! <= 0 { action(); repeatT[name] = 0.12 }
    }
}

extension Scene {
    /// First gamepad input only activates focus mode; returns true if the input was consumed.
    func padWake() -> Bool {
        if padCursor { return false }
        padCursor = true; mouse = SIMD2(-1, -1)
        return true
    }
    private var focusTargets: [R] { clicks.map { $0.0 }.filter { t in t.w < VW * 0.9 && t.h < VH * 0.9 && !padNoFocus.contains { $0 == t } } }

    private func autoTarget(_ targets: [R]) -> R? {
        if let p = padPrimary, targets.contains(where: { $0 == p }) { return p }
        let pool = targets.filter { t in !padNoAuto.contains { $0 == t } }
        return (pool.isEmpty ? targets : pool).min { simd_length($0.mid - SIMD2(VW / 2, VH / 2)) < simd_length($1.mid - SIMD2(VW / 2, VH / 2)) }
    }

    /// Moves focus to the nearest interactive element in the given direction.
    func padFocus(_ d: SIMD2<Float>) {
        let targets = focusTargets
        guard !targets.isEmpty else { return }
        guard let cur = focusedRect(targets) else { if let a = autoTarget(targets) { mouseMoved(a.mid) }; return }
        let o = cur.mid
        var best: (Float, R)?
        for t in targets where t.mid != o {
            let v = t.mid - o
            let along = v.x * d.x + v.y * d.y
            if along <= 4 { continue }
            let score = along + abs(v.x * d.y - v.y * d.x) * 2.5
            if best == nil || score < best!.0 { best = (score, t) }
        }
        if let b = best { mouseMoved(b.1.mid) }
    }

    private func focusedRect(_ targets: [R]) -> R? {
        guard mouse.x >= 0 else { return nil }
        return targets.filter { $0.contains(mouse) }.min { $0.w * $0.h < $1.w * $1.h }
    }

    func drawPadCursor() {
        guard padCursor else { return }
        let targets = focusTargets
        guard !targets.isEmpty else { return }
        guard let f = focusedRect(targets) else {
            if let a = autoTarget(targets) { mouseMoved(a.mid) }
            return
        }
        let pulse = 0.75 + 0.25 * sin(time * 5)
        r.rect(f.inset(-4), RGBA(r: 1, g: 0.8, b: 0.35, a: 0.10 * pulse))
        r.frame(f.inset(-4), RGBA(r: 1, g: 0.84, b: 0.4, a: pulse), 3)
        r.frame(f.inset(-9), RGBA(r: 1, g: 0.75, b: 0.3, a: 0.35 * pulse), 2)
    }
}
