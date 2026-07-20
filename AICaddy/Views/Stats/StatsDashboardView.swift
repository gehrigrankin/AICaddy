import SwiftUI
import SwiftData

/// Unified stats entry point with at-a-glance metrics and navigation cards
struct StatsDashboardView: View {
    @Query(filter: #Predicate<Round> { $0.isComplete == true }, sort: \Round.date, order: .reverse)
    private var rounds: [Round]

    private var handicapRounds: [HandicapRound] {
        rounds.prefix(20).compactMap { HandicapRound.fromRound($0) }
    }

    private var calculatedHandicap: Double? {
        HandicapCalculator.calculateIndex(rounds: handicapRounds)
    }

    private var allTimeStats: PeriodStats {
        AdvancedStatsCalculator.periodStats(rounds: rounds.map { $0 }, label: "All Time")
    }

    private var strokesGained: StrokesGainedResult {
        let allHoles = rounds.flatMap { $0.holes }
        return AdvancedStatsCalculator.strokesGained(holes: allHoles)
    }

    private var avgDriveDistance: Int? {
        var distances: [Int] = []
        for round in rounds {
            for hole in round.holes where hole.par >= 4 {
                if let shot = hole.shots.first(where: { $0.shotNumber == 1 && $0.club == .driver }),
                   let dist = shot.distanceYards, dist > 0 {
                    distances.append(dist)
                }
            }
        }
        guard !distances.isEmpty else { return nil }
        return distances.reduce(0, +) / distances.count
    }

    private var parAnalysis: (par3: ParTypeStats, par4: ParTypeStats, par5: ParTypeStats) {
        AdvancedStatsCalculator.parTypeAnalysis(rounds: rounds.map { $0 })
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.Colors.backdrop, Theme.Colors.surfaceDeep, Theme.Colors.backdrop],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    atAGlanceSection
                    navigationCardsSection
                }
                .padding()
            }
        }
        .navigationTitle("STATS")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.Colors.surface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    // MARK: - At a Glance

    @ViewBuilder
    private var atAGlanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AT A GLANCE")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.Colors.textMuted)

            LazyVGrid(columns: [.init(), .init()], spacing: 10) {
                glanceCard(
                    label: "Handicap",
                    value: calculatedHandicap.map { String(format: "%.1f", $0) } ?? "--",
                    icon: "number"
                )
                glanceCard(
                    label: "Avg Score",
                    value: allTimeStats.roundCount > 0 ? String(format: "%.0f", allTimeStats.avgScore) : "--",
                    icon: "chart.bar.fill"
                )
                glanceCard(
                    label: "Rounds Played",
                    value: "\(rounds.count)",
                    icon: "flag.fill"
                )
                glanceCard(
                    label: "Best Round",
                    value: allTimeStats.roundCount > 0 ? "\(allTimeStats.bestScore)" : "--",
                    icon: "star.fill"
                )
            }
        }
    }

    private func glanceCard(label: String, value: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textMuted)
                Text(value)
                    .font(.title2.bold())
            }
            Spacer()
        }
        .padding(12)
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Navigation Cards

    @ViewBuilder
    private var navigationCardsSection: some View {
        VStack(spacing: 12) {
            NavigationLink {
                StrokesGainedDetailView(rounds: rounds.map { $0 })
            } label: {
                navCard(
                    title: "Strokes Gained",
                    icon: "chart.line.uptrend.xyaxis",
                    color: .green,
                    preview: sgPreview
                )
            }

            NavigationLink {
                ClubDistancesDetailView(rounds: rounds.map { $0 })
            } label: {
                navCard(
                    title: "Club Distances",
                    icon: "figure.golf",
                    color: .blue,
                    preview: avgDriveDistance.map { "Avg Drive: \($0)y" } ?? "No data yet"
                )
            }

            NavigationLink {
                TrendsDetailView(rounds: rounds.map { $0 })
            } label: {
                navCard(
                    title: "Trends",
                    icon: "chart.xyaxis.line",
                    color: .purple,
                    preview: trendsPreview
                )
            }

            NavigationLink {
                ParPerformanceDetailView(rounds: rounds.map { $0 })
            } label: {
                navCard(
                    title: "Par Performance",
                    icon: "chart.pie.fill",
                    color: .orange,
                    preview: parPreview
                )
            }

            // Link to full deep dive
            NavigationLink {
                StatsDeepDiveView()
            } label: {
                HStack {
                    Text("All Stats (Deep Dive)")
                        .font(.subheadline.bold())
                        .foregroundStyle(Theme.Colors.accent)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textMuted)
                }
                .padding()
                .background(Theme.Colors.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func navCard(title: String, icon: String, color: Color, preview: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 40, height: 40)
                .background(color.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(preview)
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textMuted)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textMuted.opacity(0.6))
        }
        .padding(14)
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Preview Strings

    private var sgPreview: String {
        guard allTimeStats.roundCount > 0 else { return "No data yet" }
        return String(format: "SG Approach: %+.1f", strokesGained.approach)
    }

    private var trendsPreview: String {
        let trend = allTimeStats.scoreTrend
        guard trend.count >= 2 else { return "No data yet" }
        let recent = trend.suffix(5)
        let avg = recent.reduce(0, +) / recent.count
        return "Last \(recent.count) avg: \(avg)"
    }

    private var parPreview: String {
        let p4 = parAnalysis.par4
        guard p4.count > 0 else { return "No data yet" }
        return String(format: "Par 4 avg: %.1f", Double(4) + p4.avgToPar)
    }
}

