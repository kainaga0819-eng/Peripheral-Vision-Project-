import SwiftUI

// MARK: - Severity

enum DetachmentSeverity: String, CaseIterable, Identifiable {
    case normal = "Normal Vision"
    case mild   = "Mild"
    case medium = "Medium"
    case severe = "Severe"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .normal: return "Healthy control — full visual field, no detachment zone"
        case .mild:   return "Outer-edge detachment (≥22°) — 5–6 dots at far periphery only"
        case .medium: return "Second-layer detachment (20°–24°) — small wedge one ring inside the edge"
        case .severe: return "Third-layer detachment (15°–20°) — moderate wedge two rings inside the edge"
        }
    }

    var icon: String {
        switch self {
        case .normal: return "eye"
        case .mild:   return "circle.dashed"
        case .medium: return "circle.lefthalf.filled"
        case .severe: return "exclamationmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .normal: return .green
        case .mild:   return .yellow
        case .medium: return .orange
        case .severe: return .red
        }
    }

    // MARK: Procedural generation

    /// Generate a DetachmentZone for this severity level. Returns nil for Normal Vision.
    func generate() -> DetachmentZone? {
        guard self != .normal else { return nil }

        let thetaStart = Float.random(in: 0..<360)

        switch self {
        case .normal:
            return nil  // unreachable — handled above
        case .mild:
            // ~5–6 dots: thin wedge clipped to the outermost ring only
            return DetachmentZone(
                thetaStart:  thetaStart,
                thetaSweep:  Float.random(in: 60...75),
                rMin:        Float.random(in: 22...26),
                severity:    self
            )
        case .medium:
            // ~9–13 dots: clearly larger than mild, wedge in layer 2
            return DetachmentZone(
                thetaStart:  thetaStart,
                thetaSweep:  Float.random(in: 65...80),
                rMin:        Float.random(in: 19...23),
                severity:    self
            )
        case .severe:
            // ~14–20 dots: larger still, wedge in layer 3
            return DetachmentZone(
                thetaStart:  thetaStart,
                thetaSweep:  Float.random(in: 105...130),
                rMin:        Float.random(in: 15...19),
                severity:    self
            )
        }
    }

    // MARK: Reaction time

    /// Simulated RT (seconds) for a visible stimulus. Slower at periphery and for dim stimuli.
    func reactionTime(eccentricityDeg: Float, brightness: Float) -> Double {
        let base              = 0.40
        let eccPenalty        = Double(eccentricityDeg) * 0.012
        let brightnessPenalty = Double(1.0 - brightness) * 0.25
        let jitter            = Double.random(in: -0.05...0.15)
        return max(0.25, base + eccPenalty + brightnessPenalty + jitter)
    }
}

// MARK: - Detachment Zone

struct DetachmentZone {
    /// Starting polar angle of the detachment sector (0–360°). 0° = rightward/nasal.
    let thetaStart: Float
    /// Angular width of the damaged sector in degrees (sweeps counter-clockwise from thetaStart).
    let thetaSweep: Float
    /// Inner radius boundary — detachment runs from rMin outward to the edge of vision.
    let rMin: Float
    let severity: DetachmentSeverity

    /// Outer radius of the visual field (30-2 test grid maximum).
    private static let rMax: Float = 30.0

    // MARK: Vision test logic

    /// Returns true if (xDeg, yDeg) lies in HEALTHY retina (patient should respond).
    ///
    /// A point is inside the detachment zone (blind) if:
    ///   • its radius r ≥ rMin  (from the tear outward to the edge of the field), AND
    ///   • its polar angle falls within [thetaStart, thetaStart + thetaSweep] (with wrap-around).
    func isHealthy(xDeg: Float, yDeg: Float) -> Bool {
        let r = (xDeg * xDeg + yDeg * yDeg).squareRoot()

        // Inside the foveal region (closer than the inner tear boundary) → healthy
        guard r >= rMin else { return true }
        // Beyond the outer test grid → treated as healthy (not tested)
        guard r <= Self.rMax else { return true }

        // Compute polar angle in [0, 360)
        var theta = atan2(yDeg, xDeg) * 180.0 / Float.pi
        if theta < 0 { theta += 360 }

        // Rotate so that thetaStart maps to 0°; result is in [0, 360).
        // If the rotated angle is within the sweep, the point is inside the blind sector.
        let rotated = (theta - thetaStart + 360).truncatingRemainder(dividingBy: 360)
        let insideSector = rotated <= thetaSweep

        return !insideSector   // healthy = outside the detachment sector
    }

    /// Hit probability for a healthy retina point — used by both instance and static paths.
    /// At r=0 (center): ~0.97. At r=30 (far edge): ~0.82. Never drops to 0.
    static func healthySensitivity(xDeg: Float, yDeg: Float, brightness: Float) -> Double {
        let r = Double((xDeg * xDeg + yDeg * yDeg).squareRoot())
        let eccFactor    = 0.82 + 0.15 * (1.0 - r / Double(rMax))
        let brightFactor = 0.92 + 0.08 * Double(min(brightness, 1.0))
        return min(eccFactor * brightFactor, 0.97)
    }

    /// Hit probability 0–1 for a stimulus at (xDeg, yDeg) with given brightness.
    /// 0.0 = inside detachment (blind). Healthy retina stays 0.80–0.97 across the full field.
    func sensitivity(xDeg: Float, yDeg: Float, brightness: Float) -> Double {
        guard isHealthy(xDeg: xDeg, yDeg: yDeg) else { return 0.0 }
        return Self.healthySensitivity(xDeg: xDeg, yDeg: yDeg, brightness: brightness)
    }

    // MARK: Debug description

    /// Human-readable summary printed to the Xcode console when a simulation starts.
    var locationDescription: String {
        let thetaEnd  = (thetaStart + thetaSweep).truncatingRemainder(dividingBy: 360)
        let midAngle  = (thetaStart + thetaSweep / 2).truncatingRemainder(dividingBy: 360)
        let clock     = clockLabel(for: midAngle)
        return """
        ┌─ Detachment Zone ────────────────────────────
        │  Severity   : \(severity.rawValue)
        │  Sector     : \(Int(thetaStart))° → \(Int(thetaEnd))° (\(Int(thetaSweep))° sweep)
        │  Mid-sector : \(clock) (\(Int(midAngle))°)
        │  Blind from : r = \(String(format: "%.1f", rMin))° outward to edge of field (\(Int(Self.rMax))°)
        └──────────────────────────────────────────────
        """
    }

    private func clockLabel(for angleDeg: Float) -> String {
        // Math angle: 0°=right, 90°=up, 180°=left, 270°=down
        // Clock mapping: 3=right, 12=up, 9=left, 6=down
        let clockHour = Int(((-angleDeg + 90).truncatingRemainder(dividingBy: 360) + 360) / 30) % 12
        let hour = clockHour == 0 ? 12 : clockHour
        return "\(hour) o'clock"
    }
}
