import AppKit
import QuartzCore

enum EffectMode {
    case none
    case loader    // working, responding
    case thinking  // thinking
}

final class EffectLayer: CALayer {

    private var mode: EffectMode = .none
    private var displayTimer: Timer?
    private var time: CGFloat = 0

    // Body frame in this layer's coordinate space (set by OrbView)
    var bodyFrame: CGRect = .zero

    // Tick color
    private var effectColor: CGColor = AvatarState.idle.primaryColor.cgColor

    // Loader state
    private var loaderTicks: [CAShapeLayer] = []
    private let tickCount = 4
    private var headPosition: CGFloat = 0  // distance along perimeter
    private var stepAccum: CGFloat = 0
    private let stepInterval: CGFloat = 0.08  // 80ms per step

    // Thinking state
    private var thinkDots: [CAShapeLayer] = []
    private let dotCount = 4
    private var thinkTime: CGFloat = 0

    // Fade
    private var currentOpacity: CGFloat = 0
    private var targetOpacity: CGFloat = 0

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
        // Create loader tick layers
        for _ in 0..<tickCount {
            let tick = CAShapeLayer()
            tick.fillColor = effectColor
            tick.strokeColor = nil
            tick.opacity = 0
            addSublayer(tick)
            loaderTicks.append(tick)
        }

