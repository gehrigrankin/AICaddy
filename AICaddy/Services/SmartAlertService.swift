import Foundation

// MARK: - Smart Alert Model

struct SmartAlert {
    let message: String
    let type: AlertType
    let icon: String  // SF Symbol name

    enum AlertType {
        case weather, momentum, pace, fatigue, milestone
    }
}

// MARK: - Smart Alert Service

struct SmartAlertService {

    // MARK: - Momentum Detection

    /// Analyzes the last 3 completed holes for scoring streaks.
    static func checkMomentum(holes: [HoleScore], currentHole: Int) -> SmartAlert? {
        let completed = holes.filter { $0.strokes > 0 && $0.holeNumber < currentHole }
        let last3 = completed.suffix(3)
        guard last3.count == 3 else { return nil }

        let scoresToPar = last3.compactMap { $0.scoreToPar }
        guard scoresToPar.count == 3 else { return nil }

        let birdieCount = scoresToPar.filter { $0 <= -1 }.count
        let bogeyCount = scoresToPar.filter { $0 >= 1 }.count

        if birdieCount >= 2 {
            return SmartAlert(
                message: "You're on fire! \u{1F525} Stay aggressive.",
                type: .momentum,
                icon: "flame.fill"
            )
        }

        if bogeyCount >= 3 {
            return SmartAlert(
                message: "Rough patch. Take a breath, aim for the fat of the green.",
                type: .momentum,
                icon: "wind"
            )
        }

        // Check for recovery: last 2 are pars after earlier bogeys
        let last3Array = Array(last3)
        let recentTwo = last3Array.suffix(2).compactMap { $0.scoreToPar }
        let earlierHoles = completed.dropLast(2).suffix(3)
        let hadBogeys = earlierHoles.contains { ($0.scoreToPar ?? 0) >= 1 }

        if recentTwo.count == 2 && recentTwo.allSatisfy({ $0 == 0 }) && hadBogeys {
            return SmartAlert(
                message: "Nice recovery. Keep the momentum.",
                type: .momentum,
                icon: "arrow.up.heart.fill"
            )
        }

        return nil
    }

    // MARK: - Pace of Play

    /// Checks whether the player is falling behind a reasonable pace.
    static func checkPace(roundStartTime: Date, currentHole: Int) -> SmartAlert? {
        guard currentHole > 1 else { return nil }

        let elapsed = Date().timeIntervalSince(roundStartTime)
        let completedHoles = currentHole - 1
        let avgMinutesPerHole = (elapsed / 60.0) / Double(completedHoles)

        if avgMinutesPerHole > 16 {
            let rounded = String(format: "%.0f", avgMinutesPerHole)
            return SmartAlert(
                message: "You're at \(rounded) min/hole — a bit behind pace. Consider ready golf.",
                type: .pace,
                icon: "clock.badge.exclamationmark"
            )
        }

        return nil
    }

    // MARK: - Fatigue Analysis

    /// Compares front 9 and back 9 scoring once the player reaches hole 14+.
    static func checkFatigue(holes: [HoleScore]) -> SmartAlert? {
        let completed = holes.filter { $0.strokes > 0 }

        let front9 = completed.filter { $0.holeNumber <= 9 }
        let back9 = completed.filter { $0.holeNumber >= 10 }

        guard front9.count == 9, back9.count >= 5 else { return nil }

        let front9Avg = Double(front9.map { $0.strokes - $0.par }.reduce(0, +)) / Double(front9.count)
        let back9Avg = Double(back9.map { $0.strokes - $0.par }.reduce(0, +)) / Double(back9.count)

        let difference = back9Avg - front9Avg
        if difference > 0.5 {
            let formatted = String(format: "%.1f", difference)
            return SmartAlert(
                message: "Your back 9 is trending +\(formatted) vs front. Stay hydrated and focused.",
                type: .fatigue,
                icon: "drop.fill"
            )
        }

        return nil
    }

    // MARK: - Milestone Alerts

    /// Checks whether the player is on pace for a personal best front 9 or full round.
    static func checkMilestone(holes: [HoleScore], allRounds: [Round], courseName: String) -> SmartAlert? {
        let completed = holes.filter { $0.strokes > 0 }
        guard !completed.isEmpty else { return nil }

        let completedRounds = allRounds.filter { $0.isComplete }

        // Check front 9 personal best
        let front9Completed = completed.filter { $0.holeNumber <= 9 }
        if front9Completed.count == 9 {
            let currentFront9 = front9Completed.map { $0.strokes }.reduce(0, +)

            let previousFront9Scores: [Int] = completedRounds.compactMap { round in
                let roundHoles = round.holes.filter { $0.holeNumber <= 9 && $0.strokes > 0 }
                guard roundHoles.count == 9 else { return nil }
                return roundHoles.map { $0.strokes }.reduce(0, +)
            }

            if let bestFront9 = previousFront9Scores.min(), currentFront9 < bestFront9 {
                return SmartAlert(
                    message: "This is your best front 9 ever! Keep it up.",
                    type: .milestone,
                    icon: "star.fill"
                )
            }
        }

        // Check if on pace for personal best round
        guard completed.count >= 9 else { return nil }

        let currentTotal = completed.map { $0.strokes }.reduce(0, +)
        let projectedTotal = Double(currentTotal) / Double(completed.count) * 18.0

        let previousTotals: [Int] = completedRounds.compactMap { round in
            let roundHoles = round.holes.filter { $0.strokes > 0 }
            guard roundHoles.count == 18 else { return nil }
            return roundHoles.map { $0.strokes }.reduce(0, +)
        }

        if let bestTotal = previousTotals.min(), Int(projectedTotal) < bestTotal {
            return SmartAlert(
                message: "You're on pace for a personal best at \(courseName)! Stay in the zone.",
                type: .milestone,
                icon: "trophy.fill"
            )
        }

        return nil
    }

    // MARK: - Weather Alert

    /// Returns a weather-related alert based on condition changes.
    static func checkWeather(windSpeedMph: Double?, rainChance: Double?, temperatureF: Double?) -> SmartAlert? {
        if let wind = windSpeedMph, wind >= 20 {
            let rounded = String(format: "%.0f", wind)
            return SmartAlert(
                message: "Wind is picking up to \(rounded) mph. Club up and keep it low.",
                type: .weather,
                icon: "wind"
            )
        }

        if let rain = rainChance, rain >= 0.6 {
            let pct = String(format: "%.0f", rain * 100)
            return SmartAlert(
                message: "\(pct)% rain chance — keep your towels handy and glove dry.",
                type: .weather,
                icon: "cloud.rain.fill"
            )
        }

        if let temp = temperatureF, temp >= 95 {
            return SmartAlert(
                message: "It's \(String(format: "%.0f", temp))°F out there. Drink water every few holes.",
                type: .weather,
                icon: "thermometer.sun.fill"
            )
        }

        return nil
    }
}
