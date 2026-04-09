import Foundation
import CoreLocation

// MARK: - Models

enum AlertSeverity: String, Codable {
    case low, medium, high
}

struct DangerZoneAlert: Identifiable {
    let id = UUID()
    let message: String
    let severity: AlertSeverity
}

struct MissTendency: Identifiable {
    let id = UUID()
    let club: Club
    let tendency: String   // e.g. "right", "left", "short", "long"
    let count: Int         // how many misses went this direction
    let total: Int         // total misses analysed

    var description: String {
        "You miss \(club.displayName) \(tendency) \(count)/\(total) times"
    }
}

// MARK: - Service

@Observable
final class CourseStrategyService {

    // MARK: - Suggested Target (AI Caddy layup)

    /// Calculate the ideal landing spot for the tee shot when the green is out of range.
    /// Factors in: player's club distances, hazard locations, hole geometry.
    ///
    /// Returns a coordinate along the tee-to-green line at the recommended distance,
    /// or nil if the green is reachable (no layup needed).
    func suggestedTarget(
        userLocation: CLLocationCoordinate2D,
        holeGps: HoleGps,
        par: Int,
        clubAverages: [(club: Club, avg: Int, count: Int)],
        bagClubs: [BagClub]
    ) -> (coordinate: CLLocationCoordinate2D, club: Club, distance: Int, reason: String)? {
        guard let greenCenter = holeGps.greenCenter else { return nil }

        let distToGreen = LocationService.distanceYards(from: userLocation, to: greenCenter.coordinate)

        // Find the longest club the player can hit (driver or longest in bag)
        // Default to 230y driver if no data available
        let longest = findLongestClub(clubAverages: clubAverages, bagClubs: bagClubs)
            ?? (club: Club.driver, avg: 230)

        // If green is reachable with longest club, no target needed
        if distToGreen <= longest.avg + 15 { return nil }

        // Par 3s should always be reachable — don't suggest layups
        if par <= 3 { return nil }

        // Find ideal layup distance: leave a comfortable approach shot
        // Prefer leaving 100-150y to the green (wedge/short iron range)
        let idealApproach = findIdealApproachDistance(clubAverages: clubAverages, bagClubs: bagClubs)
        var targetDistFromUser = distToGreen - idealApproach

        // Find the club that matches this target distance
        var selectedClub = findBestClub(for: targetDistFromUser, clubAverages: clubAverages, bagClubs: bagClubs)

        // Check for hazards near the landing zone
        if let tee = holeGps.tee, let hazards = holeGps.hazards, !hazards.isEmpty {
            let teeCoord = tee.coordinate
            let adjusted = avoidHazards(
                targetDistFromTee: LocationService.distanceYards(from: teeCoord, to: greenCenter.coordinate) - idealApproach,
                targetDistFromUser: targetDistFromUser,
                userLocation: userLocation,
                greenCenter: greenCenter.coordinate,
                tee: teeCoord,
                hazards: hazards,
                clubAverages: clubAverages,
                bagClubs: bagClubs
            )
            targetDistFromUser = adjusted.distance
            selectedClub = adjusted.club
        }

        // Calculate the coordinate along the user-to-green line at targetDistFromUser
        let targetCoord = interpolateCoordinate(
            from: userLocation,
            to: greenCenter.coordinate,
            distanceYards: targetDistFromUser,
            totalDistanceYards: distToGreen
        )

        let reason: String
        let remainingToGreen = distToGreen - targetDistFromUser
        if let hazardWarning = nearbyHazardWarning(
            targetDistFromTee: targetDistFromUser,
            userLocation: userLocation,
            tee: holeGps.tee?.coordinate,
            hazards: holeGps.hazards ?? []
        ) {
            reason = "\(selectedClub.club.displayName) to \(targetDistFromUser)y, leaves \(remainingToGreen)y in. \(hazardWarning)"
        } else {
            reason = "\(selectedClub.club.displayName) to \(targetDistFromUser)y, leaves \(remainingToGreen)y approach"
        }

        return (targetCoord, selectedClub.club, targetDistFromUser, reason)
    }

    // MARK: - Target Calculation Helpers

    private func findLongestClub(clubAverages: [(club: Club, avg: Int, count: Int)], bagClubs: [BagClub]) -> (club: Club, avg: Int)? {
        let bagMax = bagClubs.compactMap { bc -> (club: Club, avg: Int)? in
            guard let y = bc.effectiveYardage else { return nil }
            return (club: bc.club, avg: y)
        }.max(by: { $0.avg < $1.avg })

        let historyMax = clubAverages.max(by: { $0.avg < $1.avg }).map { (club: $0.club, avg: $0.avg) }

        if let b = bagMax, let h = historyMax {
            return b.avg >= h.avg ? b : h
        }
        return bagMax ?? historyMax
    }

