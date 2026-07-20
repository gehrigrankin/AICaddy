import SwiftUI

struct YearlyWrappedView: View {
    let rounds: [Round]
    let year: Int

    init(rounds: [Round], year: Int = Calendar.current.component(.year, from: Date())) {
        self.rounds = rounds
        self.year = year
    }

    // MARK: - Computed Data

    private var allStats: [(Round, RoundStats)] {
        rounds.map { ($0, StatsCalculator.calculate(holes: $0.holes)) }
    }

    private var totalRounds: Int { rounds.count }

    private var totalHolesPlayed: Int {
        rounds.flatMap { $0.holes }.filter { $0.strokes > 0 }.count
    }

    private var estimatedMiles: Double {
        let eighteenHoleEquivalent = Double(totalHolesPlayed) / 18.0
        return eighteenHoleEquivalent * 5.0
    }

    private var bestRound: (Round, RoundStats)? {
        allStats.filter { $0.1.totalStrokes > 0 }.min(by: { $0.1.totalStrokes < $1.1.totalStrokes })
    }

    private var worstRound: (Round, RoundStats)? {
        allStats.filter { $0.1.totalStrokes > 0 }.max(by: { $0.1.totalStrokes < $1.1.totalStrokes })
    }

    private var mostPlayedCourse: (String, Int)? {
        let counts = Dictionary(grouping: rounds, by: { $0.courseName })
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }
        guard let top = counts.first else { return nil }
        return (top.key, top.value)
    }

    private var mostUsedClub: (Club, Int)? {
        var clubCounts: [Club: Int] = [:]
        for round in rounds {
            for hole in round.holes {
                for shot in hole.shots {
                    if let club = shot.club {
                        clubCounts[club, default: 0] += 1
                    }
                }
            }
        }
        guard let top = clubCounts.max(by: { $0.value < $1.value }) else { return nil }
        return (top.key, top.value)
    }

    private var bestHole: (Int, String)? {
        // Find the hole number where the player scored the most birdies or better
        var holeBirdies: [Int: Int] = [:]
        for round in rounds {
            for hole in round.holes {
                if let diff = hole.scoreToPar, diff < 0 {
                    holeBirdies[hole.holeNumber, default: 0] += 1
                }
            }
        }
        guard let top = holeBirdies.max(by: { $0.value < $1.value }) else { return nil }
        let label = top.value == 1 ? "birdie or better" : "birdies or better"
        return (top.key, "\(top.value) \(label)")
    }

    private var scoringImprovement: Double? {
        let sorted = allStats.sorted { $0.0.date < $1.0.date }
        guard sorted.count >= 10 else { return nil }
        let first5 = sorted.prefix(5).map { Double($0.1.totalStrokes) }
        let last5 = sorted.suffix(5).map { Double($0.1.totalStrokes) }
        let avgFirst = first5.reduce(0, +) / Double(first5.count)
        let avgLast = last5.reduce(0, +) / Double(last5.count)
        return avgFirst - avgLast
    }

    private var totalPutts: Int {
        allStats.reduce(0) { $0 + $1.1.totalPutts }
    }

    private var totalFairways: Int {
        allStats.reduce(0) { $0 + $1.1.fairwaysHit }
    }

    private var totalBirdies: Int {
        allStats.reduce(0) { $0 + $1.1.birdies }
    }

    private var totalPars: Int {
        allStats.reduce(0) { $0 + $1.1.pars }
    }

    private var totalEagles: Int {
        allStats.reduce(0) { $0 + $1.1.eagles }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                titleCard
                overviewCard
                bestRoundCard
                worstRoundCard
                mostPlayedCard
                mostUsedClubCard
                bestHoleCard
                improvementCard
                funStatsCard
            }
            .padding()
        }
        .background(Theme.Colors.backdrop.ignoresSafeArea())
        .navigationTitle("\(String(year)) WRAPPED")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.Colors.surface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    // MARK: - Cards

    private var titleCard: some View {
        VStack(spacing: 8) {
            Text("Your \(String(year))")
                .font(.title3)
                .foregroundStyle(Theme.Colors.textMuted)
            Text("Golf Wrapped")
                .font(.system(size: 36, weight: .black))
                .foregroundStyle(Theme.Colors.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var overviewCard: some View {
        wrappedCard {
            VStack(spacing: 20) {
                Text("THE OVERVIEW")
                    .font(.caption.bold())
                    .foregroundStyle(Theme.Colors.accent)
                    .tracking(2)

                HStack(spacing: 24) {
                    bigStat(value: "\(totalRounds)", label: "Rounds")
                    bigStat(value: "\(totalHolesPlayed)", label: "Holes")
                    bigStat(value: String(format: "%.0f", estimatedMiles), label: "Miles")
                }
            }
        }
    }

    private var bestRoundCard: some View {
        wrappedCard {
            VStack(spacing: 12) {
                Text("BEST ROUND")
                    .font(.caption.bold())
                    .foregroundStyle(Theme.Colors.accent)
                    .tracking(2)

                if let (round, stats) = bestRound {
                    Text("\(stats.totalStrokes)")
                        .font(.system(size: 64, weight: .black))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(round.courseName)
                        .font(.title3.bold())
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(round.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.textMuted)
                    ScoreText(scoreToPar: stats.scoreToPar)
                        .font(.headline.bold())
                } else {
                    Text("-")
                        .font(.title)
                        .foregroundStyle(Theme.Colors.textMuted)
                }
            }
        }
    }

    private var worstRoundCard: some View {
        wrappedCard {
            VStack(spacing: 12) {
                Text("TOUGHEST DAY")
                    .font(.caption.bold())
                    .foregroundStyle(Theme.Colors.accent)
                    .tracking(2)

                if let (round, stats) = worstRound {
                    Text("\(stats.totalStrokes)")
                        .font(.system(size: 48, weight: .black))
                        .foregroundStyle(Theme.Colors.textPrimary.opacity(0.7))
                    Text(round.courseName)
                        .font(.subheadline.bold())
                        .foregroundStyle(Theme.Colors.textPrimary.opacity(0.7))
                    Text(round.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textMuted)
                } else {
                    Text("-")
                        .font(.title)
                        .foregroundStyle(Theme.Colors.textMuted)
                }
            }
        }
    }

    private var mostPlayedCard: some View {
        wrappedCard {
            VStack(spacing: 12) {
                Text("HOME COURSE")
                    .font(.caption.bold())
                    .foregroundStyle(Theme.Colors.accent)
                    .tracking(2)

                if let (name, count) = mostPlayedCourse {
                    Text(name)
                        .font(.title2.bold())
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .multilineTextAlignment(.center)
                    Text("\(count) \(count == 1 ? "round" : "rounds")")
                        .font(.headline)
                        .foregroundStyle(Theme.Colors.textMuted)
                } else {
                    Text("-")
                        .font(.title)
                        .foregroundStyle(Theme.Colors.textMuted)
                }
            }
        }
    }

    private var mostUsedClubCard: some View {
        wrappedCard {
            VStack(spacing: 12) {
                Text("GO-TO CLUB")
                    .font(.caption.bold())
                    .foregroundStyle(Theme.Colors.accent)
                    .tracking(2)

                if let (club, count) = mostUsedClub {
                    Text(club.displayName)
                        .font(.system(size: 36, weight: .black))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("\(count) shots")
                        .font(.headline)
                        .foregroundStyle(Theme.Colors.textMuted)
                } else {
                    Text("-")
                        .font(.title)
                        .foregroundStyle(Theme.Colors.textMuted)
                }
            }
        }
    }

    private var bestHoleCard: some View {
        wrappedCard {
            VStack(spacing: 12) {
                Text("MONEY HOLE")
                    .font(.caption.bold())
                    .foregroundStyle(Theme.Colors.accent)
                    .tracking(2)

                if let (holeNum, description) = bestHole {
                    Text("Hole \(holeNum)")
                        .font(.system(size: 36, weight: .black))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(description)
                        .font(.headline)
                        .foregroundStyle(Theme.Colors.textMuted)
                } else {
                    Text("No birdies yet")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.textMuted)
                }
            }
        }
    }

    private var improvementCard: some View {
        wrappedCard {
            VStack(spacing: 12) {
                Text("IMPROVEMENT")
                    .font(.caption.bold())
                    .foregroundStyle(Theme.Colors.accent)
                    .tracking(2)

                if let improvement = scoringImprovement {
                    let improved = improvement > 0
                    Text(String(format: "%+.1f", improved ? -improvement : -improvement))
                        .font(.system(size: 48, weight: .black))
                        .foregroundStyle(improved ? .green : .red)
                    Text(improved ? "strokes better" : "strokes higher")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.textMuted)
                    Text("Last 5 rounds vs first 5")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textMuted.opacity(0.7))
                } else {
                    Text("Play 10+ rounds to unlock")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.textMuted)
                }
            }
        }
    }

    private var funStatsCard: some View {
        wrappedCard {
            VStack(spacing: 16) {
                Text("BY THE NUMBERS")
                    .font(.caption.bold())
                    .foregroundStyle(Theme.Colors.accent)
                    .tracking(2)

                VStack(spacing: 12) {
                    funStatRow(value: "\(totalPutts)", label: "Total Putts")
                    funStatRow(value: "\(totalFairways)", label: "Fairways Hit")
                    funStatRow(value: "\(totalBirdies)", label: "Birdies Made")
                    funStatRow(value: "\(totalEagles)", label: "Eagles Made")
                    funStatRow(value: "\(totalPars)", label: "Pars")
                }
            }
        }
    }

    // MARK: - Helpers

    private func wrappedCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .padding(.horizontal, 24)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Theme.Colors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Theme.Colors.accent.opacity(0.25), lineWidth: 1)
            )
    }

    private func bigStat(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 32, weight: .black))
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.Colors.textMuted)
        }
    }

    private func funStatRow(value: String, label: String) -> some View {
        HStack {
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(Theme.Colors.textPrimary)
                .frame(width: 60, alignment: .trailing)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textMuted)
            Spacer()
        }
    }
}
