import AppKit
import QuartzCore
import CoreText

final class CookingLayer: CALayer {

    // Body frame in parent coordinate space (set by OrbView)
    var bodyFrame: CGRect = .zero

    private var displayTimer: Timer?
    private var time: CGFloat = 0
    private var frameCount: Int = 0

    // Visibility
    private var currentOpacity: CGFloat = 0
    private var targetOpacity: CGFloat = 0
    private var isVisible = false

    // Chef hat
    private let hatLayer = CAShapeLayer()
    private let hatBrimLayer = CAShapeLayer()
    private let hatPleat1 = CAShapeLayer()
    private let hatPleat2 = CAShapeLayer()
    private var hatEntryProgress: CGFloat = 0 // 0=above, 1=landed

    // Pan
    private let panBody = CAShapeLayer()
    private let panHandle = CAShapeLayer()
    private var panWobblePhase: CGFloat = 0

    // Fire (4 overlapping rotated flames per Figma)
    private let fireCount = 4
    private var fireLayers: [CAShapeLayer] = []
    private var fireColorPhase: Int = 0

    // Apron (grembiule — only during cooking)
    private let apronLayer = CAShapeLayer()
    private let apronSeam = CAShapeLayer()
    private let apronButton1 = CAShapeLayer()
    private let apronButton2 = CAShapeLayer()
    private let apronButton3 = CAShapeLayer()

