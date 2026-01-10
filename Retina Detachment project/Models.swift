import Foundation
import SwiftUI

// MARK: - Game State Management
enum GameState {
    case mainMenu
    case settings
    case testing
    case results
}

// MARK: - Test Configuration
struct TestSettings: Codable {
    // Perimetry Bowl Geometry
    var bowlRadiusMeters: Float = 2.0  // Fixed distance for all stimuli (Humphrey's bowl)

    // Stimulus Parameters (Clinical Standard)
    var stimulusDurationMs: Double = 200  // Goldmann standard: 200ms presentation
    var stimulusDiameterDeg: Float = 0.43  // Goldmann size III (0.43°)
    var stimulusBrightness: Float = 1.0  // Brightness multiplier

    // Background & Environment
    var backgroundLevel: Float = 0.1  // 0..1, VR approximation of perimeter background

    // Timing
    var responseWindowMs: Double = 1200  // Time allowed for response after stimulus onset
    var intervalRange: ClosedRange<Double> = 2.0...5.0  // Between stimuli

    // Test Configuration
    var testMode: TestMode = .standard
    var maxStimuli: Int = 20
    var eccentricityAngles: [Float] = [15, 30, 45, 60, 75, 90] // degrees
    var polarAngleStep: Float = 45.0  // degrees between polar angles (45° = 8 locations per ring)
    var repetitionsPerLocation: Int = 3  // How many times to test each location

    /// Generate all test locations based on eccentricity angles and polar angle step
    func generateTestLocations() -> [TestLocation] {
        var locations: [TestLocation] = []

        for eccentricity in eccentricityAngles {
            // Number of polar angles around the circle
            let numPolarAngles = Int(360.0 / polarAngleStep)

            for i in 0..<numPolarAngles {
                let polarAngle = Float(i) * polarAngleStep
                locations.append(TestLocation(eccentricityDeg: eccentricity, polarAngleDeg: polarAngle))
            }
        }

        return locations
    }

    /// Generate full trial list: each location repeated N times, shuffled
    func generateShuffledTrials() -> [TestLocation] {
        let baseLocations = generateTestLocations()
        var allTrials: [TestLocation] = []

        // Repeat each location N times
        for _ in 0..<repetitionsPerLocation {
            allTrials.append(contentsOf: baseLocations)
        }

        // Shuffle to randomize presentation order
        return allTrials.shuffled()
    }

    // Legacy properties (deprecated, use new names above)
    @available(*, deprecated, renamed: "bowlRadiusMeters")
    var stimulusDistance: Float {
        get { bowlRadiusMeters }
        set { bowlRadiusMeters = newValue }
    }

    @available(*, deprecated, renamed: "stimulusDurationMs")
    var displayDuration: Double {
        get { stimulusDurationMs / 1000.0 }
        set { stimulusDurationMs = newValue * 1000.0 }
    }

    @available(*, deprecated, renamed: "stimulusDiameterDeg")
    var stimulusSize: Float {
        get { stimulusDiameterDeg }
        set { stimulusDiameterDeg = newValue }
    }

    static var shared = TestSettings()
}

enum TestMode: String, CaseIterable, Codable {
    case standard = "Standard"
    case adaptive = "Adaptive"
    case focused = "Focused Angles"
    
    var description: String {
        switch self {
        case .standard:
            return "Test all peripheral angles randomly"
        case .adaptive:
            return "Adapts difficulty based on performance"
        case .focused:
            return "Focus on specific eccentricity angles"
        }
    }
}

// MARK: - Test Location Definition
struct TestLocation: Hashable, Codable {
    let eccentricityDeg: Float
    let polarAngleDeg: Float
}

// MARK: - Trial Record (Comprehensive Data Logging)
struct TrialRecord: Codable, Identifiable {
    let id: UUID
    let trialIndex: Int
    let eccentricityDeg: Float
    let polarAngleDeg: Float
    let onsetTimestamp: Date
    let seen: Bool
    let reactionTimeSec: Double?
    let brightness: Float
    let bowlRadiusMeters: Float

