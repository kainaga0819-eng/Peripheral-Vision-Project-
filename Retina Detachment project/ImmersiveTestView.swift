import SwiftUI
import RealityKit
import simd
import QuartzCore
import UIKit

struct ImmersiveTestView: View {
    @State private var currentStimulus: ModelEntity?
    @State private var testActive = false
    @State private var score = 0
    @State private var missedCount = 0
    @State private var rootEntity: Entity = Entity()
    @State private var inResponseWindow = false
    @State private var currentStimulusID: UUID?  // Track which stimulus is active
    @State private var currentTrialFinalized = false  // Race-safe: only finalize once
    @State private var stimulusOnsetTime: Double?  // For reaction time
    @State private var lastReactionTimeMs: Double?  // For UI/debug

    // Trial-based testing
    @State private var trialList: [TestLocation] = []  // Pre-generated, shuffled locations
    @State private var currentTrialIndex = 0
    @State private var sessionTrials: [TrialRecord] = []  // Collected trial data
    @State private var sessionStartTime: Date?
    @State private var showExportSheet = false
    @State private var lastExportedURL: URL? = nil
    @State private var exportStatusText: String? = nil

    private let settings = TestSettings.shared

    var body: some View {
        RealityView { content in
            // Create head anchor - makes entire stimulus bowl follow user's head
            let headAnchor = AnchorEntity(.head)

            // Attach rootEntity to head anchor (not directly to world)
            headAnchor.addChild(rootEntity)

            // Add head anchor to scene
            content.add(headAnchor)

            // Create dark background environment (use backgroundLevel from settings)
            let backgroundBrightness = CGFloat(settings.backgroundLevel)
            let background = ModelEntity(
                mesh: .generateSphere(radius: 50),
                materials: [SimpleMaterial(color: UIColor(white: backgroundBrightness, alpha: 1.0), isMetallic: false)]
            )
            background.scale = SIMD3<Float>(-1, 1, 1)
            rootEntity.addChild(background)

            // Invisible tap-catcher so taps can be registered during the whole response window
            // (Humphrey-style response is "press when you see it", not "tap the dot")
            let tapCatcherRadius: Float = 5.0
            let tapCatcher = ModelEntity(
                mesh: .generateSphere(radius: tapCatcherRadius),
                materials: [UnlitMaterial(color: .clear)]
            )
            tapCatcher.name = "TapCatcher"
            tapCatcher.position = .zero
            tapCatcher.components.set(InputTargetComponent())
            tapCatcher.components.set(CollisionComponent(shapes: [.generateSphere(radius: tapCatcherRadius)]))
            rootEntity.addChild(tapCatcher)

            // Create central fixation point (small, glowing)
            let fixationPoint = ModelEntity(
                mesh: .generateSphere(radius: 0.01),
                materials: [SimpleMaterial(color: .white, isMetallic: false)]
            )
            fixationPoint.position = PeripheralGeometry.fixationPosition(distance: settings.bowlRadiusMeters)

            // Make fixation point glow
            let fixationMaterial = UnlitMaterial(color: .white)
            fixationPoint.model?.materials = [fixationMaterial]

            rootEntity.addChild(fixationPoint)

            // Add some lighting
            let directionalLight = DirectionalLight()
            directionalLight.light.intensity = 5000
            directionalLight.look(at: [0, 0, 0], from: [0, 2, 2], relativeTo: nil)
            rootEntity.addChild(directionalLight)

        }
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    handleTap(on: value.entity)
                }
        )
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 12) {
                // === TRIAL PROGRESS COUNTER (ALWAYS VISIBLE, LARGE) ===
                VStack(alignment: .leading, spacing: 4) {
                    if trialList.isEmpty {
                        Text("Trial: 0 / 0")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    } else if currentTrialIndex >= trialList.count {
                        // Test complete: show total/total
                        Text("Trial: \(trialList.count) / \(trialList.count)")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                        Text("Complete!")
                            .font(.headline)
                            .foregroundColor(.green)
                    } else {
                        // Active trial: show (currentTrialIndex + 1) for 1-based counting
                        let currentTrial = currentTrialIndex + 1
                        let totalTrials = trialList.count
                        let remainingTrials = totalTrials - currentTrial

                        Text("Trial: \(currentTrial) / \(totalTrials)")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        Text("Remaining: \(remainingTrials)")
                            .font(.headline)
                            .foregroundColor(.gray)
                    }
                }
                .padding(12)
                .background(.black.opacity(0.8))
                .cornerRadius(10)

                Divider()
                    .background(.white.opacity(0.3))

                // Stats
                Text("Seen: \(score) | Missed: \(missedCount)")
                    .font(.title3)
                    .foregroundColor(.white)
                Text("RT: \(lastReactionTimeMs.map { "\(Int($0)) ms" } ?? "--")")
                    .font(.caption)
                    .foregroundColor(.white)

                if currentTrialIndex >= trialList.count && !trialList.isEmpty {
                    Divider()
                        .background(.white.opacity(0.3))

                    Button("Export CSV") {
                        let url = exportTrialsToCSV()
                        lastExportedURL = url
                        exportStatusText = "Saved CSV to:\n\(url.path)"
                        showExportSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .font(.headline)

                    // Show export status and copy button
                    if let statusText = exportStatusText {
                        Text(statusText)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.green)
                            .padding(.top, 8)

                        Button("Copy Path") {
                            if let url = lastExportedURL {
                                UIPasteboard.general.string = url.path
                                exportStatusText = "Copied path:\n\(url.path)"
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(.gray)
                        .font(.caption)
                    }
                }
            }
            .padding(16)
            .background(.black.opacity(0.7))
            .cornerRadius(12)
            .padding()
        }
        .overlay(alignment: .topTrailing) {
            if inResponseWindow {
                Button("I Saw It") {
                    handleResponse()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .font(.title2)
                .padding()
            }
        }
        .sheet(isPresented: $showExportSheet) {
            if let url = lastExportedURL {
                ShareSheet(activityItems: [url])
            } else {
                Text("No export file found.")
            }
        }
        .onAppear {
            startTest()
        }
    }

    private func startTest() {
        // Generate shuffled trial list
        trialList = settings.generateShuffledTrials()
        currentTrialIndex = 0
        sessionTrials = []
        sessionStartTime = Date()
        score = 0
        missedCount = 0

        testActive = true
        print("Peripheral vision test started")
        print("Total trials: \(trialList.count)")
        print("Locations: \(settings.generateTestLocations().count)")
        print("Repetitions per location: \(settings.repetitionsPerLocation)")

        scheduleNextStimulus()
    }

    private func scheduleNextStimulus() {
        guard testActive else { return }
        guard currentTrialIndex < trialList.count else {
            print("Test complete! \(sessionTrials.count) trials recorded.")
            return
        }

        // Random delay between stimuli
        let delay = Double.random(in: settings.intervalRange)

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.spawnPeripheralStimulus()
        }
    }

    private func handleTap(on entity: Entity) {
        print("Tapped on entity: \(entity.name)")

        // Delegate to main response handler
        handleResponse()
    }

    /// Handle user response (button press or tap)
    private func handleResponse() {
        // Only accept responses during response window
        guard inResponseWindow else {
            print("Response outside response window - ignored")
            return
        }

        // Calculate reaction time
        let now = CACurrentMediaTime()
        var reactionTimeSec: Double? = nil
        if let onset = stimulusOnsetTime {
            reactionTimeSec = now - onset
            lastReactionTimeMs = reactionTimeSec! * 1000.0
            print("Reaction time: \(lastReactionTimeMs!) ms")
        }

        // Finalize trial with seen=true
        finalizeTrial(seen: true, reactionTimeSec: reactionTimeSec)
    }

    private func spawnPeripheralStimulus() {
        // Clean up any existing stimulus without counting it as a miss here.
        // Misses are counted only when the response window closes.
        if let existing = currentStimulus {
            existing.removeFromParent()
            currentStimulus = nil
            currentStimulusID = nil
            inResponseWindow = false
        }

        // Check if we have more trials to run
        guard currentTrialIndex < trialList.count else {
            print("No more trials to run")
            return
        }

        // Get pre-defined location from trial list
        let location = trialList[currentTrialIndex]
        let eccentricityDeg = location.eccentricityDeg
        let polarAngleDeg = location.polarAngleDeg

        // Fixed radius from user (all stimuli at same distance = Humphrey's bowl)
        let radius = settings.bowlRadiusMeters

        // Convert angular coordinates to 3D position using geometry helper
        let position = PeripheralGeometry.angularToPosition(
            eccentricityDeg: eccentricityDeg,
            polarAngleDeg: polarAngleDeg,
            radius: radius
        )

        // DEBUG: Verify stimulus is at fixed bowl radius
        let actualDistance = length(position)
        print("DEBUG: Stimulus distance from origin = \(actualDistance)m (expected: \(radius)m)")

        // Convert angular stimulus size to physical size at bowl radius
        let stimulusDiameterMeters = PeripheralGeometry.angularDiameterToPhysical(
            angularDiameterDeg: settings.stimulusDiameterDeg,
            radius: radius
        )
        let stimulusRadius = stimulusDiameterMeters / 2.0

        // Create yellow sphere (Goldmann size III: 0.43°)
        let stimulus = ModelEntity(
            mesh: .generateSphere(radius: stimulusRadius),
            materials: [UnlitMaterial(color: .yellow)]
        )
        stimulus.position = position
        stimulus.name = "PeripheralStimulus"

        // Enable input handling
        stimulus.components.set(InputTargetComponent())
        stimulus.components.set(CollisionComponent(shapes: [.generateSphere(radius: stimulusRadius)]))

        currentStimulus = stimulus
        let stimulusID = UUID()
        currentStimulusID = stimulusID

        // Reset trial finalization flag
        currentTrialFinalized = false

        // Open response window
        inResponseWindow = true

        rootEntity.addChild(stimulus)

        // Record onset for reaction time
        stimulusOnsetTime = CACurrentMediaTime()
        lastReactionTimeMs = nil

        print("Spawned stimulus [\(currentTrialIndex + 1)/\(trialList.count)] at polarAngle: \(polarAngleDeg)°, eccentricity: \(eccentricityDeg)°")
        print("  Physical size: \(stimulusDiameterMeters * 1000)mm diameter at \(radius)m")

        // Remove stimulus after stimulusDurationMs (e.g., 200ms)
        let hideDelay = settings.stimulusDurationMs / 1000.0
        DispatchQueue.main.asyncAfter(deadline: .now() + hideDelay) {
            if self.currentStimulusID == stimulusID {
                // Remove the stimulus from scene (response window stays open)
                stimulus.removeFromParent()
                print("Stimulus removed after \(self.settings.stimulusDurationMs)ms (response window still open)")
            }
        }

        // Close response window after responseWindowMs (e.g., 1200ms total)
        let responseDelay = settings.responseWindowMs / 1000.0
        DispatchQueue.main.asyncAfter(deadline: .now() + responseDelay) {
            if self.currentStimulusID == stimulusID && self.inResponseWindow {
                // Response window closed - no response detected
                // Finalize trial as missed
                self.finalizeTrial(seen: false, reactionTimeSec: nil)
            }
        }
    }

    /// Finalize current trial (race-safe: only finalizes once per trial)
    private func finalizeTrial(seen: Bool, reactionTimeSec: Double?) {
        // Race-safe check: only finalize once
        guard !currentTrialFinalized else {
            print("Trial already finalized - ignoring duplicate finalization")
            return
        }
        guard currentTrialIndex < trialList.count else {
            print("No active trial to finalize")
            return
        }

        currentTrialFinalized = true

        // Get current location
        let location = trialList[currentTrialIndex]

        // Create trial record
        let trial = TrialRecord(
            id: currentStimulusID ?? UUID(),
            trialIndex: currentTrialIndex,
            location: location,
            onsetTimestamp: Date(timeIntervalSince1970: (stimulusOnsetTime ?? CACurrentMediaTime())),
            seen: seen,
            reactionTimeSec: reactionTimeSec,
            brightness: settings.stimulusBrightness,
            bowlRadiusMeters: settings.bowlRadiusMeters
        )

        sessionTrials.append(trial)

        // Update counters
        if seen {
            score += 1
            print("Trial \(currentTrialIndex + 1): SEEN (RT: \(reactionTimeSec.map { String(format: "%.3f", $0) } ?? "N/A")s)")
        } else {
            missedCount += 1
            print("Trial \(currentTrialIndex + 1): MISSED")
        }

        // Clean up
        inResponseWindow = false
        currentStimulusID = nil
        currentStimulus?.removeFromParent()
        currentStimulus = nil

        // Move to next trial
        currentTrialIndex += 1

        // Schedule next stimulus
        scheduleNextStimulus()
    }

    /// Export trials to CSV file and return URL
    private func exportTrialsToCSV() -> URL {
        var csv = TrialRecord.csvHeader + "\n"

        for trial in sessionTrials {
            csv += trial.toCSV() + "\n"
        }

        // Save to Documents directory
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let dateString = dateFormatter.string(from: sessionStartTime ?? Date())
        let filename = "perimetry_\(dateString).csv"
        let fileURL = documentsPath.appendingPathComponent(filename)

        do {
            try csv.write(to: fileURL, atomically: true, encoding: .utf8)
            print("Exported \(sessionTrials.count) trials to: \(fileURL.path)")
        } catch {
            print("Error writing CSV: \(error)")
        }

        return fileURL
    }
}
