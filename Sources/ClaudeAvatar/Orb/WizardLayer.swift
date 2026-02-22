import AppKit
import QuartzCore
import CoreText

final class WizardLayer: CALayer {

    // Body frame in parent coordinate space (set by OrbView)
    var bodyFrame: CGRect = .zero

    private var displayTimer: Timer?
    private var time: CGFloat = 0
    private var frameCount: Int = 0

    // Visibility
    private var currentOpacity: CGFloat = 0
    private var targetOpacity: CGFloat = 0
    private var isVisible = false

    // Wizard hat
    private let hatCone = CAShapeLayer()   // pentagonal cone (lighter purple)
    private let hatBrim = CAShapeLayer()   // rectangular band (darker purple)
    private var coneStarLayers: [CAShapeLayer] = []  // 7 stars on cone
    private var brimStarLayers: [CAShapeLayer] = []  // 5 stars on brim
    private var hatEntryProgress: CGFloat = 0

    // Beard (single path, all rects combined) — reparented above face by OrbView
    let beardLayer = CAShapeLayer()

    // Robe/toga
    private let robeLayer = CAShapeLayer()
    private var robeStarLayers: [CAShapeLayer] = []

    // Magic orb (left of body, like pan)
    private let orbOuter = CAShapeLayer()
    private let orbMiddle = CAShapeLayer()
    private let orbInner = CAShapeLayer()
    private let orbGlyph = CATextLayer()
    private var orbBobPhase: CGFloat = 0

    // Particles
    private let particleCount = 6
    private var particleLayers: [CATextLayer] = []
    private var particleStates: [ParticleState] = []
    private let sgaFontName = "SGA Font"
    private let particleColors: [NSColor] = [
        NSColor(red: 0.302, green: 0.878, blue: 1.00, alpha: 1.0),  // #4de0ff bright cyan
        NSColor(red: 0.302, green: 0.659, blue: 1.00, alpha: 1.0),  // #4da8ff sky blue
        NSColor(red: 0.102, green: 0.239, blue: 0.651, alpha: 1.0), // #1a3da6 dark blue
        NSColor(red: 0.200, green: 0.800, blue: 0.600, alpha: 1.0), // #33cc99 sea green
        NSColor(red: 0.302, green: 0.920, blue: 0.780, alpha: 1.0), // #4debc7 mint green
    ]

    // Orb color cycling
    private var orbColorPhase: CGFloat = 0

    // Colors
    private let coneColor = NSColor(red: 0.439, green: 0.239, blue: 0.863, alpha: 1.0).cgColor  // #703ddc uniform purple
    private let brimColor = NSColor(red: 0.439, green: 0.239, blue: 0.863, alpha: 1.0).cgColor  // #703ddc
    private let robeColor = NSColor(red: 0.439, green: 0.239, blue: 0.863, alpha: 1.0).cgColor  // #703ddc
    private let starColor = NSColor(red: 1.0, green: 0.784, blue: 0.275, alpha: 1.0).cgColor    // #ffc846 golden yellow

    private struct ParticleState {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var velocityX: CGFloat = 0
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
        // Wizard hat cone (lighter purple, pentagonal shape)
        hatCone.fillColor = coneColor
        hatCone.strokeColor = nil
        hatCone.opacity = 0
        addSublayer(hatCone)

        // Hat brim (darker purple, rectangle)
        hatBrim.fillColor = brimColor
        hatBrim.strokeColor = nil
        hatBrim.opacity = 0
        addSublayer(hatBrim)

        // Cone stars (7, various sizes — matching Figma stelleCappello)
        for _ in 0..<7 {
            let star = CAShapeLayer()
            star.fillColor = starColor
            star.strokeColor = nil
            star.opacity = 0
            addSublayer(star)
            coneStarLayers.append(star)
        }

        // Brim stars (5, matching Figma stelleBordoCappello — big+medium, skip tiniest)
        for _ in 0..<5 {
            let star = CAShapeLayer()
            star.fillColor = starColor
            star.strokeColor = nil
            star.opacity = 0
            addSublayer(star)
            brimStarLayers.append(star)
        }

        // Beard (single combined shape)
        beardLayer.fillColor = NSColor(white: 0.99, alpha: 1.0).cgColor // #fefefe
        beardLayer.strokeColor = nil
        beardLayer.opacity = 0
        addSublayer(beardLayer)

