import SwiftUI
import RealityKit

// Clinical test location (fixed grid position)
struct StimulusLocation {
    let angleDegrees: Float // 0-360 degrees around user
    let eccentricityDegrees: Float // Distance from center
    let id: Int
}

// Scheduled trial: combines a location with a specific brightness level
struct ScheduledTrial {
    let location: StimulusLocation
    let brightnessValue: Float
    let brightnessLevelIndex: Int // 0=Low, 1=Medium, 2=High
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
    let brightnessValue: Float      // Actual brightness (0.25, 0.60, 1.00)
    let brightnessLevelIndex: Int   // Index into brightnessLevels array (0=Low, 1=Medium, 2=High)

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

    // Clinical parameters - pre-generated trial list (48 locations × 3 brightness = 144 trials)
    @State private var scheduledTrials: [ScheduledTrial] = []
    @State private var currentAngleDegrees: Float = 0
    @State private var currentEccentricityDegrees: Float = 0

    // CSV Export
    @State private var csvExportPath: String? = nil

    // Brightness levels: Low (0.25), Medium (0.60), High (1.00)
    let brightnessLevels: [Float] = [0.25, 0.60, 1.00]
    let brightnessLabels: [String] = ["Low", "Medium", "High"]
    @State private var currentBrightness: Float = 1.0
    @State private var currentBrightnessIndex: Int = 2

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
                    // Total trials = 48 locations × 3 brightness levels = 144
                    let totalTrials = clinicalGrid.count * brightnessLevels.count
                    let completedTrials = currentTrialID
                    let remainingTrials = totalTrials - completedTrials

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Trial: \(completedTrials + 1) / \(totalTrials)")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        Text("Remaining: \(remainingTrials)")
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
                Text("Brightness: \(brightnessLabels[currentBrightnessIndex]) (\(String(format: "%.2f", currentBrightness)))")
                    .font(.caption)
                    .foregroundColor(.yellow)
                Text("Test Active: \(testActive ? "YES" : "NO")")
                    .font(.caption)
                    .foregroundColor(testActive ? .green : .red)

                // Show CSV export status
                if let exportPath = csvExportPath {
                    Divider()
                        .background(.white.opacity(0.3))
                        .padding(.vertical, 4)

                    Text("Exported CSV to:")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                    Text(exportPath)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.green)
                        .lineLimit(3)
                }
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
            print("Brightness levels: \(brightnessLevels.count)")

            // Generate all 144 trials: each location × each brightness level
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

            // Shuffle all trials for random presentation order
            scheduledTrials = allTrials.shuffled()

            print("Total trials: \(scheduledTrials.count) (48 locations × 3 brightness levels)")
            testActive = true
            scheduleNextStimulus()
        }
    }

    private func createClinicalStimulus(angleDegrees: Float, eccentricityDegrees: Float, trialID: Int, brightness: Float) -> ModelEntity {
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

        // Apply brightness to yellow color (scaled R and G channels)
        let b = CGFloat(brightness)
        let brightYellow = UIColor(red: b, green: b, blue: 0.0, alpha: 1.0)

        // Create stimulus sphere with brightness-adjusted color
        let stimulus = ModelEntity(
            mesh: .generateSphere(radius: sphereRadius),
            materials: [UnlitMaterial(color: brightYellow)]
        )
        stimulus.position = SIMD3<Float>(x, y, z)
        stimulus.name = "Stimulus_\(trialID)"

        print("   Created stimulus sphere at angle=\(String(format: "%.1f", angleDegrees))°, ecc=\(String(format: "%.1f", eccentricityDegrees))°")
        print("   Brightness: \(String(format: "%.2f", brightness))")
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

        // Check if all trials are complete
        if scheduledTrials.isEmpty {
            print("✅ All 144 trials complete!")
            testActive = false
            return
        }

        // Get next scheduled trial (includes location + brightness)
        let scheduledTrial = scheduledTrials.removeFirst()
        let location = scheduledTrial.location
        currentAngleDegrees = location.angleDegrees
        currentEccentricityDegrees = location.eccentricityDegrees

        // Use the pre-assigned brightness for this trial
        currentBrightnessIndex = scheduledTrial.brightnessLevelIndex
        currentBrightness = scheduledTrial.brightnessValue

        print("\n🎯 ===============================================")
        print("🎯 SPAWNING STIMULUS #\(currentTrialID + 1) / 144")
        print("🎯 Location ID: \(location.id)")
        print("🎯 Angle: \(String(format: "%.1f", location.angleDegrees))°")
        print("🎯 Eccentricity: \(String(format: "%.1f", location.eccentricityDegrees))°")
        print("🎯 Brightness: \(brightnessLabels[currentBrightnessIndex]) (\(String(format: "%.2f", currentBrightness)))")
        print("🎯 ===============================================")

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
            timedOut: true,
            brightnessValue: currentBrightness,
            brightnessLevelIndex: currentBrightnessIndex
        )
        trials.append(trial)

        print("📊 Trial recorded as TIMEOUT (brightness: \(brightnessLabels[currentBrightnessIndex]))")

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
                    timedOut: false,
                    brightnessValue: currentBrightness,
                    brightnessLevelIndex: currentBrightnessIndex
                )
                trials.append(trial)

                print("📊 Trial recorded: RT=\(String(format: "%.3f", trial.reactionTimeSeconds ?? 0))s, brightness: \(brightnessLabels[currentBrightnessIndex])")
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

        // Regenerate all 144 trials (48 locations × 3 brightness levels)
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

        // Restart test
        testActive = true
        scheduleNextStimulus()

        print("   Test restarted. Hits=0, Misses=0")
        print("   Trials scheduled: \(scheduledTrials.count)")
    }

    private func leaveTest() {
        print("\n🚪 Leaving test...")

        // Stop the test
        testActive = false

        // Print final results
        printTestResults()

        // Export CSV automatically
        exportTrialsToCSV()

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

    private func exportTrialsToCSV() {
        // Skip if no trials
        guard !trials.isEmpty else {
            print("⚠️ No trials to export")
            return
        }

        // Create CSV content with brightness as int (1=least bright, 2=medium, 3=brightest)
        var csv = "trial_index,angle_deg,ecc_deg,hit,reaction_time_sec,brightness_value\n"

        for trial in trials {
            let trialIndex = trial.trialID
            let angleDeg = String(format: "%.1f", trial.angleDegrees)
            let eccDeg = String(format: "%.1f", trial.eccentricityDegrees)
            let hit = trial.wasHit ? "true" : "false"
            let rtSec = trial.reactionTimeSeconds.map { String(format: "%.3f", $0) } ?? "-1.0"
            // Convert brightness index (0,1,2) to int scale (1,2,3)
            let brightnessInt = trial.brightnessLevelIndex + 1

            csv += "\(trialIndex),\(angleDeg),\(eccDeg),\(hit),\(rtSec),\(brightnessInt)\n"
        }

        // Generate filename with timestamp
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let filename = "perimetry_\(timestamp).csv"

        // Get Documents directory
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsPath.appendingPathComponent(filename)

        // Write CSV file
        do {
            try csv.write(to: fileURL, atomically: true, encoding: .utf8)
            let fullPath = fileURL.path
            print("✅ Exported CSV to: \(fullPath)")
            csvExportPath = fullPath
        } catch {
            print("❌ Error writing CSV: \(error)")
            csvExportPath = "Error: \(error.localizedDescription)"
        }
    }
}
