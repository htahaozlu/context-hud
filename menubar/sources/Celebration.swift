import AppKit
import Foundation
import QuartzCore

/// Lightweight reset-window celebration. Emits a brief burst of colored
/// particles inside the given view, respecting reduce-motion. Tracks
/// most-recent reset times in UserDefaults so a single reset only celebrates
/// once across popover open/close cycles.
enum Celebration {
    private static let kLastSession5h = "celebration.lastSession5h"
    private static let kLastWeek7d = "celebration.lastWeek7d"

    /// Returns true and records the new reset date if `resetsAt` is in the
    /// near past (within the last 10 min) AND newer than the last recorded
    /// reset for this key. Caller uses it to gate a single celebration per
    /// window rollover.
    static func consumeReset(_ resetsAt: Date?, key: String) -> Bool {
        guard let resetsAt else { return false }
        let now = Date()
        let elapsed = now.timeIntervalSince(resetsAt)
        // Reset must be in the recent past, not the future.
        guard elapsed >= 0, elapsed < 600 else { return false }
        let defaultsKey = "celebration." + key
        let last = UserDefaults.standard.double(forKey: defaultsKey)
        if last > 0, abs(resetsAt.timeIntervalSince1970 - last) < 60 { return false }
        UserDefaults.standard.set(resetsAt.timeIntervalSince1970, forKey: defaultsKey)
        return true
    }

    static func session5hKey() -> String { kLastSession5h }
    static func week7dKey() -> String { kLastWeek7d }

    /// Fires a short particle burst in `host`. No-op if reduce-motion is on
    /// or celebrations are disabled by user.
    static func burst(in host: NSView) {
        guard DisplayPrefs.confetti, !MotionPrefs.reduceMotion else { return }
        host.wantsLayer = true
        guard let layer = host.layer else { return }
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = CGPoint(x: layer.bounds.midX, y: layer.bounds.maxY - 4)
        emitter.emitterShape = .line
        emitter.emitterSize = CGSize(width: max(40, layer.bounds.width * 0.8), height: 1)
        emitter.emitterCells = makeCells()
        emitter.birthRate = 1
        emitter.beginTime = CACurrentMediaTime()
        layer.addSublayer(emitter)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            emitter.birthRate = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            emitter.removeFromSuperlayer()
        }
    }

    private static func makeCells() -> [CAEmitterCell] {
        let palette: [NSColor] = [
            ThemeStore.current.accent,
            ThemeStore.current.pctMid,
            .systemYellow,
            .systemPink,
            .systemTeal,
        ]
        return palette.map { color in
            let cell = CAEmitterCell()
            cell.birthRate = 14
            cell.lifetime = 1.6
            cell.lifetimeRange = 0.4
            cell.velocity = 90
            cell.velocityRange = 40
            cell.emissionLongitude = .pi / 2
            cell.emissionRange = .pi / 5
            cell.yAcceleration = 110
            cell.spin = 3
            cell.spinRange = 2
            cell.scale = 0.04
            cell.scaleRange = 0.02
            cell.color = color.cgColor
            cell.contents = particleImage().cgImage(forProposedRect: nil, context: nil, hints: nil)
            return cell
        }
    }

    private static func particleImage() -> NSImage {
        let size = NSSize(width: 6, height: 6)
        let img = NSImage(size: size)
        img.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(origin: .zero, size: size)).fill()
        img.unlockFocus()
        return img
    }
}
