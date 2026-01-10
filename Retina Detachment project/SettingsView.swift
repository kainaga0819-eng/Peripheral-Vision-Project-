import SwiftUI

struct SettingsView: View {
    @Binding var gameState: GameState
    @State private var settings = TestSettings.shared
    @State private var showingResetAlert = false
    
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.orange.opacity(0.8), Color.red.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 30) {
                    // Header
                    VStack(spacing: 10) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.white)
                        
                        Text("Test Settings")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Text("Calibrate your vision test experience")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(.top, 20)
                    
                    // Basic Settings
                    VStack(spacing: 20) {
                        SettingsSection(title: "Basic Configuration") {
                            VStack(spacing: 15) {
                                HStack {
                                    Text("Distance: \(settings.stimulusDistance, specifier: "%.1f")m")
                                        .foregroundColor(.primary)
                                    Spacer()
                                }
                                Slider(value: $settings.stimulusDistance, in: 1.0...5.0)
                                
                                HStack {
                                    Text("Size: \(settings.stimulusSize, specifier: "%.2f")m")
                                        .foregroundColor(.primary)
                                    Spacer()
                                }
                                Slider(value: $settings.stimulusSize, in: 0.02...0.15)
                                
                                HStack {
                                    Text("Max Stimuli: \(settings.maxStimuli)")
                                        .foregroundColor(.primary)
                                    Spacer()
                                }
                                Slider(value: Binding(
                                    get: { Double(settings.maxStimuli) },
                                    set: { settings.maxStimuli = Int($0) }
                                ), in: 10...50, step: 5)
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    // Action Buttons
                    VStack(spacing: 15) {
                        Button("Reset to Defaults") {
                            showingResetAlert = true
                        }
                        .foregroundColor(.red)
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(10)
                        
                        Button("Back to Menu") {
                            saveSettings()
                            gameState = .mainMenu
                        }
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .padding(.horizontal)
                    
                    Spacer(minLength: 50)
                }
            }
        }
        .alert("Reset Settings", isPresented: $showingResetAlert) {
            Button("Reset", role: .destructive) {
                settings = TestSettings()
                saveSettings()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will reset all settings to their default values.")
        }
    }
    
    private func saveSettings() {
        TestSettings.shared.stimulusDistance = settings.stimulusDistance
        TestSettings.shared.stimulusSize = settings.stimulusSize
        TestSettings.shared.maxStimuli = settings.maxStimuli
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            content
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(15)
        .shadow(radius: 2)
    }
}

#Preview {
    SettingsView(gameState: .constant(.settings))
}
