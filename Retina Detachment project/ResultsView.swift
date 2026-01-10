import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ResultsView: View {
    @Binding var gameState: GameState
    @EnvironmentObject var dataManager: TestDataManager
    @State private var selectedSession: TestSession?
    @State private var showingExportSheet = false
    @State private var exportText = ""
    
    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(
                    colors: [Color.blue.opacity(0.8), Color.green.opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 10) {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.white)
                        
                        Text("Test Results")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Text("Your peripheral vision performance")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(.top, 20)
                    
                    if dataManager.sessions.isEmpty {
                        // Empty State
                        VStack(spacing: 20) {
                            Image(systemName: "chart.bar.xaxis")
                                .font(.system(size: 80))
                                .foregroundColor(.white.opacity(0.6))
                            
                            Text("No Test Data")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                            
                            Text("Complete your first peripheral vision test to see results here.")
                                .font(.body)
                                .foregroundColor(.white.opacity(0.8))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                            
                            Button("Start First Test") {
                                gameState = .testing
                            }
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                            .fontWeight(.semibold)
                        }
                        .padding()
                        
                    } else {
                        // Results Content
                        ScrollView {
                            VStack(spacing: 20) {
                                // Overall Statistics
                                OverallStatsView(sessions: dataManager.sessions)
                                
                                // Session List
                                VStack(alignment: .leading, spacing: 15) {
                                    HStack {
                                        Text("Test Sessions")
                                            .font(.title2)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.white)
                                        
                                        Spacer()
                                        
                                        Button("Export Data") {
                                            exportData()
                                        }
                                        .font(.caption)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.white.opacity(0.2))
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                    }
                                    
                                    LazyVStack(spacing: 10) {
                                        ForEach(dataManager.sessions.reversed()) { session in
                                            SessionCard(session: session) {
                                                selectedSession = session
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                    
                    // Back Button
                    Button("Back to Menu") {
                        gameState = .mainMenu
                    }
                    .padding()
                    .background(Color.white.opacity(0.2))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .fontWeight(.semibold)
                    
                    Spacer()
                }
            }
        }
        .sheet(item: $selectedSession) { session in
            SessionDetailView(session: session)
        }
        .sheet(isPresented: $showingExportSheet) {
            ShareSheet(activityItems: [exportText])
        }
    }
    
    private func exportData() {
        exportText = dataManager.exportData()
        showingExportSheet = true
    }
}

struct OverallStatsView: View {
    let sessions: [TestSession]
    
    private var overallAccuracy: Double {
        guard !sessions.isEmpty else { return 0 }
        let totalAccuracy = sessions.map { $0.accuracy }.reduce(0, +)
        return totalAccuracy / Double(sessions.count)
    }
    
    private var averageReactionTime: Double {
        guard !sessions.isEmpty else { return 0 }
        let totalRT = sessions.map { $0.averageReactionTime }.reduce(0, +)
        return totalRT / Double(sessions.count)
    }
    
    private var totalTrials: Int {
        sessions.map { $0.trials.count }.reduce(0, +)
    }
    
    var body: some View {
        VStack(spacing: 15) {
            Text("Overall Performance")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            HStack(spacing: 20) {
                StatCardLarge(
                    title: "Average Accuracy",
                    value: "\(Int(overallAccuracy * 100))%",
                    icon: "target",
                    color: .green
                )
                
                StatCardLarge(
                    title: "Avg Reaction Time",
                    value: "\(Int(averageReactionTime * 1000))ms",
                    icon: "timer",
                    color: .orange
                )
                
                StatCardLarge(
                    title: "Total Trials",
                    value: "\(totalTrials)",
                    icon: "circle.grid.cross",
                    color: .blue
                )
            }
        }
        .padding()
        .background(Color.black.opacity(0.2))
        .cornerRadius(15)
        .padding(.horizontal)
    }
}

struct StatCardLarge: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
    }
}

struct SessionCard: View {
    let session: TestSession
    let onTap: () -> Void
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(dateFormatter.string(from: session.startTime))
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text("\(session.trials.count) trials • \(Int((session.endTime.timeIntervalSince(session.startTime) / 60).rounded())) min")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accuracy")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(Int(session.accuracy * 100))%")
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Avg Reaction")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(Int(session.averageReactionTime * 1000))ms")
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                    
                    Spacer()
                }
                
                // Accuracy by eccentricity preview
                let accuracyData = session.accuracyByEccentricity()
                if !accuracyData.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(accuracyData.keys.sorted(), id: \.self) { angle in
                            let accuracy = accuracyData[angle] ?? 0
                            Rectangle()
                                .fill(Color.green.opacity(accuracy))
                                .frame(height: 4)
                        }
                    }
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(radius: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct SessionDetailView: View {
    let session: TestSession
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Session Overview
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Session Overview")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        HStack(spacing: 30) {
                            DetailStat(title: "Accuracy", value: "\(Int(session.accuracy * 100))%")
                            DetailStat(title: "Trials", value: "\(session.trials.count)")
                            DetailStat(title: "Duration", value: "\(Int((session.endTime.timeIntervalSince(session.startTime) / 60).rounded())) min")
                        }
                    }
                    
                    // Accuracy by Eccentricity
                    let accuracyData = session.accuracyByEccentricity()
                    if !accuracyData.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Accuracy by Eccentricity")
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            VStack(spacing: 8) {
                                ForEach(accuracyData.keys.sorted(), id: \.self) { angle in
                                    let accuracy = accuracyData[angle] ?? 0
                                    HStack {
                                        Text("\(Int(angle))°")
                                            .frame(width: 40, alignment: .leading)
                                        
                                        ProgressView(value: accuracy)
                                            .progressViewStyle(LinearProgressViewStyle())
                                        
                                        Text("\(Int(accuracy * 100))%")
                                            .frame(width: 40, alignment: .trailing)
                                    }
                                }
                            }
                        }
                    }
                    
                    // Trial Details
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Individual Trials")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        ForEach(session.trials) { trial in
                            TrialRow(trial: trial)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Session Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct DetailStat: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
        }
    }
}

struct TrialRow: View {
    let trial: TestTrial
    
    var body: some View {
        HStack {
            Circle()
                .fill(trial.wasDetected ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            
            Text("\(Int(trial.eccentricity))°")
                .frame(width: 30, alignment: .leading)
                .font(.caption)
            
            Text(trial.wasDetected ? "Detected" : "Missed")
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(.caption)
            
            if let reactionTime = trial.reactionTime {
                Text("\(Int(reactionTime * 1000))ms")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("—")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    ResultsView(gameState: .constant(.results))
        .environmentObject(TestDataManager())
}