import SwiftUI
import SwiftData

/// Comprehensive stats dashboard with all the analytics
struct StatsDeepDiveView: View {
    @Query(filter: #Predicate<Round> { $0.isComplete == true }, sort: \Round.date, order: .reverse)
    private var rounds: [Round]

    @State private var selectedTab = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Tab picker
                Picker("Stats", selection: $selectedTab) {
                    Text("Overview").tag(0)
                    Text("Strokes Gained").tag(1)
                    Text("Par Splits").tag(2)
                    Text("Clubs").tag(3)
                    Text("Trends").tag(4)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                switch selectedTab {
                case 0: overviewTab
                case 1: strokesGainedTab
                case 2: parSplitsTab
                case 3: clubsTab
                case 4: trendsTab
                default: EmptyView()
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Deep Stats")
    }

    // MARK: - Overview

    @ViewBuilder
    private var overviewTab: some View {
        let allTime = AdvancedStatsCalculator.periodStats(rounds: rounds.map { $0 }, label: "All Time")
        let thisMonth = AdvancedStatsCalculator.periodStats(
            rounds: rounds.filter { Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .month) },
            label: "This Month"
        )
        let last5 = AdvancedStatsCalculator.periodStats(
            rounds: Array(rounds.prefix(5)),
            label: "Last 5 Rounds"
        )

        VStack(spacing: 16) {
            // Period comparison
            ForEach([last5, thisMonth, allTime], id: \.label) { period in
                if period.roundCount > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(period.label)
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)

                        LazyVGrid(columns: [.init(), .init(), .init()], spacing: 6) {
                            StatCard(label: "Avg Score", value: String(format: "%.0f", period.avgScore))
                            StatCard(label: "Best", value: "\(period.bestScore)")
                            StatCard(label: "Rounds", value: "\(period.roundCount)")
                            StatCard(label: "Avg Putts", value: String(format: "%.0f", period.avgPutts))
                            StatCard(label: "GIR", value: String(format: "%.0f%%", period.avgGIR))
                            StatCard(label: "FIR", value: String(format: "%.0f%%", period.avgFIR))
                        }
                    }
                }
            }

            // Streak detection for last round
            if let lastRound = rounds.first {
                let streaks = AdvancedStatsCalculator.detectStreaks(holes: lastRound.holes)

                if !streaks.hotStreaks.isEmpty || !streaks.coldStreaks.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Last Round Streaks")
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)