// MARK: - Detail Wrappers

/// Wraps StrokesGainedView with navigation title
private struct StrokesGainedDetailView: View {
    let rounds: [Round]

    var body: some View {
        ScrollView {
            StrokesGainedView(rounds: rounds)
                .padding()
        }
        .navigationTitle("Strokes Gained")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Club distances detail, reusing logic from StatsDeepDiveView
private struct ClubDistancesDetailView: View {
    let rounds: [Round]

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

    var body: some View {
        ScrollView {
            let dispersion = AdvancedStatsCalculator.shotDispersion(rounds: rounds)
            let clubDists = buildClubDistances()

            VStack(spacing: 12) {
                if clubDists.isEmpty {
                    Text("No club data recorded yet.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.textMuted)
                        .padding(.top, 40)
                } else {
                    ForEach(
                        clubDists.sorted { ($0.value.reduce(0, +) / max(1, $0.value.count)) > ($1.value.reduce(0, +) / max(1, $1.value.count)) },
                        id: \.key
                    ) { club, distances in
                        ClubDistanceCard(club: club, distances: distances, dispersion: dispersion[club])
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Club Distances")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Trends detail view
private struct TrendsDetailView: View {
    let rounds: [Round]

    var body: some View {
        ScrollView {
            let allTime = AdvancedStatsCalculator.periodStats(rounds: rounds, label: "All Time")

            VStack(spacing: 20) {
                if allTime.scoreTrend.count >= 2 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Score Trend")
                            .font(.headline)
                        DashboardTrendBars(values: allTime.scoreTrend.reversed(), color: .green)
                    }
                }

                if allTime.handicapTrend.count >= 2 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Handicap Trend")
                            .font(.headline)
                        DashboardTrendBars(values: allTime.handicapTrend.map { Int($0) }, color: .cyan)
                    }
                }

                if allTime.scoreTrend.count < 2 && allTime.handicapTrend.count < 2 {
                    Text("Play more rounds to see trends.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.textMuted)
                        .padding(.top, 40)
                }
            }
            .padding()
        }
        .navigationTitle("Trends")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Par performance detail view
private struct ParPerformanceDetailView: View {
    let rounds: [Round]

    var body: some View {
        ScrollView {
            let analysis = AdvancedStatsCalculator.parTypeAnalysis(rounds: rounds)

            VStack(spacing: 16) {
                DashboardParSplitCard(par: 3, stats: analysis.par3)
                DashboardParSplitCard(par: 4, stats: analysis.par4)
                DashboardParSplitCard(par: 5, stats: analysis.par5)

                if analysis.par3.count == 0 && analysis.par4.count == 0 && analysis.par5.count == 0 {
                    Text("No par performance data yet.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.textMuted)
                        .padding(.top, 20)
                }
            }
            .padding()
        }
        .navigationTitle("Par Performance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Reusable Helper Views (private to this file)

private struct ClubDistanceCard: View {
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
                    .foregroundStyle(Theme.Colors.accent)
            }

            HStack(spacing: 12) {
                Text("Min: \(distances.min() ?? 0)y")
                    .font(.caption2).foregroundStyle(Theme.Colors.textMuted)
                Text("Max: \(distances.max() ?? 0)y")
                    .font(.caption2).foregroundStyle(Theme.Colors.textMuted)
                Text("\(distances.count) shots")
                    .font(.caption2).foregroundStyle(Theme.Colors.textMuted)
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

private struct DashboardParSplitCard: View {
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
                        .foregroundStyle(Theme.Colors.textMuted)
                }

                HStack {
                    Text("Avg: \(String(format: "%.1f", Double(par) + stats.avgToPar))")
                        .font(.subheadline)
                    Text("(\(stats.avgToPar >= 0 ? "+" : "")\(String(format: "%.1f", stats.avgToPar)) vs par)")
                        .font(.caption)
                        .foregroundStyle(stats.avgToPar <= 0 ? .green : .red)
                }

                Text("Birdies: \(stats.birdieOrBetter) | Pars: \(stats.pars) | Bogeys: \(stats.bogeys) | Dbl+: \(stats.doublePlus)")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textMuted)

                Text("Total vs par: \(stats.totalToPar >= 0 ? "+" : "")\(stats.totalToPar)")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textMuted)
            }
            .padding()
            .background(Color(.systemGray6).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

private struct DashboardTrendBars: View {
    let values: [Int]
    let color: Color

    var body: some View {
        let maxVal = Double(values.max() ?? 1)
        let minVal = Double(values.min() ?? 0)
        let range = max(1, maxVal - minVal)

        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, val in
                let height = max(8, (Double(val) - minVal) / range * 80)
                VStack(spacing: 1) {
                    Text("\(val)")
                        .font(.system(size: 8))
                        .foregroundStyle(Theme.Colors.textMuted)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(height: height)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 100)
    }
}
