import AppKit
import QuartzCore

final class OrbView: NSView {

    private let glowLayer = GlowLayer()
    private let avatarContainer = CALayer()  // container for body+face+tentacles+effects
    private let bodyLayer = CALayer()
    private let tentacleLayer = TentacleLayer()
    private let effectLayer = EffectLayer()
    private let cookingLayer = CookingLayer()
    private let wizardLayer = WizardLayer()
    private let faceLayer = FaceLayer()
    private let animator = Animator()
    private var lifeAnimator: LifeAnimator?

    // Approve exclamation mark (! above head)
    private let exclamationBar = CAShapeLayer()
    private let exclamationDot = CAShapeLayer()
    private var exclamationVisible = false
    private var exclamationOpacity: CGFloat = 0
    private var exclamationBouncePhase: CGFloat = 0
    private var exclamationTimer: Timer?

    // Speaker/mute icon (pixel-art, shown on hover)
    private let speakerIconLayer = CALayer()
    private let speakerBodyShape = CAShapeLayer()
    private let speakerStatusShape = CAShapeLayer()

    var isMuted: Bool {
        get { UserDefaults.standard.bool(forKey: "avatarMuted") }
        set {
            UserDefaults.standard.set(newValue, forKey: "avatarMuted")
            buildSpeakerPaths()
        }
    }

    private lazy var approveSound: NSSound? = {
        let execURL = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        let candidates = [
            execURL.appendingPathComponent("fah.mp3").path,
            NSHomeDirectory() + "/.local/bin/fah.mp3"
        ]
        for path in candidates {
            if let sound = NSSound(contentsOfFile: path, byReference: true) {
                return sound
            }
        }
        return nil
    }()

    private var currentState: AvatarState = .idle
    private let sessionStartDate = Date()
    private var sleepTimer: DispatchSourceTimer?
    private var successTimer: DispatchSourceTimer?
    private var stateTimeoutTimer: DispatchSourceTimer?

    private let sleepDelay: TimeInterval = 120 // 2 minutes

    /// Body hit rect with ~10% margin, for drag hitbox
    var bodyHitRect: NSRect {
        let margin = bodyLayer.frame.width * 0.10
        return bodyLayer.frame.insetBy(dx: -margin, dy: -margin)
    }

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

        // Avatar container (holds body, tentacles, effects, cooking, face, exclamation)
        layer?.addSublayer(avatarContainer)

        // Body layer: flat colored rectangle, sharp corners
        bodyLayer.backgroundColor = AvatarState.idle.primaryColor.cgColor
        avatarContainer.addSublayer(bodyLayer)

        // Tentacle layer
        avatarContainer.addSublayer(tentacleLayer)

        // Effect layer (above tentacles, below cooking)
        avatarContainer.addSublayer(effectLayer)

        // Cooking layer (above effects, below face)
        avatarContainer.addSublayer(cookingLayer)

        // Wizard layer (above effects, below face — same z as cooking)
        avatarContainer.addSublayer(wizardLayer)

        // Face layer
        avatarContainer.addSublayer(faceLayer)

        // Exclamation mark layers (topmost, above face)
        let exclamColor = AvatarState.approve.primaryColor.cgColor
        exclamationBar.fillColor = exclamColor
        exclamationBar.strokeColor = nil
        exclamationBar.opacity = 0
        avatarContainer.addSublayer(exclamationBar)

        exclamationDot.fillColor = exclamColor
        exclamationDot.strokeColor = nil
        exclamationDot.opacity = 0
        avatarContainer.addSublayer(exclamationDot)

        // Wizard beard: reparent above everything (face, exclamation)
        wizardLayer.beardLayer.removeFromSuperlayer()
        avatarContainer.addSublayer(wizardLayer.beardLayer)

        // Speaker icon (topmost sublayer, shown on hover)
        speakerIconLayer.opacity = 0
        speakerBodyShape.strokeColor = nil
        speakerStatusShape.strokeColor = nil
        speakerIconLayer.addSublayer(speakerBodyShape)
        speakerIconLayer.addSublayer(speakerStatusShape)
        avatarContainer.addSublayer(speakerIconLayer)

