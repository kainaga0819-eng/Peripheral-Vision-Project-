import SwiftUI

struct SimpleContentView: View {
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var hasSavedProgress = false
    @State private var showingResults = false
    @State private var showingSettings = false
    @State private var showingSimulation = false
    @State private var showingMonocular = false
    @AppStorage("simulationModeEnabled") private var simulationModeEnabled = false
    @AppStorage("simulationSeverityRaw") private var simulationSeverityRaw: String = DetachmentSeverity.mild.rawValue
    @AppStorage("simulationRepeatCount") private var simulationRepeatCount: Int = 1
    @AppStorage("monocularModeEnabled") private var monocularModeEnabled = false
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "eye.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.blue)

            Text("Peripheral Vision Test")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Welcome to the peripheral vision testing app!")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Resume button — only visible when a saved session exists
            if hasSavedProgress {
                Button("Resume Test") {
                    handleTap()   // SavedTestProgress still in UserDefaults; view will load it
                }
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.horizontal, 40)
                .padding(.vertical, 20)
                .background(Color.orange)
                .foregroundColor(.white)
                .cornerRadius(20)
            }

            // Start test button — always visible, clears any saved session
            Button(hasSavedProgress ? "Start Fresh" : "Start Test") {
                SavedTestProgress.clear()
                hasSavedProgress = false
                handleTap()
            }
            .font(.title)
            .fontWeight(.bold)
            .padding(.horizontal, 50)
            .padding(.vertical, 25)
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(20)

            VStack(spacing: 15) {
                Button {
                    showingMonocular = true
                } label: {
                    Label("Monocular Testing", systemImage: "eye.trianglebadge.exclamationmark")
                }
                .padding()
                .background(Color.teal)
                .foregroundColor(.white)
                .cornerRadius(10)

                Button {
                    showingSimulation = true
                } label: {
                    Label("Simulation Mode", systemImage: "person.fill.checkmark")
                }
                .padding()
                .background(Color.purple)
                .foregroundColor(.white)
                .cornerRadius(10)

                Button("Settings") {
                    showingSettings = true
                }
                .padding()
                .background(Color.gray)
                .foregroundColor(.white)
                .cornerRadius(10)

                Button("Results") {
                    showingResults = true
                }
                .padding()
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
        }
        .padding()
        .onAppear {
            hasSavedProgress = SavedTestProgress.load() != nil
        }
        .sheet(isPresented: $showingResults) {
            SimpleResultsView()
        }
        .sheet(isPresented: $showingSettings) {
            MenuSettingsSheet()
        }
        .sheet(isPresented: $showingSimulation) {
            SimulationSetupSheet { severity, repeatCount in
                simulationSeverityRaw = severity.rawValue
                simulationRepeatCount = repeatCount
                simulationModeEnabled = true
                showingSimulation = false
                handleTap()
            }
        }
        .sheet(isPresented: $showingMonocular) {
            MonocularSetupSheet {
                monocularModeEnabled = true
                showingMonocular = false
                handleTap()
            }
        }
        .alert("Info", isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }

    private func handleTap() {
        print("Starting peripheral vision test...")

        // Open immersive space
        Task {
            print("Opening immersive space...")
            let result = await openImmersiveSpace(id: "ImmersiveSpace")
            print("Immersive space result: \(result)")

            // Dismiss the main window if immersive space opened successfully
            if case .opened = result {
                dismissWindow(id: "MainWindow")
                print("Main window dismissed")
            }
        }
    }
    
    private func showAlert(_ message: String) {
        alertMessage = message
        showingAlert = true
    }
}

// MARK: - Menu Settings Sheet

struct MenuSettingsSheet: View {
    @AppStorage("voiceControlEnabled") private var voiceControlEnabled = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $voiceControlEnabled) {
                        Label("Voice Control", systemImage: voiceControlEnabled ? "mic.fill" : "mic.slash.fill")
                    }
                    Text("When enabled, say \"I see it\" while looking at the fixation dot to register a response.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Response Method")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Simulation Setup Sheet