    init(id: UUID = UUID(), trialIndex: Int, location: TestLocation, onsetTimestamp: Date, seen: Bool, reactionTimeSec: Double?, brightness: Float, bowlRadiusMeters: Float) {
        self.id = id
        self.trialIndex = trialIndex
        self.eccentricityDeg = location.eccentricityDeg
        self.polarAngleDeg = location.polarAngleDeg
        self.onsetTimestamp = onsetTimestamp
        self.seen = seen
        self.reactionTimeSec = reactionTimeSec
        self.brightness = brightness
        self.bowlRadiusMeters = bowlRadiusMeters
    }

    /// CSV header row
    static var csvHeader: String {
        "stimulus_id,trial_index,ecc_deg,pol_deg,onset_timestamp,seen,rt_sec,brightness,bowl_radius_m"
    }

    /// Convert to CSV row
    func toCSV() -> String {
        let iso8601 = ISO8601DateFormatter().string(from: onsetTimestamp)
        let seenInt = seen ? 1 : 0
        let rtString = reactionTimeSec.map { String(format: "%.3f", $0) } ?? ""
        return "\(id.uuidString),\(trialIndex),\(eccentricityDeg),\(polarAngleDeg),\(iso8601),\(seenInt),\(rtString),\(brightness),\(bowlRadiusMeters)"
    }
}

// MARK: - Legacy Test Data Models
struct TestTrial: Codable, Identifiable {
    let id = UUID()
    let timestamp: Date
    let stimulusAngle: Float // degrees from forward
    let eccentricity: Float // degrees from center
    let reactionTime: Double? // seconds, nil if missed
    let wasDetected: Bool
    let stimulusPosition: SIMD3<Float>

    init(angle: Float, eccentricity: Float, position: SIMD3<Float>, reactionTime: Double? = nil, detected: Bool = false) {
        self.timestamp = Date()
        self.stimulusAngle = angle
        self.eccentricity = eccentricity
        self.stimulusPosition = position
        self.reactionTime = reactionTime
        self.wasDetected = detected
    }
}

struct TestSession: Codable, Identifiable {
    let id = UUID()
    let startTime: Date
    let endTime: Date
    let trials: [TestTrial]
    let settings: TestSettings
    
    init(startTime: Date, endTime: Date, trials: [TestTrial], settings: TestSettings) {
        self.startTime = startTime
        self.endTime = endTime
        self.trials = trials
        self.settings = settings
    }
    
    var accuracy: Double {
        guard !trials.isEmpty else { return 0 }
        let detected = trials.filter { $0.wasDetected }.count
        return Double(detected) / Double(trials.count)
    }
    
    var averageReactionTime: Double {
        let reactionTimes = trials.compactMap { $0.reactionTime }
        guard !reactionTimes.isEmpty else { return 0 }
        return reactionTimes.reduce(0, +) / Double(reactionTimes.count)
    }
    
    func accuracyByEccentricity() -> [Float: Double] {
        var results: [Float: (detected: Int, total: Int)] = [:]
        
        for trial in trials {
            let key = round(trial.eccentricity / 15) * 15 // Group by 15-degree intervals
            results[key, default: (0, 0)].total += 1
            if trial.wasDetected {
                results[key, default: (0, 0)].detected += 1
            }
        }
        
        return results.mapValues { Double($0.detected) / Double($0.total) }
    }
}

// MARK: - Data Manager
class TestDataManager: ObservableObject {
    @Published var sessions: [TestSession] = []
    private let userDefaults = UserDefaults.standard
    private let sessionsKey = "PeripheralVisionSessions"
    
    init() {
        loadSessions()
    }
    
    func addSession(_ session: TestSession) {
        sessions.append(session)
        saveSessions()
    }
    
    func exportData() -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        
        do {
            let data = try encoder.encode(sessions)
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return "Error exporting data: \(error.localizedDescription)"
        }
    }
    
    private func saveSessions() {
        do {
            let data = try JSONEncoder().encode(sessions)
            userDefaults.set(data, forKey: sessionsKey)
        } catch {
            print("Error saving sessions: \(error)")
        }
    }
    
    private func loadSessions() {
        guard let data = userDefaults.data(forKey: sessionsKey) else { return }
        
        do {
            sessions = try JSONDecoder().decode([TestSession].self, from: data)
        } catch {
            print("Error loading sessions: \(error)")
        }
    }
}