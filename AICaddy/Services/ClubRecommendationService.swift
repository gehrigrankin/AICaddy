import Foundation
import SwiftData
import CoreLocation

/// The actual "AI Caddy" — recommends clubs based on your history and current distance.
@Observable
final class ClubRecommendationService {
    private var clubHistory: [Club: [Int]] = [:]  // club -> distances hit

    /// Load historical club distances from completed rounds
    func loadHistory(rounds: [Round]) {
        clubHistory = [:]
        for round in rounds where round.isComplete {
            for hole in round.holes {
                for shot in hole.shots where !shot.isPutt && !shot.isPenalty {
                    if let club = shot.club, let dist = shot.distanceYards, dist > 0 {
                        clubHistory[club, default: []].append(dist)
                    }
                }
            }
        }
    }

    /// Get club recommendation for a given distance.
    /// When `bagClubs` is provided, manual yardages are preferred over shot history.
    /// When `adjustedDistance` is provided, club selection uses it instead of raw distance.
    func recommend(distanceYards: Int, bagClubs: [BagClub] = [], adjustedDistance: Int? = nil, adjustmentNote: String? = nil) -> ClubRecommendation? {
        let selectionDistance = adjustedDistance ?? distanceYards
        // Build candidates from bag yardages first, then fall back to shot history
        var candidates: [(club: Club, avg: Int, count: Int, diff: Int)] = []

        // Clubs already covered by bag yardages (manual or learned)
        var coveredClubs: Set<Club> = []

        for bagClub in bagClubs {
            if let yardage = bagClub.effectiveYardage {
                let count = bagClub.manualYardage != nil ? 0 : (bagClub.learnedShotCount ?? 0)
                let diff = abs(yardage - selectionDistance)
                candidates.append((bagClub.club, yardage, count, diff))
                coveredClubs.insert(bagClub.club)
            }
        }

        // Fill in from shot history for clubs not covered by bag yardages
        for (club, distances) in clubHistory where !coveredClubs.contains(club) {
            guard distances.count >= 2 else { continue }
            let avg = distances.reduce(0, +) / distances.count
            let diff = abs(avg - selectionDistance)
            candidates.append((club, avg, distances.count, diff))
        }

        guard !candidates.isEmpty else { return nil }

        // Sort by closest to target distance
        candidates.sort { $0.diff < $1.diff }

        let best = candidates[0]
        let alternate = candidates.count > 1 ? candidates[1] : nil

        // Determine recommendation reasoning
        let reasoning: String
        let diffFromTarget = best.avg - selectionDistance

        if abs(diffFromTarget) <= 5 {
            reasoning = "Your \(best.club.displayName) averages \(best.avg)y — right on the number."
        } else if diffFromTarget > 0 {
            reasoning = "Your \(best.club.displayName) averages \(best.avg)y. A smooth swing should be perfect for \(selectionDistance)y."
        } else {
            reasoning = "Your \(best.club.displayName) averages \(best.avg)y. Give it a little extra for \(selectionDistance)y."
        }

        return ClubRecommendation(
            primaryClub: best.club,
            primaryAvg: best.avg,
            primaryCount: best.count,
            alternateClub: alternate?.club,
            alternateAvg: alternate?.avg,
            alternateCount: alternate?.count,
            targetDistance: distanceYards,
            reasoning: reasoning,
            adjustedDistance: adjustedDistance,
            adjustmentNote: adjustmentNote
        )
    }

    /// Get your average distances for all clubs (for the bag/stats screen)
    var clubAverages: [(club: Club, avg: Int, count: Int)] {
        clubHistory
            .filter { $0.value.count >= 1 }
            .map { (club: $0.key, avg: $0.value.reduce(0, +) / $0.value.count, count: $0.value.count) }
            .sorted { $0.avg > $1.avg }
    }

    /// Check if we have enough data to make recommendations
    var hasData: Bool { !clubHistory.isEmpty }
}

struct ClubRecommendation {
    let primaryClub: Club
    let primaryAvg: Int
    let primaryCount: Int
    let alternateClub: Club?
    let alternateAvg: Int?
    let alternateCount: Int?
    let targetDistance: Int
    let reasoning: String
    let adjustedDistance: Int?
    let adjustmentNote: String?

    init(primaryClub: Club, primaryAvg: Int, primaryCount: Int,
         alternateClub: Club? = nil, alternateAvg: Int? = nil, alternateCount: Int? = nil,
         targetDistance: Int, reasoning: String,
         adjustedDistance: Int? = nil, adjustmentNote: String? = nil) {
        self.primaryClub = primaryClub
        self.primaryAvg = primaryAvg
        self.primaryCount = primaryCount
        self.alternateClub = alternateClub
        self.alternateAvg = alternateAvg
        self.alternateCount = alternateCount
        self.targetDistance = targetDistance
        self.reasoning = reasoning
        self.adjustedDistance = adjustedDistance
        self.adjustmentNote = adjustmentNote
    }
}
