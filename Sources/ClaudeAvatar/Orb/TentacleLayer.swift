import AppKit
import QuartzCore

final class TentacleLayer: CALayer {

    private let tentacleCount = 4
    private var tentacles: [CAShapeLayer] = []

    private var displayTimer: Timer?
    private var time: CGFloat = 0

    // Current wave parameters
    private var frequency: CGFloat = 1.0
    private var amplitude: CGFloat = 2.0
    private var targetFrequency: CGFloat = 1.0
    private var targetAmplitude: CGFloat = 2.0

    // Drag offset from eye/body movement
    private var dragDX: CGFloat = 0
    private var dragDY: CGFloat = 0

    // Tentacle color
    private var tentacleColor: CGColor = AvatarState.idle.primaryColor.cgColor

    // Orbit rotation around body center
    private var orbitAngle: CGFloat = 0
    private var orbitSpeed: CGFloat = 0
    private var targetOrbitSpeed: CGFloat = 0
    private var singleOrbitTarget: CGFloat? = nil
    private var singleOrbitCompletion: (() -> Void)? = nil

    // Thinking mode: tentacles march above head on rectangular path
    private var isThinking: Bool = false
    private var thinkingBlend: CGFloat = 0      // 0 = normal, 1 = fully thinking
    private var thinkPathProgress: CGFloat = 0  // accumulated distance along perimeter
    private var thinkStepAccum: CGFloat = 0     // accumulator for stepping

    /// Y coordinate of the body center in this layer's coordinate space.
    /// Set by OrbView during layout.
    var bodyCenterYOffset: CGFloat = 0

