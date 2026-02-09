import AppKit
import QuartzCore

final class Animator {

    private static let breathingKey = "breathing"
    private static let stateAnimationKey = "stateAnimation"
    private static let shakeKey = "shake"
    private static let flashKey = "flash"

    // MARK: - Breathing

    func startBreathing(on layer: CALayer, duration: CFTimeInterval) {
        let anim = CABasicAnimation(keyPath: "transform.scale")
        anim.fromValue = 0.95
        anim.toValue = 1.05
        anim.duration = duration
        anim.autoreverses = true
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(anim, forKey: Self.breathingKey)
    }

    func stopBreathing(on layer: CALayer) {
        layer.removeAnimation(forKey: Self.breathingKey)
    }

    // MARK: - Spin (state transition pirouette)

    func spin(layer: CALayer) {
        let anim = CABasicAnimation(keyPath: "transform.rotation.z")
        anim.fromValue = 0
        anim.toValue = CGFloat.pi * 2.0
        anim.duration = 0.45
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(anim, forKey: Self.shakeKey)
    }

    // MARK: - Glow Pulse (gentle attention signal on prompt submit)

    func glowPulse(layer: CALayer) {
        let anim = CAKeyframeAnimation(keyPath: "opacity")
        anim.values = [layer.opacity, 1.0, layer.opacity]
        anim.keyTimes = [0, 0.4, 1.0]
        anim.duration = 0.5
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(anim, forKey: "glowPulse")
    }

    // MARK: - Flash (success)

    func flash(layer: CALayer) {
        let anim = CAKeyframeAnimation(keyPath: "opacity")
        anim.values = [layer.opacity, 1.0, 0.5, 1.0, layer.opacity]
        anim.keyTimes = [0, 0.2, 0.4, 0.6, 1.0]
        anim.duration = 0.8
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(anim, forKey: Self.flashKey)
    }

    // MARK: - Fade In/Out

    func fadeOut(layer: CALayer, completion: (() -> Void)? = nil) {
        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = 1.0
        anim.toValue = 0.0
        anim.duration = 1.5
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        anim.fillMode = .forwards
        anim.isRemovedOnCompletion = false
        layer.add(anim, forKey: "fadeOut")
        CATransaction.commit()
    }

    func fadeIn(layer: CALayer) {
        layer.removeAnimation(forKey: "fadeOut")
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = 0.0
        anim.toValue = 1.0
        anim.duration = 0.8
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.opacity = 1.0
        layer.add(anim, forKey: "fadeIn")
    }

    // MARK: - State Animation Control

    func stopStateAnimation(on layer: CALayer) {
        layer.removeAnimation(forKey: Self.shakeKey)
        layer.removeAnimation(forKey: Self.flashKey)
        layer.removeAnimation(forKey: Self.stateAnimationKey)
    }
}