                        ForEach(streaks.hotStreaks.prefix(2), id: \.startHole) { streak in
                            HStack {
                                Image(systemName: "flame.fill").foregroundStyle(.orange)
                                Text(streak.description).font(.caption)
                            }
                        }
                        ForEach(streaks.coldStreaks.prefix(2), id: \.startHole) { streak in
                            HStack {
                                Image(systemName: "snowflake").foregroundStyle(.blue)
                                Text(streak.description).font(.caption)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Strokes Gained

    @ViewBuilder
    private var strokesGainedTab: some View {
        StrokesGainedView(rounds: rounds.map { $0 })
            .padding(.horizontal)
    }

    // MARK: - Par Splits

    @ViewBuilder
    private var parSplitsTab: some View {
        let analysis = AdvancedStatsCalculator.parTypeAnalysis(rounds: rounds.map { $0 })

        VStack(spacing: 16) {
            ParSplitCard(par: 3, stats: analysis.par3)
            ParSplitCard(par: 4, stats: analysis.par4)
            ParSplitCard(par: 5, stats: analysis.par5)
        }
        .padding(.horizontal)
    }

    // MARK: - Clubs

    private func buildClubDistances() -> [Club: [Int]] {
        var clubDists: [Club: [Int]] = [:]
        for round in rounds {
            for hole in round.holes {
                for shot in hole.shots where !shot.isPutt {
                    if let club = shot.club, let dist = shot.distanceYards, dist > 0 {
                        clubDists[club, default: []].append(dist)
                    }
                }
            }
        }
        return clubDists
    }

    @ViewBuilder
    private var clubsTab: some View {
        let dispersion = AdvancedStatsCalculator.shotDispersion(rounds: rounds.map { $0 })
        let clubDists = buildClubDistances()

        VStack(spacing: 12) {
            ForEach(
                clubDists.sorted { ($0.value.reduce(0, +) / max(1, $0.value.count)) > ($1.value.reduce(0, +) / max(1, $1.value.count)) },
                id: \.key
            ) { club, distances in
                ClubDistanceRow(club: club, distances: distances, dispersion: dispersion[club])
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Trends

    @ViewBuilder
    private var trendsTab: some View {
        let allTime = AdvancedStatsCalculator.periodStats(rounds: rounds.map { $0 }, label: "All Time")

        VStack(spacing: 16) {
            // Score trend
            if allTime.scoreTrend.count >= 2 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Score Trend").font(.subheadline.bold()).foregroundStyle(.secondary)
                    TrendBars(values: allTime.scoreTrend.reversed(), color: .green)
                }
            }

            // Handicap trend
            if allTime.handicapTrend.count >= 2 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Handicap Trend").font(.subheadline.bold()).foregroundStyle(.secondary)
                    TrendBars(values: allTime.handicapTrend.map { Int($0) }, color: .cyan)
                }
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Helper Views

private struct ParSplitCard: View {
    let par: Int
    let stats: ParTypeStats

    var body: some View {
        if stats.count > 0 {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Par \(par)s")
                        .font(.headline.bold())
                    Spacer()
                    Text("\(stats.count) holes played")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Avg: \(String(format: "%.1f", Double(par) + stats.avgToPar))")
                        .font(.subheadline)
                    Text("(\(stats.avgToPar >= 0 ? "+" : "")\(String(format: "%.1f", stats.avgToPar)) vs par)")
                        .font(.caption)
                        .foregroundStyle(stats.avgToPar <= 0 ? .green : .red)
                }

                HStack(spacing: 2) {
                    if stats.birdieOrBetter > 0 {
                        DistBar(label: "Bird+", count: stats.birdieOrBetter, total: stats.count, color: .red)
                    }
                    if stats.pars > 0 {
                        DistBar(label: "Par", count: stats.pars, total: stats.count, color: .green)
                    }
                    if stats.bogeys > 0 {
                        DistBar(label: "Bogey", count: stats.bogeys, total: stats.count, color: .cyan)
                    }
                    if stats.doublePlus > 0 {
                        DistBar(label: "Dbl+", count: stats.doublePlus, total: stats.count, color: .blue)
                    }
                }
                .frame(height: 24)

                Text("Total vs par: \(stats.totalToPar >= 0 ? "+" : "")\(stats.totalToPar)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(.systemGray6).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

private struct ClubDistanceRow: View {
    let club: Club
    let distances: [Int]
    let dispersion: ShotDispersion?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(club.displayName)
                    .font(.subheadline.bold())
                Spacer()
                Text("avg \(distances.reduce(0, +) / distances.count)y")
                    .font(.subheadline.bold())
                    .foregroundStyle(.green)
            }

            HStack(spacing: 12) {
                Text("Min: \(distances.min() ?? 0)y")
                    .font(.caption2).foregroundStyle(.secondary)
                Text("Max: \(distances.max() ?? 0)y")
                    .font(.caption2).foregroundStyle(.secondary)
                Text("\(distances.count) shots")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            if let disp = dispersion {
                Text(disp.missTendency)
                    .font(.caption2)
                    .foregroundStyle(disp.missTendency == "Balanced" ? .green : .orange)
            }
        }
        .padding(10)
        .background(Color(.systemGray6).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct SGCard: View {
    let label: String
    let value: Double

    var body: some View {
        VStack(spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(String(format: "%+.1f", value))
                .font(.title3.bold())
                .foregroundStyle(value >= 0 ? .green : .red)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct DistBar: View {
    let label: String
    let count: Int
    let total: Int
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let pct = total > 0 ? CGFloat(count) / CGFloat(total) : 0
            RoundedRectangle(cornerRadius: 4)
                .fill(color.opacity(0.3))
                .frame(width: geo.size.width * pct)
                .overlay(
                    Text("\(label) \(count)")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                )
        }
    }
}

private struct TrendBars: View {
    let values: [Int]
    let color: Color

    var body: some View {
        let maxVal = Double(values.max() ?? 1)
        let minVal = Double(values.min() ?? 0)
        let range = max(1, maxVal - minVal)

        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, val in
                let height = max(8, (Double(val) - minVal) / range * 60)
                VStack(spacing: 1) {
                    Text("\(val)")
                        .font(.system(size: 7))
                        .foregroundStyle(.secondary)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(height: height)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 80)
    }
}