        // Robe
        robeLayer.fillColor = robeColor
        robeLayer.strokeColor = nil
        robeLayer.opacity = 0
        addSublayer(robeLayer)

        // Robe stars (9 yellow stars)
        for _ in 0..<9 {
            let star = CAShapeLayer()
            star.fillColor = starColor
            star.strokeColor = nil
            star.opacity = 0
            addSublayer(star)
            robeStarLayers.append(star)
        }

        // Magic orb layers (outer, middle, inner)
        for orb in [orbOuter, orbMiddle, orbInner] {
            orb.fillColor = brimColor
            orb.strokeColor = nil
            orb.opacity = 0
            addSublayer(orb)
        }

        // Orb center glyph
        orbGlyph.fontSize = 18
        orbGlyph.alignmentMode = .center
        orbGlyph.contentsScale = 2.0
        orbGlyph.foregroundColor = NSColor(white: 0.99, alpha: 1.0).cgColor
        orbGlyph.opacity = 0
        if let font = NSFont(name: sgaFontName, size: 18) {
            orbGlyph.font = font
            orbGlyph.fontSize = 18
        } else if let font = NSFont(name: "SGAFont", size: 18) {
            orbGlyph.font = font
            orbGlyph.fontSize = 18
        } else {
            orbGlyph.font = NSFont(name: "Menlo", size: 16)
            orbGlyph.fontSize = 16
        }
        orbGlyph.string = "w"
        addSublayer(orbGlyph)

        // Particles
        for i in 0..<particleCount {
            let text = CATextLayer()
            text.fontSize = 14
            text.alignmentMode = .center
            text.contentsScale = 2.0
            text.opacity = 0
            if let font = NSFont(name: sgaFontName, size: 14) {
                text.font = font
                text.fontSize = 14
            } else if let font = NSFont(name: "SGAFont", size: 14) {
                text.font = font
                text.fontSize = 14
            } else {
                text.font = NSFont(name: "Menlo", size: 12)
                text.fontSize = 12
            }
            addSublayer(text)
            particleLayers.append(text)

            var state = ParticleState()
            state.spawnDelay = CGFloat(i) * 0.35
            particleStates.append(state)
        }
    }

    // MARK: - Public API

