import SwiftUI

// MARK: - Handicap-Level Benchmarks

/// Benchmark stats by handicap level for strokes gained comparisons
enum SGBenchmark: String, CaseIterable, Identifiable {
    case scratch = "Scratch (0)"
    case mid = "10 Handicap"
    case high = "20 Handicap"

    var id: String { rawValue }

    var avgDrivingDistance: Double {
        switch self {
        case .scratch: return 270
        case .mid: return 240
        case .high: return 210
        }
    }

    var girPct: Double {
        switch self {
        case .scratch: return 67
        case .mid: return 45
        case .high: return 28
        }
    }

    var scramblingPct: Double {
        switch self {
        case .scratch: return 60
        case .mid: return 35
        case .high: return 20
        }
    }

    var puttsPerGIR: Double {
        switch self {
        case .scratch: return 1.75
        case .mid: return 1.85
        case .high: return 2.0
        }
    }

    /// Fairway hit percentage benchmark
    var fairwayPct: Double {
        switch self {
        case .scratch: return 65
        case .mid: return 55
        case .high: return 45
        }
    }

    /// Cost per missed GIR in strokes
    static let missedGIRCost: Double = 0.4
}

// MARK: - Strokes Gained by Category (benchmark-aware)

struct SGCategoryResult: Identifiable {
    let id = UUID()
    let category: String
    let value: Double
    let detail: String
}

/// Calculates strokes gained per category against a chosen benchmark
enum SGCalculator {

    struct Result {
        let offTheTee: SGCategoryResult
        let approach: SGCategoryResult
        let aroundTheGreen: SGCategoryResult
        let putting: SGCategoryResult
        var total: Double {
            offTheTee.value + approach.value + aroundTheGreen.value + putting.value
        }
        var categories: [SGCategoryResult] {
            [offTheTee, approach, aroundTheGreen, putting]
        }
    }

    static func calculate(stats: RoundStats, holesPlayed: Int, benchmark: SGBenchmark) -> Result {
        let holes = max(holesPlayed, 1)

        // -- Off the Tee --
        let playerFIR = stats.fairwaysPct
        let benchFIR = benchmark.fairwayPct
        let playerDriving = Double(stats.avgDrivingDistance)
        let benchDriving = benchmark.avgDrivingDistance

        // Each % of FIR difference is worth ~0.02 strokes/hole on par-4/5 holes
        // Each 10y of driving distance is worth ~0.1 strokes/hole on par-4/5 holes
        let fairwayHoles = Double(max(stats.fairwayHoles, 1))
        let firGain = (playerFIR - benchFIR) / 100.0 * fairwayHoles * 0.02 * 18.0 / Double(holes)
        let distGain = playerDriving > 0 ? (playerDriving - benchDriving) / 10.0 * 0.1 * fairwayHoles / Double(holes) : 0
        // Penalty strokes off the tee
        let penalties = stats.eagles // reuse: count OB/water from shots if available
        let teeSG = firGain + distGain
        let teeDetail: String
        if playerDriving > 0 {
            teeDetail = String(format: "%.0f%% FIR (bench %.0f%%), %.0fy avg (bench %.0fy)", playerFIR, benchFIR, playerDriving, benchDriving)
        } else {
            teeDetail = String(format: "%.0f%% FIR (bench %.0f%%)", playerFIR, benchFIR)
        }

        // -- Approach --
        let playerGIR = stats.greensInRegulationPct
        let benchGIR = benchmark.girPct
        let girDiff = playerGIR - benchGIR
        let girHoles = Double(max(stats.girHoles, 1))
        let approachSG = (girDiff / 100.0) * girHoles * SGBenchmark.missedGIRCost * 18.0 / Double(holes)
        let approachDetail = String(format: "%.0f%% GIR (bench %.0f%%), %.1f missed GIR cost",
                                    playerGIR, benchGIR,
                                    Double(stats.girHoles - stats.greensInRegulation) * SGBenchmark.missedGIRCost)

        // -- Around the Green --
        let playerScrambling = stats.scramblingPct
        let benchScrambling = benchmark.scramblingPct
        let missedGreens = Double(stats.girHoles - stats.greensInRegulation)
        let scramblingGain = missedGreens > 0
            ? (playerScrambling - benchScrambling) / 100.0 * missedGreens * 0.5 * 18.0 / Double(holes)
            : 0
        let shortDetail = String(format: "%.0f%% scrambling (bench %.0f%%)", playerScrambling, benchScrambling)

        // -- Putting --
        let playerPuttsPerHole = stats.puttsPerHole
        let girCount = Double(stats.greensInRegulation)
        let playerPuttsPerGIR = girCount > 0 ? Double(stats.totalPutts) / girCount : playerPuttsPerHole
        let benchPuttsPerGIR = benchmark.puttsPerGIR
        // Scale to 18 holes: fewer putts per GIR = positive SG
        let puttingSG = (benchPuttsPerGIR - playerPuttsPerGIR) * girCount * 18.0 / Double(holes)
        let puttDetail = String(format: "%.2f putts/GIR (bench %.2f), %d 3-putts", playerPuttsPerGIR, benchPuttsPerGIR, stats.threeputts)

        return Result(
            offTheTee: SGCategoryResult(category: "Off the Tee", value: teeSG, detail: teeDetail),
            approach: SGCategoryResult(category: "Approach", value: approachSG, detail: approachDetail),
            aroundTheGreen: SGCategoryResult(category: "Around the Green", value: scramblingGain, detail: shortDetail),
            putting: SGCategoryResult(category: "Putting", value: puttingSG, detail: puttDetail)
        )
    }
}