    private func findIdealApproachDistance(clubAverages: [(club: Club, avg: Int, count: Int)], bagClubs: [BagClub]) -> Int {
        // Find a comfortable wedge/short iron distance (prefer 100-150 range)
        let wedgeClubs: [Club] = [.pw, .gw, .sw, .iron9]
        for wedge in wedgeClubs {
            if let bc = bagClubs.first(where: { $0.club == wedge }), let y = bc.effectiveYardage {
                return y
            }
            if let avg = clubAverages.first(where: { $0.club == wedge }) {
                return avg.avg
            }
        }
        return 120 // default comfortable approach distance
    }

    private func findBestClub(for distance: Int, clubAverages: [(club: Club, avg: Int, count: Int)], bagClubs: [BagClub]) -> (club: Club, avg: Int) {
        var candidates: [(club: Club, avg: Int, diff: Int)] = []

        for bc in bagClubs {
            if let y = bc.effectiveYardage {
                candidates.append((bc.club, y, abs(y - distance)))
            }
        }
        for ca in clubAverages where !candidates.contains(where: { $0.club == ca.club }) {
            candidates.append((ca.club, ca.avg, abs(ca.avg - distance)))
        }

        if let best = candidates.min(by: { $0.diff < $1.diff }) {
            return (best.club, best.avg)
        }
        return (.driver, distance)
    }

    private func avoidHazards(
        targetDistFromTee: Int,
        targetDistFromUser: Int,
        userLocation: CLLocationCoordinate2D,
        greenCenter: CLLocationCoordinate2D,
        tee: CLLocationCoordinate2D,
        hazards: [HoleHazard],
        clubAverages: [(club: Club, avg: Int, count: Int)],
        bagClubs: [BagClub]
    ) -> (distance: Int, club: (club: Club, avg: Int)) {
        let teeLocation = CLLocation(latitude: tee.latitude, longitude: tee.longitude)

        // Check if any hazard is within ±25y of our target landing zone
        for hazard in hazards {
            let hazardLoc = CLLocation(latitude: hazard.position.lat, longitude: hazard.position.lng)
            let hazardDistFromTee = Int(teeLocation.distance(from: hazardLoc) * 1.09361)

            if abs(hazardDistFromTee - targetDistFromTee) < 25 {
                // Hazard in the way — lay up shorter (30y before the hazard)
                let saferDist = targetDistFromUser - (25 + (targetDistFromTee - hazardDistFromTee + 25))
                let saferDistClamped = max(saferDist, targetDistFromUser - 50) // don't lay up more than 50y shorter
                let club = findBestClub(for: max(100, saferDistClamped), clubAverages: clubAverages, bagClubs: bagClubs)
                return (club.avg, club)
            }
        }

        let club = findBestClub(for: targetDistFromUser, clubAverages: clubAverages, bagClubs: bagClubs)
        return (targetDistFromUser, club)
    }

    private func nearbyHazardWarning(targetDistFromTee: Int, userLocation: CLLocationCoordinate2D, tee: CLLocationCoordinate2D?, hazards: [HoleHazard]) -> String? {
        guard let tee else { return nil }
        let teeLocation = CLLocation(latitude: tee.latitude, longitude: tee.longitude)

        for hazard in hazards {
            let hazardLoc = CLLocation(latitude: hazard.position.lat, longitude: hazard.position.lng)
            let hazardDist = Int(teeLocation.distance(from: hazardLoc) * 1.09361)
            if hazardDist > targetDistFromTee && hazardDist < targetDistFromTee + 40 {
                return "Avoids \(hazard.type) at \(hazardDist)y"
            }
        }
        return nil
    }

