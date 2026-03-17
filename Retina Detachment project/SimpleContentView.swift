import SwiftUI

struct SimpleContentView: View {
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var hasSavedProgress = false
    @State private var showingResults = false
    @State private var showingSettings = false
    @State private var showingSimulation = false
    @AppStorage("simulationModeEnabled") private var simulationModeEnabled = false
    @AppStorage("simulationProfileRaw") private var simulationProfileRaw: String = VisionProfile.normal.rawValue
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
            SimulationSetupSheet { profile in
                simulationProfileRaw = profile.rawValue
                simulationModeEnabled = true
                showingSimulation = false
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
    let onStart: (VisionProfile) -> Void
    @State private var selectedProfile: VisionProfile = .normal
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(VisionProfile.allCases) { profile in
                        Button {
                            selectedProfile = profile
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: profile.icon)
                                    .font(.title3)
                                    .foregroundColor(selectedProfile == profile ? .purple : .secondary)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(profile.rawValue)
                                        .fontWeight(selectedProfile == profile ? .semibold : .regular)
                                        .foregroundColor(.primary)
                                    Text(profile.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                if selectedProfile == profile {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.purple)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Select Vision Profile")
                } footer: {
                    Text("The app will automatically run all 228 trials as a simulated patient with this profile. ~10 random mistakes will be injected to mimic human error.")
                }

            }
            .navigationTitle("Simulation Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start Simulation") {
                        onStart(selectedProfile)
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(.purple)
                }
            }
        }
    }
}

#Preview {
    SimpleContentView()
}