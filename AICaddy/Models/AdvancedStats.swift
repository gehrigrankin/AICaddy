import Foundation

// MARK: - Strokes Gained Analysis

/// Strokes Gained benchmarks (approximate PGA/amateur averages)
/// Based on Mark Broadie's research — expected strokes from various distances/lies
enum StrokesGainedBenchmarks {
    /// Expected strokes to hole out from tee on each par
    static let teeExpected: [Int: Double] = [3: 3.0, 4: 4.0, 5: 5.0]

    /// Expected strokes from fairway at given yardage (scratch golfer)
    static func fromFairway(yards: Int) -> Double {
        switch yards {
        case 0..<30: return 2.2
        case 30..<60: return 2.6
        case 60..<100: return 2.8
        case 100..<125: return 2.9
        case 125..<150: return 3.0
        case 150..<175: return 3.1
        case 175..<200: return 3.2
        case 200..<225: return 3.4
        case 225..<250: return 3.6
        default: return 3.8
        }
    }

    /// Expected strokes from rough
    static func fromRough(yards: Int) -> Double {
        fromFairway(yards: yards) + 0.3
    }

    /// Expected strokes from bunker
    static func fromBunker(yards: Int) -> Double {
        if yards < 30 { return 2.5 }  // greenside bunker
        return fromFairway(yards: yards) + 0.5
    }

    /// Expected strokes on the green
    static func fromGreen(feet: Int) -> Double {
        switch feet {
        case 0..<3: return 1.04
        case 3..<5: return 1.14
        case 5..<8: return 1.33
        case 8..<12: return 1.50
        case 12..<20: return 1.70
        case 20..<30: return 1.87
        case 30..<40: return 1.98
        default: return 2.1
        }
    }

    /// Bogey golfer expected strokes (for comparison)
    static func bogeyFromFairway(yards: Int) -> Double {
        fromFairway(yards: yards) + 0.8
    }
}

struct StrokesGainedResult {
    var offTheTee: Double
    var approach: Double
    var aroundTheGreen: Double
    var putting: Double
    var total: Double

    static var zero: StrokesGainedResult {
        StrokesGainedResult(offTheTee: 0, approach: 0, aroundTheGreen: 0, putting: 0, total: 0)
    }
}

// MARK: - Shot Dispersion

struct ShotDispersion {
    let club: Club
    let leftCount: Int
    let rightCount: Int
    let straightCount: Int
    let shortCount: Int
    let longCount: Int
    let totalShots: Int

    var leftPct: Double { totalShots > 0 ? Double(leftCount) / Double(totalShots) * 100 : 0 }
    var rightPct: Double { totalShots > 0 ? Double(rightCount) / Double(totalShots) * 100 : 0 }
    var straightPct: Double { totalShots > 0 ? Double(straightCount) / Double(totalShots) * 100 : 0 }

    var missTendency: String {
        if leftPct > 50 { return "Tends left" }
        if rightPct > 50 { return "Tends right" }
        if leftPct > rightPct + 15 { return "Slight left miss" }
        if rightPct > leftPct + 15 { return "Slight right miss" }
        return "Balanced"
    }
}

// MARK: - Putting Splits

struct PuttingSplits {
    let inside5ft: PuttingRange
    let ft5to15: PuttingRange
    let ft15to30: PuttingRange
    let outside30ft: PuttingRange

    struct PuttingRange {
        let label: String
        let attempts: Int
        let makes: Int
        var makePct: Double { attempts > 0 ? Double(makes) / Double(attempts) * 100 : 0 }
        var avgPutts: Double // average putts from this distance
    }
}

// MARK: - Proximity to Hole

struct ProximityStats {
    let avgProximityFeet: Double   // average distance of approach shots from the pin
    let byClub: [Club: Double]    // avg proximity per club
    let byDistance: [(range: String, avgFeet: Double, count: Int)]  // by yardage bucket
}

// MARK: - Streaks & Patterns

struct StreakAnalysis {
    let hotStreaks: [Streak]
    let coldStreaks: [Streak]
    let currentStreak: Streak?

    struct Streak {
        let startHole: Int
        let endHole: Int
        let scoreToPar: Int
        let holes: Int

        var description: String {
            let score = scoreToPar >= 0 ? "+\(scoreToPar)" : "\(scoreToPar)"
            return "Holes \(startHole)-\(endHole): \(score) (\(holes) holes)"
        }
    }
}

// MARK: - Hole History

struct HoleHistory {
    let holeNumber: Int
    let courseName: String
    let rounds: [(date: Date, strokes: Int, par: Int)]
    var avgScore: Double { rounds.isEmpty ? 0 : Double(rounds.reduce(0) { $0 + $1.strokes }) / Double(rounds.count) }
    var bestScore: Int { rounds.map(\.strokes).min() ?? 0 }
    var worstScore: Int { rounds.map(\.strokes).max() ?? 0 }
    var timesPlayed: Int { rounds.count }
}

// MARK: - Season/Period Stats

