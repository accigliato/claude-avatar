import AppKit

enum AvatarState: String, CaseIterable {
    case idle
    case listening
    case thinking
    case working
    case responding
    case error
    case success
    case goodbye
    case sleep

    var primaryColor: NSColor {
        switch self {
        case .idle:       return NSColor(red: 0.76, green: 0.52, blue: 0.39, alpha: 1.0) // Terracotta
        case .listening:  return NSColor(red: 0.65, green: 0.80, blue: 0.96, alpha: 1.0) // Pastel blue
        case .thinking:   return NSColor(red: 0.78, green: 0.65, blue: 0.96, alpha: 1.0) // Pastel purple
        case .working:    return NSColor(red: 0.96, green: 0.82, blue: 0.55, alpha: 1.0) // Pastel amber
        case .responding: return NSColor(red: 0.55, green: 0.92, blue: 0.78, alpha: 1.0) // Pastel mint
        case .error:      return NSColor(red: 0.96, green: 0.55, blue: 0.55, alpha: 1.0) // Pastel coral
        case .success:    return NSColor(red: 0.78, green: 0.96, blue: 0.55, alpha: 1.0) // Pastel lime
        case .goodbye:    return NSColor(red: 0.55, green: 0.48, blue: 0.70, alpha: 1.0) // Muted purple
        case .sleep:      return NSColor(red: 0.45, green: 0.42, blue: 0.52, alpha: 1.0) // Dark grey-purple
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
        case .error:      return 2.0
        case .success:    return 4.0
        case .goodbye:    return 12.0
        case .sleep:      return 12.0
        }
    }
}