// MARK: - "What Cost You" Items

struct CostItem: Identifiable {
    let id = UUID()
    let icon: String
    let text: String
    let strokes: Double
}

enum WhatCostYouCalculator {

    static func topCosts(stats: RoundStats, holesPlayed: Int) -> [CostItem] {
        var items: [CostItem] = []
        let holes = Double(max(holesPlayed, 1))

        // 3-putts
        if stats.threeputts > 0 {
            let cost = Double(stats.threeputts) * 0.7
            items.append(CostItem(icon: "circle.grid.3x3", text: "3-putts cost you", strokes: cost))
        }

        // Missed GIRs beyond scratch benchmark
        let missedGIR = stats.girHoles - stats.greensInRegulation
        if missedGIR > 0 {
            let excessMisses = Double(missedGIR) - Double(stats.girHoles) * (1.0 - 0.67)
            if excessMisses > 0 {
                let cost = excessMisses * SGBenchmark.missedGIRCost
                items.append(CostItem(icon: "scope", text: "Extra missed greens cost you", strokes: cost))
            }
        }

        // Poor scrambling
        let scramblingAttempts = stats.girHoles > 0 ? stats.girHoles - stats.greensInRegulation : 0
        let scramblingSuccesses = Int(stats.scramblingPct / 100.0 * Double(scramblingAttempts))
        let expectedScrambles = Int(0.6 * Double(scramblingAttempts)) // vs scratch
        if scramblingSuccesses < expectedScrambles {
            let cost = Double(expectedScrambles - scramblingSuccesses) * 0.5
            items.append(CostItem(icon: "arrow.up.right", text: "Failed up-and-downs cost you", strokes: cost))
        }

        // Missed fairways
        let missedFairways = stats.fairwayHoles - stats.fairwaysHit
        if missedFairways > 4 {
            let cost = Double(missedFairways) * 0.15
            items.append(CostItem(icon: "arrow.left.and.right", text: "Missed fairways cost you", strokes: cost))
        }

        // Double bogeys or worse
        let bigNumbers = stats.doubleBogeys + stats.triplePlus
        if bigNumbers > 0 {
            let cost = Double(stats.doubleBogeys) * 1.0 + Double(stats.triplePlus) * 2.0
            items.append(CostItem(icon: "exclamationmark.triangle", text: "Big numbers cost you", strokes: cost))
        }

        // Sort by strokes descending and return top 3
        return Array(items.sorted { $0.strokes > $1.strokes }.prefix(3))
    }
}

// MARK: - Strokes Gained Full View

struct StrokesGainedView: View {
    let rounds: [Round]
    @State private var selectedBenchmark: SGBenchmark = .scratch
    @State private var selectedRoundIndex: Int = 0

    private var availableRounds: [Round] {
        rounds.filter { $0.isComplete }
    }

    private var currentRound: Round? {
        guard selectedRoundIndex < availableRounds.count else { return nil }
        return availableRounds[selectedRoundIndex]
    }

    private var stats: RoundStats? {
        guard let round = currentRound else { return nil }
        return StatsCalculator.calculate(holes: round.holes)
    }

