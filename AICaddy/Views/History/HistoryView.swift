import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Round> { $0.isComplete == true },
           sort: \Round.date, order: .reverse)
    private var rounds: [Round]

    @State private var selectedRound: Round?
    @State private var comparing = false
    @State private var comparisonSelections: [Round] = []
    @State private var showComparison = false

    var body: some View {
        List {
            if rounds.isEmpty {
                ContentUnavailableView(
                    "No Rounds Yet",
                    systemImage: "flag.fill",
                    description: Text("Complete a round to see your history and stats here.")
                )
            }

            // Compare Rounds button
            if rounds.count >= 2 {
                Section {
                    if comparing {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Select 2 rounds to compare")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Button("Cancel") {
                                comparing = false
                                comparisonSelections.removeAll()
                            }
                            .foregroundStyle(.red)
                        }
                    } else {
                        Button {
                            comparing = true
                            comparisonSelections.removeAll()
                        } label: {
                            Label("Compare Rounds", systemImage: "arrow.left.arrow.right")
                        }
                    }
                }
            }

            // Aggregate stats section
            if rounds.count >= 2 {
                Section("Averages (\(rounds.count) rounds)") {
                    let allStats = rounds.map { StatsCalculator.calculate(holes: $0.holes) }
                    let avgScore = Double(allStats.reduce(0) { $0 + $1.totalStrokes }) / Double(allStats.count)
                    let avgPutts = Double(allStats.reduce(0) { $0 + $1.totalPutts }) / Double(allStats.count)
                    let avgGIR = allStats.reduce(0.0) { $0 + $1.greensInRegulationPct } / Double(allStats.count)
                    let avgFIR = allStats.reduce(0.0) { $0 + $1.fairwaysPct } / Double(allStats.count)
                    let best = allStats.min(by: { $0.totalStrokes < $1.totalStrokes })?.totalStrokes ?? 0

                    HStack {
                        MiniStat(label: "Avg", value: String(format: "%.0f", avgScore))
                        MiniStat(label: "Best", value: "\(best)")
                        MiniStat(label: "Putts", value: String(format: "%.0f", avgPutts))
                        MiniStat(label: "GIR", value: String(format: "%.0f%%", avgGIR))
                        MiniStat(label: "FIR", value: String(format: "%.0f%%", avgFIR))
                    }
                }
            }

            // Round list
            Section("Rounds") {
                ForEach(rounds) { round in
                    Button {
                        if comparing {
                            toggleComparisonSelection(round)
                        } else {
                            selectedRound = round
                        }
                    } label: {
                        HStack {
                            RoundRow(round: round)
                            if comparing {
                                Spacer()
                                if comparisonSelections.contains(where: { $0.id == round.id }) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .onDelete(perform: deleteRounds)
            }
        }
        .navigationTitle("History")
        .navigationDestination(isPresented: $showComparison) {
            if comparisonSelections.count == 2 {
                RoundComparisonView(round1: comparisonSelections[0], round2: comparisonSelections[1])
            }
        }
        .sheet(item: $selectedRound) { round in
            NavigationStack {
                RoundSummaryView(round: round, onDone: { selectedRound = nil })
                    .navigationTitle("Round Detail")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { selectedRound = nil }
                        }
                    }
            }
        }
    }

    private func toggleComparisonSelection(_ round: Round) {
        if let index = comparisonSelections.firstIndex(where: { $0.id == round.id }) {
            comparisonSelections.remove(at: index)
        } else if comparisonSelections.count < 2 {
            comparisonSelections.append(round)
            if comparisonSelections.count == 2 {
                comparing = false
                showComparison = true
            }
        }
    }

    private func deleteRounds(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(rounds[index])
        }
    }
}

struct RoundRow: View {
    let round: Round

    private var stats: RoundStats {
        StatsCalculator.calculate(holes: round.holes)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(round.courseName)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                Text("\(round.date.formatted(date: .abbreviated, time: .omitted)) · \(round.teeName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    if stats.totalPutts > 0 {
                        Text("\(stats.totalPutts) putts").font(.caption2).foregroundStyle(.secondary)
                    }
                    if stats.girHoles > 0 {
                        Text(String(format: "%.0f%% GIR", stats.greensInRegulationPct))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    if stats.fairwayHoles > 0 {
                        Text(String(format: "%.0f%% FIR", stats.fairwaysPct))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(stats.totalStrokes)")
                    .font(.title2.bold())
                ScoreText(scoreToPar: stats.scoreToPar)
                    .font(.caption.bold())
            }
        }
        .padding(.vertical, 4)
    }
}

struct MiniStat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline.bold())
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
