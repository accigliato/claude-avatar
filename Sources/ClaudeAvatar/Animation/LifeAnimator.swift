import Foundation
import QuartzCore

final class LifeAnimator {

    private weak var faceLayer: FaceLayer?
    private weak var bodyLayer: CALayer?
    private weak var tentacleLayer: TentacleLayer?
    private weak var effectLayer: EffectLayer?
    private weak var glowLayer: CALayer?
    private weak var avatarContainer: CALayer?

    private var blinkTimer: DispatchSourceTimer?
    private var wanderTimer: DispatchSourceTimer?
    private var glanceTimer: DispatchSourceTimer?
    private var mouthTimer: DispatchSourceTimer?
    private var yawnTimer: DispatchSourceTimer?
    private var loaderTimer: DispatchSourceTimer?
    private var floatTimer: Timer?

    private var isRunning = false
    private var currentState: AvatarState = .idle

    // Float state
    private var floatTime: CGFloat = 0
    private var floatRadius: CGFloat = 12
    private var floatPeriod: CGFloat = 8.0
    private var targetFloatRadius: CGFloat = 12
    private var targetFloatPeriod: CGFloat = 8.0
    private var glowOffsetX: CGFloat = 0
    private var glowOffsetY: CGFloat = 0

    // Timer-based breathing (no CA animation snap)
    private var breathingPeriod: CGFloat = 3.0
    private var targetBreathingPeriod: CGFloat = 3.0
    private var bodyBreathAmplitude: CGFloat = 0.02
    private var targetBodyBreathAmplitude: CGFloat = 0.02

    // Spin momentum
    private var spinAngle: CGFloat = 0
    private var spinVelocity: CGFloat = 0
    private var totalSpinAccumulated: CGFloat = 0
    private var isDizzy: Bool = false
    private var dizzyTime: CGFloat = 0

    // Base positions (set during layout)
    var containerBasePosition: CGPoint = .zero
    var glowBasePosition: CGPoint = .zero

    init(faceLayer: FaceLayer, bodyLayer: CALayer, tentacleLayer: TentacleLayer, effectLayer: EffectLayer, glowLayer: CALayer, avatarContainer: CALayer) {
        self.faceLayer = faceLayer
        self.bodyLayer = bodyLayer
        self.tentacleLayer = tentacleLayer
        self.effectLayer = effectLayer
        self.glowLayer = glowLayer
        self.avatarContainer = avatarContainer
    }

    // MARK: - Start / Stop

    func start() {
        guard !isRunning else { return }
        isRunning = true
        startBlinking()
        startWandering()
        startGlancing()
        startMouthExpressions()
        startYawning()
        startFloating()
    }

    func stop() {
        isRunning = false
        blinkTimer?.cancel()
        blinkTimer = nil
        wanderTimer?.cancel()
        wanderTimer = nil
        glanceTimer?.cancel()
        glanceTimer = nil
        mouthTimer?.cancel()
        mouthTimer = nil
        yawnTimer?.cancel()
        yawnTimer = nil
        loaderTimer?.cancel()
        loaderTimer = nil
        // Keep float timer running for spin decay + smooth breathing wind-down
    }

    func updateForState(_ state: AvatarState) {
        currentState = state
        targetFloatRadius = state.floatRadius
        targetFloatPeriod = state.floatPeriod
        targetBreathingPeriod = state.breathingDuration
        targetBodyBreathAmplitude = state.isAlive ? 0.02 : 0.0

        // Effect + tentacle management
        loaderTimer?.cancel()
        loaderTimer = nil

        if state == .working {
            tentacleLayer?.retract()
            effectLayer?.setMode(.loader, animated: true)
        } else if state == .thinking {
            tentacleLayer?.retract()
            effectLayer?.setMode(.thinking, animated: true)
        } else if state == .responding {
            tentacleLayer?.extend()
            effectLayer?.setMode(.none, animated: true)
            scheduleOccasionalLoader()
        } else {
            tentacleLayer?.extend()
            effectLayer?.setMode(.none, animated: true)
        }
    }

    /// Add rotational impulse on state transition
    func addSpinImpulse() {
        spinVelocity += 8.0
        totalSpinAccumulated += 8.0
    }

    // MARK: - Occasional Loader (responding)

