import SwiftUI

// MARK: - Demo data generator

private func makeDemoSession() -> SimpleTestSession {
    // Mirrors the live 76-point Humphrey 30-2 style grid (6° Cartesian, ±27°, 228 trials)
    let steps: [Float] = [-27, -21, -15, -9, -3, 3, 9, 15, 21, 27]
    let brightnessLevels: [(value: Float, index: Int)] = [(0.25, 0), (0.60, 1), (1.00, 2)]

    // Hit probability drops with eccentricity and dim stimuli
    func hitProb(ecc: Float, brightnessIndex: Int) -> Double {
        let eccFactor = max(0.30, 1.0 - Double(ecc) / 42.0)
        let brightFactor: Double = brightnessIndex == 0 ? 0.70 : brightnessIndex == 1 ? 0.88 : 1.00
        return min(eccFactor * brightFactor, 0.98)
    }

    var trials: [StimulusTrial] = []
    var trialID = 0
    let sessionStart = Date(timeIntervalSinceNow: -1400) // ~23 min ago
    var rng = SystemRandomNumberGenerator()

    for yDeg in steps {
        for xDeg in steps {
            let eccSq = xDeg * xDeg + yDeg * yDeg
            guard eccSq < 882 else { continue }

            let ecc = eccSq.squareRoot()
            var angle = atan2(yDeg, xDeg) * 180.0 / Float.pi
            if angle < 0 { angle += 360 }

            for (bVal, bIdx) in brightnessLevels {
                let offset = Double(trialID) * 6.2
                let spawnTime = sessionStart.addingTimeInterval(offset)
                let prob = hitProb(ecc: ecc, brightnessIndex: bIdx)
                let wasHit = Double.random(in: 0...1, using: &rng) < prob
                let baseRT = 0.30 + (Double(ecc) / 29.7) * 0.55 + (Double(2 - bIdx) * 0.15)
                let rt = wasHit ? baseRT + Double.random(in: -0.08...0.25, using: &rng) : nil
                trials.append(StimulusTrial(
                    trialID: trialID, spotID: trialID,
                    angleDegrees: angle, eccentricityDegrees: ecc,
                    spawnTime: spawnTime,
                    responseTime: wasHit ? spawnTime.addingTimeInterval(rt!) : nil,
                    wasHit: wasHit, timedOut: !wasHit,
                    brightnessValue: bVal, brightnessLevelIndex: bIdx
                ))
                trialID += 1
            }
        }
    }

    let hits = trials.filter { $0.wasHit }.count
    return SimpleTestSession(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        date: sessionStart,
        completedTrials: trials.count,
        totalTrials: 228,
        hitCount: hits,
        missedCount: trials.count - hits,
        trials: trials
    )
}

// MARK: - Results view

