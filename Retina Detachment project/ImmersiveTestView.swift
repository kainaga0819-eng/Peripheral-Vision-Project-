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

    // Fixation break tracking
    @State private var fixationBreakCount = 0
    @State private var lastFixationBreakTarget: String? = nil
    @State private var currentTrialFixationBreak = false
    @State private var currentTrialFixationBreakTarget: String = ""

    private let settings = TestSettings.shared

    var body: some View {
        RealityView { content, attachments in
            // NOTEBOOK: AnchorEntity(.head) locks the entire scene to the user's head pose.
            // All children move with the user — stimuli never drift to world-space floor.
            let headAnchor = AnchorEntity(.head)

            // NOTEBOOK: rootEntity is the scene root. Parenting it to headAnchor means every
            // stimulus, background, and detector is positioned relative to the head, not the world.
            headAnchor.addChild(rootEntity)

            // NOTEBOOK: rootEntity.position offsets the bowl centre from the head origin.
            // yOffsetMeters / zOffsetMeters calibrate vertical height and forward depth.
            let yOffsetMeters: Float = -5.55
            let zOffsetMeters: Float = -2.45
            rootEntity.position = SIMD3<Float>(0, yOffsetMeters, zOffsetMeters)

            // Add head anchor to scene
            content.add(headAnchor)

            // Attach HUD panel to head anchor (left side, in front of user)
            if let hudEntity = attachments.entity(for: "TestHUD") {
                hudEntity.position = SIMD3<Float>(-0.25, -0.10, -0.70)
                headAnchor.addChild(hudEntity)
            }

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

            // Fixation point is now a SwiftUI attachment (head-anchored) so it reliably
            // receives look+pinch input. The 3D entity is gone; the attachment IS the fixation.
            if let fixAttachment = attachments.entity(for: "FixationButton") {
                fixAttachment.position = SIMD3<Float>(0, 0, -0.70)
                headAnchor.addChild(fixAttachment)
            }

            // Fixation break detector ring lives in scene space (rootEntity) near the bowl centre.
            // These are a best-effort signal; primary response is via the SwiftUI attachment above.
            let ringRadius: Float = 0.08
            let detectorRadius: Float = 0.025
            let detectorCount = 12
            let fixPos = PeripheralGeometry.fixationPosition(distance: settings.bowlRadiusMeters)
            for i in 0..<detectorCount {
                let angle = Float(i) * (2.0 * .pi / Float(detectorCount))
                let detector = ModelEntity(
                    mesh: .generateSphere(radius: detectorRadius),
                    materials: [UnlitMaterial(color: .clear)]
                )
                detector.name = "FixBreak_\(i)"
                detector.position = SIMD3<Float>(
                    fixPos.x + ringRadius * cos(angle),
                    fixPos.y + ringRadius * sin(angle),
                    fixPos.z
                )
                detector.components.set(InputTargetComponent())
                detector.components.set(CollisionComponent(shapes: [.generateSphere(radius: detectorRadius)]))
                rootEntity.addChild(detector)
            }

            // Add some lighting
            let directionalLight = DirectionalLight()
            directionalLight.light.intensity = 5000
            directionalLight.look(at: [0, 0, 0], from: [0, 2, 2], relativeTo: nil)
            rootEntity.addChild(directionalLight)

        } attachments: {
            // NOTEBOOK: FixationButton is a SwiftUI Attachment (not a 3D entity).
            // visionOS look+pinch only fires here when the user is gazing directly at the dot.
            // A response is accepted only while inResponseWindow is true (stimulus is live).
            Attachment(id: "FixationButton") {
                Button(action: {
                    if inResponseWindow {
                        handleResponse()
                    }
                }) {
                    ZStack {
                        // Outer ring — subtle hit-area indicator
                        Circle()
                            .stroke(.white.opacity(0.25), lineWidth: 1)
                            .frame(width: 36, height: 36)
                        // Inner white dot — the fixation point
                        Circle()
                            .fill(.white)
                            .frame(width: 12, height: 12)
                    }
                }
                .buttonStyle(.plain)
            }

            Attachment(id: "TestHUD") {
                VStack(alignment: .leading, spacing: 12) {
                    // === TRIAL PROGRESS COUNTER ===
                    VStack(alignment: .leading, spacing: 4) {
                        if trialList.isEmpty {
                            Text("Trial: 0 / 0")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        } else if currentTrialIndex >= trialList.count {
                            Text("Trial: \(trialList.count) / \(trialList.count)")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.green)
                            Text("Complete!")
                                .font(.headline)
                                .foregroundColor(.green)
                        } else {
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
                    Text("Fix breaks: \(fixationBreakCount)")
                        .font(.caption)
                        .foregroundColor(fixationBreakCount > 0 ? .orange : .white)
                    if let target = lastFixationBreakTarget {
                        Text("Last: \(target)")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }

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
            }

        }
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    handleTap(on: value.entity)
                }
        )
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
        // NOTEBOOK: Any spatial tap that reaches here hit a 3D entity, NOT the fixation button.
        // That means the user pinched while looking away from the fixation dot → fixation break.
        print("Off-fixation entity tap: \(entity.name)")
        fixationBreakCount += 1
        lastFixationBreakTarget = entity.name
        currentTrialFixationBreak = true
        currentTrialFixationBreakTarget = entity.name
    }

    /// Handle user response (button press or tap)
    private func handleResponse() {
        // Only accept responses during response window
        guard inResponseWindow else {
            print("Response outside response window - ignored")
            return
        }

        // NOTEBOOK: reactionTimeSec = now − stimulusOnsetTime (both from CACurrentMediaTime).
        // Millisecond precision. Only valid when stimulusOnsetTime was set at spawn.
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

        // NOTEBOOK: angularToPosition converts (eccentricity°, polar°, radius) → SIMD3<Float>.
        // All stimuli lie on a sphere of constant radius — the Humphrey bowl model.
        let position = PeripheralGeometry.angularToPosition(
            eccentricityDeg: eccentricityDeg,
            polarAngleDeg: polarAngleDeg,
            radius: radius
        )

        // NOTEBOOK: length(position) must equal radius for every trial.
        // This confirms the bowl geometry is correct — every stimulus is equidistant from the user.
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

        // Reset fixation break flags for this trial
        currentTrialFixationBreak = false
        currentTrialFixationBreakTarget = ""

        // Open response window
        inResponseWindow = true

        rootEntity.addChild(stimulus)

        // NOTEBOOK: stimulusOnsetTime stamps the exact moment the stimulus appears.
        // Reaction time = fixation-button press time − this value (measured in handleResponse).
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

        // NOTEBOOK: Response window closes after responseWindowMs with no pinch → trial is a miss.
        // reactionTimeSec is stored as -1.0 (not nil) so every CSV row has a numeric RT field.
        let responseDelay = settings.responseWindowMs / 1000.0
        DispatchQueue.main.asyncAfter(deadline: .now() + responseDelay) {
            if self.currentStimulusID == stimulusID && self.inResponseWindow {
                self.finalizeTrial(seen: false, reactionTimeSec: -1.0)
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
            bowlRadiusMeters: settings.bowlRadiusMeters,
            fixationBreak: currentTrialFixationBreak,
            fixationBreakTarget: currentTrialFixationBreakTarget
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