struct PeriodStats {
    let label: String  // "This Month", "This Season", "All Time"
    let roundCount: Int
    let avgScore: Double
    let avgPutts: Double
    let avgGIR: Double
    let avgFIR: Double
    let avgDriving: Int
    let bestScore: Int
    let handicapTrend: [Double]  // handicap over time
    let scoreTrend: [Int]        // scores over time
}

// MARK: - Advanced Stats Calculator

enum AdvancedStatsCalculator {

    // MARK: - Strokes Gained

    static func strokesGained(holes: [HoleScore]) -> StrokesGainedResult {
        var sg = StrokesGainedResult.zero

        for hole in holes where hole.strokes > 0 {
            let expected = Double(hole.par)
            let actual = Double(hole.strokes)

            // Simplified strokes gained by category
            let shots = hole.shots
            let teeShot = shots.first { $0.shotNumber == 1 }
            let putts = shots.filter(\.isPutt)
            let approachShots = shots.filter { !$0.isPutt && $0.shotNumber > 1 && $0.shotNumber <= hole.par - 2 }
            let shortGameShots = shots.filter { !$0.isPutt && $0.shotNumber > hole.par - 2 && !$0.isPutt }

            // Off the tee (par 4/5 only)
            if hole.par >= 4, let ts = teeShot {
                let expectedAfterTee: Double
                if ts.result == .fairway {
                    expectedAfterTee = StrokesGainedBenchmarks.fromFairway(yards: estimateRemaining(hole: hole, afterShot: 1))
                } else {
                    expectedAfterTee = StrokesGainedBenchmarks.fromRough(yards: estimateRemaining(hole: hole, afterShot: 1))
                }
                sg.offTheTee += (expected - 1.0 - expectedAfterTee) - 0  // vs expected tee shot
            }

            // Putting
            let expectedPutts = hole.putts.map(Double.init) ?? Double(putts.count)
            let benchmarkPutts = 1.8  // average putts per hole for scratch
            sg.putting += benchmarkPutts - expectedPutts

            // Approach (simplified: remaining strokes gained split between approach and short game)
            let nonPuttNonTee = actual - (teeShot != nil && hole.par >= 4 ? 1 : 0) - expectedPutts
            let expectedNonPuttNonTee = expected - (hole.par >= 4 ? 1 : 0) - benchmarkPutts
            let approachSG = expectedNonPuttNonTee - nonPuttNonTee

            if hole.greenInRegulation == true {
                sg.approach += approachSG
            } else {
                sg.approach += approachSG * 0.6
                sg.aroundTheGreen += approachSG * 0.4
            }
        }

        sg.total = sg.offTheTee + sg.approach + sg.aroundTheGreen + sg.putting
        return sg
    }

    private static func estimateRemaining(hole: HoleScore, afterShot: Int) -> Int {
        // Estimate remaining distance based on hole yardage and shot distance
        guard let totalYardage = hole.yardage else { return 150 }
        let shotDist = hole.shots.first { $0.shotNumber == afterShot }?.distanceYards ?? (totalYardage / hole.par)
        return max(0, totalYardage - shotDist)
    }

    // MARK: - Shot Dispersion

    static func shotDispersion(rounds: [Round]) -> [Club: ShotDispersion] {
        var clubShots: [Club: (left: Int, right: Int, straight: Int, short: Int, long: Int, total: Int)] = [:]

        for round in rounds {
            for hole in round.holes {
                for shot in hole.shots where !shot.isPutt {
                    guard let club = shot.club, let result = shot.result else { continue }
                    var entry = clubShots[club] ?? (0, 0, 0, 0, 0, 0)
                    entry.total += 1

                    switch result {
                    case .fairway, .green, .holed:
                        entry.straight += 1
                    case .rough, .trees, .deepRough:
                        // Use notes or default to split
                        entry.right += 1  // simplified — would need L/R data
                    case .bunker:
                        entry.short += 1
                    default:
                        entry.straight += 1
                    }

                    clubShots[club] = entry
                }
            }
        }

        return clubShots.mapValues { data in
            ShotDispersion(
                club: .driver, // overwritten by key
                leftCount: data.left,
                rightCount: data.right,
                straightCount: data.straight,
                shortCount: data.short,
                longCount: data.long,
                totalShots: data.total
            )
        }
    }

    // MARK: - Streak Detection

    static func detectStreaks(holes: [HoleScore]) -> StreakAnalysis {
        var hotStreaks: [StreakAnalysis.Streak] = []
        var coldStreaks: [StreakAnalysis.Streak] = []

        let played = holes.filter { $0.strokes > 0 }
        guard played.count >= 3 else {
            return StreakAnalysis(hotStreaks: [], coldStreaks: [], currentStreak: nil)
        }

        var streakStart = 0
        var streakScore = 0

        for i in 0..<played.count {
            let diff = played[i].strokes - played[i].par
            streakScore += diff

            let length = i - streakStart + 1
            if length >= 3 {
                let streak = StreakAnalysis.Streak(
                    startHole: played[streakStart].holeNumber,
                    endHole: played[i].holeNumber,
                    scoreToPar: streakScore,
                    holes: length
                )

                if streakScore <= -2 { hotStreaks.append(streak) }
                if streakScore >= 4 { coldStreaks.append(streak) }
            }

            // Reset streak on a big swing
            if diff >= 2 && streakScore < 0 { streakStart = i; streakScore = diff }
            if diff <= -1 && streakScore > 2 { streakStart = i; streakScore = diff }
        }

        // Current streak (last 3+ holes)
        let last3 = played.suffix(3)
        let last3Score = last3.reduce(0) { $0 + $1.strokes - $1.par }
        let current = StreakAnalysis.Streak(
            startHole: last3.first?.holeNumber ?? 0,
            endHole: last3.last?.holeNumber ?? 0,
            scoreToPar: last3Score,
            holes: last3.count
        )

        return StreakAnalysis(
            hotStreaks: hotStreaks.sorted { $0.scoreToPar < $1.scoreToPar },
            coldStreaks: coldStreaks.sorted { $0.scoreToPar > $1.scoreToPar },
            currentStreak: current
        )
    }