struct SimpleResultsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var sessions: [SimpleTestSession] = []
    @State private var selectedSession: SimpleTestSession? = nil

    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }

    private let demoSession = makeDemoSession()

    var body: some View {
        NavigationStack {
            List {
                // Real sessions (most recent first)
                if !sessions.isEmpty {
                    Section("Your Sessions") {
                        ForEach(sessions.reversed()) { session in
                            Button {
                                selectedSession = session
                            } label: {
                                SessionRowView(session: session, dateFormatter: dateFormatter)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Demo session — always visible
                Section {
                    Button {
                        selectedSession = demoSession
                    } label: {
                        SessionRowView(session: demoSession, dateFormatter: dateFormatter)
                    }
                    .buttonStyle(.plain)
                } header: {
                    Label("Demo — Example of a completed test", systemImage: "info.circle")
                }
            }
            .navigationTitle("Results")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(item: $selectedSession) { session in
                SessionDetailSheet(session: session)
            }
            .onAppear {
                sessions = SimpleSessionStore.loadAll()
            }
        }
    }
}

// MARK: - Session row in the list

struct SessionRowView: View {
    let session: SimpleTestSession
    let dateFormatter: DateFormatter

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(dateFormatter.string(from: session.date))
                    .font(.headline)
                Spacer()
                Text("\(Int(session.accuracy * 100))% accuracy")
                    .font(.subheadline)
                    .foregroundColor(session.accuracy >= 0.7 ? .green : .orange)
            }
            HStack(spacing: 18) {
                Label("\(session.hitCount) hits", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Label("\(session.missedCount) misses", systemImage: "xmark.circle.fill")
                    .foregroundColor(.red)
                Text("\(session.completedTrials) / \(session.totalTrials) trials")
                    .foregroundColor(.secondary)
            }
            .font(.subheadline)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Detail sheet for one session

struct SessionDetailSheet: View {
    let session: SimpleTestSession
    @Environment(\.dismiss) private var dismiss

    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .short
        return f
    }

    // Builds the CSV as a temp file URL so ShareLink can attach it
    private var csvFileURL: URL {
        var csv = "trial_index,angle_deg,ecc_deg,hit,reaction_time_sec,brightness_value\n"
        for trial in session.trials {
            let hit = trial.wasHit ? "true" : "false"
            let rt  = trial.reactionTimeSeconds.map { String(format: "%.3f", $0) } ?? "-1.0"
            csv += "\(trial.trialID),\(String(format: "%.1f", trial.angleDegrees)),\(String(format: "%.1f", trial.eccentricityDegrees)),\(hit),\(rt),\(trial.brightnessLevelIndex + 1)\n"
        }
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd_HHmmss"
        let name = "perimetry_\(df.string(from: session.date)).csv"
        let url  = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // Summary cards
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ResultStatCard(label: "Accuracy", value: "\(Int(session.accuracy * 100))%", color: .blue)
                        ResultStatCard(label: "Avg RT",
                                 value: session.averageReactionTime > 0
                                    ? "\(Int(session.averageReactionTime * 1000))ms"
                                    : "—",
                                 color: .orange)
                        ResultStatCard(label: "Trials",
                                 value: "\(session.completedTrials)/\(session.totalTrials)",
                                 color: .purple)
                    }

                    // Accuracy by eccentricity
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Accuracy by Eccentricity")
                            .font(.title3).fontWeight(.semibold)

                        ForEach(session.accuracyByEccentricity(), id: \.eccentricity) { item in
                            HStack(spacing: 10) {
                                Text("\(Int(item.eccentricity))°")
                                    .font(.subheadline).monospacedDigit()
                                    .frame(width: 36, alignment: .trailing)
                                ProgressView(value: item.accuracy)
                                    .tint(item.accuracy >= 0.7 ? .green : .orange)
                                Text("\(Int(item.accuracy * 100))%")
                                    .font(.subheadline).monospacedDigit()
                                    .frame(width: 40, alignment: .trailing)
                            }
                        }
                    }

                    // Hits vs misses breakdown
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Trial Breakdown")
                            .font(.title3).fontWeight(.semibold)

                        LazyVStack(spacing: 4) {
                            ForEach(session.trials) { trial in
                                HStack {
                                    Circle()
                                        .fill(trial.wasHit ? Color.green : Color.red)
                                        .frame(width: 8, height: 8)
                                    Text("\(Int(trial.eccentricityDegrees))°  \(Int(trial.angleDegrees))°az")
                                        .font(.caption).monospacedDigit()
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(trial.wasHit ? "Hit" : (trial.timedOut ? "Timeout" : "Miss"))
                                        .font(.caption)
                                        .foregroundColor(trial.wasHit ? .green : .secondary)
                                    if let rt = trial.reactionTimeSeconds {
                                        Text("\(Int(rt * 1000))ms")
                                            .font(.caption).monospacedDigit()
                                            .foregroundColor(.secondary)
                                            .frame(width: 50, alignment: .trailing)
                                    } else {
                                        Text("—")
                                            .font(.caption).foregroundColor(.secondary)
                                            .frame(width: 50, alignment: .trailing)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(dateFormatter.string(from: session.date))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ShareLink(item: csvFileURL) {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct ResultStatCard: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.title2).fontWeight(.bold)
                .foregroundColor(color)
            Text(label)
                .font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.quaternary)
        .cornerRadius(12)
    }
}