        // Set initial expression
        layoutLayers()
        faceLayer.setExpression(.idle, animated: false)
        tentacleLayer.updateForState(.idle, animated: false)
        effectLayer.updateColor(AvatarState.idle.primaryColor.cgColor, animated: false)

        // Start life animations (float timer controls container + glow + breathing)
        lifeAnimator = LifeAnimator(
            faceLayer: faceLayer,
            bodyLayer: bodyLayer,
            tentacleLayer: tentacleLayer,
            effectLayer: effectLayer,
            cookingLayer: cookingLayer,
            wizardLayer: wizardLayer,
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

        // Fatigue timer: update eye bags every 30s
        let fatigueTimer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            self?.updateFatigue()
        }
        RunLoop.main.add(fatigueTimer, forMode: .common)
        updateFatigue()
    }

    override func layout() {
        super.layout()
        layoutLayers()
        updateBasePositions()
    }

    private func layoutLayers() {
        let b = bounds

        // Body dimensions: wide rectangle (~1.9:1 ratio, matching Figma 1483:782)
        let bodyWidth: CGFloat = 140
        let bodyHeight: CGFloat = 74

        // Glow: sized relative to body
        let glowSize = bodyHeight * 1.3
        let glowOrigin = CGPoint(x: (b.width - glowSize) / 2, y: (b.height - glowSize) / 2)
        glowLayer.frame = CGRect(origin: glowOrigin, size: CGSize(width: glowSize, height: glowSize))

        // Container: full bounds (float timer moves its position)
        avatarContainer.frame = b

        // Body: centered, lowered 15px
        let bodyOriginX = (b.width - bodyWidth) / 2
        let bodyOriginY = (b.height - bodyHeight) / 2 - 15
        bodyLayer.frame = CGRect(x: bodyOriginX, y: bodyOriginY, width: bodyWidth, height: bodyHeight)
        bodyLayer.cornerRadius = 0

        // Tentacles: below body, same width
        let tentacleHeight = bodyHeight * 0.3
        tentacleLayer.frame = CGRect(x: bodyOriginX, y: bodyOriginY - tentacleHeight, width: bodyWidth, height: tentacleHeight)

        // Effect layer: full container bounds, positions internally using bodyFrame
        effectLayer.frame = b
        effectLayer.bodyFrame = CGRect(x: bodyOriginX, y: bodyOriginY, width: bodyWidth, height: bodyHeight)

        // Cooking layer: full container bounds, positions internally using bodyFrame
        cookingLayer.frame = b
        cookingLayer.bodyFrame = CGRect(x: bodyOriginX, y: bodyOriginY, width: bodyWidth, height: bodyHeight)

        // Wizard layer: full container bounds, positions internally using bodyFrame
        wizardLayer.frame = b
        wizardLayer.bodyFrame = CGRect(x: bodyOriginX, y: bodyOriginY, width: bodyWidth, height: bodyHeight)

        // Face: same as body
        faceLayer.frame = bodyLayer.frame

        // Speaker icon: bottom-right of body
        layoutSpeakerIcon()
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

        // Cancel timers on any new state
        cancelSuccessTimer()
        cancelStateTimeout()

        // Animate glow color
        glowLayer.updateColor(state.glowColor, intensity: state.glowIntensity, animated: true)

        // Animate body color (wizard states keep idle orange — the outfit covers it)
        if state == .thinking || state == .planning {
            animateBodyColor(for: .idle)
        } else {
            animateBodyColor(for: state)
        }

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

        // Mouth animations: talking for responding, breathing for sleep
        faceLayer.stopTalking()
        faceLayer.stopMouthBreathing()

        if state == .responding {
            faceLayer.startTalking()
        } else if state == .sleep {
            faceLayer.startMouthBreathing()
        }

        // Cooking layer: show on tool state, hide in all other states
        cookingLayer.setVisible(state == .tool, animated: true)

        // Wizard layer: show on thinking/planning, hide otherwise
        wizardLayer.setVisible(state == .thinking || state == .planning, animated: true)

        // Exclamation mark + sound: show on approve, hide otherwise
        if state == .approve {
            if !isMuted {
                approveSound?.stop()
                approveSound?.play()
            }
            showExclamation()
        } else if exclamationVisible {
            hideExclamation()
        }

        // State-specific animations
        animator.stopStateAnimation(on: self.layer!)

        switch state {
        case .success:
            animator.flash(layer: glowLayer)
            scheduleSuccessTimer()
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

        // Safety timeout for states that may not get an explicit exit hook
        scheduleStateTimeoutIfNeeded(state)

        // Reset sleep timer for active states
        if state != .sleep && state != .goodbye {
            resetSleepTimer()
        } else {
            cancelSleepTimer()
        }
    }

    // MARK: - Exclamation Mark (!)

    private func showExclamation() {
        exclamationVisible = true
        exclamationBouncePhase = 0

        let exclamColor = AvatarState.approve.primaryColor.cgColor
        exclamationBar.fillColor = exclamColor
        exclamationDot.fillColor = exclamColor

        // Start bounce animation timer
        if exclamationTimer == nil {
            let timer = Timer(timeInterval: 0.016, repeats: true) { [weak self] _ in
                self?.exclamationTick()
            }
            RunLoop.main.add(timer, forMode: .common)
            exclamationTimer = timer
        }
    }

    private func hideExclamation() {
        exclamationVisible = false
        // Timer will fade out and stop itself
    }

    private func exclamationTick() {
        let dt: CGFloat = 0.016
        exclamationBouncePhase += dt

        // Fade in/out
        let targetO: CGFloat = exclamationVisible ? 1.0 : 0.0
        exclamationOpacity += (targetO - exclamationOpacity) * 0.15
        if exclamationOpacity < 0.01 && !exclamationVisible {
            exclamationOpacity = 0
            exclamationBar.opacity = 0
            exclamationDot.opacity = 0
            exclamationTimer?.invalidate()
            exclamationTimer = nil
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let bw = bodyLayer.frame.width
        let bh = bodyLayer.frame.height
        let bx = bodyLayer.frame.origin.x
        let bodyTop = bodyLayer.frame.maxY

        // Exclamation mark dimensions (8-bit pixel rects, sized to body height)
        let barW = floor(bh * 0.12)
        let barH = floor(bh * 0.40)
        let dotSize = floor(bh * 0.12)
        let gap = floor(bh * 0.06)

        // Follow eye gaze (shift horizontally with eyes, subtle vertical)
        let eyeDx = faceLayer.currentEyeOffsetX
        let eyeDy = faceLayer.currentEyeOffsetY
        let gazeShiftX = eyeDx * bh * 0.04
        let gazeShiftY = eyeDy * bh * 0.02

        let centerX = floor(bx + bw / 2 - barW / 2 + gazeShiftX)

        // Gentle bounce (subtle bob up and down)
        let bounce = floor(sin(exclamationBouncePhase * 3.0) * bh * 0.03)
        let baseY = bodyTop + floor(bh * 0.25) + 8 + gazeShiftY

        // Dot (bottom of exclamation)
        let dotY = baseY + bounce
        exclamationDot.path = CGPath(rect: CGRect(x: centerX, y: dotY, width: dotSize, height: dotSize), transform: nil)

        // Bar (above dot)
        let barY = dotY + dotSize + gap
        exclamationBar.path = CGPath(rect: CGRect(x: centerX, y: barY, width: barW, height: barH), transform: nil)

        exclamationBar.opacity = Float(exclamationOpacity)
        exclamationDot.opacity = Float(exclamationOpacity)

        CATransaction.commit()
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

    // MARK: - Success Auto-Timer

    private func scheduleSuccessTimer() {
        cancelSuccessTimer()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1.5)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            if self.currentState == .success {
                self.transitionTo(.idle)
            }
        }
        successTimer = timer
        timer.resume()
    }

    private func cancelSuccessTimer() {
        successTimer?.cancel()
        successTimer = nil
    }

    // MARK: - State Timeout Safety Net

    private func scheduleStateTimeoutIfNeeded(_ state: AvatarState) {
        let timeout: TimeInterval
        switch state {
        case .approve:  timeout = 30
        case .tool:     timeout = 120
        case .planning: timeout = 120
        case .error:    timeout = 5
        default:       return
        }

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + timeout)
        timer.setEventHandler { [weak self] in
            guard let self = self, self.currentState == state else { return }
            self.transitionTo(.idle)
        }
        stateTimeoutTimer = timer
        timer.resume()
    }

    private func cancelStateTimeout() {
        stateTimeoutTimer?.cancel()
        stateTimeoutTimer = nil
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

    // MARK: - Speaker Icon

    private func layoutSpeakerIcon() {
        let iconW: CGFloat = 18
        let iconH: CGFloat = 14
        let x = bodyLayer.frame.maxX - iconW - 2
        let y = bodyLayer.frame.minY + 2
        speakerIconLayer.frame = CGRect(x: x, y: y, width: iconW, height: iconH)
        buildSpeakerPaths()
    }

    private func buildSpeakerPaths() {
        let px: CGFloat = 2.0
        let ox: CGFloat = 1  // offset for centering
        let oy: CGFloat = 1

        // Speaker body (pixel-art, facing right)
        let body = CGMutablePath()
        // Driver back plate: cols 0-1, rows 2-3
        body.addRect(CGRect(x: ox, y: oy + 2 * px, width: 2 * px, height: 2 * px))
        // Cone mid: col 2, rows 1-4
        body.addRect(CGRect(x: ox + 2 * px, y: oy + 1 * px, width: px, height: 4 * px))
        // Cone wide: col 3, rows 0-5
        body.addRect(CGRect(x: ox + 3 * px, y: oy, width: px, height: 6 * px))
        speakerBodyShape.path = body
        speakerBodyShape.fillColor = NSColor.white.cgColor

        // Status indicator: waves (unmuted) or X (muted)
        let status = CGMutablePath()
        if isMuted {
            // Red pixel-art X
            status.addRect(CGRect(x: ox + 5 * px, y: oy + 4 * px, width: px, height: px))
            status.addRect(CGRect(x: ox + 6 * px, y: oy + 3 * px, width: px, height: px))
            status.addRect(CGRect(x: ox + 7 * px, y: oy + 2 * px, width: px, height: px))
            status.addRect(CGRect(x: ox + 5 * px, y: oy + 2 * px, width: px, height: px))
            status.addRect(CGRect(x: ox + 7 * px, y: oy + 4 * px, width: px, height: px))
            speakerStatusShape.fillColor = NSColor(red: 1, green: 0.25, blue: 0.25, alpha: 1).cgColor
        } else {
            // Two vertical bars as sound waves
            status.addRect(CGRect(x: ox + 5 * px, y: oy + 2 * px, width: px, height: 2 * px))
            status.addRect(CGRect(x: ox + 7 * px, y: oy + 1 * px, width: px, height: 4 * px))
            speakerStatusShape.fillColor = NSColor.white.cgColor
        }
        speakerStatusShape.path = status
    }

    /// Speaker icon frame in avatarContainer coords (with hit margin)
    var speakerIconHitRect: NSRect {
        speakerIconLayer.frame.insetBy(dx: -6, dy: -6)
    }

    var isSpeakerIconVisible: Bool {
        speakerIconLayer.opacity > 0.5
    }

    func showSpeakerIcon(animated: Bool = true) {
        guard speakerIconLayer.opacity < 0.5 else { return }
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = speakerIconLayer.opacity
        anim.toValue = 1.0
        anim.duration = animated ? 0.2 : 0.01
        speakerIconLayer.add(anim, forKey: "speakerFade")
        speakerIconLayer.opacity = 1.0
    }

    func hideSpeakerIcon(animated: Bool = true) {
        guard speakerIconLayer.opacity > 0.5 else { return }
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = speakerIconLayer.opacity
        anim.toValue = 0.0
        anim.duration = animated ? 0.3 : 0.01
        speakerIconLayer.add(anim, forKey: "speakerFade")
        speakerIconLayer.opacity = 0.0
    }

    func toggleMute() {
        isMuted = !isMuted
    }

    // MARK: - Fatigue (Eye Bags)

    private func updateFatigue() {
        let elapsed = Date().timeIntervalSince(sessionStartDate)
        let thickness = min(8.0, 1.0 + 7.0 * log(1.0 + elapsed / 1200.0) / log(10.0))
        faceLayer.setBagThickness(thickness)
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
