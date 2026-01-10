import SwiftUI

struct MainMenuView: View {
    @Binding var gameState: GameState
    @StateObject private var dataManager = TestDataManager()
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [Color.blue.opacity(0.8), Color.purple.opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 40) {
                    // App Title
                    VStack(spacing: 10) {
                        Image(systemName: "eye.circle.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.white)
                        
                        Text("Peripheral Vision")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Text("Professional Vision Testing")
                            .font(.title3)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    
                    // Main Menu Buttons
                    VStack(spacing: 20) {
                        MenuButton(
                            title: "Start Vision Test",
                            subtitle: "Begin peripheral vision assessment",
                            icon: "play.circle.fill",
                            color: .green
                        ) {
                            gameState = .testing
                        }
                        
                        MenuButton(
                            title: "Settings",
                            subtitle: "Calibrate test parameters",
                            icon: "gearshape.fill",
                            color: .orange
                        ) {
                            gameState = .settings
                        }
                        
                        MenuButton(
                            title: "View Results",
                            subtitle: "Review past test sessions",
                            icon: "chart.bar.fill",
                            color: .blue
                        ) {
                            gameState = .results
                        }
                    }
                    .padding(.horizontal)
                    
                    // Statistics Summary
                    if !dataManager.sessions.isEmpty {
                        VStack(spacing: 8) {
                            Text("Recent Performance")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            HStack(spacing: 30) {
                                StatCard(
                                    title: "Sessions",
                                    value: "\(dataManager.sessions.count)",
                                    icon: "clock.fill"
                                )
                                
                                if let lastSession = dataManager.sessions.last {
                                    StatCard(
                                        title: "Last Accuracy",
                                        value: "\(Int(lastSession.accuracy * 100))%",
                                        icon: "target"
                                    )
                                    
                                    StatCard(
                                        title: "Avg Reaction",
                                        value: "\(Int(lastSession.averageReactionTime * 1000))ms",
                                        icon: "timer"
                                    )
                                }
                            }
                        }
                        .padding()
                        .background(Color.black.opacity(0.2))
                        .cornerRadius(15)
                        .padding(.horizontal)
                    }
                    
                    Spacer()
                }
                .padding(.top, 50)
            }
        }
        .environmentObject(dataManager)
    }
}

struct MenuButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 15) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                    .frame(width: 30)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(radius: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.white.opacity(0.8))
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(minWidth: 80)
    }
}

#Preview {
    MainMenuView(gameState: .constant(.mainMenu))
}