struct SimulationSetupSheet: View {
    let onStart: (DetachmentSeverity, Int) -> Void
    @State private var selectedSeverity: DetachmentSeverity = .mild
    @State private var customRunCount: Int = 5
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(DetachmentSeverity.allCases) { severity in
                        Button {
                            selectedSeverity = severity
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: severity.icon)
                                    .font(.title3)
                                    .foregroundColor(selectedSeverity == severity
                                                     ? severity.color : .secondary)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(severity.rawValue)
                                        .fontWeight(selectedSeverity == severity ? .semibold : .regular)
                                        .foregroundColor(.primary)
                                    Text(severity.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                if selectedSeverity == severity {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(severity.color)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Detachment Severity")
                } footer: {
                    Text("A retinal detachment zone is procedurally generated from a random angle and eccentricity range matching the chosen severity. ~10 random misclicks mimic human error.")
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("How it works", systemImage: "waveform.path.ecg.rectangle")
                            .font(.subheadline).fontWeight(.semibold)
                        Text("A random polar angle (0°–360°) is chosen as the detachment origin. A blind sector of matching size is generated around that angle. Any stimulus falling inside the sector will be missed; healthy-field stimuli follow normal detection probability.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Button {
                        onStart(selectedSeverity, 1)
                    } label: {
                        HStack {
                            Image(systemName: "play.circle.fill")
                                .foregroundColor(selectedSeverity.color)
                            Text("Run 1 Test")
                                .fontWeight(.semibold)
                            Spacer()
                            Text("228 trials")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)

                    Button {
                        onStart(selectedSeverity, 10)
                    } label: {
                        HStack {
                            Image(systemName: "play.circle.fill")
                                .foregroundColor(selectedSeverity.color)
                            Text("Run 10 Tests")
                                .fontWeight(.semibold)
                            Spacer()
                            Text("2,280 trials · 1 CSV")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)

                    HStack {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundColor(selectedSeverity.color)
                        Text("Custom")
                            .fontWeight(.semibold)
                        Spacer()
                        Stepper("\(customRunCount) tests", value: $customRunCount, in: 2...50)
                            .labelsHidden()
                        Text("\(customRunCount)")
                            .font(.subheadline).monospacedDigit()
                            .frame(width: 28, alignment: .trailing)
                        Button {
                            onStart(selectedSeverity, customRunCount)
                        } label: {
                            Image(systemName: "play.circle.fill")
                                .font(.title2)
                                .foregroundColor(selectedSeverity.color)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("How Many Runs?")
                } footer: {
                    Text("10 Tests (or a custom amount) runs the same simulation back-to-back with a fresh detachment zone each time, then combines everything into one CSV file.")
                }
            }
            .navigationTitle("Dynamic Simulation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Monocular Setup Sheet

struct MonocularSetupSheet: View {
    let onStart: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // Overview card
                    VStack(alignment: .leading, spacing: 10) {
                        Label("How it works", systemImage: "info.circle.fill")
                            .font(.title3).fontWeight(.semibold)
                            .foregroundColor(.teal)

                        Text("Monocular mode tests each eye independently using the full 76-point Humphrey 30-2 grid (228 trials per eye).")
                            .font(.body)

                        Text("Two separate CSV files are exported at the end — one for each eye.")
                            .font(.body)
                    }
                    .padding()
                    .background(.quaternary)
                    .cornerRadius(14)

                    // Step-by-step instructions
                    VStack(alignment: .leading, spacing: 16) {
                        Label("Instructions", systemImage: "list.number")
                            .font(.title3).fontWeight(.semibold)

                        StepRow(number: "1", title: "Right eye first (OD)",
                                detail: "Cover your LEFT eye completely with your hand or an eye patch.")
                        StepRow(number: "2", title: "Complete the test",
                                detail: "Look at the fixation dot and tap the button (or say \"I see it\") whenever you spot a white dot in your peripheral vision.")
                        StepRow(number: "3", title: "Switch eyes",
                                detail: "An overlay will appear prompting you to cover your RIGHT eye before the left-eye test begins.")
                        StepRow(number: "4", title: "Left eye (OS)",
                                detail: "Repeat the same test with your left eye while the right eye is covered.")
                        StepRow(number: "5", title: "Results",
                                detail: "Two CSV files are saved — perimetry_OD_... and perimetry_OS_... — and printed to the Xcode console.")
                    }
                    .padding()
                    .background(.quaternary)
                    .cornerRadius(14)
                }
                .padding()
            }
            .navigationTitle("Monocular Testing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start — Right Eye") {
                        onStart()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(.teal)
                }
            }
        }
    }
}

private struct StepRow: View {
    let number: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number)
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(Color.teal)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .fontWeight(.semibold)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    SimpleContentView()
}