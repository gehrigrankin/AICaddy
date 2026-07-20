import Foundation
import CoreLocation

/// Detects when the player walks to the next tee box and auto-advances the hole
@Observable
final class AutoAdvanceService {
    var isEnabled = true
    var suggestedAdvance: Int?  // hole number to advance to, nil if no suggestion

    /// Suggest an advance when within this many yards of the next tee box.
    static let teeProximityYards = 30
    /// Minimum time between suggestions after one is confirmed/dismissed.
    static let cooldownSeconds: TimeInterval = 120

    private var lastAdvanceTime: Date?

    /// Check if the user has moved to the next tee box.
    /// Call this whenever location updates.
    /// - Parameters:
    ///   - lastHole: the final hole of this round (9-hole courses exist —
    ///     never hardcode 18).
    ///   - hasScoredCurrentHole: only suggest once the current hole has a score,
    ///     so adjacent tee boxes can't trigger a premature advance.
    func checkForAdvance(
        currentHole: Int,
        userLocation: CLLocationCoordinate2D,
        nextTeebox: GpsPoint?,
        lastHole: Int = 18,
        hasScoredCurrentHole: Bool = true,
        now: Date = Date()
    ) {
        guard isEnabled, let nextTee = nextTeebox, hasScoredCurrentHole, currentHole < lastHole else {
            suggestedAdvance = nil
            return
        }

        // Don't re-suggest right after the user confirmed or dismissed one
        if let last = lastAdvanceTime, now.timeIntervalSince(last) < Self.cooldownSeconds {
            return
        }

        let distToNextTee = LocationService.distanceYards(from: userLocation, to: nextTee.coordinate)

        if distToNextTee < Self.teeProximityYards {
            suggestedAdvance = currentHole + 1
        } else {
            suggestedAdvance = nil
        }
    }

    func confirmAdvance(now: Date = Date()) {
        lastAdvanceTime = now
        suggestedAdvance = nil
    }

    func dismissAdvance(now: Date = Date()) {
        lastAdvanceTime = now
        suggestedAdvance = nil
    }
}
