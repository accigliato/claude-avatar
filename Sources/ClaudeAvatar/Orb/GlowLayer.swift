import AppKit
import QuartzCore

final class GlowLayer: CALayer {

    private let glowGradient = CAGradientLayer()

    override init() {
        super.init()
        setup()
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        glowGradient.type = .radial
        glowGradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        glowGradient.endPoint = CGPoint(x: 1.0, y: 1.0)
        glowGradient.locations = [0.0, 0.5, 1.0]
        addSublayer(glowGradient)
        updateColor(AvatarState.idle.glowColor, intensity: AvatarState.idle.glowIntensity)
    }

    override func layoutSublayers() {
        super.layoutSublayers()
        glowGradient.frame = bounds
        glowGradient.cornerRadius = bounds.width * 0.12
    }

    func updateColor(_ color: NSColor, intensity: Float, animated: Bool = false) {
        let cgColor = color.cgColor
        let clearColor = color.withAlphaComponent(0.0).cgColor
        let midColor = color.withAlphaComponent(CGFloat(intensity) * 0.5).cgColor

        let newColors = [cgColor, midColor, clearColor]

        if animated {
            let anim = CABasicAnimation(keyPath: "colors")
            anim.fromValue = glowGradient.colors
            anim.toValue = newColors
            anim.duration = 0.6
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            glowGradient.add(anim, forKey: "colorTransition")
        }

        glowGradient.colors = newColors
        glowGradient.opacity = intensity
    }
}
