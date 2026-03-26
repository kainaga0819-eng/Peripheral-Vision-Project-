import SwiftUI
import RealityKit
import Speech
import AVFoundation

// MARK: - Voice control controller

class SpeechController: ObservableObject {
    @Published var keywordFiredAt: Date = .distantPast
    @Published var isListening = false

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let engine = AVAudioEngine()
    private var tapInstalled = false
    private var lastFire = Date.distantPast

    // Accepted spoken phrases
    static let keywords = ["i see it", "i saw it", "seen", "see it", "i see", "yes"]

    func requestPermissionAndStart() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard status == .authorized else {
                    print("Speech recognition not authorized")
                    return
                }
                self?.start()
            }
        }
    }

    func start() {
        guard !engine.isRunning else { return }
        let rec = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard rec?.isAvailable == true else {
            print("Speech recognizer unavailable")
            return
        }
        recognizer = rec

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        request = req

        let node = engine.inputNode
        node.installTap(onBus: 0, bufferSize: 1024, format: node.outputFormat(forBus: 0)) { [weak self] buf, _ in
            self?.request?.append(buf)
        }
        tapInstalled = true

        do {
            try engine.start()
        } catch {
            print("Speech engine failed: \(error)")
            node.removeTap(onBus: 0)
            tapInstalled = false
            return
        }

        task = recognizer?.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString.lowercased()
                print("Voice heard: \"\(text)\"")
                if Self.keywords.contains(where: { text.contains($0) }) {
                    let now = Date()
                    if now.timeIntervalSince(self.lastFire) > 1.5 {
                        self.lastFire = now
                        print("Voice control: keyword matched")
                        DispatchQueue.main.async { self.keywordFiredAt = now }
                    }
                }
            }
            // Apple ends recognition tasks after ~1 min — auto-restart
            if error != nil || (result?.isFinal ?? false) {
                DispatchQueue.main.async { [weak self] in
                    self?.stop()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.start() }
                }
            }
        }
        DispatchQueue.main.async { self.isListening = true }
    }

    func stop() {
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine.stop()
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
        DispatchQueue.main.async { self.isListening = false }
    }
}

// Clinical test location (fixed grid position)
struct StimulusLocation: Codable {
    let angleDegrees: Float // 0-360 degrees around user
    let eccentricityDegrees: Float // Distance from center
    let id: Int
}

// Scheduled trial: combines a location with a specific brightness level
struct ScheduledTrial: Codable {
    let location: StimulusLocation
    let brightnessValue: Float
    let brightnessLevelIndex: Int // 0=Low, 1=Medium, 2=High
}

// Persisted progress snapshot used by Save & Quit / Resume
struct SavedTestProgress: Codable {
    var remainingTrials: [ScheduledTrial]
    var completedTrialID: Int
    var hitCount: Int
    var missedCount: Int
    var savedAt: Date

    private static let key = "SavedTestProgress"

    static func load() -> SavedTestProgress? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let progress = try? JSONDecoder().decode(SavedTestProgress.self, from: data)
        else { return nil }
        return progress
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

struct StimulusTrial: Identifiable, Codable {
    let id: UUID
    let trialID: Int
    let spotID: Int
    let angleDegrees: Float
    let eccentricityDegrees: Float
    let spawnTime: Date
    let responseTime: Date?
    let wasHit: Bool
    let timedOut: Bool
    let brightnessValue: Float      // Actual brightness (0.25, 0.60, 1.00)
    let brightnessLevelIndex: Int   // Index into brightnessLevels array (0=Low, 1=Medium, 2=High)

    init(trialID: Int, spotID: Int, angleDegrees: Float, eccentricityDegrees: Float,
         spawnTime: Date, responseTime: Date?, wasHit: Bool, timedOut: Bool,
         brightnessValue: Float, brightnessLevelIndex: Int) {
        self.id = UUID()
        self.trialID = trialID; self.spotID = spotID
        self.angleDegrees = angleDegrees; self.eccentricityDegrees = eccentricityDegrees
        self.spawnTime = spawnTime; self.responseTime = responseTime
        self.wasHit = wasHit; self.timedOut = timedOut
        self.brightnessValue = brightnessValue; self.brightnessLevelIndex = brightnessLevelIndex
    }

    var reactionTimeSeconds: Double? {
        guard let responseTime else { return nil }
        return responseTime.timeIntervalSince(spawnTime)
    }
}

// MARK: - Persisted test session (saved after each completed/quit test)

struct SimpleTestSession: Codable, Identifiable {
    let id: UUID
    let date: Date
    let completedTrials: Int
    let totalTrials: Int
    let hitCount: Int
    let missedCount: Int
    let trials: [StimulusTrial]
    var modeName: String = "Normal Test"  // default keeps old saved sessions decodable

    var accuracy: Double {
        guard completedTrials > 0 else { return 0 }
        return Double(hitCount) / Double(completedTrials)
    }

