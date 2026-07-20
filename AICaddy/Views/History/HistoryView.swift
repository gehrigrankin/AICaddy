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
        ZStack {
            LinearGradient(
                colors: [Theme.Colors.backdrop, Theme.Colors.surfaceDeep, Theme.Colors.backdrop],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    if rounds.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "flag.fill")
                                .font(.system(size: 36, weight: .heavy))
                                .foregroundStyle(Theme.Colors.textMuted)
                            Text("NO ROUNDS YET")
                                .font(Theme.Font.title(15))
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .tracking(1.5)
                            Text("COMPLETE A ROUND TO SEE HISTORY")
                                .font(Theme.Font.caption(10))
                                .foregroundStyle(Theme.Colors.textMuted)
                                .tracking(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                    }

                    if rounds.count >= 2 {
                        if comparing {
                            VStack(spacing: 6) {
                                Text("SELECT 2 ROUNDS TO COMPARE")
                                    .font(Theme.Font.caption(11))
                                    .foregroundStyle(Theme.Colors.accent)
                                    .tracking(1)
                                Button {
                                    comparing = false
                                    comparisonSelections.removeAll()
                                } label: {
                                    Text("CANCEL")
                                        .font(Theme.Font.caption(10))
                                        .foregroundStyle(Theme.Colors.negative)
                                        .tracking(1)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                                    .fill(Theme.Colors.surface)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                                    .strokeBorder(Theme.Colors.border, lineWidth: 1)
                            )
                        } else {
                            Button {
                                comparing = true
                                comparisonSelections.removeAll()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.left.arrow.right")
                                        .font(.system(size: 13, weight: .heavy))
                                    Text("COMPARE ROUNDS")
                                        .font(Theme.Font.title(13))
                                        .tracking(1)
                                }
                                .foregroundStyle(Theme.Colors.accent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                                        .fill(Theme.Colors.surface)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                                        .strokeBorder(Theme.Colors.border, lineWidth: 1)
                                )
                            }
                        }
                    }

                    if rounds.count >= 2 {
                        let allStats = rounds.map { StatsCalculator.calculate(holes: $0.holes) }
                        let avgScore = Double(allStats.reduce(0) { $0 + $1.totalStrokes }) / Double(allStats.count)
                        let avgPutts = Double(allStats.reduce(0) { $0 + $1.totalPutts }) / Double(allStats.count)
                        let avgGIR = allStats.reduce(0.0) { $0 + $1.greensInRegulationPct } / Double(allStats.count)
                        let avgFIR = allStats.reduce(0.0) { $0 + $1.fairwaysPct } / Double(allStats.count)
                        let best = allStats.min(by: { $0.totalStrokes < $1.totalStrokes })?.totalStrokes ?? 0

                        VStack(alignment: .leading, spacing: 8) {
                            Text("AVERAGES · \(rounds.count) ROUNDS")
                                .font(Theme.Font.caption(10))
                                .foregroundStyle(Theme.Colors.accent)
                                .tracking(1.5)
                            HStack(spacing: 6) {
                                MiniStat(label: "AVG", value: String(format: "%.0f", avgScore))
                                MiniStat(label: "BEST", value: "\(best)")
                                MiniStat(label: "PUTTS", value: String(format: "%.0f", avgPutts))
                                MiniStat(label: "GIR", value: String(format: "%.0f%%", avgGIR))
                                MiniStat(label: "FIR", value: String(format: "%.0f%%", avgFIR))
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                                    .fill(Theme.Colors.surface)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                                    .strokeBorder(Theme.Colors.border, lineWidth: 1)
                            )
                        }
                    }

                    if !rounds.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("ROUNDS")
                                .font(Theme.Font.caption(10))
                                .foregroundStyle(Theme.Colors.accent)
                                .tracking(1.5)

                            VStack(spacing: 8) {
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
                                                Image(systemName: comparisonSelections.contains(where: { $0.id == round.id }) ? "checkmark.circle.fill" : "circle")
                                                    .font(.system(size: 18, weight: .heavy))
                                                    .foregroundStyle(comparisonSelections.contains(where: { $0.id == round.id }) ? Theme.Colors.accent : Theme.Colors.textMuted)
                                            }
                                        }
                                        .padding(12)
                                        .background(
                                            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                                                .fill(Theme.Colors.surface)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                                                .strokeBorder(Theme.Colors.border, lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("HISTORY")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.Colors.surface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationDestination(isPresented: $showComparison) {
            if comparisonSelections.count == 2 {
                RoundComparisonView(round1: comparisonSelections[0], round2: comparisonSelections[1])
            }
        }
        .sheet(item: $selectedRound) { round in
            NavigationStack {
                RoundSummaryView(round: round, onDone: { selectedRound = nil })
                    .navigationTitle("ROUND DETAIL")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                selectedRound = nil
                            } label: {
                                Text("DONE")
                                    .font(Theme.Font.caption(12))
                                    .foregroundStyle(Theme.Colors.accent)
                                    .tracking(1)
                            }
                        }
                    }
                    .toolbarBackground(Theme.Colors.surface, for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
            }
            .preferredColorScheme(.dark)
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
}

struct RoundRow: View {
    let round: Round

    private var stats: RoundStats {
        StatsCalculator.calculate(holes: round.holes)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(round.courseName.uppercased())
                    .font(Theme.Font.title(14))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .tracking(0.5)
                Text("\(round.date.formatted(date: .abbreviated, time: .omitted)) · \(round.teeName)".uppercased())
                    .font(Theme.Font.caption(10))
                    .foregroundStyle(Theme.Colors.textMuted)
                    .tracking(0.5)
                HStack(spacing: 10) {
                    if stats.totalPutts > 0 {
                        Text("\(stats.totalPutts) PUTTS")
                            .font(Theme.Font.caption(9))
                            .foregroundStyle(Theme.Colors.textMuted)
                            .tracking(0.5)
                    }
                    if stats.girHoles > 0 {
                        Text(String(format: "%.0f%% GIR", stats.greensInRegulationPct))
                            .font(Theme.Font.caption(9))
                            .foregroundStyle(Theme.Colors.textMuted)
                            .tracking(0.5)
                    }
                    if stats.fairwayHoles > 0 {
                        Text(String(format: "%.0f%% FIR", stats.fairwaysPct))
                            .font(Theme.Font.caption(9))
                            .foregroundStyle(Theme.Colors.textMuted)
                            .tracking(0.5)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(stats.totalStrokes)")
                    .font(Theme.Font.display(22))
                    .foregroundStyle(Theme.Colors.textPrimary)
                ScoreText(scoreToPar: stats.scoreToPar)
                    .font(Theme.Font.caption(11))
            }
        }
    }
}

struct MiniStat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(Theme.Font.display(16))
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(label)
                .font(Theme.Font.caption(9))
                .foregroundStyle(Theme.Colors.textMuted)
                .tracking(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}
