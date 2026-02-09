import AppKit
import QuartzCore

final class OrbView: NSView {

    private let glowLayer = GlowLayer()
    private let avatarContainer = CALayer()  // container for body+face+tentacles+effects
    private let bodyLayer = CALayer()
    private let tentacleLayer = TentacleLayer()
    private let effectLayer = EffectLayer()
    private let faceLayer = FaceLayer()
    private let animator = Animator()
    private var lifeAnimator: LifeAnimator?

    private var currentState: AvatarState = .idle
    private var sleepTimer: DispatchSourceTimer?

    private let sleepDelay: TimeInterval = 120 // 2 minutes

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        // Glow layer (outermost, on root)
        layer?.addSublayer(glowLayer)

        // Avatar container (holds body, tentacles, effects, face)
        layer?.addSublayer(avatarContainer)

        // Body layer: flat colored rectangle, sharp corners
        bodyLayer.backgroundColor = AvatarState.idle.primaryColor.cgColor
        avatarContainer.addSublayer(bodyLayer)

        // Tentacle layer
        avatarContainer.addSublayer(tentacleLayer)

        // Effect layer (above tentacles, below face)
        avatarContainer.addSublayer(effectLayer)

        // Face layer (topmost)
        avatarContainer.addSublayer(faceLayer)

        // Set initial expression
        layoutLayers()
        faceLayer.setExpression(.idle, animated: false)
        tentacleLayer.updateForState(.idle, animated: false)
        effectLayer.updateColor(AvatarState.idle.primaryColor.cgColor, animated: false)

        // Breathing is now timer-based in LifeAnimator — no CA animation needed

        // Start life animations (float timer controls container + glow + breathing)
        lifeAnimator = LifeAnimator(
            faceLayer: faceLayer,
            bodyLayer: bodyLayer,
            tentacleLayer: tentacleLayer,
            effectLayer: effectLayer,
            glowLayer: glowLayer,
            avatarContainer: avatarContainer
        )
        updateBasePositions()
        lifeAnimator?.updateForState(.idle)
        lifeAnimator?.start()

        // Start tentacle animation
        tentacleLayer.start()

        // Start effect layer animation
        effectLayer.start()

