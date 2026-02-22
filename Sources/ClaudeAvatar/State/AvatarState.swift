import AppKit

enum AvatarState: String, CaseIterable {
    case idle
    case listening
    case thinking
    case working
    case responding
    case tool       // executing a tool ("let me cook")
    case approve    // awaiting permission approval
    case error
    case success
    case goodbye
    case sleep

    var primaryColor: NSColor {
        switch self {
        case .idle:       return NSColor(red: 1.00, green: 0.478, blue: 0.302, alpha: 1.0) // #FF7A4D base orange
        case .listening:  return NSColor(red: 0.302, green: 0.659, blue: 1.00, alpha: 1.0)  // #4DA8FF soft blue
        case .thinking:   return NSColor(red: 0.627, green: 0.478, blue: 1.00, alpha: 1.0)  // #A07AFF soft purple
        case .working:    return NSColor(red: 1.00, green: 0.706, blue: 0.302, alpha: 1.0)  // #FFB44D warm amber
        case .responding: return NSColor(red: 0.302, green: 1.00, blue: 0.706, alpha: 1.0)  // #4DFFB4 soft mint
        case .tool:       return NSColor(red: 1.00, green: 0.353, blue: 0.176, alpha: 1.0)  // #FF5A2D intense orange
        case .approve:    return NSColor(red: 1.00, green: 0.831, blue: 0.302, alpha: 1.0)  // #FFD44D attention yellow
        case .error:      return NSColor(red: 1.00, green: 0.302, blue: 0.416, alpha: 1.0)  // #FF4D6A soft coral
        case .success:    return NSColor(red: 0.478, green: 1.00, blue: 0.302, alpha: 1.0)  // #7AFF4D bright lime
        case .goodbye:    return NSColor(red: 0.549, green: 0.416, blue: 0.478, alpha: 1.0) // #8C6A7A muted mauve
        case .sleep:      return NSColor(red: 0.239, green: 0.165, blue: 0.149, alpha: 1.0) // #3D2A26 dark dusk
        }
    }

    var glowColor: NSColor {
        return primaryColor.withAlphaComponent(0.6)
    }

    var breathingDuration: CFTimeInterval {
        switch self {
        case .idle:       return 3.0
        case .listening:  return 2.5
        case .thinking:   return 1.5
        case .working:    return 1.0
        case .responding: return 2.0
        case .tool:       return 1.0
        case .approve:    return 2.0
        case .error:      return 1.5
        case .success:    return 1.5
        case .goodbye:    return 4.0
        case .sleep:      return 5.0
        }
    }

    var glowIntensity: Float {
        switch self {
        case .idle:       return 0.0
        case .listening:  return 0.65
        case .thinking:   return 0.7
        case .working:    return 0.85
        case .responding: return 0.6
        case .tool:       return 0.85
        case .approve:    return 0.75
        case .error:      return 0.6
        case .success:    return 0.9
        case .goodbye:    return 0.3
        case .sleep:      return 0.15
        }
    }

    var isAlive: Bool {
        switch self {
        case .goodbye, .sleep:
            return false
        default:
            return true
        }
    }

    var tentacleFrequency: CGFloat {
        switch self {
        case .idle:       return 1.0
        case .listening:  return 1.3
        case .thinking:   return 0.8
        case .working:    return 2.5
        case .responding: return 1.5
        case .tool:       return 2.8
        case .approve:    return 1.5
        case .error:      return 3.0
        case .success:    return 2.0
        case .goodbye:    return 0.4
        case .sleep:      return 0.3
        }
    }

    var tentacleAmplitude: CGFloat {
        switch self {
        case .idle:       return 2.0
        case .listening:  return 2.5
        case .thinking:   return 1.5
        case .working:    return 3.5
        case .responding: return 3.0
        case .tool:       return 3.5
        case .approve:    return 2.0
        case .error:      return 1.0
        case .success:    return 4.0
        case .goodbye:    return 1.0
        case .sleep:      return 0.5
        }
    }

    /// Float radius in points (how far the avatar drifts from center)
    var floatRadius: CGFloat {
        switch self {
        case .idle:       return 12
        case .listening:  return 8
        case .thinking:   return 10
        case .working:    return 18
        case .responding: return 12
        case .tool:       return 15
        case .approve:    return 6
        case .error:      return 5
        case .success:    return 15
        case .goodbye:    return 3
        case .sleep:      return 3
        }
    }

    /// Float period in seconds (full cycle time)
    var floatPeriod: CGFloat {
        switch self {
        case .idle:       return 8.0
        case .listening:  return 5.0
        case .thinking:   return 10.0
        case .working:    return 4.0
        case .responding: return 6.0
        case .tool:       return 5.0
        case .approve:    return 3.0
        case .error:      return 2.0
        case .success:    return 4.0
        case .goodbye:    return 12.0
        case .sleep:      return 12.0
        }
    }
}
