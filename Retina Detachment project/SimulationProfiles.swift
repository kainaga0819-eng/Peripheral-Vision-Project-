import Foundation

// MARK: - Vision profiles for simulation mode

enum VisionProfile: String, CaseIterable, Identifiable {
    case normal             = "Normal Vision"
    case superiorLoss       = "Superior Field Loss"
    case inferiorLoss       = "Inferior Field Loss"
    case centralScotoma     = "Central Scotoma"
    case leftHemianopia     = "Left Hemianopia"
    case rightHemianopia    = "Right Hemianopia"
    case arcuateGlaucoma    = "Arcuate Defect (Glaucoma)"
    case peripheralTunnel   = "Peripheral Constriction"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .normal:           return "Full sensitivity across all 76 test points."
        case .superiorLoss:     return "Upper visual field severely reduced — common in inferior retinal damage."
        case .inferiorLoss:     return "Lower visual field severely reduced — common in superior retinal damage."
        case .centralScotoma:   return "Blind spot within 12° of fixation — common in macular disease."
        case .leftHemianopia:   return "Left half of visual field lost — typical of right brain lesion."
        case .rightHemianopia:  return "Right half of visual field lost — typical of left brain lesion."
        case .arcuateGlaucoma:  return "Superior arcuate nerve bundle defect — classic early glaucoma pattern."
        case .peripheralTunnel: return "Peripheral vision constricted beyond 15° — typical of advanced glaucoma."
        }
    }

    var icon: String {
        switch self {
        case .normal:           return "eye.fill"
        case .superiorLoss:     return "arrow.up.circle.fill"
        case .inferiorLoss:     return "arrow.down.circle.fill"
        case .centralScotoma:   return "circle.fill"
        case .leftHemianopia:   return "arrow.left.circle.fill"
        case .rightHemianopia:  return "arrow.right.circle.fill"
        case .arcuateGlaucoma:  return "waveform.path.ecg"
        case .peripheralTunnel: return "circle.dashed"
        }
    }

    // Probability (0–1) that the fake patient detects a stimulus at (xDeg, yDeg) with given brightness
    // xDeg: positive = right visual field, yDeg: positive = superior visual field
    func sensitivity(xDeg: Float, yDeg: Float, brightness: Float) -> Double {
        let ecc = Double(sqrt(xDeg * xDeg + yDeg * yDeg))
        // Dim stimuli are harder to detect regardless of profile
        let brightScale = 0.55 + 0.45 * Double(brightness)

        let base: Double
        switch self {

        case .normal:
            // Slight falloff at extreme periphery
            base = max(0.80, 0.97 - ecc * 0.004)

        case .superiorLoss:
            // Upper field (yDeg > 0) nearly blind; lower field near-normal
            base = yDeg > 0 ? 0.05 : max(0.75, 0.95 - ecc * 0.005)

        case .inferiorLoss:
            // Lower field (yDeg < 0) nearly blind; upper field near-normal
            base = yDeg < 0 ? 0.05 : max(0.75, 0.95 - ecc * 0.005)

        case .centralScotoma:
            // Blind within 12°, normal beyond
            base = ecc < 12 ? 0.05 : max(0.75, 0.95 - ecc * 0.005)

        case .leftHemianopia:
            base = xDeg < 0 ? 0.05 : max(0.75, 0.95 - ecc * 0.005)

        case .rightHemianopia:
            base = xDeg > 0 ? 0.05 : max(0.75, 0.95 - ecc * 0.005)

        case .arcuateGlaucoma:
            // Superior arcuate scotoma: dense defect in the superior arcuate region
            if Double(yDeg) > 3 && ecc > 9 && ecc < 29 {
                base = 0.07
            } else if Double(yDeg) > 0 && ecc > 15 {
                // Nasal step: partial loss in superior nasal quadrant
                base = 0.45
            } else {
                base = max(0.75, 0.95 - ecc * 0.005)
            }

        case .peripheralTunnel:
            // Good central vision, drops sharply beyond 15°
            if ecc > 15 {
                base = max(0.05, 0.85 - (ecc - 15) * 0.09)
            } else {
                base = max(0.82, 0.97 - ecc * 0.005)
            }
        }

        return min(base * brightScale, 0.98)
    }

    // Simulated reaction time in seconds — slower at periphery and for dim stimuli
    func reactionTime(eccentricityDeg: Float, brightness: Float) -> Double {
        let eccDelay = Double(eccentricityDeg) / 29.7 * 0.55   // 0–0.55s based on eccentricity
        let dimDelay = (1.0 - Double(brightness)) * 0.20        // up to 0.20s extra for dim stimuli
        let jitter   = Double.random(in: -0.08...0.30)
        return max(0.25, 0.45 + eccDelay + dimDelay + jitter)
    }
}
