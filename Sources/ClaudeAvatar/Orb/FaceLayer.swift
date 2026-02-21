import AppKit
import QuartzCore

final class FaceLayer: CALayer {

    private let leftEye = CAShapeLayer()
    private let rightEye = CAShapeLayer()
    private let leftEyeBorder = CAShapeLayer()
    private let rightEyeBorder = CAShapeLayer()
    private let mouth = CAShapeLayer()

    private let featureColor = NSColor.black.cgColor

    // Current base expression (set by state)
    private var currentState: AvatarState = .idle

    // Eye offset for wander animations (in grid units)
    private var eyeOffsetX: CGFloat = 0
    private var eyeOffsetY: CGFloat = 0

    // Mouth offset (follows eyes at 50%)
    private var mouthOffsetX: CGFloat = 0
    private var mouthOffsetY: CGFloat = 0

    // Squint factor (0 = normal, 1 = fully closed)
    private var squintFactor: CGFloat = 0

    // Mouth reaction: -1 = puckered/frown, 0 = neutral, +1 = wide open/surprised
    private var mouthReactionOpenness: CGFloat = 0

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
        let borderColor = AvatarState.idle.primaryColor.cgColor

        // Borders behind eyes so fill covers inner stroke half → border appears external
        for border in [leftEyeBorder, rightEyeBorder] {
            border.fillColor = nil
            border.strokeColor = borderColor
            border.lineWidth = 10.0  // 5px visible externally (half hidden by fill)
            addSublayer(border)
        }
        for eye in [leftEye, rightEye] {
            eye.fillColor = featureColor
            eye.strokeColor = nil
            addSublayer(eye)
        }
        mouth.fillColor = featureColor
        mouth.strokeColor = nil
        addSublayer(mouth)
    }

    override func layoutSublayers() {
        super.layoutSublayers()
    }

    // Current eye offset (for external elements that follow gaze)
    var currentEyeOffsetX: CGFloat { eyeOffsetX }
    var currentEyeOffsetY: CGFloat { eyeOffsetY }

    // MARK: - Public API


    func setExpression(_ state: AvatarState, animated: Bool) {
        currentState = state
        eyeOffsetX = 0
        eyeOffsetY = 0
        mouthOffsetX = 0
        mouthOffsetY = 0
        squintFactor = 0
        mouthReactionOpenness = 0
        updateEyeBorderColor(for: state, animated: animated)
        applyExpression(animated: animated)
    }

    func applySquint(_ factor: CGFloat, animated: Bool) {
        squintFactor = max(0, min(1, factor))
        let eyes = eyePaths(for: currentState)
        if animated {
            animatePath(layer: leftEye, to: eyes.left, duration: 0.3)
            animatePath(layer: rightEye, to: eyes.right, duration: 0.3)
            animatePath(layer: leftEyeBorder, to: eyes.left, duration: 0.3)
            animatePath(layer: rightEyeBorder, to: eyes.right, duration: 0.3)
        } else {
            leftEye.path = eyes.left
            rightEye.path = eyes.right
            leftEyeBorder.path = eyes.left
            rightEyeBorder.path = eyes.right
        }

    }

    func applyEyeOffset(dx: CGFloat, dy: CGFloat, animated: Bool, duration: CFTimeInterval = 0.6, easing: CAMediaTimingFunctionName = .easeInEaseOut) {
        eyeOffsetX = dx
        eyeOffsetY = dy
        mouthOffsetX = dx * 0.5
        mouthOffsetY = dy * 0.5

        let eyeP = eyePaths(for: currentState)
        let mouthP = reactiveMouthPath(for: currentState)

        if animated {
            animatePath(layer: leftEye, to: eyeP.left, duration: duration, easing: easing)
            animatePath(layer: rightEye, to: eyeP.right, duration: duration, easing: easing)
            animatePath(layer: leftEyeBorder, to: eyeP.left, duration: duration, easing: easing)
            animatePath(layer: rightEyeBorder, to: eyeP.right, duration: duration, easing: easing)
            animatePath(layer: mouth, to: mouthP, duration: duration, easing: easing)
        } else {
            leftEye.path = eyeP.left
            rightEye.path = eyeP.right
            leftEyeBorder.path = eyeP.left
            rightEyeBorder.path = eyeP.right
            mouth.path = mouthP
        }
    }

    func applyMouthReaction(openness: CGFloat, animated: Bool) {
        mouthReactionOpenness = max(-1, min(1, openness))
        let path = reactiveMouthPath(for: currentState)
        if animated {
            animatePath(layer: mouth, to: path, duration: 0.5)
        } else {
            mouth.path = path
        }
    }

    func blink(completion: (() -> Void)? = nil) {
        let closedLeft = closedEyePath(gx: leftEyeBaseX, gy: eyeBaseY + eyeOffsetY)
        let closedRight = closedEyePath(gx: rightEyeBaseX, gy: eyeBaseY + eyeOffsetY)
        let openLeft = leftEye.path
        let openRight = rightEye.path

        // Close eyes + borders
        for layer in [leftEye, leftEyeBorder] {
            let anim = CABasicAnimation(keyPath: "path")
            anim.toValue = closedLeft
            anim.duration = 0.08
            anim.fillMode = .forwards
            anim.isRemovedOnCompletion = false
            layer.add(anim, forKey: "blinkClose")
        }
        for layer in [rightEye, rightEyeBorder] {
            let anim = CABasicAnimation(keyPath: "path")
            anim.toValue = closedRight
            anim.duration = 0.08
            anim.fillMode = .forwards
            anim.isRemovedOnCompletion = false
            layer.add(anim, forKey: "blinkClose")
        }

        // Open eyes after brief hold
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self = self else { return }
            for layer in [self.leftEye, self.leftEyeBorder] {
                layer.removeAnimation(forKey: "blinkClose")
                let anim = CABasicAnimation(keyPath: "path")
                anim.fromValue = closedLeft
                anim.toValue = openLeft
                anim.duration = 0.1
                layer.add(anim, forKey: "blinkOpen")
                layer.path = openLeft
            }
            for layer in [self.rightEye, self.rightEyeBorder] {
                layer.removeAnimation(forKey: "blinkClose")
                let anim = CABasicAnimation(keyPath: "path")
                anim.fromValue = closedRight
                anim.toValue = openRight
                anim.duration = 0.1
                layer.add(anim, forKey: "blinkOpen")
                layer.path = openRight
            }

            completion?()
        }
    }

    // MARK: - Mouth Breathing (sleep)

    func startMouthBreathing() {
        // Remove any in-flight transition animation to avoid conflicts
        mouth.removeAnimation(forKey: "pathMorph")

        let p = px
        let xo = xOff
        let my = mouthBaseY + mouthOffsetY
        let mx = mouthOffsetX

        let wideGW: CGFloat = 3.0
        let narrowGW: CGFloat = 1.5
        let gh: CGFloat = 1.5

        // Center the mouth for both wide and narrow paths
        let wideGX = 6.5 + mx - (wideGW - 3.0) / 2.0
        let narrowGX = 6.5 + mx - (narrowGW - 3.0) / 2.0 + (wideGW - narrowGW) / 2.0

        let widePath = CGPath(rect: CGRect(x: xo + wideGX * p, y: my * p, width: wideGW * p, height: gh * p), transform: nil)
        let narrowPath = CGPath(rect: CGRect(x: xo + narrowGX * p, y: my * p, width: narrowGW * p, height: gh * p), transform: nil)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mouth.path = widePath
        CATransaction.commit()

        let anim = CABasicAnimation(keyPath: "path")
        anim.fromValue = widePath
        anim.toValue = narrowPath
        anim.duration = 1.5
        anim.autoreverses = true
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        mouth.add(anim, forKey: "mouthBreathing")
    }

    func stopMouthBreathing() {
        mouth.removeAnimation(forKey: "mouthBreathing")
    }

    // MARK: - Talking Animation (responding)

    private var talkTimer: Timer?
    private var talkPhase: Int = 0

    func startTalking() {
        guard talkTimer == nil else { return }
        let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.talkTick()
        }
        RunLoop.main.add(timer, forMode: .common)
        talkTimer = timer
    }

    func stopTalking() {
        guard talkTimer != nil else { return }
        talkTimer?.invalidate()
        talkTimer = nil
        // Return mouth to base
        let base = mouthPath(for: currentState)
        animatePath(layer: mouth, to: base, duration: 0.3)
    }

    private func talkTick() {
        talkPhase += 1
        let p = px
        let xo = xOff

        // Semi-random mouth variations to simulate speech (subtler at 150ms tick)
        let baseGW: CGFloat = 5.0
        let baseGH: CGFloat = 1.2
        let baseGX: CGFloat = 5.5
        let baseGY: CGFloat = 4.3

        let widthVar: CGFloat
        let heightVar: CGFloat

        // Every ~8 ticks, do an "emphasis" (bigger mouth)
        if talkPhase % 8 == 0 {
            widthVar = CGFloat.random(in: 0.3...0.8)
            heightVar = CGFloat.random(in: 0.2...0.5)
        } else if talkPhase % 5 == 0 {
            // Occasional brief pause (smaller mouth)
            widthVar = CGFloat.random(in: -0.8...(-0.3))
            heightVar = CGFloat.random(in: -0.3...(-0.1))
        } else {
            // Normal talking variation
            widthVar = CGFloat.random(in: -0.5...0.5)
            heightVar = CGFloat.random(in: -0.15...0.25)
        }

        let gw = baseGW + widthVar
        let gh = max(0.4, baseGH + heightVar)
        let gx = baseGX + mouthOffsetX - widthVar * 0.5
        let gy = baseGY + mouthOffsetY

        let path = CGPath(rect: CGRect(x: xo + gx * p, y: gy * p, width: gw * p, height: gh * p), transform: nil)
        animatePath(layer: mouth, to: path, duration: 0.12)
    }

    /// Yawn animation with anticipation and follow-through
    func yawn(completion: (() -> Void)? = nil) {
        guard currentState == .idle else { completion?(); return }

        // Phase 0 — Anticipation: mouth tightens before opening
        let tightMouth = pixelRect(gx: 7.0 + mouthOffsetX, gy: 4.5 + mouthOffsetY, gw: 2.0, gh: 0.5)
        animatePath(layer: mouth, to: tightMouth, duration: 0.15, easing: .easeOut)

        // Phase 1: mouth opens wide, eyes half-close (after anticipation)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self = self, self.currentState == .idle else { completion?(); return }

            let wideMouth = self.pixelRect(gx: 5.5, gy: 4.0, gw: 5.0, gh: 2.5)
            let squintLeft = self.closedEyePath(gx: self.leftEyeBaseX + self.eyeOffsetX, gy: self.eyeBaseY + self.eyeOffsetY + 0.3)
            let squintRight = self.closedEyePath(gx: self.rightEyeBaseX + self.eyeOffsetX, gy: self.eyeBaseY + self.eyeOffsetY + 0.3)

            self.animatePath(layer: self.mouth, to: wideMouth, duration: 0.5)
            self.animatePath(layer: self.leftEye, to: squintLeft, duration: 0.4)
            self.animatePath(layer: self.rightEye, to: squintRight, duration: 0.4)
            self.animatePath(layer: self.leftEyeBorder, to: squintLeft, duration: 0.4)
            self.animatePath(layer: self.rightEyeBorder, to: squintRight, duration: 0.4)

            // Phase 2: hold the yawn
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self = self, self.currentState == .idle else { completion?(); return }

                // Phase 3: close mouth, open eyes back
                let baseMouth = self.mouthPath(for: self.currentState)
                let eyes = self.eyePaths(for: self.currentState)
                self.animatePath(layer: self.mouth, to: baseMouth, duration: 0.4)
                self.animatePath(layer: self.leftEye, to: eyes.left, duration: 0.5)
                self.animatePath(layer: self.rightEye, to: eyes.right, duration: 0.5)
                self.animatePath(layer: self.leftEyeBorder, to: eyes.left, duration: 0.5)
                self.animatePath(layer: self.rightEyeBorder, to: eyes.right, duration: 0.5)

                // Phase 4 — Follow-through: blink + sigh
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    guard let self = self, self.currentState == .idle else { completion?(); return }
                    // Post-yawn blink
                    self.blink(completion: nil)
                    // Small sigh — slight mouth opening
                    let sighMouth = self.pixelRect(gx: 6.0 + self.mouthOffsetX, gy: 4.5 + self.mouthOffsetY, gw: 3.5, gh: 1.0)
                    self.animatePath(layer: self.mouth, to: sighMouth, duration: 0.2)

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                        guard let self = self else { completion?(); return }
                        let finalMouth = self.mouthPath(for: self.currentState)
                        self.animatePath(layer: self.mouth, to: finalMouth, duration: 0.3)
                        completion?()
                    }
                }
            }
        }
    }

    /// Applies a small random mouth variation (micro-expression)
    func applyMouthTwitch(widthDelta: CGFloat, heightDelta: CGFloat, animated: Bool) {
        guard currentState != .sleep else { return }
        let base = mouthParams(for: currentState)
        let gx = base.gx + mouthOffsetX - widthDelta * 0.5
        let gy = base.gy + mouthOffsetY
        let gw = base.gw + widthDelta
        let gh = max(0.3, base.gh + heightDelta)
        let path = pixelRect(gx: gx, gy: gy, gw: gw, gh: gh)
        if animated {
            animatePath(layer: mouth, to: path, duration: 0.5)
        } else {
            mouth.path = path
        }
    }

    // MARK: - Eye Border Color

    private func updateEyeBorderColor(for state: AvatarState, animated: Bool) {
        let newColor = state.primaryColor.cgColor
        if animated {
            for border in [leftEyeBorder, rightEyeBorder] {
                let anim = CABasicAnimation(keyPath: "strokeColor")
                anim.fromValue = border.strokeColor
                anim.toValue = newColor
                anim.duration = 0.6
                anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                border.add(anim, forKey: "borderColor")
                border.strokeColor = newColor
            }
        } else {
            leftEyeBorder.strokeColor = newColor
            rightEyeBorder.strokeColor = newColor
        }
    }

    // MARK: - Internal

    private func applyExpression(animated: Bool) {
        let eyes = eyePaths(for: currentState)
        let mouthP = mouthPath(for: currentState)

        if animated {
            animatePath(layer: leftEye, to: eyes.left, duration: 0.3)
            animatePath(layer: rightEye, to: eyes.right, duration: 0.3)
            animatePath(layer: leftEyeBorder, to: eyes.left, duration: 0.3)
            animatePath(layer: rightEyeBorder, to: eyes.right, duration: 0.3)
            animatePath(layer: mouth, to: mouthP, duration: 0.3)
        } else {
            leftEye.path = eyes.left
            rightEye.path = eyes.right
            leftEyeBorder.path = eyes.left
            rightEyeBorder.path = eyes.right
            mouth.path = mouthP
        }

    }

    private func animatePath(layer: CAShapeLayer, to path: CGPath, duration: CFTimeInterval = 0.3, easing: CAMediaTimingFunctionName = .easeInEaseOut) {
        let anim = CABasicAnimation(keyPath: "path")
        anim.fromValue = layer.path
        anim.toValue = path
        anim.duration = duration
        anim.timingFunction = CAMediaTimingFunction(name: easing)
        layer.add(anim, forKey: "pathMorph")
        layer.path = path
    }

    // MARK: - Pixel grid helpers

    // Face grid: square pixels, oversized so eyes overflow above body (like original)
    private var faceGridSize: CGFloat { min(bounds.width, bounds.height) * 1.5 }
    private var px: CGFloat { faceGridSize / 16.0 }
    private var xOff: CGFloat { (bounds.width - faceGridSize) / 2.0 }

    private func pixelRect(gx: CGFloat, gy: CGFloat, gw: CGFloat, gh: CGFloat) -> CGPath {
        let p = px
        return CGPath(rect: CGRect(x: xOff + gx * p, y: gy * p, width: gw * p, height: gh * p), transform: nil)
    }

    // MARK: - Base positions (grid coords, Y=0 is bottom)
    // Eyes in upper area (~gy 9), mouth in lower area (~gy 4.5)

    private let leftEyeBaseX: CGFloat = 3.51
    private let rightEyeBaseX: CGFloat = 9.99
    private let eyeBaseY: CGFloat = 9
    private let mouthBaseY: CGFloat = 4.5

    // MARK: - Eye Paths

    private struct EyePaths {
        let left: CGPath
        let right: CGPath
    }

    private func eyePaths(for state: AvatarState) -> EyePaths {
        let ox = eyeOffsetX
        let oy = eyeOffsetY
        let sq = 1.0 - squintFactor * 0.7  // squint reduces height

        switch state {
        case .idle:
            let left = pixelRect(gx: leftEyeBaseX + ox, gy: eyeBaseY + oy, gw: 2.5, gh: 3.0 * sq)
            let right = pixelRect(gx: rightEyeBaseX + ox, gy: eyeBaseY + oy, gw: 2.5, gh: 3.0 * sq)
            return EyePaths(left: left, right: right)

        case .listening:
            // Convergent eyes — closer together for focused attention
            let left = pixelRect(gx: 3.51 + ox, gy: 8.5 + oy, gw: 3, gh: 3.5 * sq)
            let right = pixelRect(gx: 9.49 + ox, gy: 8.5 + oy, gw: 3, gh: 3.5 * sq)
            return EyePaths(left: left, right: right)

        case .thinking:
            // Smaller + higher eyes — reflective gaze
            let left = pixelRect(gx: 4.51 + ox, gy: 10.5 + oy, gw: 2.5, gh: 2.5 * sq)
            let right = pixelRect(gx: 10.99 + ox, gy: 10.5 + oy, gw: 2.5, gh: 2.5 * sq)
            return EyePaths(left: left, right: right)

        case .working:
            let left = pixelRect(gx: leftEyeBaseX + ox, gy: 9.5 + oy, gw: 2.5, gh: 2.0 * sq)
            let right = pixelRect(gx: rightEyeBaseX + ox, gy: 9.5 + oy, gw: 2.5, gh: 2.0 * sq)
            return EyePaths(left: left, right: right)

        case .responding:
            // Slight leftward offset — reading/composing gaze
            let rdx: CGFloat = -0.3
            let left = pixelRect(gx: leftEyeBaseX + ox + rdx, gy: eyeBaseY + oy, gw: 2.5, gh: 3.0 * sq)
            let right = pixelRect(gx: rightEyeBaseX + ox + rdx, gy: eyeBaseY + oy, gw: 2.5, gh: 3.0 * sq)
            return EyePaths(left: left, right: right)

        case .tool:
            // Slightly narrowed focused eyes — determined, cooking face
            let left = pixelRect(gx: 4.01 + ox, gy: 9.5 + oy, gw: 2.5, gh: 2.5 * sq)
            let right = pixelRect(gx: 10.49 + ox, gy: 9.5 + oy, gw: 2.5, gh: 2.5 * sq)
            return EyePaths(left: left, right: right)

        case .approve:
            // Wide alert eyes — waiting, attentive
            let left = pixelRect(gx: 3.01 + ox, gy: 8.5 + oy, gw: 3.0, gh: 4.0 * sq)
            let right = pixelRect(gx: 9.99 + ox, gy: 8.5 + oy, gw: 3.0, gh: 4.0 * sq)
            return EyePaths(left: left, right: right)

        case .error:
            let left = xEyePath(cx: 4.76 + ox, cy: 10.25 + oy)
            let right = xEyePath(cx: 11.24 + ox, cy: 10.25 + oy)
            return EyePaths(left: left, right: right)

        case .success:
            let left = happyEyePath(cx: 4.76 + ox, cy: 10 + oy)
            let right = happyEyePath(cx: 11.24 + ox, cy: 10 + oy)
            return EyePaths(left: left, right: right)

        case .goodbye, .sleep:
            let left = closedEyePath(gx: leftEyeBaseX + ox, gy: 10 + oy)
            let right = closedEyePath(gx: rightEyeBaseX + ox, gy: 10 + oy)
            return EyePaths(left: left, right: right)
        }
    }

    private func closedEyePath(gx: CGFloat, gy: CGFloat) -> CGPath {
        return pixelRect(gx: gx, gy: gy, gw: 2.5, gh: 0.6)
    }

    private func xEyePath(cx: CGFloat, cy: CGFloat) -> CGPath {
        let p = px
        let xo = xOff
        let path = CGMutablePath()
        path.addRect(CGRect(x: xo + (cx - 1.2) * p, y: (cy - 1.2) * p, width: 0.7 * p, height: 0.7 * p))
        path.addRect(CGRect(x: xo + (cx - 0.35) * p, y: (cy - 0.35) * p, width: 0.7 * p, height: 0.7 * p))
        path.addRect(CGRect(x: xo + (cx + 0.5) * p, y: (cy + 0.5) * p, width: 0.7 * p, height: 0.7 * p))
        path.addRect(CGRect(x: xo + (cx + 0.5) * p, y: (cy - 1.2) * p, width: 0.7 * p, height: 0.7 * p))
        path.addRect(CGRect(x: xo + (cx - 1.2) * p, y: (cy + 0.5) * p, width: 0.7 * p, height: 0.7 * p))
        return path
    }

    private func happyEyePath(cx: CGFloat, cy: CGFloat) -> CGPath {
        let p = px
        let xo = xOff
        let path = CGMutablePath()
        path.addRect(CGRect(x: xo + (cx - 1.2) * p, y: (cy + 0.5) * p, width: 0.7 * p, height: 0.7 * p))
        path.addRect(CGRect(x: xo + (cx - 0.5) * p, y: (cy - 0.2) * p, width: 0.7 * p, height: 0.7 * p))
        path.addRect(CGRect(x: xo + (cx + 0.2) * p, y: (cy - 0.8) * p, width: 0.7 * p, height: 0.7 * p))
        path.addRect(CGRect(x: xo + (cx + 0.9) * p, y: (cy - 0.2) * p, width: 0.7 * p, height: 0.7 * p))
        path.addRect(CGRect(x: xo + (cx + 1.6) * p, y: (cy + 0.5) * p, width: 0.7 * p, height: 0.7 * p))
        return path
    }

    // MARK: - Mouth Paths (rectangular)

    private struct MouthParams {
        let gx: CGFloat
        let gy: CGFloat
        let gw: CGFloat
        let gh: CGFloat
    }

    private func mouthParams(for state: AvatarState) -> MouthParams {
        switch state {
        case .idle:       return MouthParams(gx: 6.0, gy: 4.5, gw: 3.5, gh: 0.7)
        case .listening:  return MouthParams(gx: 5.5, gy: 4.5, gw: 4.5, gh: 0.8)
        case .thinking:   return MouthParams(gx: 7.2, gy: 4.5, gw: 2.0, gh: 0.6)  // asymmetric "hmm"
        case .working:    return MouthParams(gx: 6.5, gy: 4.5, gw: 2.5, gh: 0.5)  // tight determination
        case .responding: return MouthParams(gx: 5.5, gy: 4.3, gw: 5.0, gh: 1.2)
        case .tool:       return MouthParams(gx: 6.5, gy: 5.5, gw: 3.0, gh: 0.6)  // slight grin, above apron
        case .approve:    return MouthParams(gx: 6.0, gy: 4.3, gw: 4.0, gh: 1.2)  // slightly open, attentive
        case .error:      return MouthParams(gx: 6.5, gy: 4.5, gw: 3.5, gh: 1.8)  // wider shock
        case .success:    return MouthParams(gx: 5.5, gy: 4.5, gw: 5.5, gh: 0.7)  // wide flat smile
        case .goodbye:    return MouthParams(gx: 6.5, gy: 4.5, gw: 2.5, gh: 0.5)
        case .sleep:      return MouthParams(gx: 6.5, gy: 4.5, gw: 2.5, gh: 0.7)
        }
    }

    private func mouthPath(for state: AvatarState) -> CGPath {
        let p = mouthParams(for: state)
        return pixelRect(gx: p.gx + mouthOffsetX, gy: p.gy + mouthOffsetY, gw: p.gw, gh: p.gh)
    }

    private func reactiveMouthPath(for state: AvatarState) -> CGPath {
        let base = mouthParams(for: state)
        let o = mouthReactionOpenness
        let gw: CGFloat
        let gh: CGFloat

        if o > 0 {
            // Open/surprised: taller and slightly wider
            gh = base.gh + o * 1.8
            gw = base.gw + o * 0.5
        } else if o < 0 {
            // Puckered/frown: shorter and narrower
            gh = max(0.3, base.gh * (1.0 + o * 0.5))
            gw = max(1.0, base.gw * (1.0 + o * 0.4))
        } else {
            gh = base.gh
            gw = base.gw
        }

        // Re-center horizontally based on width change
        let gx = base.gx + mouthOffsetX - (gw - base.gw) * 0.5
        let gy = base.gy + mouthOffsetY
        return pixelRect(gx: gx, gy: gy, gw: gw, gh: gh)
    }
}