    // MARK: - Hole History

    static func holeHistory(holeNumber: Int, courseId: String, rounds: [Round]) -> HoleHistory {
        let courseRounds = rounds.filter { $0.courseId == courseId && $0.isComplete }
        let entries = courseRounds.compactMap { round -> (Date, Int, Int)? in
            guard let hole = round.holes.first(where: { $0.holeNumber == holeNumber }),
                  hole.strokes > 0 else { return nil }
            return (round.date, hole.strokes, hole.par)
        }

        return HoleHistory(
            holeNumber: holeNumber,
            courseName: courseRounds.first?.courseName ?? "",
            rounds: entries
        )
    }

    // MARK: - Period Stats

    static func periodStats(rounds: [Round], label: String) -> PeriodStats {
        let completed = rounds.filter(\.isComplete)
        guard !completed.isEmpty else {
            return PeriodStats(label: label, roundCount: 0, avgScore: 0, avgPutts: 0,
                             avgGIR: 0, avgFIR: 0, avgDriving: 0, bestScore: 0,
                             handicapTrend: [], scoreTrend: [])
        }

        let allStats = completed.map { StatsCalculator.calculate(holes: $0.holes) }
        let scores = allStats.map(\.totalStrokes)

        return PeriodStats(
            label: label,
            roundCount: completed.count,
            avgScore: Double(scores.reduce(0, +)) / Double(scores.count),
            avgPutts: Double(allStats.reduce(0) { $0 + $1.totalPutts }) / Double(allStats.count),
            avgGIR: allStats.reduce(0.0) { $0 + $1.greensInRegulationPct } / Double(allStats.count),
            avgFIR: allStats.reduce(0.0) { $0 + $1.fairwaysPct } / Double(allStats.count),
            avgDriving: {
                let withDrives = allStats.filter { $0.driveCount > 0 }
                return withDrives.isEmpty ? 0 : withDrives.reduce(0) { $0 + $1.avgDrivingDistance } / withDrives.count
            }(),
            bestScore: scores.min() ?? 0,
            handicapTrend: buildHandicapTrend(rounds: completed),
            scoreTrend: scores
        )
    }

    private static func buildHandicapTrend(rounds: [Round]) -> [Double] {
        var trend: [Double] = []
        let sorted = rounds.sorted { $0.date < $1.date }

        for i in 2..<sorted.count {
            let subset = Array(sorted.prefix(i + 1))
            let hcRounds = subset.compactMap { HandicapRound.fromRound($0) }
            if let idx = HandicapCalculator.calculateIndex(rounds: hcRounds) {
                trend.append(idx)
            }
        }

        return trend
    }

    // MARK: - Best/Worst by Par

    static func parTypeAnalysis(rounds: [Round]) -> (par3: ParTypeStats, par4: ParTypeStats, par5: ParTypeStats) {
        var par3Scores: [Int] = [], par4Scores: [Int] = [], par5Scores: [Int] = []

        for round in rounds where round.isComplete {
            for hole in round.holes where hole.strokes > 0 {
                switch hole.par {
                case 3: par3Scores.append(hole.strokes - hole.par)
                case 4: par4Scores.append(hole.strokes - hole.par)
                case 5: par5Scores.append(hole.strokes - hole.par)
                default: break
                }
            }
        }

        return (
            ParTypeStats(par: 3, scores: par3Scores),
            ParTypeStats(par: 4, scores: par4Scores),
            ParTypeStats(par: 5, scores: par5Scores)
        )
    }
}

struct ParTypeStats {
    let par: Int
    let scores: [Int]  // score relative to par

    var count: Int { scores.count }
    var avgToPar: Double { scores.isEmpty ? 0 : Double(scores.reduce(0, +)) / Double(scores.count) }
    var totalToPar: Int { scores.reduce(0, +) }
    var birdieOrBetter: Int { scores.filter { $0 <= -1 }.count }
    var pars: Int { scores.filter { $0 == 0 }.count }
    var bogeys: Int { scores.filter { $0 == 1 }.count }
    var doublePlus: Int { scores.filter { $0 >= 2 }.count }
    var birdieRate: Double { count > 0 ? Double(birdieOrBetter) / Double(count) * 100 : 0 }
}
