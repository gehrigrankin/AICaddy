import Foundation

// MARK: - Course History Service

struct CourseHistoryService {

    // MARK: - Types

    enum TipType: String {
        case noteFromPast
        case missTendency
        case scoringPattern
        case strategy
    }

    struct HoleTip: Identifiable {
        let id = UUID()
        let message: String
        let type: TipType
    }

    // MARK: - Public API

    /// Returns up to 3 tips for a specific hole based on past rounds at the same course.
    func getTips(courseId: String, holeNumber: Int, rounds: [Round]) -> [HoleTip] {
        let pastRounds = rounds.filter { $0.courseId == courseId && $0.isComplete }

        guard !pastRounds.isEmpty else { return [] }

        let holeScores: [HoleScore] = pastRounds.compactMap { round in
            round.holes.first { $0.holeNumber == holeNumber }
        }

        guard !holeScores.isEmpty else { return [] }

        var tips: [HoleTip] = []

        // 1. Past notes (highest priority)
        if let noteTip = buildNoteTip(from: holeScores) {
            tips.append(noteTip)
        }

        // 2. Tee shot miss tendency
        if let missTip = buildMissTendencyTip(from: holeScores) {
            tips.append(missTip)
        }

        // 3. Scoring pattern
        if let scoreTip = buildScoringPatternTip(from: holeScores) {
            tips.append(scoreTip)
        }

        // 4. Best strategy (club off the tee)
        if let strategyTip = buildStrategyTip(from: holeScores) {
            tips.append(strategyTip)
        }

        return Array(tips.prefix(3))
    }

    // MARK: - Tip Builders

    private func buildNoteTip(from holeScores: [HoleScore]) -> HoleTip? {
        // Find the most recent hole that has a note
        for score in holeScores.reversed() {
            if let note = score.notes, !note.isEmpty {
                return HoleTip(message: "Last time: \(note)", type: .noteFromPast)
            }
        }
        return nil
    }

    private func buildMissTendencyTip(from holeScores: [HoleScore]) -> HoleTip? {
        // Look at tee shots (shot number 1) and find the most common non-fairway result
        let teeShots = holeScores.compactMap { score in
            score.shots.first { $0.shotNumber == 1 && !$0.isPutt }
        }

        guard teeShots.count >= 2 else { return nil }

        let missResults: [ShotResult] = [.rough, .deepRough, .bunker, .water, .ob, .trees]
        var resultCounts: [ShotResult: Int] = [:]

        for shot in teeShots {
            if let result = shot.result, missResults.contains(result) {
                resultCounts[result, default: 0] += 1
            }
        }

        guard let (topResult, count) = resultCounts.max(by: { $0.value < $1.value }) else {
            return nil
        }

        let total = teeShots.count
        let ratio = Double(count) / Double(total)

        guard ratio > 0.5 else { return nil }

        let direction = directionLabel(for: topResult)
        return HoleTip(
            message: "You've hit it \(direction) off the tee \(count)/\(total) times here",
            type: .missTendency
        )
    }

    private func buildScoringPatternTip(from holeScores: [HoleScore]) -> HoleTip? {
        let playedScores = holeScores.filter { $0.strokes > 0 }
        guard !playedScores.isEmpty else { return nil }

        let total = playedScores.reduce(0) { $0 + $1.strokes }
        let average = Double(total) / Double(playedScores.count)
        let par = playedScores[0].par

        let formatted = String(format: "%.1f", average)
        let label = scoringLabel(average: average, par: par)

        return HoleTip(
            message: "You average \(formatted) on this hole (\(label))",
            type: .scoringPattern
        )
    }

    private func buildStrategyTip(from holeScores: [HoleScore]) -> HoleTip? {
        // Group scores by tee club and see if a particular club yields better results
        var clubScores: [Club: [Int]] = [:]

        for score in holeScores where score.strokes > 0 {
            if let teeShot = score.shots.first(where: { $0.shotNumber == 1 }),
               let club = teeShot.club {
                clubScores[club, default: []].append(score.strokes)
            }
        }

        // Need at least two different clubs to compare
        guard clubScores.count >= 2 else { return nil }

        let clubAverages = clubScores.compactMap { club, strokes -> (Club, Double, Int)? in
            guard !strokes.isEmpty else { return nil }
            let avg = Double(strokes.reduce(0, +)) / Double(strokes.count)
            return (club, avg, strokes.count)
        }

        guard let best = clubAverages.min(by: { $0.1 < $1.1 }),
              let worst = clubAverages.max(by: { $0.1 < $1.1 }),
              best.1 < worst.1 - 0.3,
              best.2 >= 2 else {
            return nil
        }

        let avgFormatted = String(format: "%.1f", best.1)
        return HoleTip(
            message: "You score better with \(best.0.displayName) off the tee (avg \(avgFormatted))",
            type: .strategy
        )
    }

    // MARK: - Helpers

    private func directionLabel(for result: ShotResult) -> String {
        switch result {
        case .rough: return "into the rough"
        case .deepRough: return "into the deep rough"
        case .bunker: return "into a bunker"
        case .water: return "into the water"
        case .ob: return "out of bounds"
        case .trees: return "into the trees"
        default: return result.displayName.lowercased()
        }
    }

    private func scoringLabel(average: Double, par: Int) -> String {
        let diff = average - Double(par)
        switch diff {
        case ..<(-0.5): return "below par"
        case -0.5..<0.5: return "par"
        case 0.5..<1.5: return "bogey"
        case 1.5..<2.5: return "double bogey"
        default: return "bogey+"
        }
    }
}
