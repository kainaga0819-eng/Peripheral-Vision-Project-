import SwiftUI

// MARK: - Test UI Components

struct TestStartUI: View {
    let onStart: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 15) {
                Image(systemName: "eye.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.white)
                
                Text("Peripheral Vision Test")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                VStack(spacing: 10) {
                    Text("Instructions:")
                        .font(.headline)
                        .foregroundColor(.white)
                        .fontWeight(.semibold)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 10) {
                            Text("1.")
                                .foregroundColor(.white.opacity(0.8))
                            Text("Keep your eyes focused on the white sphere in the center")
                                .foregroundColor(.white.opacity(0.9))
                        }
                        
                        HStack(alignment: .top, spacing: 10) {
                            Text("2.")
                                .foregroundColor(.white.opacity(0.8))
                            Text("Yellow spheres will appear in your peripheral vision")
                                .foregroundColor(.white.opacity(0.9))
                        }
                        
                        HStack(alignment: .top, spacing: 10) {
                            Text("3.")
                                .foregroundColor(.white.opacity(0.8))
                            Text("Tap immediately when you detect a sphere (don't look at it)")
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                    .font(.body)
                }
                .padding()
                .background(Color.black.opacity(0.2))
                .cornerRadius(12)
            }
            
            Button("Begin Test") {
                onStart()
            }
            .font(.title2)
            .fontWeight(.semibold)
            .padding(.horizontal, 30)
            .padding(.vertical, 15)
            .background(Color.green)
            .foregroundColor(.white)
            .cornerRadius(15)
            .shadow(radius: 5)
        }
        .padding(30)
        .background(Color.black.opacity(0.4))
        .cornerRadius(20)
        .shadow(radius: 10)
    }
}

struct TestRunningUI: View {
    let score: Int
    let total: Int
    let maxStimuli: Int
    let onStop: () -> Void
    let onExit: () -> Void
    
    private var progress: Double {
        maxStimuli > 0 ? Double(total) / Double(maxStimuli) : 0
    }
    
    private var accuracy: Double {
        total > 0 ? Double(score) / Double(total) : 0
    }
    
    var body: some View {
        VStack(spacing: 15) {
            // Progress and Stats
            VStack(spacing: 10) {
                HStack {
                    Text("Progress: \(total)/\(maxStimuli)")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Text("Accuracy: \(Int(accuracy * 100))%")
                        .font(.headline)
                        .foregroundColor(.white)
                }
                
                ProgressView(value: progress)
                    .progressViewStyle(LinearProgressViewStyle(tint: .green))
                    .scaleEffect(y: 2)
                
                Text("Keep looking at the center. Tap when you see yellow spheres.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
            
            // Control Buttons
            HStack(spacing: 20) {
                Button("Stop Test") {
                    onStop()
                }
                .font(.body)
                .fontWeight(.medium)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.orange)
                .foregroundColor(.white)
                .cornerRadius(10)
                
                Button("Exit") {
                    onExit()
                }
                .font(.body)
                .fontWeight(.medium)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
        }
        .padding(20)
        .background(Color.black.opacity(0.4))
        .cornerRadius(15)
        .shadow(radius: 5)
    }
}

struct TestCompletedUI: View {
    let session: TestSession
    let onRestart: () -> Void
    let onExit: () -> Void
    
    private var accuracyColor: Color {
        let accuracy = session.accuracy
        if accuracy >= 0.8 { return .green }
        else if accuracy >= 0.6 { return .orange }
        else { return .red }
    }
    
    private var performanceText: String {
        let accuracy = session.accuracy
        if accuracy >= 0.9 { return "Excellent!" }
        else if accuracy >= 0.8 { return "Very Good" }
        else if accuracy >= 0.7 { return "Good" }
        else if accuracy >= 0.6 { return "Fair" }
        else { return "Needs Practice" }
    }
    
    var body: some View {
        VStack(spacing: 25) {
            // Header
            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)
                
                Text("Test Complete!")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text(performanceText)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(accuracyColor)
            }
            
            // Results Summary
            VStack(spacing: 15) {
                Text("Your Results")
                    .font(.headline)
                    .foregroundColor(.white)
                
                HStack(spacing: 30) {
                    ResultStat(
                        title: "Accuracy",
                        value: "\(Int(session.accuracy * 100))%",
                        color: accuracyColor
                    )
                    
                    ResultStat(
                        title: "Avg Reaction",
                        value: "\(Int(session.averageReactionTime * 1000))ms",
                        color: .blue
                    )
                    
                    ResultStat(
                        title: "Trials",
                        value: "\(session.trials.count)",
                        color: .purple
                    )
                }
                
                // Accuracy by Eccentricity Summary
                let accuracyData = session.accuracyByEccentricity()
                if !accuracyData.isEmpty {
                    VStack(spacing: 8) {
                        Text("Performance by Angle")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
                        
                        HStack(spacing: 5) {
                            ForEach(accuracyData.keys.sorted(), id: \.self) { angle in
                                let accuracy = accuracyData[angle] ?? 0
                                VStack(spacing: 4) {
                                    Rectangle()
                                        .fill(Color.green.opacity(accuracy))
                                        .frame(width: 30, height: 20)
                                        .cornerRadius(4)
                                    
                                    Text("\(Int(angle))°")
                                        .font(.caption2)
                                        .foregroundColor(.white.opacity(0.7))
                                }
                            }
                        }
                    }
                }
            }
            .padding()
            .background(Color.black.opacity(0.2))
            .cornerRadius(15)
            
            // Action Buttons
            VStack(spacing: 15) {
                Button("Test Again") {
                    onRestart()
                }
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.horizontal, 40)
                .padding(.vertical, 15)
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(15)
                
                Button("Back to Menu") {
                    onExit()
                }
                .font(.body)
                .fontWeight(.medium)
                .padding(.horizontal, 30)
                .padding(.vertical, 12)
                .background(Color.gray.opacity(0.7))
                .foregroundColor(.white)
                .cornerRadius(12)
            }
        }
        .padding(30)
        .background(Color.black.opacity(0.4))
        .cornerRadius(20)
        .shadow(radius: 10)
    }
}

struct ResultStat: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
        }
        .frame(minWidth: 80)
    }
}

#Preview {
    ZStack {
        Color.black
        
        VStack(spacing: 50) {
            TestStartUI {
                print("Start test")
            }
            
            TestRunningUI(
                score: 8,
                total: 12,
                maxStimuli: 20,
                onStop: { print("Stop") },
                onExit: { print("Exit") }
            )
        }
    }
}