    /// Body dimensions for thinking path calculation. Set by OrbView.
    var bodyWidth: CGFloat = 0
    var bodyHeight: CGFloat = 0

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
        for _ in 0..<tentacleCount {
            let t = CAShapeLayer()
            t.fillColor = tentacleColor
            t.strokeColor = nil
            addSublayer(t)
            tentacles.append(t)
        }
    }

    // MARK: - Public API

    func updateForState(_ state: AvatarState, animated: Bool) {
        targetFrequency = state.tentacleFrequency
        targetAmplitude = state.tentacleAmplitude

        let newColor = state.primaryColor.cgColor
        if animated {
            let anim = CABasicAnimation(keyPath: "fillColor")
            anim.toValue = newColor
            anim.duration = 0.6
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            for t in tentacles {
                anim.fromValue = t.fillColor
                t.add(anim, forKey: "colorTransition")
                t.fillColor = newColor
            }
        } else {
            for t in tentacles {
                t.fillColor = newColor
            }
        }
        tentacleColor = newColor
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

    func applyDrag(dx: CGFloat, dy: CGFloat) {
        dragDX = dx
        dragDY = dy
    }

    // MARK: - Orbit API

    func startContinuousOrbit(speed: CGFloat) {
        targetOrbitSpeed = speed
        singleOrbitTarget = nil
        singleOrbitCompletion = nil
    }

    func doSingleOrbit(speed: CGFloat = 2.5, completion: (() -> Void)? = nil) {
        singleOrbitTarget = orbitAngle + .pi * 2
        singleOrbitCompletion = completion
        targetOrbitSpeed = speed
    }

    func stopOrbit() {
        targetOrbitSpeed = 0
        singleOrbitTarget = nil
        singleOrbitCompletion = nil
    }

    // MARK: - Thinking Mode API

    func setThinkingMode(_ enabled: Bool) {
        isThinking = enabled
        if enabled {
            thinkPathProgress = 0
            thinkStepAccum = 0
            // Draw tentacles above face
            self.zPosition = 100
        } else {
            self.zPosition = 0
        }
    }

    // MARK: - Animation tick

    private func tick() {
        let dt: CGFloat = 0.016
        time += dt

        // Smoothly interpolate towards target parameters
        let lerp: CGFloat = 0.05
        frequency += (targetFrequency - frequency) * lerp
        amplitude += (targetAmplitude - amplitude) * lerp

        // Smoothly decay drag
        dragDX *= 0.95
        dragDY *= 0.95

        // Blend towards thinking mode
        let blendSpeed: CGFloat = 0.06
        if isThinking {
            thinkingBlend += (1.0 - thinkingBlend) * blendSpeed
            // Advance path progress in steps
            thinkStepAccum += dt
            let stepInterval: CGFloat = 0.12  // step every 120ms
            if thinkStepAccum >= stepInterval {
                thinkStepAccum -= stepInterval
                thinkPathProgress += 5.0  // 5px per step
            }
        } else {
            thinkingBlend += (0.0 - thinkingBlend) * blendSpeed
        }

        updateTentaclePaths()

        // Only update orbit when not thinking
        if thinkingBlend < 0.5 {
            updateOrbit()
        } else {
            // Clear orbit transform when thinking
            self.transform = CATransform3DIdentity
        }
    }

    private func updateTentaclePaths() {
        guard bounds.width > 0 else { return }

        let w = bounds.width
        let h = bounds.height

        for i in 0..<tentacleCount {
            // Normal position
            let normalRect = normalTentacleRect(index: i, layerW: w, layerH: h)

            if thinkingBlend < 0.01 {
                // Pure normal mode
                tentacles[i].path = CGPath(rect: normalRect, transform: nil)
            } else {
                // Thinking position
                let thinkRect = thinkingTentacleRect(index: i, layerW: w, layerH: h)

                // Lerp between normal and thinking
                let b = thinkingBlend
                let blendedRect = CGRect(
                    x: normalRect.origin.x + (thinkRect.origin.x - normalRect.origin.x) * b,
                    y: normalRect.origin.y + (thinkRect.origin.y - normalRect.origin.y) * b,
                    width: normalRect.width + (thinkRect.width - normalRect.width) * b,
                    height: normalRect.height + (thinkRect.height - normalRect.height) * b
                )
                tentacles[i].path = CGPath(rect: blendedRect, transform: nil)
            }
        }
    }

    // Normal tentacle rect (below body, vertical, wiggling)
    private func normalTentacleRect(index i: Int, layerW w: CGFloat, layerH h: CGFloat) -> CGRect {
        let tentacleWidth = w * 0.1
        let tentacleHeight = h * 0.7
        let positions: [CGFloat] = [0.15, 0.28, 0.72, 0.85]

        let t = CGFloat(i)
        let basePhase = t * .pi / 2.0
        let baseX = w * positions[i] - tentacleWidth / 2.0

        let isOuter = (i == 0 || i == tentacleCount - 1)
        let ampMultiplier: CGFloat = isOuter ? 1.2 : 1.0

        let offsetX = amplitude * ampMultiplier * sin(time * frequency * 2.0 * .pi + basePhase)
        let offsetY = amplitude * ampMultiplier * 0.3 * sin(time * frequency * 2.0 * .pi * 0.7 + basePhase)

        let x = baseX + offsetX + dragDX * 0.4
        let y = offsetY + dragDY * 0.3

        return CGRect(x: x, y: y, width: tentacleWidth, height: tentacleHeight)
    }

    // Thinking tentacle rect (above body, horizontal, marching on rectangle path)
    private func thinkingTentacleRect(index i: Int, layerW w: CGFloat, layerH h: CGFloat) -> CGRect {
        let tentH = h * 0.7   // original tentacle height → becomes width when horizontal
        let tentW = w * 0.1   // original tentacle width → becomes height when horizontal

        // Rectangle path: half body size, centered above body
        let rectW = bodyWidth * 0.5
        let rectH = bodyHeight * 0.5
        let gap: CGFloat = 8.0
        let rectCenterX = w / 2.0
        let rectCenterY = bodyCenterYOffset + bodyHeight / 2.0 + gap + rectH / 2.0

        // Perimeter of rectangle
        let perimeter = 2.0 * (rectW + rectH)

        // Each tentacle evenly spaced around perimeter
        let spacing = perimeter / CGFloat(tentacleCount)
        let dist = (thinkPathProgress + CGFloat(i) * spacing).truncatingRemainder(dividingBy: perimeter)

        // Convert distance to position on rectangle perimeter
        let (px, py) = pointOnRectPerimeter(
            dist: dist, perimeter: perimeter,
            rectW: rectW, rectH: rectH,
            centerX: rectCenterX, centerY: rectCenterY
        )

        // Add subtle wobble
        let wobbleX = 0.5 * sin(time * 2.0 + CGFloat(i) * 1.5)
        let wobbleY = 0.3 * sin(time * 1.7 + CGFloat(i) * 1.2)

        // Horizontal tentacle: width = tentH (long dimension), height = tentW (short)
        return CGRect(
            x: px - tentH / 2.0 + wobbleX,
            y: py - tentW / 2.0 + wobbleY,
            width: tentH,
            height: tentW
        )
    }

    /// Convert a distance along the rectangle perimeter to an (x,y) point
    private func pointOnRectPerimeter(
        dist: CGFloat, perimeter: CGFloat,
        rectW: CGFloat, rectH: CGFloat,
        centerX: CGFloat, centerY: CGFloat
    ) -> (CGFloat, CGFloat) {
        let left = centerX - rectW / 2
        let right = centerX + rectW / 2
        let bottom = centerY - rectH / 2
        let top = centerY + rectH / 2

        var d = dist.truncatingRemainder(dividingBy: perimeter)
        if d < 0 { d += perimeter }

        if d < rectW {
            // Bottom edge: left to right
            return (left + d, bottom)
        }
        d -= rectW
        if d < rectH {
            // Right edge: bottom to top
            return (right, bottom + d)
        }
        d -= rectH
        if d < rectW {
            // Top edge: right to left
            return (right - d, top)
        }
        d -= rectW
        // Left edge: top to bottom
        return (left, top - d)
    }

    // MARK: - Orbit

    private func updateOrbit() {
        let dt: CGFloat = 0.016

        // Lerp orbit speed
        let orbitLerp: CGFloat = 0.08
        orbitSpeed += (targetOrbitSpeed - orbitSpeed) * orbitLerp

        // Check single orbit completion
        if let target = singleOrbitTarget, orbitAngle >= target {
            targetOrbitSpeed = 0
            singleOrbitTarget = nil
            let completion = singleOrbitCompletion
            singleOrbitCompletion = nil
            completion?()
        }

        if abs(orbitSpeed) > 0.05 {
            orbitAngle += orbitSpeed * dt
            applyOrbitTransform()
        } else if abs(targetOrbitSpeed) < 0.001 && abs(orbitAngle) > 0.01 {
            // Spring back to nearest full rotation (= upright)
            let twoPi = CGFloat.pi * 2
            let nearest = round(orbitAngle / twoPi) * twoPi
            let displacement = nearest - orbitAngle
            if abs(displacement) > 0.02 {
                orbitAngle += displacement * 0.08
                applyOrbitTransform()
            } else {
                orbitAngle = 0
                orbitSpeed = 0
                self.transform = CATransform3DIdentity
            }
        }
    }

    private func applyOrbitTransform() {
        let pivotX = bounds.width / 2
        let pivotY = bodyCenterYOffset
        // Rotate around body center: translate to pivot, rotate, translate back
        var t = CATransform3DMakeTranslation(pivotX, pivotY, 0)
        t = CATransform3DRotate(t, orbitAngle, 0, 0, 1)
        t = CATransform3DTranslate(t, -pivotX, -pivotY, 0)
        self.transform = t
    }
}
