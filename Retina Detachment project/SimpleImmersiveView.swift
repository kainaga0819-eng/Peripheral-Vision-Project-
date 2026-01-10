import SwiftUI
import RealityKit

// Clinical test location (fixed grid position)
struct StimulusLocation {
    let angleDegrees: Float // 0-360 degrees around user
    let eccentricityDegrees: Float // Distance from center
    let id: Int
}

struct StimulusTrial: Identifiable {
    let id = UUID()
    let trialID: Int
    let spotID: Int
    let angleDegrees: Float
    let eccentricityDegrees: Float
    let spawnTime: Date
    let responseTime: Date?
    let wasHit: Bool
    let timedOut: Bool

    var reactionTimeSeconds: Double? {
        guard let responseTime else { return nil }
        return responseTime.timeIntervalSince(spawnTime)
    }
}

struct SimpleImmersiveView: View {
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow

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

    // Clinical parameters
    @State private var availableLocations: [StimulusLocation] = []
    @State private var currentAngleDegrees: Float = 0
    @State private var currentEccentricityDegrees: Float = 0

    // Clinical grid: simplified 24-2 style with ~6° spacing
    // Covers central ±24° in all quadrants at multiple eccentricities
    let clinicalGrid: [StimulusLocation] = {
        var locations: [StimulusLocation] = []
        var id = 0

        // 8 primary meridians
        let meridians: [Float] = [0, 45, 90, 135, 180, 225, 270, 315]

        // Eccentricities at 6°, 12°, 18°, 24° from center
        let eccentricities: [Float] = [6, 12, 18, 24]

        for meridian in meridians {
            for eccentricity in eccentricities {
                locations.append(StimulusLocation(
                    angleDegrees: meridian,
                    eccentricityDegrees: eccentricity,
                    id: id
                ))
                id += 1
            }
        }

        // Add some intermediate positions for better coverage
        let intermediateMeridians: [Float] = [22.5, 67.5, 112.5, 157.5, 202.5, 247.5, 292.5, 337.5]
        for meridian in intermediateMeridians {
            // Only at 12° and 24° eccentricity for intermediate
            for eccentricity in [12.0, 24.0] as [Float] {
                locations.append(StimulusLocation(
                    angleDegrees: meridian,
                    eccentricityDegrees: eccentricity,
                    id: id
                ))
                id += 1
            }
        }

        return locations
    }()

