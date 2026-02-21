import Foundation
import QuartzCore

final class LifeAnimator {

    private weak var faceLayer: FaceLayer?
    private weak var bodyLayer: CALayer?
    private weak var tentacleLayer: TentacleLayer?
    private weak var effectLayer: EffectLayer?
    private weak var cookingLayer: CookingLayer?
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

    // Blink clustering: track last double-blink to enforce cooldown
    private var lastDoubleBlinkTime: CFAbsoluteTime = 0

    // Float state (phase accumulators avoid jump on freq change)
    private var floatPhaseX: CGFloat = 0
    private var floatPhaseY: CGFloat = 0.5  // initial offset for Lissajous
    private var breathPhase: CGFloat = 0
    private var bodyBreathPhase: CGFloat = 0
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

    // Base positions (set during layout)
    var containerBasePosition: CGPoint = .zero
    var glowBasePosition: CGPoint = .zero

    init(faceLayer: FaceLayer, bodyLayer: CALayer, tentacleLayer: TentacleLayer, effectLayer: EffectLayer, cookingLayer: CookingLayer, glowLayer: CALayer, avatarContainer: CALayer) {
        self.faceLayer = faceLayer
        self.bodyLayer = bodyLayer
        self.tentacleLayer = tentacleLayer
        self.effectLayer = effectLayer
        self.cookingLayer = cookingLayer
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
        // Keep float timer running for smooth breathing wind-down
    }

    func updateForState(_ state: AvatarState) {
        currentState = state
        targetFloatRadius = state.floatRadius
        targetFloatPeriod = state.floatPeriod
        targetBreathingPeriod = state.breathingDuration
        targetBodyBreathAmplitude = (state.isAlive && state != .tool) ? 0.02 : 0.0

        // Effect + tentacle management
        loaderTimer?.cancel()
        loaderTimer = nil

        if state == .tool {
            // Tool state: retract tentacles, hide effects (CookingLayer handles visuals)
            tentacleLayer?.retract()
            effectLayer?.setMode(.none, animated: true)
        } else if state == .working {
            tentacleLayer?.retract()
            effectLayer?.setMode(.loader, animated: true)
        } else if state == .thinking {
            tentacleLayer?.retract()
            effectLayer?.setMode(.thinking, animated: true)
        } else if state == .approve {
            // Approve: extend tentacles, no effects, alert scanning
            tentacleLayer?.extend()
            effectLayer?.setMode(.none, animated: true)
        } else if state == .responding {
            tentacleLayer?.extend()
            effectLayer?.setMode(.none, animated: true)
            scheduleOccasionalLoader()
        } else {
            tentacleLayer?.extend()
            effectLayer?.setMode(.none, animated: true)
        }
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

    // MARK: - Floating (parallax) + Breathing

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

        // Smooth interpolation towards target params
        let lerp: CGFloat = 0.03
        floatRadius += (targetFloatRadius - floatRadius) * lerp
        floatPeriod += (targetFloatPeriod - floatPeriod) * lerp
        breathingPeriod += (targetBreathingPeriod - breathingPeriod) * lerp
        bodyBreathAmplitude += (targetBodyBreathAmplitude - bodyBreathAmplitude) * lerp

        // Phase accumulators: freq changes only affect rate, not current position
        let freq = 1.0 / max(floatPeriod, 0.1)
        floatPhaseX += freq * dt * 2.0 * .pi
        floatPhaseY += freq * dt * 2.0 * .pi * 0.7

        // Lissajous pattern for organic movement
        let dx = floatRadius * sin(floatPhaseX)
        let dy = floatRadius * sin(floatPhaseY)

        // --- Timer-based breathing (phase accumulators) ---
        let glowBreathFreq = 1.0 / max(breathingPeriod, 0.1)
        breathPhase += glowBreathFreq * dt * 2.0 * .pi
        bodyBreathPhase += dt * 2.0 * .pi / 3.0
        let glowBreathScale = 1.0 + 0.05 * sin(breathPhase)
        let bodyBreathScale = 1.0 + bodyBreathAmplitude * sin(bodyBreathPhase)

        // Move container (body+face+tentacles move together)
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        avatarContainer?.transform = CATransform3DMakeTranslation(dx, dy, 0)

        // Glow: breathing scale + position follow with delay
        let glowLerp: CGFloat = 0.04
        glowOffsetX += (dx - glowOffsetX) * glowLerp
        glowOffsetY += (dy - glowOffsetY) * glowLerp
        glowLayer?.position = CGPoint(x: glowBasePosition.x + glowOffsetX, y: glowBasePosition.y + glowOffsetY)
        glowLayer?.transform = CATransform3DMakeScale(glowBreathScale, glowBreathScale, 1)

        // Body: breathing scale
        bodyLayer?.transform = CATransform3DMakeScale(bodyBreathScale, bodyBreathScale, 1)

        // Cooking layer: breathing scale synced with body (scale around body center)
        if let body = bodyLayer, let cooking = cookingLayer {
            let offX = body.position.x - cooking.position.x
            let offY = body.position.y - cooking.position.y
            let s = bodyBreathScale
            var ct = CATransform3DIdentity
            ct = CATransform3DScale(ct, s, s, 1)
            ct = CATransform3DTranslate(ct, offX * (1 - s), offY * (1 - s), 0)
            cooking.transform = ct
        }

        CATransaction.commit()
    }