    // Ingredients (SGA glitch text)
    private let ingredientCount = 6
    private var ingredientLayers: [CATextLayer] = []
    private var ingredientStates: [IngredientState] = []
    // Font names: family = "SGA Font", PostScript = "SGAFont"
    private let sgaFontName = "SGA Font"
    private let ingredientColors: [NSColor] = [
        NSColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 1.0),   // red
        NSColor(red: 1.0, green: 0.9, blue: 0.3, alpha: 1.0),   // yellow
        NSColor(red: 0.3, green: 0.9, blue: 0.4, alpha: 1.0),   // green
        NSColor(red: 1.0, green: 0.5, blue: 0.7, alpha: 1.0),   // pink
        NSColor(red: 0.9, green: 0.3, blue: 0.9, alpha: 1.0),   // magenta
    ]

    private struct IngredientState {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var velocityY: CGFloat = 0
        var character: Character = "a"
        var color: NSColor = .white
        var age: CGFloat = 0
        var lifetime: CGFloat = 1.5
        var active: Bool = false
        var spawnDelay: CGFloat = 0
        var glitchCounter: Int = 0
    }

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
        let figmaGray = NSColor(white: 0.85, alpha: 1.0).cgColor // #d9d9d9

        // Chef hat
        hatLayer.fillColor = NSColor(white: 0.99, alpha: 1.0).cgColor // #fefefe
        hatLayer.strokeColor = nil
        hatLayer.opacity = 0
        addSublayer(hatLayer)

        hatBrimLayer.fillColor = figmaGray
        hatBrimLayer.strokeColor = nil
        hatBrimLayer.opacity = 0
        addSublayer(hatBrimLayer)

        for pleat in [hatPleat1, hatPleat2] {
            pleat.fillColor = figmaGray
            pleat.strokeColor = nil
            pleat.opacity = 0
            addSublayer(pleat)
        }

        // Pan (Figma #d9d9d9)
        panBody.fillColor = figmaGray
        panBody.strokeColor = nil
        panBody.opacity = 0
        addSublayer(panBody)

        panHandle.fillColor = figmaGray
        panHandle.strokeColor = nil
        panHandle.opacity = 0
        addSublayer(panHandle)

        // Fire
        for _ in 0..<fireCount {
            let flame = CAShapeLayer()
            flame.strokeColor = nil
            flame.opacity = 0
            addSublayer(flame)
            fireLayers.append(flame)
        }

        // Apron (Figma #fefefe with #d9d9d9 seam and black buttons)
        apronLayer.fillColor = NSColor(white: 0.99, alpha: 1.0).cgColor
        apronLayer.strokeColor = nil
        apronLayer.opacity = 0
        addSublayer(apronLayer)

        apronSeam.fillColor = figmaGray
        apronSeam.strokeColor = nil
        apronSeam.opacity = 0
        addSublayer(apronSeam)

        for btn in [apronButton1, apronButton2, apronButton3] {
            btn.fillColor = NSColor.black.cgColor
            btn.strokeColor = nil
            btn.opacity = 0
            addSublayer(btn)
        }

        // Ingredients
        for i in 0..<ingredientCount {
            let text = CATextLayer()
            text.fontSize = 16
            text.alignmentMode = .center
            text.contentsScale = 2.0
            text.opacity = 0
            // Try SGA font, fallback to monospace
            if let font = NSFont(name: sgaFontName, size: 16) {
                text.font = font
                text.fontSize = 16
            } else if let font = NSFont(name: "SGAFont", size: 16) {
                text.font = font
                text.fontSize = 16
            } else {
                text.font = NSFont(name: "Menlo", size: 14)
                text.fontSize = 14
            }
            addSublayer(text)
            ingredientLayers.append(text)

            var state = IngredientState()
            state.spawnDelay = CGFloat(i) * 0.3
            ingredientStates.append(state)
        }
    }

    // MARK: - Public API

    func setVisible(_ visible: Bool, animated: Bool) {
        isVisible = visible
        targetOpacity = visible ? 1.0 : 0.0

        if visible {
            // Reset entry animation
            hatEntryProgress = 0
            time = 0
            frameCount = 0
            panWobblePhase = 0
            fireColorPhase = 0

            // Reset ingredients
            for i in 0..<ingredientCount {
                ingredientStates[i].active = false
                ingredientStates[i].spawnDelay = CGFloat(i) * 0.3
                ingredientStates[i].age = 0
            }

            start()
        }

        if !animated {
            currentOpacity = targetOpacity
            applyAllOpacity()
            if !visible { stop() }
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
        frameCount += 1
        guard bodyFrame.width > 0 else { return }

        // Fade opacity
        let opacityLerp: CGFloat = 0.1
        currentOpacity += (targetOpacity - currentOpacity) * opacityLerp
        if currentOpacity < 0.01 && targetOpacity == 0 {
            currentOpacity = 0
            applyAllOpacity()
            stop()
            return
        }
        applyAllOpacity()

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        updateHat(dt: dt)
        updateApron(dt: dt)
        updatePan(dt: dt)
        updateFire(dt: dt)
        updateIngredients(dt: dt)

        CATransaction.commit()
    }

    private func applyAllOpacity() {
        let o = Float(currentOpacity)
        hatLayer.opacity = o
        hatBrimLayer.opacity = o
        hatPleat1.opacity = o
        hatPleat2.opacity = o
        panBody.opacity = o
        panHandle.opacity = o
        apronLayer.opacity = o
        apronSeam.opacity = o
        apronButton1.opacity = o
        apronButton2.opacity = o
        apronButton3.opacity = o
        for flame in fireLayers {
            flame.opacity = o
        }
    }

    // MARK: - Chef Hat (Figma: 839×825 on body 1483×782)

    private func updateHat(dt: CGFloat) {
        let bw = bodyFrame.width
        let bh = bodyFrame.height
        let bx = bodyFrame.origin.x
        let by = bodyFrame.origin.y

        // Figma proportions: 839/1483 = 56.6% width, 825/782 = 105.5% height
        let hatW = floor(bw * 0.566)
        let hatH = floor(bh * 1.055)
        let hatX = floor(bx + (bw - hatW) / 2)

        // Entry animation: drops from above with overshoot bounce
        if hatEntryProgress < 1.0 {
            hatEntryProgress = min(1.0, hatEntryProgress + dt / 0.4)
        }

        let t = hatEntryProgress
        let bounce: CGFloat
        if t < 0.7 {
            bounce = (t / 0.7) * (t / 0.7)
        } else {
            let bt = (t - 0.7) / 0.3
            bounce = 1.0 + 0.15 * sin(bt * .pi)
        }

        // Hat sits ON TOP of body with small gap
        let hatRestY = by + bh + floor(bh * 0.02)
        let hatStartY = hatRestY + bh * 2.0  // start well above
        let hatY = floor(hatStartY + (hatRestY - hatStartY) * bounce)

        hatLayer.path = CGPath(rect: CGRect(x: hatX, y: hatY, width: hatW, height: hatH), transform: nil)

        // Brim: Figma 733/839 = 87.4% of hat width, 40/825 = 4.8% of hat height
        let brimH = floor(hatH * 0.048)
        let brimW = floor(hatW * 0.874)
        let brimX = floor(hatX + (hatW - brimW) / 2)
        hatBrimLayer.path = CGPath(rect: CGRect(x: brimX, y: hatY, width: brimW, height: brimH), transform: nil)

        // Pleats: Figma 40/839 = 4.8% of hat width, 607/825 = 73.6% of hat height
        let pleatW = max(2, floor(hatW * 0.048))
        let pleatH = floor(hatH * 0.736)
        let pleatY = hatY + brimH + floor((hatH - brimH - pleatH) / 2)
        let pleat1X = floor(hatX + hatW * 0.38 - pleatW / 2)
        let pleat2X = floor(hatX + hatW * 0.62 - pleatW / 2)

        hatPleat1.path = CGPath(rect: CGRect(x: pleat1X, y: pleatY, width: pleatW, height: pleatH), transform: nil)
        hatPleat2.path = CGPath(rect: CGRect(x: pleat2X, y: pleatY, width: pleatW, height: pleatH), transform: nil)
    }

    // MARK: - Apron (Figma: 1483×317 on body 1483×782, bottom of body)

    private func updateApron(dt: CGFloat) {
        let bw = bodyFrame.width
        let bh = bodyFrame.height
        let bx = bodyFrame.origin.x
        let by = bodyFrame.origin.y

        // Figma: apron same width as body, 317/782 = 40.5% of body height
        let apronH = floor(bh * 0.405)
        apronLayer.path = CGPath(rect: CGRect(x: bx, y: by, width: bw, height: apronH), transform: nil)

        // Seam: Figma 17/1483 = 1.1% width, 228/317 = 71.9% of apron height
        let seamW = max(2, floor(bw * 0.011))
        let seamH = floor(apronH * 0.719)
        let seamX = floor(bx + bw / 2 - seamW / 2)
        let seamY = by + floor((apronH - seamH) / 2)
        apronSeam.path = CGPath(rect: CGRect(x: seamX, y: seamY, width: seamW, height: seamH), transform: nil)

        // Buttons: Figma 37×40, 3 buttons evenly spaced vertically, to the right of seam
        let btnW = max(3, floor(bw * 0.025))
        let btnH = max(3, floor(bh * 0.051))
        let btnX = seamX + seamW + 3
        let btnSpacing = seamH / 4.0
        let btnBaseY = seamY + btnSpacing - btnH / 2

        apronButton1.path = CGPath(rect: CGRect(x: btnX, y: btnBaseY, width: btnW, height: btnH), transform: nil)
        apronButton2.path = CGPath(rect: CGRect(x: btnX, y: btnBaseY + btnSpacing, width: btnW, height: btnH), transform: nil)
        apronButton3.path = CGPath(rect: CGRect(x: btnX, y: btnBaseY + btnSpacing * 2, width: btnW, height: btnH), transform: nil)
    }

    // MARK: - Pan (cached positions for fire/ingredient use)

    private var cachedPanX: CGFloat = 0
    private var cachedPanY: CGFloat = 0      // with wobble (for ingredients)
    private var cachedPanBaseY: CGFloat = 0  // without wobble (for fire)
    private var cachedPanW: CGFloat = 0
    private var cachedPanH: CGFloat = 0

    private func updatePan(dt: CGFloat) {
        panWobblePhase += dt * 2.5 * 2.0 * .pi

        let bw = bodyFrame.width
        let bh = bodyFrame.height
        let bx = bodyFrame.origin.x
        let by = bodyFrame.origin.y

        let panW = floor(bw * 0.35)
        let panH = floor(bh * 0.18)
        let panX = floor(bx - panW - bw * 0.03) // to the LEFT of body
        let panBaseY = floor(by + bh * 0.3) + 5
        let wobble = floor(sin(panWobblePhase) * bh * 0.04)
        let panY = panBaseY + wobble

        // Cache for fire/ingredients
        cachedPanX = panX
        cachedPanY = panY
        cachedPanBaseY = panBaseY  // stable Y for fire
        cachedPanW = panW
        cachedPanH = panH

        panBody.path = CGPath(rect: CGRect(x: panX, y: panY, width: panW, height: panH), transform: nil)

        // Handle: extends right toward avatar body
        let handleW = floor(bw * 0.08)
        let handleH = floor(panH * 0.35)
        let handleX = panX + panW
        let handleY = panY + floor((panH - handleH) / 2)

        panHandle.path = CGPath(rect: CGRect(x: handleX, y: handleY, width: handleW, height: handleH), transform: nil)
    }

    // MARK: - Fire (4 overlapping rotated flames, Figma-matched)
    // Flames are clustered and overlap, each with rotation. Anchored below pan.

    private func updateFire(dt: CGFloat) {
        // Color shift every ~10 frames
        if frameCount % 10 == 0 {
            fireColorPhase += 1
        }

        let bh = bodyFrame.height

        // Fire group dimensions (from Figma bounding box, scaled up to spread flames apart)
        let fireGroupW = bh * 0.20
        let fireGroupH = bh * 0.34

        // Fire group: centered under pan, top at pan bottom
        let fireMidX = cachedPanX + cachedPanW * 0.5
        let fireGroupLeft = fireMidX - fireGroupW / 2
        let fireGroupTop = cachedPanBaseY  // top of fire = pan bottom

        // Figma flame specs: (unrotated w/h relative to bh, angle°, center x/y relative to fire group)
        // Centers derived from Figma container positions (all at left:0 top:0, centered within)
        let flameScale: CGFloat = 1.6  // scale up individual flame sizes
        let specs: [(w: CGFloat, h: CGFloat, deg: CGFloat, cx: CGFloat, cy: CGFloat)] = [
            (0.0819 * flameScale, 0.1381 * flameScale, -31.94, 0.500, 0.328),  // red
            (0.0585 * flameScale, 0.1000 * flameScale,  60.0,  0.406, 0.206),  // dark orange
            (0.0458 * flameScale, 0.0784 * flameScale,  -9.55, 0.204, 0.174),  // golden yellow
            (0.0819 * flameScale, 0.2312 * flameScale,  15.0,  0.487, 0.500),  // orange (tallest)
        ]

        let colors: [CGColor] = [
            NSColor(red: 0.973, green: 0.039, blue: 0.039, alpha: 1.0).cgColor,  // #f80a0a
            NSColor(red: 0.973, green: 0.286, blue: 0.039, alpha: 1.0).cgColor,  // #f8490a
            NSColor(red: 0.973, green: 0.737, blue: 0.039, alpha: 1.0).cgColor,  // #f8bc0a
            NSColor(red: 0.973, green: 0.600, blue: 0.039, alpha: 1.0).cgColor,  // #f8990a
        ]

        // Draw tallest (index 3) first so it's behind
        let drawOrder = [3, 0, 1, 2]

        for order in 0..<fireCount {
            let i = drawOrder[order]
            let s = specs[i]
            let w = floor(bh * s.w)
            let h = floor(bh * s.h)
            let angle = s.deg * .pi / 180.0

            // Subtle height flicker (sinusoidal, ±12%)
            let flicker = 1.0 + sin(CGFloat(frameCount) * 0.25 + CGFloat(i) * 2.1) * 0.12
            let actualH = floor(h * flicker)

            // Gentle rotation sway (±3° oscillation)
            let sway = sin(CGFloat(frameCount) * 0.15 + CGFloat(i) * 1.3) * 0.05
            let actualAngle = angle + sway

            // Flame center in CA coordinates (flipped so flames grow upward toward pan)
            let cx = fireGroupLeft + s.cx * fireGroupW
            let cy = fireGroupTop - (1.0 - s.cy) * fireGroupH

            // Rectangle centered at (cx, cy)
            let rect = CGRect(x: cx - w / 2, y: cy - actualH / 2, width: w, height: actualH)

            // Rotate around rectangle center
            var t = CGAffineTransform.identity
            t = t.translatedBy(x: cx, y: cy)
            t = t.rotated(by: actualAngle)
            t = t.translatedBy(x: -cx, y: -cy)
            fireLayers[i].path = CGPath(rect: rect, transform: &t)

            // Color flicker
            let colorIdx = (i + fireColorPhase) % colors.count
            fireLayers[i].fillColor = colors[colorIdx]
        }
    }

    // MARK: - Ingredients (SGA glitch characters rising from pan)

    private func updateIngredients(dt: CGFloat) {
        let spawnY = cachedPanY + cachedPanH // top of pan

        for i in 0..<ingredientCount {
            var s = ingredientStates[i]

            if !s.active {
                s.spawnDelay -= dt
                if s.spawnDelay <= 0 {
                    // Spawn
                    s.active = true
                    s.x = cachedPanX + CGFloat.random(in: cachedPanW * 0.15...cachedPanW * 0.85)
                    s.y = spawnY
                    s.velocityY = CGFloat.random(in: 40...70) // upward speed
                    s.character = randomSGACharacter()
                    s.color = ingredientColors.randomElement() ?? .white
                    s.age = 0
                    s.lifetime = CGFloat.random(in: 1.2...2.0)
                    s.glitchCounter = 0

                    ingredientLayers[i].foregroundColor = s.color.cgColor
                    ingredientLayers[i].string = String(s.character)
                }
            }

            if s.active {
                s.age += dt

                // Rise with deceleration
                s.velocityY *= 0.98
                s.y += s.velocityY * dt

                // Slight horizontal drift
                s.x += CGFloat.random(in: -0.5...0.5)

                // Glitch: change character every ~8 frames
                s.glitchCounter += 1
                if s.glitchCounter % 8 == 0 {
                    s.character = randomSGACharacter()
                    ingredientLayers[i].string = String(s.character)
                }

                // Position
                ingredientLayers[i].frame = CGRect(x: floor(s.x), y: floor(s.y), width: 20, height: 20)

                // Fade: full opacity in middle, fade at start and end
                let lifeRatio = s.age / s.lifetime
                let fadeIn = min(lifeRatio / 0.15, 1.0)
                let fadeOut = max(1.0 - (lifeRatio - 0.7) / 0.3, 0.0)
                ingredientLayers[i].opacity = Float(min(fadeIn, fadeOut) * currentOpacity)

                // Respawn when lifetime exceeded
                if s.age >= s.lifetime {
                    s.active = false
                    s.spawnDelay = CGFloat.random(in: 0.1...0.4)
                    ingredientLayers[i].opacity = 0
                }
            }

            ingredientStates[i] = s
        }
    }

    private func randomSGACharacter() -> Character {
        let letters = "abcdefghijklmnopqrstuvwxyz"
        return letters.randomElement() ?? "a"
    }
}