    func setVisible(_ visible: Bool, animated: Bool) {
        isVisible = visible
        targetOpacity = visible ? 1.0 : 0.0

        if visible {
            hatEntryProgress = 0
            time = 0
            frameCount = 0
            orbBobPhase = 0
            orbColorPhase = 0

            for i in 0..<particleCount {
                particleStates[i].active = false
                particleStates[i].spawnDelay = CGFloat(i) * 0.35
                particleStates[i].age = 0
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
        updateBeard(dt: dt)
        updateRobe(dt: dt)
        updateOrb(dt: dt)
        updateParticles(dt: dt)

        CATransaction.commit()
    }

    private func applyAllOpacity() {
        let o = Float(currentOpacity)
        hatCone.opacity = o
        hatBrim.opacity = o
        for star in coneStarLayers { star.opacity = o }
        for star in brimStarLayers { star.opacity = o }
        beardLayer.opacity = o
        robeLayer.opacity = o
        for star in robeStarLayers { star.opacity = o }
        orbOuter.opacity = o
        orbMiddle.opacity = o
        orbInner.opacity = o
        orbGlyph.opacity = o
    }

    // MARK: - Wizard Hat (Figma-matched pentagonal cone + brim)
    //
    // From Figma (585:161 cappelloMago):
    //   puntaCappello (cone): 1702×906.5 — pentagonal vector, lighter purple
    //   bordoCappello (brim): 1293×333 — rectangle, #703ddc
    //   Body reference: 1483×782

    private func updateHat(dt: CGFloat) {
        let bw = bodyFrame.width
        let bh = bodyFrame.height
        let bx = bodyFrame.origin.x
        let by = bodyFrame.origin.y

        // Entry bounce (same as CookingLayer)
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

        // --- Brim ---
        // Figma: 1293/1483 = 87.2% body width, 333/782 = 42.6% body height
        // Scale down height for our small avatar (keep proportional but cap)
        let brimW = floor(bw * 0.872)
        let brimH = floor(bh * 0.25)  // slightly smaller for readability at scale
        let brimX = floor(bx + (bw - brimW) / 2)

        // Brim sits on top of body with small overlap
        let brimRestY = by + bh - floor(bh * 0.02) + 1
        let brimStartY = brimRestY + bh * 2.0
        let brimY = floor(brimStartY + (brimRestY - brimStartY) * bounce)

        hatBrim.path = CGPath(rect: CGRect(x: brimX, y: brimY, width: brimW, height: brimH), transform: nil)

        // --- Cone (pentagonal shape with droopy right tip) ---
        // Figma: 1702/1483 = 114.8% body width, 906.5/782 = 115.9% body height
        let coneW = floor(bw * 1.148)
        let coneH = floor(bh * 1.0)  // slightly shorter for avatar scale
        let coneBaseY = brimY + brimH  // cone sits on top of brim

        // Cone left edge is offset right relative to brim
        // Figma: cone left = brim left + 135.5/1293 of brim = +10.5%
        let coneLeftX = floor(brimX + brimW * 0.105)

        // Polygon vertices (normalized to cone bounding box, CA coordinates y-up)
        // Derived from Figma Vector 585:36 screenshot:
        //   0: bottom-left (base left)
        //   1: upper-left (left edge, angled inward)
        //   2: peak (top center, slightly right of center)
        //   3: right tip (droopy tip, far right, mid-height)
        //   4: right indent (where cone meets brim, concave)
        //   5: bottom-right (base right)
        let vertices: [(CGFloat, CGFloat)] = [
            (0.00, 0.00),   // 0: bottom-left
            (0.08, 0.62),   // 1: upper-left
            (0.49, 1.00),   // 2: peak
            (1.00, 0.54),   // 3: right tip (droopy!)
            (0.60, 0.32),   // 4: right indent
            (0.60, 0.00),   // 5: bottom-right
        ]

        let conePath = CGMutablePath()
        for (i, v) in vertices.enumerated() {
            let px = floor(coneLeftX + v.0 * coneW)
            let py = floor(coneBaseY + v.1 * coneH)
            if i == 0 {
                conePath.move(to: CGPoint(x: px, y: py))
            } else {
                conePath.addLine(to: CGPoint(x: px, y: py))
            }
        }
        conePath.closeSubpath()
        hatCone.path = conePath

        // --- Cone stars (7 stars, Figma positions normalized to cone bounds) ---
        // From Figma stelleCappello: Star 1-7 with positions/sizes relative to cone
        let coneStarSpecs: [(x: CGFloat, y: CGFloat, size: CGFloat, rot: CGFloat)] = [
            (0.10, 0.50, 0.20,  0.15),  // Star 1: big, lower-left
            (0.49, 0.64, 0.19, -0.20),  // Star 2: big, center-right
            (0.34, 0.35, 0.12,  0.40),  // Star 3: medium, center
            (0.32, 0.78, 0.09, -0.10),  // Star 6: small, lower-center
            (0.27, 0.36, 0.07,  0.55),  // Star 7: small, upper-left-ish
            (0.78, 0.26, 0.08, -0.35),  // Star 4: small, right side
            (0.58, 0.08, 0.11,  0.25),  // Star 5: medium, near peak
        ]
        for (i, spec) in coneStarSpecs.enumerated() where i < coneStarLayers.count {
            let sx = floor(coneLeftX + spec.x * coneW)
            let sy = floor(coneBaseY + spec.y * coneH)
            let ss = floor(spec.size * coneH)
            coneStarLayers[i].path = fivePointStarPath(cx: sx, cy: sy, size: ss, rotation: spec.rot)
        }

        // --- Brim stars (5 visible stars) ---
        let brimStarSpecs: [(x: CGFloat, y: CGFloat, size: CGFloat, rot: CGFloat)] = [
            (0.10, 0.50, 0.65,  0.10),  // big star, left
            (0.82, 0.55, 0.60, -0.15),  // big star, right
            (0.76, 0.25, 0.30,  0.30),  // medium, right-center
            (0.43, 0.35, 0.22, -0.25),  // small, center
            (0.55, 0.70, 0.15,  0.45),  // tiny, center-low
        ]
        for (i, spec) in brimStarSpecs.enumerated() where i < brimStarLayers.count {
            let sx = floor(brimX + spec.x * brimW)
            let sy = floor(brimY + spec.y * brimH)
            let ss = floor(spec.size * brimH)
            brimStarLayers[i].path = fivePointStarPath(cx: sx, cy: sy, size: ss, rotation: spec.rot)
        }
    }

    // MARK: - Beard (#fefefe, Figma 585:109 pixel-art staircase)
    //
    // Boolean union of rectangles: wide at top, tapering to tip.
    // Each rect: (dx, dy, w, h) — dx/w as fractions of bodyWidth,
    // dy/h as fractions of bodyHeight. dx = center offset from body center,
    // dy = offset above(+)/below(-) the widest bar top edge.

    private let beardRects: [(dx: CGFloat, dy: CGFloat, w: CGFloat, h: CGFloat)] = [
        // Upper frame (sideburns + top bar around mouth hole)
        // Columns symmetric at ±0.205 so the hole centers on the mouth
        ( 0.000,  0.274, 0.456, 0.091),   // top center bar (spans between column outers)
        (-0.205,  0.274, 0.048, 0.547),   // left column
        ( 0.205,  0.274, 0.048, 0.547),   // right column
        (-0.247,  0.168, 0.078, 0.168),   // left upper block (sideburn, +3px inward)
        ( 0.247,  0.168, 0.078, 0.168),   // right upper block (sideburn, -3px inward)
        // Main horizontal bars (tapering staircase)
        ( 0.000,  0.000, 0.763, 0.188),   // widest bar (anchor)
        ( 0.000, -0.088, 0.591, 0.188),
        ( 0.000, -0.197, 0.382, 0.188),
        ( 0.000, -0.330, 0.264, 0.188),
        ( 0.000, -0.418, 0.169, 0.188),
        ( 0.000, -0.534, 0.109, 0.188),
        // Tip (slightly right-shifted per Figma)
        ( 0.022, -0.657, 0.065, 0.134),
        ( 0.057, -0.723, 0.065, 0.102),
        ( 0.089, -0.696, 0.037, 0.059),
    ]

    private func updateBeard(dt: CGFloat) {
        let bw = bodyFrame.width
        let bh = bodyFrame.height
        let bx = bodyFrame.origin.x
        let by = bodyFrame.origin.y
        let midX = bx + bw / 2

        // Anchor: widest bar top at ~34.4% above body bottom (+1px)
        // This centers the mouth hole on the actual mouth (at ~42% body height)
        let anchorY = by + bh * 0.33 + 6

        let path = CGMutablePath()
        for rect in beardRects {
            // Sway: only below anchor (dy < 0), increasing with distance
            let swayFactor = max(0, -rect.dy)
            let sway = floor(sin(time * 1.8 + swayFactor * 3.0) * swayFactor * bh * 0.06)

            let rw = floor(rect.w * bw)
            let rh = floor(rect.h * bh)
            let rx = floor(midX + rect.dx * bw - rw / 2 + sway)
            let ry = floor(anchorY + rect.dy * bh - rh)

            path.addRect(CGRect(x: rx, y: ry, width: rw, height: rh))
        }
        beardLayer.path = path
    }

    // MARK: - Robe/Toga (#864dff, bottom of body)

    private func updateRobe(dt: CGFloat) {
        let bw = bodyFrame.width
        let bh = bodyFrame.height
        let bx = bodyFrame.origin.x
        let by = bodyFrame.origin.y

        // Same proportions as apron: full width, 40.5% height
        let robeH = floor(bh * 0.405)
        robeLayer.path = CGPath(rect: CGRect(x: bx, y: by, width: bw, height: robeH), transform: nil)

        // Stars on robe — mostly in the lower half (visible below beard)
        let robeStarSpecs: [(x: CGFloat, y: CGFloat, size: CGFloat, rot: CGFloat)] = [
            // Lower area (always visible)
            (0.20, 0.15, 0.30,  0.20),
            (0.75, 0.10, 0.25, -0.30),
            (0.50, 0.25, 0.18,  0.50),
            (0.10, 0.35, 0.12, -0.15),
            (0.88, 0.30, 0.14,  0.35),
            (0.40, 0.08, 0.10, -0.40),
            (0.65, 0.35, 0.10,  0.15),
            // Upper edges (peeking out from sides of beard)
            (0.05, 0.60, 0.12,  0.25),
            (0.92, 0.55, 0.10, -0.20),
        ]
        for (i, spec) in robeStarSpecs.enumerated() where i < robeStarLayers.count {
            let sx = floor(bx + bw * spec.x)
            let sy = floor(by + robeH * spec.y)
            let ss = floor(robeH * spec.size)
            robeStarLayers[i].path = fivePointStarPath(cx: sx, cy: sy, size: ss, rotation: spec.rot)
        }
    }

    // MARK: - Magic Orb (left of body, like pan position)

    // Cached orb position for particles
    private var cachedOrbCX: CGFloat = 0
    private var cachedOrbCY: CGFloat = 0
    private var cachedOrbSize: CGFloat = 0

    private func updateOrb(dt: CGFloat) {
        orbBobPhase += dt * 2.0 * 2.0 * .pi
        orbColorPhase += dt * 0.5 // slow color cycle

        let bw = bodyFrame.width
        let bh = bodyFrame.height
        let bx = bodyFrame.origin.x
        let by = bodyFrame.origin.y

        // Orb position: left of body (like pan)
        let orbOuterSize = floor(bw * 0.34)
        let orbMidSize = floor(bw * 0.27)
        let orbInnerSize = floor(bw * 0.22)

        let orbCX = floor(bx - orbOuterSize * 0.6 - bw * 0.03)
        let bobOffset = floor(sin(orbBobPhase) * bh * 0.04)
        let orbCY = floor(by + bh * 0.5) + bobOffset

        cachedOrbCX = orbCX
        cachedOrbCY = orbCY
        cachedOrbSize = orbOuterSize

        // Color cycling: light cyan → blue → dark blue
        let phase = orbColorPhase
        let outerColor = cycleColor(phase: phase)
        let midColor = cycleColor(phase: phase + 0.33)
        let innerColor = cycleColor(phase: phase + 0.66)

        // Cross/diamond shapes (+ shape made of rects)
        orbOuter.path = crossPath(cx: orbCX, cy: orbCY, size: orbOuterSize)
        orbOuter.fillColor = outerColor

        orbMiddle.path = crossPath(cx: orbCX, cy: orbCY, size: orbMidSize)
        orbMiddle.fillColor = midColor

        orbInner.path = crossPath(cx: orbCX, cy: orbCY, size: orbInnerSize)
        orbInner.fillColor = innerColor

        // Glyph at center
        let glyphSize = floor(orbInnerSize * 0.8)
        orbGlyph.frame = CGRect(
            x: floor(orbCX - glyphSize / 2),
            y: floor(orbCY - glyphSize / 2),
            width: glyphSize,
            height: glyphSize
        )

        // Cycle glyph character every ~20 frames
        if frameCount % 20 == 0 {
            orbGlyph.string = String(randomSGACharacter())
        }
    }

    // MARK: - Particles (magic sparkles near orb)

    private func updateParticles(dt: CGFloat) {
        for i in 0..<particleCount {
            var s = particleStates[i]

            if !s.active {
                s.spawnDelay -= dt
                if s.spawnDelay <= 0 {
                    s.active = true
                    // Spawn on the circumference of the orb
                    let angle = CGFloat.random(in: 0...(2 * .pi))
                    let radius = cachedOrbSize * 0.55
                    s.x = cachedOrbCX + cos(angle) * radius
                    s.y = cachedOrbCY + sin(angle) * radius
                    // Float outward from spawn point
                    let speed = CGFloat.random(in: 25...45)
                    s.velocityX = cos(angle) * speed + CGFloat.random(in: -8...8)
                    s.velocityY = sin(angle) * speed + CGFloat.random(in: 5...15)
                    s.character = randomSGACharacter()
                    s.color = particleColors.randomElement() ?? .white
                    s.age = 0
                    s.lifetime = CGFloat.random(in: 1.0...1.8)
                    s.glitchCounter = 0

                    particleLayers[i].foregroundColor = s.color.cgColor
                    particleLayers[i].string = String(s.character)
                }
            }

            if s.active {
                s.age += dt

                // Float with deceleration
                s.velocityX *= 0.98
                s.velocityY *= 0.97
                s.x += s.velocityX * dt
                s.y += s.velocityY * dt

                // Glitch every 8 frames
                s.glitchCounter += 1
                if s.glitchCounter % 8 == 0 {
                    s.character = randomSGACharacter()
                    particleLayers[i].string = String(s.character)
                }

                particleLayers[i].frame = CGRect(x: floor(s.x), y: floor(s.y), width: 18, height: 18)

                // Fade in/out
                let lifeRatio = s.age / s.lifetime
                let fadeIn = min(lifeRatio / 0.15, 1.0)
                let fadeOut = max(1.0 - (lifeRatio - 0.7) / 0.3, 0.0)
                particleLayers[i].opacity = Float(min(fadeIn, fadeOut) * currentOpacity)

                if s.age >= s.lifetime {
                    s.active = false
                    s.spawnDelay = CGFloat.random(in: 0.1...0.5)
                    particleLayers[i].opacity = 0
                }
            }

            particleStates[i] = s
        }
    }

    // MARK: - Helpers

    /// Orb shape: center square + 4 protruding arms (Figma 585:140)
    /// Proportions from Figma: center=77.4%, armWidth=40.6%, armThickness=15.6%
    private func crossPath(cx: CGFloat, cy: CGFloat, size: CGFloat) -> CGPath {
        let centerSide = floor(size * 0.774)
        let armWidth = floor(size * 0.406)
        let protrusion = floor((size - centerSide) / 2)
        let path = CGMutablePath()

        // Center square
        path.addRect(CGRect(x: floor(cx - centerSide / 2), y: floor(cy - centerSide / 2),
                            width: centerSide, height: centerSide))
        // Top arm
        path.addRect(CGRect(x: floor(cx - armWidth / 2), y: floor(cy + centerSide / 2),
                            width: armWidth, height: protrusion))
        // Bottom arm
        path.addRect(CGRect(x: floor(cx - armWidth / 2), y: floor(cy - centerSide / 2 - protrusion),
                            width: armWidth, height: protrusion))
        // Right arm
        path.addRect(CGRect(x: floor(cx + centerSide / 2), y: floor(cy - armWidth / 2),
                            width: protrusion, height: armWidth))
        // Left arm
        path.addRect(CGRect(x: floor(cx - centerSide / 2 - protrusion), y: floor(cy - armWidth / 2),
                            width: protrusion, height: armWidth))
        return path
    }

    /// 5-pointed star (Figma 585:45). innerRadius ~38% of outer for classic proportions.
    private func fivePointStarPath(cx: CGFloat, cy: CGFloat, size: CGFloat, rotation: CGFloat = 0) -> CGPath {
        let path = CGMutablePath()
        let outerR = size / 2
        let innerR = outerR * 0.382 // golden ratio inner radius
        let startAngle = CGFloat.pi / 2 + rotation // top point up

        for i in 0..<10 {
            let r = i % 2 == 0 ? outerR : innerR
            let angle = startAngle + CGFloat(i) * (.pi / 5)
            let px = floor(cx + cos(angle) * r)
            let py = floor(cy + sin(angle) * r)
            if i == 0 {
                path.move(to: CGPoint(x: px, y: py))
            } else {
                path.addLine(to: CGPoint(x: px, y: py))
            }
        }
        path.closeSubpath()
        return path
    }

    /// Cycle through cyan → blue → dark blue → teal → sea green → mint → cyan
    private static let orbStops: [(r: CGFloat, g: CGFloat, b: CGFloat)] = [
        (0.302, 0.882, 1.000), // #4DE1FF bright cyan
        (0.302, 0.659, 1.000), // #4DA8FF sky blue
        (0.102, 0.239, 0.651), // #1A3DA6 dark blue
        (0.180, 0.500, 0.720), // #2E80B8 teal blue
        (0.200, 0.800, 0.600), // #33CC99 sea green
        (0.302, 0.920, 0.780), // #4DEBC7 mint green
    ]

    private func cycleColor(phase: CGFloat) -> CGColor {
        let stops = Self.orbStops
        let count = CGFloat(stops.count)
        let t = phase.truncatingRemainder(dividingBy: 1.0)
        let scaled = t * count
        let idx = Int(scaled) % stops.count
        let next = (idx + 1) % stops.count
        let p = scaled - floor(scaled)

        let a = stops[idx]
        let b = stops[next]
        return NSColor(
            red:   a.r * (1 - p) + b.r * p,
            green: a.g * (1 - p) + b.g * p,
            blue:  a.b * (1 - p) + b.b * p,
            alpha: 1.0
        ).cgColor
    }

    private func randomSGACharacter() -> Character {
        let letters = "abcdefghijklmnopqrstuvwxyz"
        return letters.randomElement() ?? "a"
    }
}
