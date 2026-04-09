import Foundation

/// USGA Handicap Index calculator
/// Uses the World Handicap System (WHS) formula
enum HandicapCalculator {

    /// Calculate handicap index from rounds with course rating and slope
    /// Returns nil if not enough rounds (need at least 3)
    static func calculateIndex(rounds: [HandicapRound]) -> Double? {
        guard rounds.count >= 3 else { return nil }

        // Calculate score differential for each round
        // Differential = (113 / Slope) * (Adjusted Score - Course Rating)
        let differentials = rounds.compactMap { round -> Double? in
            guard let slope = round.slope, let rating = round.rating, slope > 0 else { return nil }
            return (113.0 / Double(slope)) * (Double(round.adjustedScore) - rating)
        }

        guard differentials.count >= 3 else { return nil }

        // Sort differentials lowest to highest
        let sorted = differentials.sorted()

        // Number of differentials to use based on count
        let useCount: Int
        switch sorted.count {
        case 3...5: useCount = 1
        case 6: useCount = 2
        case 7...8: useCount = 2
        case 9...11: useCount = 3
        case 12...14: useCount = 4
        case 15...16: useCount = 5
        case 17...18: useCount = 6
        case 19: useCount = 7
        default: useCount = 8  // 20+
        }

        // Average the best differentials
        let best = Array(sorted.prefix(useCount))
        let avg = best.reduce(0, +) / Double(best.count)

        // Apply 0.96 multiplier (WHS adjustment)
        let index = avg * 0.96

        // Round to 1 decimal, cap at 54.0
        return min(54.0, (index * 10).rounded() / 10)
    }

    /// Calculate course handicap from index
    /// Course Handicap = Handicap Index × (Slope Rating / 113) + (Course Rating - Par)
    static func courseHandicap(index: Double, slope: Int, rating: Double, par: Int) -> Int {
        let ch = index * (Double(slope) / 113.0) + (rating - Double(par))
        return Int(ch.rounded())
    }

    /// Net double bogey cap: max score for handicap purposes on any hole
    /// = Par + 2 + (strokes received on that hole)
    static func maxScore(par: Int, handicapStrokes: Int) -> Int {
        return par + 2 + handicapStrokes
    }
}

struct HandicapRound {
    let date: Date
    let adjustedScore: Int  // score with net double bogey cap applied
    let slope: Int?
    let rating: Double?
    let courseName: String
}

/// Build handicap rounds from stored Round data
extension HandicapRound {
    static func fromRound(_ round: Round) -> HandicapRound? {
        guard round.isComplete else { return nil }

        let stats = StatsCalculator.calculate(holes: round.holes)
        guard stats.totalStrokes > 0 else { return nil }

        // Get slope/rating from stored course tee data
        let slope = round.courseTee?.slope
        let rating = round.courseTee?.rating

        // Apply net double bogey adjustment
        // Without full handicap strokes allocation, use a simplified max of par + 3 per hole
        let adjusted = round.holes.reduce(0) { total, hole in
            guard hole.strokes > 0 else { return total }
            let maxScore = hole.par + 3  // simplified cap
            return total + min(hole.strokes, maxScore)
        }

        return HandicapRound(
            date: round.date,
            adjustedScore: adjusted,
            slope: slope,
            rating: rating,
            courseName: round.courseName
        )
    }
}
