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

    // Retract/extend per-tentacle
    private var retractFactors: [CGFloat] = [0, 0, 0, 0]
    private var retractTargets: [CGFloat] = [0, 0, 0, 0]
    private var retractDelayTimers: [DispatchSourceTimer?] = [nil, nil, nil, nil]

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

    // MARK: - Retract / Extend

    func retract() {
        cancelDelayTimers()
        // Outer first (0, 3), then inner (1, 2)
        let order = [0, 3, 1, 2]
        for (seq, idx) in order.enumerated() {
            let delay = Double(seq) * 0.05
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now() + delay)
            timer.setEventHandler { [weak self] in
                self?.retractTargets[idx] = 1.0
            }
            retractDelayTimers[idx] = timer
            timer.resume()
        }
    }

    func extend() {
        cancelDelayTimers()
        // Inner first (1, 2), then outer (0, 3)
        let order = [1, 2, 0, 3]
        for (seq, idx) in order.enumerated() {
            let delay = Double(seq) * 0.05
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now() + delay)
            timer.setEventHandler { [weak self] in
                self?.retractTargets[idx] = 0.0
            }
            retractDelayTimers[idx] = timer
            timer.resume()
        }
    }

    private func cancelDelayTimers() {
        for i in 0..<retractDelayTimers.count {
            retractDelayTimers[i]?.cancel()
            retractDelayTimers[i] = nil
        }
    }

    // MARK: - Animation tick

    private func tick() {
        let dt: CGFloat = 0.016
        time += dt

        // Smoothly interpolate wave parameters
        let lerp: CGFloat = 0.05
        frequency += (targetFrequency - frequency) * lerp
        amplitude += (targetAmplitude - amplitude) * lerp

        // Smoothly decay drag
        dragDX *= 0.95
        dragDY *= 0.95

        // Update retract factors (fast lerp for snappy feel)
        let retractLerp: CGFloat = 0.12
        for i in 0..<tentacleCount {
            retractFactors[i] += (retractTargets[i] - retractFactors[i]) * retractLerp
            if retractFactors[i] > 0.99 && retractTargets[i] == 1.0 { retractFactors[i] = 1.0 }
            if retractFactors[i] < 0.01 && retractTargets[i] == 0.0 { retractFactors[i] = 0.0 }
        }

        updateTentaclePaths()
    }

    private func updateTentaclePaths() {
        guard bounds.width > 0 else { return }

        let w = bounds.width
        let h = bounds.height

        for i in 0..<tentacleCount {
            let rect = normalTentacleRect(index: i, layerW: w, layerH: h)
            tentacles[i].path = CGPath(rect: rect, transform: nil)
        }
    }

    // MARK: - Normal position (below body, vertical, wiggling)

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

        // Apply retract: scale height down and shift Y towards body (top of layer)
        let rf = retractFactors[i]
        let actualHeight = tentacleHeight * (1 - rf)
        let actualY = y + tentacleHeight * rf  // retract upward (toward body)

        return CGRect(x: x, y: actualY, width: tentacleWidth, height: actualHeight)
    }
}