    var averageReactionTime: Double {
        let rts = trials.compactMap { $0.reactionTimeSeconds }
        guard !rts.isEmpty else { return 0 }
        return rts.reduce(0, +) / Double(rts.count)
    }

    func accuracyByEccentricity() -> [(eccentricity: Float, accuracy: Double)] {
        let eccentricities = Set(trials.map { $0.eccentricityDegrees }).sorted()
        return eccentricities.map { ecc in
            let eccTrials = trials.filter { $0.eccentricityDegrees == ecc }
            let hits = eccTrials.filter { $0.wasHit }.count
            return (ecc, Double(hits) / Double(eccTrials.count))
        }
    }
}

struct SimpleSessionStore {
    private static let key = "SimpleTestSessions"

    static func loadAll() -> [SimpleTestSession] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let sessions = try? JSONDecoder().decode([SimpleTestSession].self, from: data)
        else { return [] }
        return sessions
    }

    static func append(_ session: SimpleTestSession) {
        var sessions = loadAll()
        sessions.append(session)
        if let data = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func clearAll() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

struct SimpleImmersiveView: View {
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow

    @StateObject private var speech = SpeechController()
    // Which eye is currently being tested — right (OD) first, then left (OS)
    enum TestedEye { case right, left }
    @State private var currentEye: TestedEye = .right

    @AppStorage("voiceControlEnabled") private var voiceControlEnabled = false
    @AppStorage("simulationModeEnabled") private var simulationModeEnabled = false
    @AppStorage("simulationSeverityRaw") private var simulationSeverityRaw = DetachmentSeverity.mild.rawValue
    @State private var detachmentZone: DetachmentZone? = nil
    @AppStorage("monocularModeEnabled") private var monocularModeEnabled = false
    @State private var showEyeSwitchOverlay = false
    @State private var isGazingAtFixation = false

    @State private var rootEntity = Entity()

    // Test state
    @State private var testActive = false
    @State private var currentStimulus: ModelEntity?
    @State private var currentSpawnTime: Date?
    @State private var currentTrialID = 0

    // Scoring
    @State private var hitCount = 0
    @State private var missedCount = 0
    @State private var trials: [StimulusTrial] = []

    // Debug mode
    @State private var debugMode = false
    @State private var gridEntity: Entity?

    // Clinical parameters - pre-generated trial list (76 locations × 3 brightness = 228 trials)
    @State private var scheduledTrials: [ScheduledTrial] = []
    @State private var currentAngleDegrees: Float = 0
    @State private var currentEccentricityDegrees: Float = 0

    // CSV Export
    @State private var csvExportPath: String? = nil

    // Settings panel
    @State private var showSettingsPanel = false

    // Brightness levels: Low (0.25), Medium (0.60), High (1.00)
    let brightnessLevels: [Float] = [0.25, 0.60, 1.00]
    let brightnessLabels: [String] = ["Low", "Medium", "High"]
    @State private var currentBrightness: Float = 1.0
    @State private var currentBrightnessIndex: Int = 2

    // Clinical grid: simplified 24-2 style with ~6° spacing
    // Covers central ±24° in all quadrants at multiple eccentricities
    let clinicalGrid: [StimulusLocation] = {
        // Humphrey 30-2 style: 6° Cartesian grid at ±3°, ±9°, ±15°, ±21°, ±27°
        // Points included where x²+y² < 882 (eccentricity < ~29.7°) → 76 locations
        var locations: [StimulusLocation] = []
        var id = 0
        let steps: [Float] = [-27, -21, -15, -9, -3, 3, 9, 15, 21, 27]

        for yDeg in steps {
            for xDeg in steps {
                let eccSq = xDeg * xDeg + yDeg * yDeg
                guard eccSq < 882 else { continue }  // cut corners beyond ~29.7°

                let eccentricity = eccSq.squareRoot()
                var angle = atan2(yDeg, xDeg) * 180.0 / Float.pi
                if angle < 0 { angle += 360 }

                locations.append(StimulusLocation(
                    angleDegrees: angle,
                    eccentricityDegrees: eccentricity,
                    id: id
                ))
                id += 1
            }
        }

        return locations
    }()

    var body: some View {
        RealityView { content, attachments in
            // Single head anchor — everything is positioned relative to the user's head,
            // not the world floor. This keeps stimuli and fixation in the user's visual field.
            let headAnchor = AnchorEntity(.head)
            content.add(headAnchor)
            headAnchor.addChild(rootEntity)

            // Light background environment — slightly dim white for clinical contrast
            let background = ModelEntity(
                mesh: .generateSphere(radius: 50),
                materials: [SimpleMaterial(color: UIColor(white: 0.88, alpha: 1.0), isMetallic: false)]
            )
            background.scale = SIMD3<Float>(-1, 1, 1)
            rootEntity.addChild(background)

            // Central fixation point — SwiftUI attachment so look+pinch works reliably.
            // Positioned 2 m directly in front; tapping it registers "I Saw It".
            if let fixationButton = attachments.entity(for: "FixationButton") {
                fixationButton.position = SIMD3<Float>(0, 0, -2)
                headAnchor.addChild(fixationButton)
            }

            // Settings button — same depth as fixation (2m), just to the upper-right.
            // Keeps it in foveal reach without the user having to look far away.
            if let topBar = attachments.entity(for: "TopBar") {
                topBar.position = SIMD3<Float>(0.09, 0.06, -2.0)
                headAnchor.addChild(topBar)
            }

            // Eye-switch overlay — shown between right-eye and left-eye tests in monocular mode
            if let eyeSwitch = attachments.entity(for: "EyeSwitchOverlay") {
                eyeSwitch.position = SIMD3<Float>(0, 0, -1.5)
                headAnchor.addChild(eyeSwitch)
            }

            // Settings panel: centered, only visible when paused
            if let settingsPanel = attachments.entity(for: "SettingsPanel") {
                settingsPanel.position = SIMD3<Float>(0, 0, -0.90)
                headAnchor.addChild(settingsPanel)
            }

            // Create debug grid (initially hidden)
            let grid = createDebugGrid()
            gridEntity = grid
        } update: { content, attachments in
            // Show/hide debug grid based on debug mode
            if let grid = gridEntity {
                if debugMode && grid.parent == nil {
                    rootEntity.addChild(grid)
                } else if !debugMode && grid.parent != nil {
                    grid.removeFromParent()
                }
            }
        } attachments: {
            // Compact settings button — sits just beside the fixation dot
            Attachment(id: "TopBar") {
                let total = clinicalGrid.count * brightnessLevels.count
                let pct = total > 0 ? Int((Double(currentTrialID) / Double(total)) * 100) : 0

                VStack(spacing: 4) {
                    Button {
                        if showSettingsPanel {
                            showSettingsPanel = false
                            testActive = true
                            scheduleNextStimulus()
                        } else {
                            testActive = false
                            showSettingsPanel = true
                        }
                    } label: {
                        Image(systemName: showSettingsPanel ? "play.circle.fill" : "gearshape.fill")
                            .font(.system(size: 38, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 80, height: 80)
                            .background(showSettingsPanel ? .green.opacity(0.85) : .black.opacity(0.55))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)

                    Text("\(pct)%")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                    if monocularModeEnabled {
                        Text(currentEye == .right ? "OD" : "OS")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(currentEye == .right ? .blue.opacity(0.9) : .orange.opacity(0.9))
                    }
                }
            }

            // Fixation button — the white dot the user stares at.
            // Look at it and pinch to register "I Saw It" during a trial.
            // .onHover tracks visionOS eye gaze — used to gate voice control responses.
            Attachment(id: "FixationButton") {
                Button {
                    guard !simulationModeEnabled else { return }
                    handleSawIt()
                } label: {
                    ZStack {
                        Circle()
                            .stroke(Color(white: 0.3).opacity(0.35), lineWidth: 1.5)
                            .frame(width: 90, height: 90)
                        Circle()
                            .fill(Color(white: 0.25))
                            .frame(width: 30, height: 30)
                    }
                }
                .buttonStyle(.plain)
                .onHover { isGazingAtFixation = $0 }
            }

            // Settings panel — centered, shown only when paused
            Attachment(id: "SettingsPanel") {
                if showSettingsPanel {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Test Paused")
                            .font(.title2).fontWeight(.bold).foregroundColor(.white)

                        let total = clinicalGrid.count * brightnessLevels.count
                        let pct = total > 0 ? Int((Double(currentTrialID) / Double(total)) * 100) : 0
                        Text("Trial \(currentTrialID) / \(total)  ·  \(pct)% complete")
                            .font(.subheadline).foregroundColor(.gray)

                        HStack(spacing: 16) {
                            Label("\(hitCount) Hits", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Label("\(missedCount) Misses", systemImage: "xmark.circle.fill")
                                .foregroundColor(.red)
                        }
                        .font(.headline)

                        Divider().background(.white.opacity(0.3))

                        // Voice control toggle
                        Toggle(isOn: $voiceControlEnabled) {
                            HStack(spacing: 8) {
                                Image(systemName: speech.isListening ? "mic.fill" : "mic.slash.fill")
                                    .foregroundColor(speech.isListening ? .green : .gray)
                                Text("Voice Control")
                                    .foregroundColor(.white)
                            }
                            .font(.headline)
                        }
                        .onChange(of: voiceControlEnabled) { _, enabled in
                            if enabled { speech.requestPermissionAndStart() }
                            else { speech.stop() }
                        }

                        Text("Say \"I see it\" while looking at the fixation dot")
                            .font(.caption)
                            .foregroundColor(.gray)

                        Divider().background(.white.opacity(0.3))

                        // Fast Forward — simulation only
                        if simulationModeEnabled {
                            Button {
                                showSettingsPanel = false
                                fastForwardSimulation()
                            } label: {
                                Label("Fast Forward — Complete Now", systemImage: "forward.end.fill")
                                    .font(.headline).foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .background(.purple)
                                    .cornerRadius(13)
                            }
                        }

                        // Resume
                        Button {
                            showSettingsPanel = false
                            testActive = true
                            scheduleNextStimulus()
                        } label: {
                            Label("Resume Test", systemImage: "play.fill")
                                .font(.headline).foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(.green)
                                .cornerRadius(13)
                        }

                        // Save & Quit
                        Button {
                            showSettingsPanel = false
                            saveAndQuit()
                        } label: {
                            Label("Save & Quit", systemImage: "square.and.arrow.down")
                                .font(.headline).foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(.orange)
                                .cornerRadius(13)
                        }

                        // Leave without saving
                        Button {
                            showSettingsPanel = false
                            leaveTest()
                        } label: {
                            Label("Leave Without Saving", systemImage: "xmark.circle")
                                .font(.headline).foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(.red.opacity(0.85))
                                .cornerRadius(13)
                        }
                    }
                    .padding(24)
                    .frame(width: 340)
                    .background(.black.opacity(0.88))
                    .cornerRadius(22)
                }
            }

            // Eye-switch overlay — full-screen prompt between OD and OS tests
            Attachment(id: "EyeSwitchOverlay") {
                if showEyeSwitchOverlay {
                    VStack(spacing: 28) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.green)

                        Text("Right Eye (OD) Complete")
                            .font(.largeTitle).fontWeight(.bold).foregroundColor(.white)

                        Divider().background(.white.opacity(0.3)).frame(width: 320)

                        VStack(spacing: 10) {
                            Text("Now testing: LEFT Eye (OS)")
                                .font(.title2).fontWeight(.semibold).foregroundColor(.orange)
                            Text("Please cover your RIGHT eye\nbefore continuing.")
                                .font(.body).foregroundColor(.white.opacity(0.85))
                                .multilineTextAlignment(.center)
                        }

                        Button {
                            showEyeSwitchOverlay = false
                            testActive = true
                            scheduleNextStimulus()
                        } label: {
                            Label("Begin Left Eye Test", systemImage: "arrow.right.circle.fill")
                                .font(.headline).fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 32).padding(.vertical, 16)
                                .background(.orange)
                                .cornerRadius(14)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(36)
                    .frame(width: 420)
                    .background(.black.opacity(0.90))
                    .cornerRadius(26)
                }
            }
        }
        .onAppear {
            if let saved = SavedTestProgress.load() {
                scheduledTrials = saved.remainingTrials
                currentTrialID = saved.completedTrialID
                hitCount = saved.hitCount
                missedCount = saved.missedCount
                SavedTestProgress.clear()
                print("Session resumed — \(saved.remainingTrials.count) trials remaining")
            } else {
                var allTrials: [ScheduledTrial] = []
                for location in clinicalGrid {
                    for (index, brightness) in brightnessLevels.enumerated() {
                        allTrials.append(ScheduledTrial(
                            location: location,
                            brightnessValue: brightness,
                            brightnessLevelIndex: index
                        ))
                    }
                }
                scheduledTrials = allTrials.shuffled()
                print("New session started — \(scheduledTrials.count) trials queued")
            }

            testActive = true
            scheduleNextStimulus()

            // Generate a fresh detachment zone when simulation mode starts
            if simulationModeEnabled {
                let severity = DetachmentSeverity(rawValue: simulationSeverityRaw) ?? .mild
                let zone = severity.generate()
                detachmentZone = zone
                if let z = zone {
                    print(z.locationDescription)
                } else {
                    print("Normal Vision — no detachment zone, full field healthy")
                }
            }

            // Auto-start voice control if the user enabled it from the menu
            if voiceControlEnabled {
                speech.requestPermissionAndStart()
            }
        }
        .onChange(of: speech.keywordFiredAt) { _, _ in
            // Voice keyword detected — act whenever voice control is enabled, but never during simulation
            guard voiceControlEnabled, !simulationModeEnabled else { return }
            handleSawIt()
        }
    }

    private func createClinicalStimulus(angleDegrees: Float, eccentricityDegrees: Float, trialID: Int, brightness: Float) -> ModelEntity {
        // DEBUG: Big yellow spheres for simulator visibility
        let distance: Float = 2.0 // 2 meters from user
        let sphereRadius: Float = 0.04 // Smaller, more clinically accurate

        // Convert degrees to radians
        let angleRad = angleDegrees * .pi / 180.0
        let eccentricityRad = eccentricityDegrees * .pi / 180.0

        // Convert spherical to Cartesian coordinates
        let x = distance * sin(eccentricityRad) * cos(angleRad)
        let y = distance * sin(eccentricityRad) * sin(angleRad)
        let z = -distance * cos(eccentricityRad)

        // White stimulus — opacity carries the brightness level so it fades into the white background.
        // NOTE: Per-eye (monocular) rendering requires StimulusShader.metal + Metal Toolchain.
        //       Install via Xcode → Settings → Platforms, then re-add the shader and swap to CustomMaterial.
        let stimulusColor = UIColor(white: 1.0, alpha: CGFloat(brightness))

        // Create stimulus sphere
        let stimulus = ModelEntity(
            mesh: .generateSphere(radius: sphereRadius),
            materials: [UnlitMaterial(color: stimulusColor)]
        )
        stimulus.position = SIMD3<Float>(x, y, z)
        stimulus.name = "Stimulus_\(trialID)"


        return stimulus
    }

    private func scheduleNextStimulus() {
        guard testActive else { return }

        let delay = Double.random(in: 1.5...3.5)

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard self.testActive else { return }
            self.spawnPeripheralStimulus()
        }
    }

    private func spawnPeripheralStimulus() {
        guard testActive else { return }

        // Remove previous stimulus if it exists
        if let oldStimulus = currentStimulus {
            oldStimulus.removeFromParent()
            currentStimulus = nil
        }

        if scheduledTrials.isEmpty {
            print("All \(clinicalGrid.count * brightnessLevels.count) trials complete.")
            completeTest()
            return
        }

        let scheduledTrial = scheduledTrials.removeFirst()
        let location = scheduledTrial.location
        currentAngleDegrees = location.angleDegrees
        currentEccentricityDegrees = location.eccentricityDegrees
        currentBrightnessIndex = scheduledTrial.brightnessLevelIndex
        currentBrightness = scheduledTrial.brightnessValue

        print("Trial \(currentTrialID + 1)/228  |  Angle: \(String(format: "%.0f", location.angleDegrees))  Ecc: \(String(format: "%.0f", location.eccentricityDegrees))  Brightness: \(brightnessLabels[currentBrightnessIndex])")

        // Simulation mode: if stimulus falls inside the detachment zone, skip rendering entirely.
        // The retina cannot perceive this location, so the stimulus simply never appears.
        if simulationModeEnabled {
            let angleRad = location.angleDegrees * Float.pi / 180.0
            let xDeg = cos(angleRad) * location.eccentricityDegrees
            let yDeg = sin(angleRad) * location.eccentricityDegrees
            if detachmentZone?.isHealthy(xDeg: xDeg, yDeg: yDeg) == false {
                print("Trial \(currentTrialID + 1)/228  |  BLIND ZONE — skipped")
                missedCount += 1
                let trial = StimulusTrial(
                    trialID: currentTrialID,
                    spotID: currentTrialID,
                    angleDegrees: location.angleDegrees,
                    eccentricityDegrees: location.eccentricityDegrees,
                    spawnTime: Date(),
                    responseTime: nil,
                    wasHit: false,
                    timedOut: true,
                    brightnessValue: currentBrightness,
                    brightnessLevelIndex: currentBrightnessIndex
                )
                trials.append(trial)
                currentTrialID += 1
                scheduleNextStimulus()
                return
            }
        }

        // Create and add the clinical stimulus
        let stimulus = createClinicalStimulus(
            angleDegrees: location.angleDegrees,
            eccentricityDegrees: location.eccentricityDegrees,
            trialID: currentTrialID,
            brightness: currentBrightness
        )
        rootEntity.addChild(stimulus)
        currentStimulus = stimulus
        currentSpawnTime = Date()

        print("✅ Stimulus added to scene. Should be VISIBLE NOW!")

        // Flash duration and response window
        let flashDuration  = 0.6
        let timeoutSeconds = 1.5
        let thisTrialID = currentTrialID

        // Simulation mode: auto-respond based on the selected vision profile
        if simulationModeEnabled {
            let angleRad = location.angleDegrees * Float.pi / 180.0
            let xDeg = cos(angleRad) * location.eccentricityDegrees
            let yDeg = sin(angleRad) * location.eccentricityDegrees
            scheduleSimulatedResponse(xDeg: xDeg, yDeg: yDeg,
                                      eccentricityDeg: location.eccentricityDegrees,
                                      brightness: currentBrightness,
                                      trialID: thisTrialID)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + flashDuration) {
            if let stim = self.currentStimulus, stim.name == "Stimulus_\(thisTrialID)" {
                stim.removeFromParent()
            }
        }

        // Schedule auto-timeout (response window)
        DispatchQueue.main.asyncAfter(deadline: .now() + timeoutSeconds) {
            self.handleTimeout(
                forTrialID: thisTrialID,
                angle: location.angleDegrees * .pi / 180.0,
                eccentricity: location.eccentricityDegrees
            )
        }

        currentTrialID += 1
    }

    private func handleTimeout(forTrialID trialID: Int, angle: Float, eccentricity: Float) {
        guard testActive,
              let stimulus = currentStimulus,
              stimulus.name == "Stimulus_\(trialID)" else {
            return
        }

        // Clean up — flash timer may have already removed it, removeFromParent is safe either way
        stimulus.removeFromParent()
        currentStimulus = nil

        if currentSpawnTime == nil {
            // spawnTime was cleared by handleSawIt — hit already recorded, just move on
            scheduleNextStimulus()
            return
        }

        // No response within the window — record as miss
        currentSpawnTime = nil
        missedCount += 1

        print("Trial \(trialID + 1)/228  |  MISSED  |  Hits: \(hitCount)  Misses: \(missedCount)")

        let trial = StimulusTrial(
            trialID: trialID,
            spotID: trialID,
            angleDegrees: angle * 180.0 / .pi,
            eccentricityDegrees: eccentricity,
            spawnTime: Date(),
            responseTime: nil,
            wasHit: false,
            timedOut: true,
            brightnessValue: currentBrightness,
            brightnessLevelIndex: currentBrightnessIndex
        )
        trials.append(trial)

        scheduleNextStimulus()
    }

    private func createDebugGrid() -> Entity {
        let gridContainer = Entity()
        gridContainer.name = "DebugGrid"

        // Grid parameters
        let gridSize: Float = 4.0 // 4 meters wide/tall
        let gridSpacing: Float = 0.5 // Lines every 0.5 meters
        let gridDistance: Float = 3.0 // 3 meters in front of user
        let lineThickness: Float = 0.005 // Very thin lines

        // Faint gray color for the grid
        let gridMaterial = UnlitMaterial(color: UIColor(white: 0.7, alpha: 0.3))

        // Create vertical lines
        let numLines = Int(gridSize / gridSpacing) + 1
        for i in 0..<numLines {
            let x = -gridSize / 2 + Float(i) * gridSpacing

            let verticalLine = ModelEntity(
                mesh: .generateBox(width: lineThickness, height: gridSize, depth: lineThickness),
                materials: [gridMaterial]
            )
            verticalLine.position = SIMD3<Float>(x, 0, -gridDistance)
            gridContainer.addChild(verticalLine)
        }

        // Create horizontal lines
        for i in 0..<numLines {
            let y = -gridSize / 2 + Float(i) * gridSpacing

            let horizontalLine = ModelEntity(
                mesh: .generateBox(width: gridSize, height: lineThickness, depth: lineThickness),
                materials: [gridMaterial]
            )
            horizontalLine.position = SIMD3<Float>(0, y, -gridDistance)
            gridContainer.addChild(horizontalLine)
        }

        return gridContainer
    }

    private func handleSawIt() {
        guard testActive else { return }

        // Require an active spawn time — nil means this trial was already responded to
        if let stimulus = currentStimulus, let spawnTime = currentSpawnTime {

            let responseTime = Date()

            // Get stimulus info from its name
            if let trialIDStr = stimulus.name.split(separator: "_").last,
               let trialID = Int(trialIDStr) {

                // Record successful trial
                let trial = StimulusTrial(
                    trialID: trialID,
                    spotID: trialID,
                    angleDegrees: currentAngleDegrees,
                    eccentricityDegrees: currentEccentricityDegrees,
                    spawnTime: spawnTime,
                    responseTime: responseTime,
                    wasHit: true,
                    timedOut: false,
                    brightnessValue: currentBrightness,
                    brightnessLevelIndex: currentBrightnessIndex
                )
                trials.append(trial)
                hitCount += 1

                print("Trial \(trialID + 1)/228  |  HIT  |  RT: \(String(format: "%.3f", trial.reactionTimeSeconds ?? 0))s  |  Hits: \(hitCount)  Misses: \(missedCount)")
            }

            // Mark as responded — stimulus stays visible until the flash timer removes it.
            // handleTimeout will see nil spawnTime and skip recording a miss.
            currentSpawnTime = nil
        }
    }

    private func restartTest() {

        // Clear current stimulus
        currentStimulus?.removeFromParent()
        currentStimulus = nil

        // Reset counters
        hitCount = 0
        missedCount = 0
        trials = []
        currentTrialID = 0
        currentSpawnTime = nil

        // Regenerate all 228 trials (76 locations × 3 brightness levels)
        var allTrials: [ScheduledTrial] = []
        for location in clinicalGrid {
            for (index, brightness) in brightnessLevels.enumerated() {
                allTrials.append(ScheduledTrial(
                    location: location,
                    brightnessValue: brightness,
                    brightnessLevelIndex: index
                ))
            }
        }
        scheduledTrials = allTrials.shuffled()

        testActive = true
        scheduleNextStimulus()
        print("Test restarted — \(scheduledTrials.count) trials queued")
    }

    private func saveAndQuit() {
        testActive = false

        // Snapshot remaining trials and current counters
        SavedTestProgress(
            remainingTrials: scheduledTrials,
            completedTrialID: currentTrialID,
            hitCount: hitCount,
            missedCount: missedCount,
            savedAt: Date()
        ).save()

        print("Progress saved — \(scheduledTrials.count) trials remaining")

        Task {
            await dismissImmersiveSpace()
            try? await Task.sleep(nanoseconds: 100_000_000)
            openWindow(id: "MainWindow")
        }
    }

    // MARK: - Simulation fast-forward (bulk-complete all remaining trials instantly)

    private func fastForwardSimulation() {
        guard simulationModeEnabled else { return }

        // Stop the live test loop
        testActive = false
        currentStimulus?.removeFromParent()
        currentStimulus = nil
        currentSpawnTime = nil

        let severity = DetachmentSeverity(rawValue: simulationSeverityRaw) ?? .mild
        let zone = detachmentZone   // use already-generated zone if available

        // Record the currently active trial if one was mid-display
        if let activeTrialName = currentStimulus?.name,
           let trialIDStr = activeTrialName.split(separator: "_").last,
           let trialID = Int(trialIDStr) {
            recordSimulatedTrial(zone: zone, severity: severity, trialID: trialID,
                                 angleDeg: currentAngleDegrees,
                                 eccentricityDeg: currentEccentricityDegrees,
                                 brightness: currentBrightness,
                                 brightnessIndex: currentBrightnessIndex)
        }

        // Bulk-record every remaining scheduled trial
        for scheduled in scheduledTrials {
            let loc = scheduled.location
            recordSimulatedTrial(zone: zone, severity: severity, trialID: currentTrialID,
                                 angleDeg: loc.angleDegrees,
                                 eccentricityDeg: loc.eccentricityDegrees,
                                 brightness: scheduled.brightnessValue,
                                 brightnessIndex: scheduled.brightnessLevelIndex)
            currentTrialID += 1
        }
        scheduledTrials = []

        // Simulation is always a single test — ensure monocular flag doesn't trigger eye switching
        monocularModeEnabled = false

        print("Fast forward complete — \(trials.count) trials processed")
        completeTest()
    }

    private func recordSimulatedTrial(zone: DetachmentZone?, severity: DetachmentSeverity,
                                      trialID: Int, angleDeg: Float, eccentricityDeg: Float,
                                      brightness: Float, brightnessIndex: Int) {
        let angleRad = angleDeg * Float.pi / 180.0
        let xDeg = cos(angleRad) * eccentricityDeg
        let yDeg = sin(angleRad) * eccentricityDeg

        let sensitivity = zone?.sensitivity(xDeg: xDeg, yDeg: yDeg, brightness: brightness)
                       ?? DetachmentZone.healthySensitivity(xDeg: xDeg, yDeg: yDeg, brightness: brightness)
        let isMistake = Double.random(in: 0...1) < (10.0 / 228.0)
        let wasHit = isMistake ? (Double.random(in: 0...1) > sensitivity) : (Double.random(in: 0...1) < sensitivity)

        let spawnTime = Date()
        let rt = wasHit ? severity.reactionTime(eccentricityDeg: eccentricityDeg, brightness: brightness) : nil

        let trial = StimulusTrial(
            trialID: trialID, spotID: trialID,
            angleDegrees: angleDeg,
            eccentricityDegrees: eccentricityDeg,
            spawnTime: spawnTime,
            responseTime: wasHit ? spawnTime.addingTimeInterval(rt!) : nil,
            wasHit: wasHit, timedOut: !wasHit,
            brightnessValue: brightness,
            brightnessLevelIndex: brightnessIndex
        )
        trials.append(trial)
        if wasHit { hitCount += 1 } else { missedCount += 1 }
    }

    // MARK: - Simulation auto-response

    private func scheduleSimulatedResponse(xDeg: Float, yDeg: Float, eccentricityDeg: Float, brightness: Float, trialID: Int) {
        let severity = DetachmentSeverity(rawValue: simulationSeverityRaw) ?? .mild
        let sensitivity = detachmentZone?.sensitivity(xDeg: xDeg, yDeg: yDeg, brightness: brightness)
                       ?? DetachmentZone.healthySensitivity(xDeg: xDeg, yDeg: yDeg, brightness: brightness)

        // Inject ~10 random mistakes across 228 trials (~4.4% chance per trial)
        let isMistake = Double.random(in: 0...1) < (10.0 / 228.0)
        let willSee   = isMistake ? (Double.random(in: 0...1) > sensitivity) : (Double.random(in: 0...1) < sensitivity)

        let inDetachment = !(detachmentZone?.isHealthy(xDeg: xDeg, yDeg: yDeg) ?? true)
        print("Sim  |  \(severity.rawValue)  |  \(inDetachment ? "DETACHMENT" : "healthy")  |  sens \(String(format: "%.2f", sensitivity))  |  \(willSee ? "WILL SEE" : "WILL MISS")\(isMistake ? "  [mistake]" : "")")

        guard willSee else { return }  // miss: let the normal 3-second timeout fire

        let rt = severity.reactionTime(eccentricityDeg: eccentricityDeg, brightness: brightness)
        DispatchQueue.main.asyncAfter(deadline: .now() + rt) {
            guard self.testActive, self.currentStimulus?.name == "Stimulus_\(trialID)" else { return }
            self.handleSawIt()
        }
    }

    private func completeTest() {
        testActive = false

        // Simulation is always single-eye — clear monocular flag before it can trigger eye switching
        if simulationModeEnabled { monocularModeEnabled = false }
        let modeName = simulationModeEnabled
            ? (DetachmentSeverity(rawValue: simulationSeverityRaw)?.rawValue ?? simulationSeverityRaw)
            : "Normal Test"
        simulationModeEnabled = false

        saveSession(modeName: modeName)
        exportTrialsToCSV(modeName: modeName)

        if currentEye == .right && monocularModeEnabled {
            // Right eye (OD) done — prepare left eye (OS) (monocular only)
            print("Right eye (OD) complete — switching to left eye (OS)")
            currentEye = .left
            trials.removeAll()
            hitCount = 0; missedCount = 0; currentTrialID = 0
            var all: [ScheduledTrial] = []
            for loc in clinicalGrid {
                for (i, b) in brightnessLevels.enumerated() {
                    all.append(ScheduledTrial(location: loc, brightnessValue: b, brightnessLevelIndex: i))
                }
            }
            scheduledTrials = all.shuffled()
            showEyeSwitchOverlay = true
        } else {
            // Test done — monocular left eye, normal test, or simulation (single-eye)
            print("\(currentEye == .left ? "Left eye (OS)" : "Test") complete — all done")
            currentEye = .right
            monocularModeEnabled = false
            Task {
                await dismissImmersiveSpace()
                try? await Task.sleep(nanoseconds: 100_000_000)
                openWindow(id: "MainWindow")
            }
        }
    }

    private func leaveTest() {
        testActive = false
        let modeName = simulationModeEnabled
            ? (DetachmentSeverity(rawValue: simulationSeverityRaw)?.rawValue ?? simulationSeverityRaw)
            : "Normal Test"
        simulationModeEnabled = false
        saveSession(modeName: modeName)
        exportTrialsToCSV(modeName: modeName)
        Task {
            await dismissImmersiveSpace()
            try? await Task.sleep(nanoseconds: 100_000_000)
            openWindow(id: "MainWindow")
        }
    }

    private func saveSession(modeName: String = "Normal Test") {
        guard !trials.isEmpty else { return }
        let session = SimpleTestSession(
            id: UUID(),
            date: Date(),
            completedTrials: trials.count,
            totalTrials: clinicalGrid.count * brightnessLevels.count,
            hitCount: hitCount,
            missedCount: missedCount,
            trials: trials,
            modeName: modeName
        )
        SimpleSessionStore.append(session)
        print("Session saved — \(trials.count) trials  Hits: \(hitCount)  Misses: \(missedCount)  Mode: \(modeName)")
    }

    private func printTestResults() {
        let rts = trials.compactMap { $0.reactionTimeSeconds }
        let avgRT = rts.isEmpty ? 0 : rts.reduce(0, +) / Double(rts.count)
        print("")
        print("-------- SESSION SUMMARY --------")
        print("Trials: \(trials.count)   Hits: \(hitCount)   Misses: \(missedCount)")
        if !rts.isEmpty {
            print("Avg RT: \(String(format: "%.3f", avgRT))s   Min: \(String(format: "%.3f", rts.min()!))s   Max: \(String(format: "%.3f", rts.max()!))s")
        }
        print("---------------------------------")
    }

    private func exportTrialsToCSV(modeName: String = "Normal Test") {
        // Skip if no trials
        guard !trials.isEmpty else { return }

        // Create CSV content with brightness as int (1=least bright, 2=medium, 3=brightest)
        var csv = "trial_index,angle_deg,ecc_deg,hit,reaction_time_sec,brightness_value\n"

        for trial in trials {
            let trialIndex = trial.trialID
            let angleDeg = String(format: "%.1f", trial.angleDegrees)
            let eccDeg = String(format: "%.1f", trial.eccentricityDegrees)
            let hit = trial.wasHit ? "true" : "false"
            let rtSec = trial.reactionTimeSeconds.map { String(format: "%.3f", $0) } ?? "-1.0"
            let brightnessInt = trial.brightnessLevelIndex + 1
            csv += "\(trialIndex),\(angleDeg),\(eccDeg),\(hit),\(rtSec),\(brightnessInt)\n"
        }

        // Print full CSV to terminal (labelled by eye)
        let eyeLabel = currentEye == .right ? "OD (Right Eye)" : "OS (Left Eye)"
        print("\n========== CSV OUTPUT — \(eyeLabel) ==========")
        print(csv)
        print("==============================================\n")

        // Generate filename with timestamp — mode name included for easy identification
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let eyeTag  = currentEye == .right ? "OD" : "OS"
        let modeTag = modeName.replacingOccurrences(of: " ", with: "_")
        let filename = "perimetry_\(modeTag)_\(eyeTag)_\(timestamp).csv"

        // Write file on a background thread so it never blocks the main thread
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsPath.appendingPathComponent(filename)
        Task.detached(priority: .background) {
            do {
                try csv.write(to: fileURL, atomically: true, encoding: .utf8)
                let fullPath = fileURL.path
                await MainActor.run {
                    print("CSV exported: \(fullPath)")
                    self.csvExportPath = fullPath
                }
            } catch {
                await MainActor.run {
                    print("CSV export failed: \(error.localizedDescription)")
                    self.csvExportPath = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
}