    // MARK: - Blinking

    private func startBlinking() {
        scheduleNextBlink()
    }

    private func blinkInterval(for state: AvatarState) -> (min: Double, max: Double) {
        switch state {
        case .idle:                return (2.5, 5.0)
        case .listening:           return (8.0, 15.0)
        case .thinking:            return (3.5, 6.0)
        case .working:             return (5.0, 8.0)
        case .responding:          return (2.0, 4.0)
        case .tool:                return (4.0, 7.0)
        case .approve:             return (2.0, 4.0)
        case .error:               return (1.5, 3.0)
        case .success, .goodbye:   return (3.0, 5.0)
        case .sleep:               return (6.0, 10.0)
        }
    }

    private func scheduleNextBlink() {
        guard isRunning else { return }
        let range = blinkInterval(for: currentState)
        var interval = Double.random(in: range.min...range.max)

        // Clustering cooldown: if a double-blink happened recently, add extra delay
        let timeSinceDouble = CFAbsoluteTimeGetCurrent() - lastDoubleBlinkTime
        if timeSinceDouble < 3.0 {
            interval += (3.0 - timeSinceDouble)
        }

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + interval)
        timer.setEventHandler { [weak self] in
            guard let self = self, self.isRunning else { return }
            self.faceLayer?.blink { [weak self] in
                guard let self = self else { return }

                // 20% chance of double-blink
                if Double.random(in: 0...1) < 0.2 {
                    self.lastDoubleBlinkTime = CFAbsoluteTimeGetCurrent()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        self.faceLayer?.blink(completion: nil)
                    }
                }

                // 50% chance of post-blink microsaccade
                if Double.random(in: 0...1) < 0.5 {
                    let microDx = CGFloat.random(in: -0.15...0.15)
                    let microDy = CGFloat.random(in: -0.1...0.1)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        self.faceLayer?.applyEyeOffset(dx: microDx, dy: microDy, animated: true, duration: 0.15, easing: .easeOut)
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

    private func wanderParams(for state: AvatarState) -> (interval: (Double, Double), range: CGFloat, biasX: CGFloat, biasY: CGFloat) {
        switch state {
        case .idle:       return ((1.5, 3.5), 0.8,  0,    0)
        case .listening:  return ((3.0, 5.0), 0.4,  0,    0)     // centered, staring at user
        case .thinking:   return ((2.0, 4.0), 0.6,  0,    0)     // no bias — looks all around
        case .working:    return ((3.0, 5.0), 0.3,  0,    0)     // minimal, concentrated
        case .responding: return ((0.8, 2.0), 0.8,  0,    0)     // reading pattern (handled specially)
        case .tool:       return ((2.0, 4.0), 0.4,  -0.2, -0.1)  // focused down-left (watching pan)
        case .approve:    return ((1.0, 2.5), 0.9,  0,    0)     // alert scanning
        case .error:      return ((0.5, 1.5), 1.0,  0,    0)     // erratic
        case .success:    return ((1.5, 3.0), 0.5,  0,    0)
        case .goodbye:    return ((3.0, 5.0), 0.3,  0,    0)
        case .sleep:      return ((4.0, 8.0), 0.2,  0,    0)
        }
    }

    private func scheduleNextWander() {
        guard isRunning else { return }
        let params = wanderParams(for: currentState)
        let interval = Double.random(in: params.interval.0...params.interval.1)
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + interval)
        timer.setEventHandler { [weak self] in
            guard let self = self, self.isRunning else { return }
            let dx: CGFloat
            let dy: CGFloat

            if self.currentState == .responding {
                // Reading pattern gestures
                let gesture = Int.random(in: 0...4)
                switch gesture {
                case 0: dx = CGFloat.random(in: -1.5...(-0.5)); dy = CGFloat.random(in: 0.5...1.2)
                case 1: dx = CGFloat.random(in: -0.3...0.3); dy = CGFloat.random(in: -0.8...(-0.3))
                case 2: dx = 0; dy = 0
                default: dx = CGFloat.random(in: -0.6...0.6); dy = CGFloat.random(in: -0.3...0.3)
                }
            } else {
                let r = params.range
                dx = CGFloat.random(in: -r...r) + params.biasX
                dy = CGFloat.random(in: -r * 0.6...r * 0.6) + params.biasY
            }
            self.faceLayer?.applyEyeOffset(dx: dx, dy: dy, animated: true)

            // ~30% chance: small mouth reaction tied to wander movement
            if Double.random(in: 0...1) < 0.3 {
                let openness = CGFloat.random(in: -0.3...0.3)
                self.faceLayer?.applyMouthReaction(openness: openness, animated: true)
            }

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

    private func glanceInterval(for state: AvatarState) -> (min: Double, max: Double) {
        switch state {
        case .listening:  return (10.0, 20.0)  // rare — focused on user
        case .thinking:   return (4.0, 8.0)
        case .tool:       return (6.0, 12.0)   // occasional glances while cooking
        case .approve:    return (3.0, 6.0)    // alert, looking around
        case .error:      return (3.0, 6.0)
        default:          return (5.0, 12.0)
        }
    }

    private func scheduleNextGlance() {
        guard isRunning else { return }
        let range = glanceInterval(for: currentState)
        let interval = Double.random(in: range.min...range.max)
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + interval)
        timer.setEventHandler { [weak self] in
            guard let self = self, self.isRunning else { return }

            // Determine glance target
            var dx: CGFloat = 0
            var dy: CGFloat = 0

            if self.currentState == .thinking {
                // Reflective gaze — looks in all directions
                let direction = Int.random(in: 0...3)
                switch direction {
                case 0: dx = CGFloat.random(in: 0.5...2.0); dy = CGFloat.random(in: 0.8...1.8)     // upper-right
                case 1: dx = CGFloat.random(in: -2.0...(-0.5)); dy = CGFloat.random(in: 0.8...1.8)  // upper-left
                case 2: dx = CGFloat.random(in: -2.0...(-0.5)); dy = CGFloat.random(in: -0.5...0.5)  // left
                default: dx = CGFloat.random(in: 0.5...2.0); dy = CGFloat.random(in: -0.5...0.5)     // right
                }
            } else if self.currentState == .approve {
                // Alert scanning — look around in all directions
                let direction = Int.random(in: 0...5)
                switch direction {
                case 0: dx = CGFloat.random(in: 1.5...2.5); dy = CGFloat.random(in: 0.5...1.0)
                case 1: dx = CGFloat.random(in: -2.5...(-1.5)); dy = CGFloat.random(in: 0.5...1.0)
                case 2: dy = CGFloat.random(in: 1.0...2.0)
                case 3: dx = CGFloat.random(in: -1.0...1.0); dy = CGFloat.random(in: -1.0...(-0.5))
                default: dx = CGFloat.random(in: 1.0...2.0); dy = CGFloat.random(in: 0.5...1.2)
                }
            } else {
                let direction = Int.random(in: 0...3)
                switch direction {
                case 0: dx = CGFloat.random(in: 1.5...2.5)
                case 1: dx = CGFloat.random(in: -2.5...(-1.5))
                case 2: dy = CGFloat.random(in: 1.0...1.8)
                case 3: dx = CGFloat.random(in: 1.0...2.0); dy = CGFloat.random(in: 0.5...1.2)
                default: break
                }
            }

            // Phase 1 — Anticipation: eyes move 0.3 gu in OPPOSITE direction (60ms)
            let antiDx = -dx * 0.15  // ~0.3 gu for a 2.0 gu glance
            let antiDy = -dy * 0.15
            self.faceLayer?.applyEyeOffset(dx: antiDx, dy: antiDy, animated: true, duration: 0.06, easing: .easeOut)

            // Phase 2 — Snap to target (250ms, easeOut)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
                guard let self = self, self.isRunning else { return }
                self.faceLayer?.applyEyeOffset(dx: dx, dy: dy, animated: true, duration: 0.25, easing: .easeOut)

                // Mouth reaction
                let magnitude = sqrt(dx * dx + dy * dy)
                let roll = Double.random(in: 0...1)
                let mouthOpenness: CGFloat
                if roll < 0.5 {
                    mouthOpenness = CGFloat.random(in: 0.4...0.8) * min(magnitude / 2.5, 1.0)
                } else if roll < 0.8 {
                    mouthOpenness = CGFloat.random(in: -0.6...(-0.3))
                } else {
                    mouthOpenness = CGFloat.random(in: 0.8...1.0)
                }
                self.faceLayer?.applyMouthReaction(openness: mouthOpenness, animated: true)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    self?.tentacleLayer?.applyDrag(dx: dx * 0.7, dy: dy * 0.7)
                }

                // Phase 3 — Hold
                let holdTime = Double.random(in: 0.8...2.0)
                DispatchQueue.main.asyncAfter(deadline: .now() + holdTime) { [weak self] in
                    guard let self = self, self.isRunning else { return }

                    // Phase 4 — Return (450ms, easeInEaseOut)
                    let returnDx = CGFloat.random(in: -0.3...0.3)
                    let returnDy = CGFloat.random(in: -0.2...0.2)
                    self.faceLayer?.applyEyeOffset(dx: returnDx, dy: returnDy, animated: true, duration: 0.45, easing: .easeInEaseOut)
                    self.faceLayer?.applyMouthReaction(openness: 0, animated: true)

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                        self?.tentacleLayer?.applyDrag(dx: returnDx * 0.5, dy: returnDy * 0.5)
                    }
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