    private func scheduleOccasionalLoader() {
        guard isRunning, currentState == .responding else { return }
        let interval = Double.random(in: 8.0...15.0)
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + interval)
        timer.setEventHandler { [weak self] in
            guard let self = self, self.isRunning, self.currentState == .responding else { return }
            // Retract tentacles, start loader
            self.tentacleLayer?.retract()
            self.effectLayer?.setMode(.loader, animated: true)
            self.faceLayer?.applySquint(0.4, animated: true)

            // After ~2 seconds (roughly one full loop), stop and extend
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self = self, self.currentState == .responding else { return }
                self.effectLayer?.setMode(.none, animated: true)
                self.tentacleLayer?.extend()
                self.faceLayer?.applySquint(0, animated: true)
                self.scheduleOccasionalLoader()
            }
        }
        loaderTimer?.cancel()
        loaderTimer = timer
        timer.resume()
    }

    // MARK: - Floating (parallax) + Spin + Breathing

    private func startFloating() {
        guard floatTimer == nil else { return }
        let timer = Timer(timeInterval: 0.016, repeats: true) { [weak self] _ in
            self?.floatTick()
        }
        RunLoop.main.add(timer, forMode: .common)
        floatTimer = timer
    }

    private func floatTick() {
        let dt: CGFloat = 0.016
        floatTime += dt

        // Smooth interpolation towards target params
        let lerp: CGFloat = 0.03
        floatRadius += (targetFloatRadius - floatRadius) * lerp
        floatPeriod += (targetFloatPeriod - floatPeriod) * lerp
        breathingPeriod += (targetBreathingPeriod - breathingPeriod) * lerp
        bodyBreathAmplitude += (targetBodyBreathAmplitude - bodyBreathAmplitude) * lerp

        let freq = 1.0 / max(floatPeriod, 0.1)

        // Lissajous pattern for organic movement
        let dx = floatRadius * sin(floatTime * freq * 2.0 * .pi)
        let dy = floatRadius * sin(floatTime * freq * 2.0 * .pi * 0.7 + 0.5)

        // --- Spin momentum ---
        spinAngle += spinVelocity * dt
        spinVelocity *= 0.97

        // Dizzy wobble after fast spinning
        if totalSpinAccumulated > 20 && abs(spinVelocity) < 1.0 && !isDizzy {
            isDizzy = true
            dizzyTime = 0
            totalSpinAccumulated = 0
        }

        var dizzyAngle: CGFloat = 0
        if isDizzy {
            dizzyTime += dt
            let wobbleDecay = exp(-dizzyTime * 1.2)
            dizzyAngle = wobbleDecay * 0.15 * sin(dizzyTime * 5.0)
            if wobbleDecay < 0.01 {
                isDizzy = false
            }
        }

        // Spring force: pull spinAngle back to nearest upright (multiple of 2π)
        if abs(spinVelocity) < 2.0 && !isDizzy {
            let twoPi = CGFloat.pi * 2.0
            let nearestUpright = round(spinAngle / twoPi) * twoPi
            let displacement = nearestUpright - spinAngle
            let springK: CGFloat = 3.0
            let damping: CGFloat = 0.92
            spinVelocity += displacement * springK * dt
            spinVelocity *= damping
        }

        if abs(spinVelocity) < 0.05 {
            let twoPi = CGFloat.pi * 2.0
            let nearestUpright = round(spinAngle / twoPi) * twoPi
            if abs(spinAngle - nearestUpright) < 0.02 {
                spinAngle = 0
                spinVelocity = 0
                if !isDizzy { totalSpinAccumulated = 0 }
            }
        }

        let totalAngle = spinAngle + dizzyAngle

        // --- Timer-based breathing (smooth, no CA animation snap) ---
        let glowBreathFreq = 1.0 / max(breathingPeriod, 0.1)
        let glowBreathScale = 1.0 + 0.05 * sin(floatTime * glowBreathFreq * 2.0 * .pi)
        let bodyBreathScale = 1.0 + bodyBreathAmplitude * sin(floatTime * 2.0 * .pi / 3.0)

        // Move container (body+face+tentacles move together)
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        var containerTransform = CATransform3DMakeTranslation(dx, dy, 0)
        if abs(totalAngle) > 0.001 {
            containerTransform = CATransform3DRotate(containerTransform, totalAngle, 0, 0, 1)
        }
        avatarContainer?.transform = containerTransform

        // Glow: breathing scale + position follow with delay
        let glowLerp: CGFloat = 0.04
        glowOffsetX += (dx - glowOffsetX) * glowLerp
        glowOffsetY += (dy - glowOffsetY) * glowLerp
        glowLayer?.position = CGPoint(x: glowBasePosition.x + glowOffsetX, y: glowBasePosition.y + glowOffsetY)
        glowLayer?.transform = CATransform3DMakeScale(glowBreathScale, glowBreathScale, 1)

        // Body: breathing scale
        bodyLayer?.transform = CATransform3DMakeScale(bodyBreathScale, bodyBreathScale, 1)

        CATransaction.commit()
    }

    // MARK: - Blinking

    private func startBlinking() {
        scheduleNextBlink()
    }

    private func scheduleNextBlink() {
        guard isRunning else { return }
        let interval = Double.random(in: 2.0...5.0)
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + interval)
        timer.setEventHandler { [weak self] in
            guard let self = self, self.isRunning else { return }
            self.faceLayer?.blink {
                if Double.random(in: 0...1) < 0.2 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        self.faceLayer?.blink(completion: nil)
                    }
                }
            }
            self.scheduleNextBlink()
        }
        blinkTimer?.cancel()
        blinkTimer = timer
        timer.resume()
    }

    // MARK: - Eye Wandering (subtle drifts)

    private func startWandering() {
        scheduleNextWander()
    }

    private func scheduleNextWander() {
        guard isRunning else { return }
        let interval = currentState == .responding
            ? Double.random(in: 0.8...2.0)
            : Double.random(in: 1.5...3.5)
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + interval)
        timer.setEventHandler { [weak self] in
            guard let self = self, self.isRunning else { return }
            let dx: CGFloat
            let dy: CGFloat

            if self.currentState == .responding {
                let gesture = Int.random(in: 0...4)
                switch gesture {
                case 0: dx = CGFloat.random(in: -1.5...(-0.5)); dy = CGFloat.random(in: 0.5...1.2)
                case 1: dx = CGFloat.random(in: -0.3...0.3); dy = CGFloat.random(in: -0.8...(-0.3))
                case 2: dx = 0; dy = 0
                default: dx = CGFloat.random(in: -0.6...0.6); dy = CGFloat.random(in: -0.3...0.3)
                }
            } else {
                dx = CGFloat.random(in: -0.8...0.8)
                dy = CGFloat.random(in: -0.5...0.5)
            }
            self.faceLayer?.applyEyeOffset(dx: dx, dy: dy, animated: true)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.tentacleLayer?.applyDrag(dx: dx * 0.5, dy: dy * 0.5)
            }

            self.scheduleNextWander()
        }
        wanderTimer?.cancel()
        wanderTimer = timer
        timer.resume()
    }

    // MARK: - Glancing (bigger, deliberate looks)

    private func startGlancing() {
        scheduleNextGlance()
    }

    private func scheduleNextGlance() {
        guard isRunning else { return }
        let interval = Double.random(in: 5.0...12.0)
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + interval)
        timer.setEventHandler { [weak self] in
            guard let self = self, self.isRunning else { return }
            let direction = Int.random(in: 0...3)
            var dx: CGFloat = 0
            var dy: CGFloat = 0
            switch direction {
            case 0: dx = CGFloat.random(in: 1.5...2.5)
            case 1: dx = CGFloat.random(in: -2.5...(-1.5))
            case 2: dy = CGFloat.random(in: 1.0...1.8)
            case 3: dx = CGFloat.random(in: 1.0...2.0); dy = CGFloat.random(in: 0.5...1.2)
            default: break
            }
            self.faceLayer?.applyEyeOffset(dx: dx, dy: dy, animated: true)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.tentacleLayer?.applyDrag(dx: dx * 0.7, dy: dy * 0.7)
            }

            let holdTime = Double.random(in: 0.8...2.0)
            DispatchQueue.main.asyncAfter(deadline: .now() + holdTime) { [weak self] in
                guard let self = self, self.isRunning else { return }
                let returnDx = CGFloat.random(in: -0.3...0.3)
                let returnDy = CGFloat.random(in: -0.2...0.2)
                self.faceLayer?.applyEyeOffset(dx: returnDx, dy: returnDy, animated: true)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    self?.tentacleLayer?.applyDrag(dx: returnDx * 0.5, dy: returnDy * 0.5)
                }
            }
            self.scheduleNextGlance()
        }
        glanceTimer?.cancel()
        glanceTimer = timer
        timer.resume()
    }

    // MARK: - Mouth Micro-Expressions

    private func startMouthExpressions() {
        scheduleNextMouthTwitch()
    }

    private func scheduleNextMouthTwitch() {
        guard isRunning else { return }
        let interval = Double.random(in: 2.0...5.0)
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + interval)
        timer.setEventHandler { [weak self] in
            guard let self = self, self.isRunning else { return }

            let widthDelta = CGFloat.random(in: -0.8...0.8)
            let heightDelta = CGFloat.random(in: -0.2...0.3)
            self.faceLayer?.applyMouthTwitch(widthDelta: widthDelta, heightDelta: heightDelta, animated: true)

            let holdTime = Double.random(in: 0.5...1.5)
            DispatchQueue.main.asyncAfter(deadline: .now() + holdTime) { [weak self] in
                guard let self = self, self.isRunning else { return }
                self.faceLayer?.applyMouthTwitch(widthDelta: 0, heightDelta: 0, animated: true)
            }

            self.scheduleNextMouthTwitch()
        }
        mouthTimer?.cancel()
        mouthTimer = timer
        timer.resume()
    }

    // MARK: - Idle Yawn

    private func startYawning() {
        scheduleNextYawn()
    }

    private func scheduleNextYawn() {
        guard isRunning else { return }
        let interval = Double.random(in: 30.0...60.0)
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + interval)
        timer.setEventHandler { [weak self] in
            guard let self = self, self.isRunning, self.currentState == .idle else {
                self?.scheduleNextYawn()
                return
            }
            self.faceLayer?.yawn {
                self.scheduleNextYawn()
            }
        }
        yawnTimer?.cancel()
        yawnTimer = timer
        timer.resume()
    }
}