    var body: some View {
        RealityView { content in
            content.add(rootEntity)

            // Dark background environment
            let background = ModelEntity(
                mesh: .generateSphere(radius: 50),
                materials: [SimpleMaterial(color: UIColor(white: 0.1, alpha: 1.0), isMetallic: false)]
            )
            background.scale = SIMD3<Float>(-1, 1, 1)
            rootEntity.addChild(background)

            // Central fixation point (bright for dark background)
            let fixation = ModelEntity(
                mesh: .generateSphere(radius: 0.05),
                materials: [UnlitMaterial(color: UIColor.white)]
            )
            fixation.position = SIMD3<Float>(0, 0, -2)
            rootEntity.addChild(fixation)

            // Create debug grid (initially hidden)
            let grid = createDebugGrid()
            gridEntity = grid
        } update: { content in
            // Show/hide debug grid based on debug mode
            if let grid = gridEntity {
                if debugMode && grid.parent == nil {
                    rootEntity.addChild(grid)
                } else if !debugMode && grid.parent != nil {
                    grid.removeFromParent()
                }
            }
        }
        .overlay {
            if !testActive && (hitCount > 0 || missedCount > 0) {
                // Results screen
                VStack(spacing: 20) {
                    Text("Test Paused")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)

                    Text("Hits: \(hitCount)")
                        .font(.title)
                        .foregroundColor(.green)

                    Text("Misses: \(missedCount)")
                        .font(.title)
                        .foregroundColor(.red)

                    Button {
                        restartTest()
                    } label: {
                        Text("Restart Test")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(.horizontal, 30)
                            .padding(.vertical, 15)
                            .background(.blue)
                            .cornerRadius(15)
                    }
                }
                .padding()
                .background(.black.opacity(0.8))
                .cornerRadius(20)
            }
        }
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    leaveTest()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.left.circle.fill")
                            .font(.title2)
                        Text("Leave Test")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.red.opacity(0.8))
                    .cornerRadius(25)
                }

                if testActive {
                    // === TRIAL PROGRESS COUNTER (ALWAYS VISIBLE) ===
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Trial: \(currentTrialID + 1) / \(clinicalGrid.count)")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        Text("Remaining: \(clinicalGrid.count - (currentTrialID % clinicalGrid.count))")
                            .font(.headline)
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.black.opacity(0.8))
                    .cornerRadius(15)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Hits: \(hitCount)")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(.green.opacity(0.8))
                            .cornerRadius(15)

                        Text("Misses: \(missedCount)")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(.red.opacity(0.8))
                            .cornerRadius(15)
                    }

                    Button {
                        handleSawIt()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "eye.fill")
                                .font(.title2)
                            Text("I Saw It")
                                .font(.headline)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(.green.opacity(0.8))
                        .cornerRadius(25)
                    }
                }
            }
            .padding(30)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                debugMode.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: debugMode ? "grid.circle.fill" : "grid.circle")
                        .font(.title2)
                    Text(debugMode ? "Debug: ON" : "Debug: OFF")
                        .font(.headline)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(debugMode ? .green.opacity(0.8) : .gray.opacity(0.8))
                .cornerRadius(25)
            }
            .padding(30)
        }
        .overlay(alignment: .bottomLeading) {
            // DEBUG: Show current trial info
            VStack(alignment: .leading, spacing: 4) {
                Text("DEBUG INFO")
                    .font(.caption)
                    .fontWeight(.bold)
                Text("Trial: #\(currentTrialID)")
                    .font(.caption)
                Text("Last Angle: \(String(format: "%.1f", currentAngleDegrees))°")
                    .font(.caption)
                Text("Last Ecc: \(String(format: "%.1f", currentEccentricityDegrees))°")
                    .font(.caption)
                Text("Test Active: \(testActive ? "YES" : "NO")")
                    .font(.caption)
                    .foregroundColor(testActive ? .green : .red)
            }
            .foregroundColor(.white)
            .padding(12)
            .background(.black.opacity(0.7))
            .cornerRadius(8)
            .padding(30)
        }
        .onAppear {
            // Start the test
            print("Test environment loaded. Starting test...")
            print("Clinical grid: \(clinicalGrid.count) locations")
            availableLocations = clinicalGrid.shuffled() // Randomize order
            testActive = true
            scheduleNextStimulus()
        }
    }

    private func createClinicalStimulus(angleDegrees: Float, eccentricityDegrees: Float, trialID: Int) -> ModelEntity {
        // DEBUG: Big yellow spheres for simulator visibility
        let distance: Float = 2.0 // 2 meters from user
        let sphereRadius: Float = 0.08 // Big and easy to see

        // Convert degrees to radians
        let angleRad = angleDegrees * .pi / 180.0
        let eccentricityRad = eccentricityDegrees * .pi / 180.0

        // Convert spherical to Cartesian coordinates
        let x = distance * sin(eccentricityRad) * cos(angleRad)
        let y = distance * sin(eccentricityRad) * sin(angleRad)
        let z = -distance * cos(eccentricityRad)

        // Create big yellow sphere for visibility
        let stimulus = ModelEntity(
            mesh: .generateSphere(radius: sphereRadius),
            materials: [UnlitMaterial(color: .yellow)]
        )
        stimulus.position = SIMD3<Float>(x, y, z)
        stimulus.name = "Stimulus_\(trialID)"

        print("   Created stimulus sphere at angle=\(String(format: "%.1f", angleDegrees))°, ecc=\(String(format: "%.1f", eccentricityDegrees))°")
        print("   Position: x=\(String(format: "%.3f", x)), y=\(String(format: "%.3f", y)), z=\(String(format: "%.3f", z))")

        return stimulus
    }

    private func scheduleNextStimulus() {
        guard testActive else {
            print("⏸️  scheduleNextStimulus() called but testActive = false, skipping")
            return
        }

        // Random delay between 1.5 and 3.5 seconds
        let delay = Double.random(in: 1.5...3.5)
        print("📅 Scheduling next stimulus in \(String(format: "%.2f", delay))s")

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard self.testActive else {
                print("⏸️  Scheduled stimulus skipped (testActive = false)")
                return
            }
            self.spawnPeripheralStimulus()
        }
    }

    private func spawnPeripheralStimulus() {
        guard testActive else { return }

        // Remove previous stimulus if it exists
        if let oldStimulus = currentStimulus {
            print("⚠️  Removing previous stimulus that was not responded to")
            oldStimulus.removeFromParent()
            currentStimulus = nil
        }

        // Check if we need to reshuffle locations
        if availableLocations.isEmpty {
            print("⚠️  No more available locations, reshuffling grid")
            availableLocations = clinicalGrid.shuffled()
        }

        // Select next location from clinical grid (without replacement)
        let location = availableLocations.removeFirst()
        currentAngleDegrees = location.angleDegrees
        currentEccentricityDegrees = location.eccentricityDegrees

        print("\n🎯 ===============================================")
        print("🎯 SPAWNING STIMULUS #\(currentTrialID)")
        print("🎯 Location ID: \(location.id)")
        print("🎯 Angle: \(String(format: "%.1f", location.angleDegrees))°")
        print("🎯 Eccentricity: \(String(format: "%.1f", location.eccentricityDegrees))°")
        print("🎯 ===============================================")

        // Create and add the clinical stimulus
        let stimulus = createClinicalStimulus(
            angleDegrees: location.angleDegrees,
            eccentricityDegrees: location.eccentricityDegrees,
            trialID: currentTrialID
        )
        rootEntity.addChild(stimulus)
        currentStimulus = stimulus
        currentSpawnTime = Date()

        print("✅ Stimulus added to scene. Should be VISIBLE NOW!")

        // Flash duration (DEBUG: 2.0 seconds for visibility, normally 0.2-0.3s)
        let flashDuration = 2.0
        let thisTrialID = currentTrialID

        DispatchQueue.main.asyncAfter(deadline: .now() + flashDuration) {
            // Hide stimulus after flash duration
            if let stim = self.currentStimulus, stim.name == "Stimulus_\(thisTrialID)" {
                print("   💡 Flash ended (\(String(format: "%.2f", flashDuration))s) - hiding stimulus")
                stim.removeFromParent()
                // Note: currentStimulus remains set so responses are still counted
            }
        }

        // Schedule 3-second auto-timeout (response window)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.handleTimeout(
                forTrialID: thisTrialID,
                angle: location.angleDegrees * .pi / 180.0,
                eccentricity: location.eccentricityDegrees
            )
        }

        currentTrialID += 1
    }

    private func handleTimeout(forTrialID trialID: Int, angle: Float, eccentricity: Float) {
        // Only process timeout if:
        // 1. Test is still active
        // 2. This is still the current trial (user hasn't responded yet)
        guard testActive,
              let stimulus = currentStimulus,
              stimulus.name == "Stimulus_\(trialID)" else {
            print("⏸️  Timeout #\(trialID) skipped (already handled or test stopped)")
            return
        }

        print("⏰ Stimulus #\(trialID) timed out (3 seconds)")

        // Remove the stimulus and clear state
        stimulus.removeFromParent()
        currentStimulus = nil
        currentSpawnTime = nil

        // Increment miss count
        missedCount += 1

        // Record the trial as a miss
        let trial = StimulusTrial(
            trialID: trialID,
            spotID: trialID,
            angleDegrees: angle * 180.0 / .pi, // Convert radians back to degrees
            eccentricityDegrees: eccentricity,
            spawnTime: Date(), // Use current time if spawn time was cleared
            responseTime: nil,
            wasHit: false,
            timedOut: true
        )
        trials.append(trial)

        print("📊 Trial recorded as TIMEOUT")

        print("   Misses: \(missedCount)")

        // Schedule next stimulus
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
        print("\n🔘 'I Saw It' button pressed")

        // Check if test is active
        guard testActive else {
            print("   ⚠️  Test not active, ignoring")
            return
        }

        // Check if there's an active stimulus
        if let stimulus = currentStimulus, let spawnTime = currentSpawnTime {
            // HIT: There was an active stimulus
            print("   ✅ Active stimulus detected!")

            let responseTime = Date()
            let reactionTime = responseTime.timeIntervalSince(spawnTime)

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
                    timedOut: false
                )
                trials.append(trial)

                print("📊 Trial recorded: RT=\(String(format: "%.3f", trial.reactionTimeSeconds ?? 0))s")
            }

            // Remove the stimulus and clear state
            stimulus.removeFromParent()
            currentStimulus = nil
            currentSpawnTime = nil

            // Increment hit count
            hitCount += 1

            print("   Reaction time: \(String(format: "%.3f", reactionTime))s")
            print("   Hits: \(hitCount), Misses: \(missedCount)")

            // Schedule next stimulus only after a successful hit
            print("   📅 Calling scheduleNextStimulus()")
            scheduleNextStimulus()

        } else {
            // MISS: No active stimulus (false positive)
            print("   ❌ No active stimulus (false positive)")
            print("   (Ignoring - waiting for current trial to timeout)")
        }
    }

    private func restartTest() {
        print("\n🔄 Restarting test...")

        // Clear current stimulus
        currentStimulus?.removeFromParent()
        currentStimulus = nil

        // Reset counters
        hitCount = 0
        missedCount = 0
        trials = []
        currentTrialID = 0
        currentSpawnTime = nil

        // Reshuffle clinical grid locations
        availableLocations = clinicalGrid.shuffled()

        // Restart test
        testActive = true
        scheduleNextStimulus()

        print("   Test restarted. Hits=0, Misses=0")
        print("   Locations available: \(availableLocations.count)")
    }

    private func leaveTest() {
        print("\n🚪 Leaving test...")

        // Stop the test
        testActive = false

        // Print final results
        printTestResults()

        Task {
            await dismissImmersiveSpace()

            // Small delay to ensure immersive space is dismissed
            try? await Task.sleep(nanoseconds: 100_000_000)

            // Reopen the main window
            openWindow(id: "MainWindow")
            print("Returned to main menu")
        }
    }

    private func printTestResults() {
        print("\n=== TEST RESULTS ===")
        print("Total trials: \(trials.count)")
        print("Hits: \(hitCount)")
        print("Misses: \(missedCount)")

        let reactionTimes = trials.compactMap { $0.reactionTimeSeconds }
        if !reactionTimes.isEmpty {
            let avgReaction = reactionTimes.reduce(0, +) / Double(reactionTimes.count)
            let minReaction = reactionTimes.min() ?? 0
            let maxReaction = reactionTimes.max() ?? 0
            print("Average reaction time: \(String(format: "%.3f", avgReaction))s")
            print("Fastest: \(String(format: "%.3f", minReaction))s")
            print("Slowest: \(String(format: "%.3f", maxReaction))s")
        }

        // Print detailed trial data
        print("\n=== DETAILED TRIAL DATA ===")
        for trial in trials {
            let rtStr = trial.reactionTimeSeconds.map { String(format: "%.3f", $0) + "s" } ?? "N/A"
            print("Trial #\(trial.trialID): angle=\(String(format: "%.1f", trial.angleDegrees))°, ecc=\(String(format: "%.1f", trial.eccentricityDegrees))°, hit=\(trial.wasHit), RT=\(rtStr)")
        }
        print("====================\n")
    }
}