        // Create thinking dot layers
        for _ in 0..<dotCount {
            let dot = CAShapeLayer()
            dot.fillColor = effectColor
            dot.strokeColor = nil
            dot.opacity = 0
            addSublayer(dot)
            thinkDots.append(dot)
        }
    }

    // MARK: - Public API

    func setMode(_ newMode: EffectMode, animated: Bool) {
        guard newMode != mode else { return }
        mode = newMode

        switch mode {
        case .none:
            targetOpacity = 0
        case .loader:
            headPosition = 0
            stepAccum = 0
            targetOpacity = 1
        case .thinking:
            thinkTime = 0
            targetOpacity = 1
        }

        if !animated {
            currentOpacity = targetOpacity
            applyOpacity()
        }
    }

    func updateColor(_ color: CGColor, animated: Bool) {
        effectColor = color
        if animated {
            let anim = CABasicAnimation(keyPath: "fillColor")
            anim.toValue = color
            anim.duration = 0.6
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            for tick in loaderTicks {
                anim.fromValue = tick.fillColor
                tick.add(anim, forKey: "colorTransition")
                tick.fillColor = color
            }
            for bubble in thinkDots {
                anim.fromValue = bubble.fillColor
                bubble.add(anim, forKey: "colorTransition")
                bubble.fillColor = color
            }
        } else {
            for tick in loaderTicks {
                tick.fillColor = color
            }
            for bubble in thinkDots {
                bubble.fillColor = color
            }
        }
    }

    func start() {
        guard displayTimer == nil else { return }
        let timer = Timer(timeInterval: 0.016, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        displayTimer = timer
    }

    func stop() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    // MARK: - Animation Tick

    private func tick() {
        let dt: CGFloat = 0.016
        time += dt

        // Fade opacity
        let opacityLerp: CGFloat = 0.12
        currentOpacity += (targetOpacity - currentOpacity) * opacityLerp
        if currentOpacity < 0.01 && targetOpacity == 0 { currentOpacity = 0 }
        applyOpacity()

        guard currentOpacity > 0.01 else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        switch mode {
        case .loader:
            updateLoader(dt: dt)
        case .thinking:
            updateThinking(dt: dt)
        case .none:
            break
        }

        CATransaction.commit()
    }

    private func applyOpacity() {
        let loaderVisible = (mode == .loader || (mode == .none && currentOpacity > 0.01))
        let thinkVisible = (mode == .thinking || (mode == .none && currentOpacity > 0.01))

        for tick in loaderTicks {
            tick.opacity = loaderVisible && mode != .thinking ? Float(currentOpacity) : 0
        }
        for dot in thinkDots {
            dot.opacity = thinkVisible && mode != .loader ? Float(currentOpacity) : 0
        }
    }

    // MARK: - Loader (8-bit marching ticks)

    private func updateLoader(dt: CGFloat) {
        guard bodyFrame.width > 0 else { return }

        let margin = bodyFrame.width * 0.25
        let rect = bodyFrame.insetBy(dx: -margin, dy: -margin)
        let perimeter = 2.0 * (rect.width + rect.height)
        let tickSize = bodyFrame.width * 0.12
        let gap: CGFloat = 10.0

        // 8-bit step accumulator
        stepAccum += dt
        if stepAccum >= stepInterval {
            let steps = floor(stepAccum / stepInterval)
            headPosition += steps * tickSize
            stepAccum = stepAccum.truncatingRemainder(dividingBy: stepInterval)
        }

        // Wrap
        if headPosition > perimeter {
            headPosition = headPosition.truncatingRemainder(dividingBy: perimeter)
        }

        // Position each tick
        for i in 0..<tickCount {
            var dist = headPosition - CGFloat(i) * (tickSize + gap)
            if dist < 0 { dist += perimeter }
            dist = dist.truncatingRemainder(dividingBy: perimeter)

            let (px, py) = pointOnRectPerimeter(
                dist: dist, perimeter: perimeter,
                rect: rect
            )

            // Snap to integer pixels (8-bit feel)
            let x = floor(px - tickSize / 2)
            let y = floor(py - tickSize / 2)

            loaderTicks[i].path = CGPath(
                rect: CGRect(x: x, y: y, width: tickSize, height: tickSize),
                transform: nil
            )
        }
    }

    // MARK: - Thinking (pulsing dots above head)

    private func updateThinking(dt: CGFloat) {
        guard bodyFrame.width > 0 else { return }
        thinkTime += dt

        let bodyTop = bodyFrame.maxY
        let bodyCenterX = bodyFrame.midX

        // 4 vertical rectangles (taller than wide)
        let dotW = bodyFrame.width * 0.07
        let dotH = dotW * 1.8
        let gap: CGFloat = 6.0
        let totalW = CGFloat(dotCount) * dotW + CGFloat(dotCount - 1) * gap
        let startX = bodyCenterX - totalW / 2
        let baseY = bodyTop + 8.0

        // Sequential bounce: each dot bounces up in turn, wave-like
        let cyclePeriod: CGFloat = 1.6  // full cycle time
        let phase = thinkTime / cyclePeriod
        let bobHeight: CGFloat = dotH * 0.5

        for i in 0..<dotCount {
            let x = floor(startX + CGFloat(i) * (dotW + gap))

            // Each dot is offset in phase by 0.2 of the cycle
            let dotPhase = phase - CGFloat(i) * 0.2
            // Use a sine wave, clamped so only the "up" part shows as a bounce
            let raw = sin(dotPhase * 2.0 * .pi)
            let bounce = floor(max(0, raw) * bobHeight)

            let y = floor(baseY + bounce)

            thinkDots[i].path = CGPath(
                rect: CGRect(x: x, y: y, width: dotW, height: dotH),
                transform: nil
            )
        }
    }

    // MARK: - Perimeter point helper

    private func pointOnRectPerimeter(
        dist: CGFloat, perimeter: CGFloat,
        rect: CGRect
    ) -> (CGFloat, CGFloat) {
        let left = rect.minX
        let right = rect.maxX
        let bottom = rect.minY
        let top = rect.maxY

        var d = dist.truncatingRemainder(dividingBy: perimeter)
        if d < 0 { d += perimeter }

        // Bottom edge: left to right
        if d < rect.width {
            return (left + d, bottom)
        }
        d -= rect.width

        // Right edge: bottom to top
        if d < rect.height {
            return (right, bottom + d)
        }
        d -= rect.height

        // Top edge: right to left
        if d < rect.width {
            return (right - d, top)
        }
        d -= rect.width

        // Left edge: top to bottom
        return (left, top - d)
    }
}
