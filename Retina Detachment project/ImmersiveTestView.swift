import SwiftUI
import RealityKit
import simd
import QuartzCore

struct ImmersiveTestView: View {
    @State private var currentStimulus: ModelEntity?
    @State private var testActive = false
    @State private var score = 0
    @State private var missedCount = 0
    @State private var rootEntity: Entity = Entity()
    @State private var inResponseWindow = false
    @State private var currentStimulusID: UUID?  // Track which stimulus is active
    @State private var stimulusOnsetTime: Double?  // For reaction time
    @State private var lastReactionTimeMs: Double?  // For UI/debug
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
            VStack(alignment: .leading, spacing: 10) {
                Text("Score: \(score)")
                    .font(.title)
                    .foregroundColor(.green)
                Text("Missed: \(missedCount)")
                    .font(.title)
                    .foregroundColor(.red)
                Text("Tap when you see a flash")
                    .font(.caption)
                    .foregroundColor(.white)

                Text("RT: \(lastReactionTimeMs.map { "\(Int($0)) ms" } ?? "--")")
                    .font(.caption)
                    .foregroundColor(.white)
            }
            .padding()
            .background(.black.opacity(0.7))
            .cornerRadius(12)
            .padding()
        }
        .onAppear {
            startTest()
        }
    }

    private func startTest() {
        testActive = true
        print("Peripheral vision test started")
        scheduleNextStimulus()
    }

    private func scheduleNextStimulus() {
        guard testActive else { return }

        // Random delay between stimuli (1-3 seconds)
        let delay = Double.random(in: 1.0...3.0)

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.spawnPeripheralStimulus()
        }
    }

    private func handleTap(on entity: Entity) {
        print("Tapped on entity: \(entity.name)")

        // Only accept taps during response window
        guard inResponseWindow else {
            print("Tap outside response window - ignored")
            return
        }

        // Humphrey-style response: any tap counts as "seen" during the response window
        let now = CACurrentMediaTime()
        if let onset = stimulusOnsetTime {
            let rt = (now - onset) * 1000.0
            lastReactionTimeMs = rt
            print("Reaction time: \(rt) ms")
        } else {
            lastReactionTimeMs = nil
        }

        score += 1
        print("Seen! Score: \(score)")

        // Close response window and invalidate timers for this stimulus
        inResponseWindow = false
        currentStimulusID = nil

        // Remove the stimulus (may already be removed after 200ms)
        currentStimulus?.removeFromParent()
        currentStimulus = nil

        // Schedule next one
        scheduleNextStimulus()
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

        // Random polar angle (0 to 360 degrees) - direction around fixation
        // 0° = right, 90° = up, 180° = left, 270° = down
        let polarAngleDeg = Float.random(in: 0...360)

        // Random eccentricity (20 to 60 degrees from center) - distance from fixation
        let eccentricityDeg = Float.random(in: 20...60)

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

        // Open response window
        inResponseWindow = true

        rootEntity.addChild(stimulus)

        // Record onset for reaction time
        stimulusOnsetTime = CACurrentMediaTime()
        lastReactionTimeMs = nil

        print("Spawned stimulus at polarAngle: \(polarAngleDeg)°, eccentricity: \(eccentricityDeg)°")
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
                self.inResponseWindow = false
                self.currentStimulusID = nil
                stimulus.removeFromParent()
                self.currentStimulus = nil
                self.missedCount += 1
                print("Response window closed. Missed count: \(self.missedCount)")
                self.scheduleNextStimulus()
            }
        }
    }
}