    private var sgResult: SGCalculator.Result? {
        guard let s = stats, let round = currentRound else { return nil }
        return SGCalculator.calculate(stats: s, holesPlayed: round.holes.filter { $0.strokes > 0 }.count, benchmark: selectedBenchmark)
    }

    var body: some View {
        if availableRounds.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("Play a round to see Strokes Gained analysis")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else {
            VStack(spacing: 16) {
                // Round selector
                if availableRounds.count > 1 {
                    Picker("Round", selection: $selectedRoundIndex) {
                        ForEach(Array(availableRounds.prefix(10).enumerated()), id: \.offset) { idx, round in
                            Text("\(round.courseName) - \(round.date.formatted(date: .abbreviated, time: .omitted))")
                                .tag(idx)
                        }
                    }
                    .pickerStyle(.menu)
                }

                // Benchmark selector
                Picker("Compare vs", selection: $selectedBenchmark) {
                    ForEach(SGBenchmark.allCases) { b in
                        Text(b.rawValue).tag(b)
                    }
                }
                .pickerStyle(.segmented)

                if let sg = sgResult {
                    // Total
                    HStack {
                        Text("Total Strokes Gained:")
                            .font(.subheadline)
                        Spacer()
                        Text(String(format: "%+.1f", sg.total))
                            .font(.title2.bold())
                            .foregroundStyle(sg.total >= 0 ? .green : .red)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // Category bars
                    ForEach(sg.categories) { cat in
                        SGBarRow(category: cat)
                    }

                    // Explanation
                    Text("Positive = better than \(selectedBenchmark.rawValue.lowercased()), Negative = worse")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)

                    // What Cost You
                    if let s = stats, let round = currentRound {
                        let costs = WhatCostYouCalculator.topCosts(
                            stats: s,
                            holesPlayed: round.holes.filter { $0.strokes > 0 }.count
                        )
                        if !costs.isEmpty {
                            WhatCostYouCard(costs: costs)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - SG Bar Row

private struct SGBarRow: View {
    let category: SGCategoryResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(category.category)
                    .font(.subheadline.bold())
                Spacer()
                Text(String(format: "%+.1f", category.value))
                    .font(.subheadline.bold())
                    .foregroundStyle(category.value >= 0 ? .green : .red)
            }

            // Visual bar
            GeometryReader { geo in
                let maxAbsolute: CGFloat = 5.0
                let normalized = min(max(CGFloat(category.value), -maxAbsolute), maxAbsolute)
                let midX = geo.size.width / 2.0
                let barWidth = abs(normalized) / maxAbsolute * midX

                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 20)

                    // Center line
                    Rectangle()
                        .fill(Color(.systemGray3))
                        .frame(width: 1, height: 20)
                        .offset(x: midX)

                    // Bar
                    if category.value >= 0 {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.green.opacity(0.7))
                            .frame(width: barWidth, height: 20)
                            .offset(x: midX)
                    } else {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.red.opacity(0.7))
                            .frame(width: barWidth, height: 20)
                            .offset(x: midX - barWidth)
                    }
                }
            }
            .frame(height: 20)

            Text(category.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(.systemGray6).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - What Cost You Card

struct WhatCostYouCard: View {
    let costs: [CostItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "exclamationmark.bubble")
                    .foregroundStyle(.orange)
                Text("What Cost You")
                    .font(.headline.bold())
            }

            ForEach(costs) { item in
                HStack(spacing: 10) {
                    Image(systemName: item.icon)
                        .font(.body)
                        .foregroundStyle(.red)
                        .frame(width: 28)

                    Text(item.text)
                        .font(.subheadline)

                    Spacer()

                    Text(String(format: "%.1f strokes", item.strokes))
                        .font(.subheadline.bold())
                        .foregroundStyle(.red)
                }
            }

            if costs.isEmpty {
                Text("Great round! Nothing major to flag.")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.systemGray6).opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

// MARK: - Compact What Cost You (for RoundSummaryView)

struct WhatCostYouCompactCard: View {
    let holes: [HoleScore]

    private var stats: RoundStats {
        StatsCalculator.calculate(holes: holes)
    }

    private var costs: [CostItem] {
        WhatCostYouCalculator.topCosts(
            stats: stats,
            holesPlayed: holes.filter { $0.strokes > 0 }.count
        )
    }

    var body: some View {
        if !costs.isEmpty {
            WhatCostYouCard(costs: costs)
        }
    }
}
