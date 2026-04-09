import Foundation
import CoreLocation

/// Detects when the player walks to the next tee box and auto-advances the hole
@Observable
final class AutoAdvanceService {
    var isEnabled = true
    var suggestedAdvance: Int?  // hole number to advance to, nil if no suggestion

    private var lastAdvanceTime: Date?

    /// Check if the user has moved to the next tee box
    /// Call this whenever location updates
    func checkForAdvance(
        currentHole: Int,
        userLocation: CLLocationCoordinate2D,
        nextTeebox: GpsPoint?
    ) {
        guard isEnabled, let nextTee = nextTeebox else {
            suggestedAdvance = nil
            return
        }

        // Don't suggest advance more than once per 2 minutes
        if let last = lastAdvanceTime, Date().timeIntervalSince(last) < 120 {
            return
        }

        let distToNextTee = LocationService.distanceYards(from: userLocation, to: nextTee.coordinate)

        // If within 30 yards of the next tee box, suggest advance
        if distToNextTee < 30 && currentHole < 18 {
            suggestedAdvance = currentHole + 1
        } else {
            suggestedAdvance = nil
        }
    }

    func confirmAdvance() {
        lastAdvanceTime = Date()
        suggestedAdvance = nil
    }

    func dismissAdvance() {
        lastAdvanceTime = Date()
        suggestedAdvance = nil
    }
}