    private func interpolateCoordinate(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, distanceYards: Int, totalDistanceYards: Int) -> CLLocationCoordinate2D {
        guard totalDistanceYards > 0 else { return from }
        let fraction = min(1.0, Double(distanceYards) / Double(totalDistanceYards))
        let lat = from.latitude + (to.latitude - from.latitude) * fraction
        let lng = from.longitude + (to.longitude - from.longitude) * fraction
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    // MARK: - Danger Zone Detection

    /// Check whether the player's typical distance with the likely tee-shot club
    /// would land near a hazard on the current hole.
    ///
    /// - Parameters:
    ///   - distanceToGreen: Yardage from tee to green centre.
    ///   - holeGps: GPS data for the hole, including hazard locations.
    ///   - clubAvgDistance: The player's average driver (or tee-club) distance.
    ///                      Pass the value from `ClubRecommendationService.clubAverages`.
    /// - Returns: A `DangerZoneAlert` if a hazard is within ±20 y of the player's
    ///            expected landing zone; `nil` otherwise.
    func checkDangerZones(
        distanceToGreen: Int,
        holeGps: HoleGps?,
        clubAvgDistance: Int?
    ) -> DangerZoneAlert? {
        guard let holeGps,
              let hazards = holeGps.hazards, !hazards.isEmpty,
              let tee = holeGps.tee,
              let greenCenter = holeGps.greenCenter,
              let avgDist = clubAvgDistance else {
            return nil
        }

        let teeLocation = CLLocation(latitude: tee.lat, longitude: tee.lng)
        let greenLocation = CLLocation(latitude: greenCenter.lat, longitude: greenCenter.lng)
        let totalYards = teeLocation.distance(from: greenLocation) * 1.09361 // metres -> yards

        guard totalYards > 0 else { return nil }

        for hazard in hazards {
            let hazardLocation = CLLocation(
                latitude: hazard.position.lat,
                longitude: hazard.position.lng
            )
            let hazardYards = Int(teeLocation.distance(from: hazardLocation) * 1.09361)

            // Is the hazard within ±20 yards of where the player's shot would land?
            let margin = 20
            guard abs(hazardYards - avgDist) <= margin else { continue }

            let label = hazard.label ?? hazard.type.capitalized
            let severity: AlertSeverity = hazard.type == "water" ? .high : .medium

            let clubName = "driver" // context: tee-shot check
            let message = "\(label) at \(hazardYards)y — your \(clubName) avg is \(avgDist)y. Consider a shorter club."

            return DangerZoneAlert(message: message, severity: severity)
        }

        return nil
    }

    // MARK: - Miss Tendency

    /// Analyse recent rounds for a specific club and return the dominant miss
    /// direction if one side accounts for > 60 % of misses.
    ///
    /// "Left" misses are inferred from results of `.rough`, `.trees`, `.bunker`, `.deepRough`
    /// whose shot notes contain "left"; similarly for "right". When notes are empty
    /// the result type itself is counted as a generic miss and the function falls
    /// back to short/long detection using distance vs the player's average.
    func getMissTendency(for club: Club, from rounds: [Round]) -> MissTendency? {
        // Collect all non-putt, non-penalty shots for the requested club
        var shots: [Shot] = []
        for round in rounds where round.isComplete {
            for hole in round.holes {
                for shot in hole.shots where shot.club == club && !shot.isPutt && !shot.isPenalty {
                    shots.append(shot)
                }
            }
        }

        // Only consider misses (not fairway, green, fringe, holed)
        let goodResults: Set<ShotResult> = [.fairway, .green, .fringe, .holed]
        let misses = shots.filter { shot in
            guard let result = shot.result else { return false }
            return !goodResults.contains(result)
        }

        guard misses.count >= 3 else { return nil }

        // Count directional tendencies
        var leftCount = 0
        var rightCount = 0
        var shortCount = 0
        var longCount = 0

        // Compute average distance for this club to detect short/long
        let distances = shots.compactMap(\.distanceYards).filter { $0 > 0 }
        let avgDistance: Int? = distances.isEmpty ? nil : distances.reduce(0, +) / distances.count

        for shot in misses {
            let notesLower = (shot.notes ?? "").lowercased()

            // Check notes for explicit direction hints
            if notesLower.contains("left") {
                leftCount += 1
            } else if notesLower.contains("right") {
                rightCount += 1
            }

            // Short / long detection based on distance vs average
            if let dist = shot.distanceYards, let avg = avgDistance {
                if dist < avg - 10 {
                    shortCount += 1
                } else if dist > avg + 10 {
                    longCount += 1
                }
            }
        }

        let total = misses.count
        let threshold = Double(total) * 0.6

        // Pick the dominant tendency
        let tendencies: [(String, Int)] = [
            ("left", leftCount),
            ("right", rightCount),
            ("short", shortCount),
            ("long", longCount),
        ]

        guard let dominant = tendencies.max(by: { $0.1 < $1.1 }),
              Double(dominant.1) >= threshold,
              dominant.1 > 0 else {
            return nil
        }

        return MissTendency(
            club: club,
            tendency: dominant.0,
            count: dominant.1,
            total: total
        )
    }
}