        // Start sleep timer
        resetSleepTimer()
    }

    override func layout() {
        super.layout()
        layoutLayers()
        updateBasePositions()
    }

    private func layoutLayers() {
        let b = bounds

        // Avatar content area: ~1/3 of window, centered
        let contentSize = b.width / 3.0

        // Glow: tight around content area
        let glowSize = contentSize * 0.66
        let glowOrigin = CGPoint(x: (b.width - glowSize) / 2, y: (b.height - glowSize) / 2)
        glowLayer.frame = CGRect(origin: glowOrigin, size: CGSize(width: glowSize, height: glowSize))

        // Container: full bounds (float timer moves its position)
        avatarContainer.frame = b

        // Body: wide rectangle, centered in container, shifted up for tentacles
        let bodyWidth = contentSize * 0.6
        let bodyHeight = bodyWidth * 0.65
        let bodyOriginX = (b.width - bodyWidth) / 2
        let bodyOriginY = (b.height - bodyHeight) / 2 + contentSize * 0.08
        bodyLayer.frame = CGRect(x: bodyOriginX, y: bodyOriginY, width: bodyWidth, height: bodyHeight)
        bodyLayer.cornerRadius = 0

        // Tentacles: below body, same width
        let tentacleHeight = bodyHeight * 0.3
        tentacleLayer.frame = CGRect(x: bodyOriginX, y: bodyOriginY - tentacleHeight, width: bodyWidth, height: tentacleHeight)

        // Effect layer: full container bounds, positions internally using bodyFrame
        effectLayer.frame = b
        effectLayer.bodyFrame = CGRect(x: bodyOriginX, y: bodyOriginY, width: bodyWidth, height: bodyHeight)

        // Face: same as body
        faceLayer.frame = bodyLayer.frame
    }

    private func updateBasePositions() {
        lifeAnimator?.containerBasePosition = avatarContainer.position
        lifeAnimator?.glowBasePosition = glowLayer.position
    }

    func transitionTo(_ state: AvatarState) {
        // Wake from sleep if any real state comes in
        if currentState == .sleep && state != .sleep && state != .goodbye {
            performWake(to: state)
            return
        }

        guard state != currentState else { return }
        let previousState = currentState
        currentState = state

        // Animate glow color
        glowLayer.updateColor(state.glowColor, intensity: state.glowIntensity, animated: true)

        // Animate body color
        animateBodyColor(for: state)

        // Animate face expression
        faceLayer.setExpression(state, animated: true)

        // Update tentacles
        tentacleLayer.updateForState(state, animated: true)

        // Update effect layer color
        effectLayer.updateColor(state.primaryColor.cgColor, animated: true)

        // Update float + spin + breathing params + effects
        lifeAnimator?.updateForState(state)

        // Life animations: start/stop based on state
        if state.isAlive {
            lifeAnimator?.start()
        } else {
            lifeAnimator?.stop()
        }

        // Sleep mouth breathing
        faceLayer.stopTalking()
        faceLayer.stopMouthBreathing()

        if state == .sleep {
            faceLayer.startMouthBreathing()
        }

        // Spin impulse on active state transitions
        if state != .idle && state != .sleep && state != .goodbye && previousState != .goodbye {
            lifeAnimator?.addSpinImpulse()
        }

        // State-specific animations
        animator.stopStateAnimation(on: self.layer!)

        switch state {
        case .success:
            animator.flash(layer: glowLayer)
        case .goodbye:
            animator.fadeOut(layer: self.layer!) {
                NotificationCenter.default.post(name: .avatarShouldHide, object: nil)
            }
        case .idle:
            if previousState == .goodbye {
                animator.fadeIn(layer: self.layer!)
            }
        default:
            break
        }

        // Reset sleep timer for active states
        if state != .sleep && state != .goodbye {
            resetSleepTimer()
        } else {
            cancelSleepTimer()
        }
    }

    // MARK: - Sleep

    private func resetSleepTimer() {
        cancelSleepTimer()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + sleepDelay)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            if self.currentState == .idle {
                self.transitionTo(.sleep)
            }
        }
        sleepTimer = timer
        timer.resume()
    }

    private func cancelSleepTimer() {
        sleepTimer?.cancel()
        sleepTimer = nil
    }

    private func performWake(to state: AvatarState) {
        currentState = .idle
        faceLayer.setExpression(.idle, animated: true)
        faceLayer.stopMouthBreathing()
        faceLayer.stopTalking()
        glowLayer.updateColor(AvatarState.idle.glowColor, intensity: AvatarState.idle.glowIntensity, animated: true)
        animateBodyColor(for: .idle)
        tentacleLayer.updateForState(.idle, animated: true)
        effectLayer.updateColor(AvatarState.idle.primaryColor.cgColor, animated: true)
        lifeAnimator?.updateForState(.idle)
        lifeAnimator?.start()

        if state != .idle {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.transitionTo(state)
            }
        } else {
            resetSleepTimer()
        }
    }

    // MARK: - Body Color

    private func animateBodyColor(for state: AvatarState) {
        let newColor = state.primaryColor.cgColor
        let anim = CABasicAnimation(keyPath: "backgroundColor")
        anim.fromValue = bodyLayer.backgroundColor
        anim.toValue = newColor
        anim.duration = 0.6
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        bodyLayer.add(anim, forKey: "bodyColorTransition")
        bodyLayer.backgroundColor = newColor
    }
}

extension Notification.Name {
    static let avatarShouldHide = Notification.Name("avatarShouldHide")
    static let avatarShouldShow = Notification.Name("avatarShouldShow")
}
