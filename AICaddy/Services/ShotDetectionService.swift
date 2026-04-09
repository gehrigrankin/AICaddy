import Foundation
import CoreMotion
import CoreLocation

// MARK: - Detected Shot

struct DetectedShot {
    let timestamp: Date
    let location: CLLocationCoordinate2D?
    let suggestedClubs: [Club]  // top 3 guesses
    let distanceToGreen: Int?
}

// MARK: - Shot Detection Service

@Observable
final class ShotDetectionService {

    // MARK: - Public State

    var lastDetectedShot: DetectedShot?
    var isMonitoring: Bool = false

    // MARK: - Configuration

    /// Minimum total acceleration (in g) to count as a swing.
    private let swingThreshold: Double = 3.0

    /// Seconds to ignore new detections after a swing is recognised.
    private let cooldownInterval: TimeInterval = 5.0

    /// Accelerometer sampling interval in seconds.
    private let sampleInterval: TimeInterval = 1.0 / 50.0  // 50 Hz

    // MARK: - Private State

    private let motionManager = CMMotionManager()
    private var lastDetectionTime: Date = .distantPast

    /// External location provider – set by the caller so the service can
    /// stamp each detected shot with the current GPS position.
    var currentLocation: CLLocationCoordinate2D?

    /// Distance to green centre, updated externally by the round view.
    var currentDistanceToGreen: Int?

    // MARK: - Lifecycle

    func startMonitoring() {
        guard !isMonitoring else { return }
        guard motionManager.isAccelerometerAvailable else { return }

        motionManager.accelerometerUpdateInterval = sampleInterval

        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, error in
            guard let self, let data else { return }
            self.processAccelerometerData(data)
        }

        isMonitoring = true
    }

    func stopMonitoring() {
        motionManager.stopAccelerometerUpdates()
        isMonitoring = false
    }

    // MARK: - Swing Detection

    private func processAccelerometerData(_ data: CMAccelerometerData) {
        let acc = data.acceleration
        let totalG = sqrt(acc.x * acc.x + acc.y * acc.y + acc.z * acc.z)

        guard totalG > swingThreshold else { return }

        // Enforce cooldown to avoid double-detections.
        let now = Date()
        guard now.timeIntervalSince(lastDetectionTime) >= cooldownInterval else { return }
        lastDetectionTime = now

        let detected = DetectedShot(
            timestamp: now,
            location: currentLocation,
            suggestedClubs: guessClubs(
                distanceToGreen: currentDistanceToGreen,
                isTeeShot: false,
                bagClubs: []
            ),
            distanceToGreen: currentDistanceToGreen
        )

        lastDetectedShot = detected
    }

    // MARK: - Club Guessing

    /// Returns up to 3 likely clubs sorted best-match-first, based on
    /// distance to the green, whether this is a tee shot, and the user's bag.
    func guessClubs(distanceToGreen: Int?, isTeeShot: Bool, bagClubs: [BagClub]) -> [Club] {
        // Tee shot on a par-4 / par-5 – driver is most likely.
        if isTeeShot {
            if let dist = distanceToGreen, dist <= 170 {
                // Short par-3: probably an iron / hybrid
                return shortGameGuess(distance: dist, bagClubs: bagClubs)
            }
            return teeGuess(bagClubs: bagClubs)
        }

        guard let distance = distanceToGreen, distance > 0 else {
            // No distance info – return generic mid-irons.
            return [.iron7, .iron8, .iron9]
        }

        // If the user has bag yardages, find the 3 closest clubs.
        let clubsWithYardage = bagClubs.compactMap { bag -> (Club, Int)? in
            guard let y = bag.effectiveYardage else { return nil }
            return (bag.club, y)
        }

        if !clubsWithYardage.isEmpty {
            let sorted = clubsWithYardage
                .sorted { abs($0.1 - distance) < abs($1.1 - distance) }
                .prefix(3)
                .map(\.0)
            return Array(sorted)
        }

        // Fallback: use generic distance brackets.
        return defaultClubsForDistance(distance)
    }

    // MARK: - Helpers

    private func teeGuess(bagClubs: [BagClub]) -> [Club] {
        let preferred: [Club] = [.driver, .wood3, .hybrid3]
        let inBag = bagClubs.map(\.club)
        if !inBag.isEmpty {
            let filtered = preferred.filter { inBag.contains($0) }
            if !filtered.isEmpty { return Array(filtered.prefix(3)) }
        }
        return preferred
    }

    private func shortGameGuess(distance: Int, bagClubs: [BagClub]) -> [Club] {
        let clubsWithYardage = bagClubs.compactMap { bag -> (Club, Int)? in
            guard let y = bag.effectiveYardage else { return nil }
            return (bag.club, y)
        }

        if !clubsWithYardage.isEmpty {
            let sorted = clubsWithYardage
                .sorted { abs($0.1 - distance) < abs($1.1 - distance) }
                .prefix(3)
                .map(\.0)
            return Array(sorted)
        }

        return defaultClubsForDistance(distance)
    }

    private func defaultClubsForDistance(_ distance: Int) -> [Club] {
        switch distance {
        case 0...30:
            return [.putter, .sw, .lw]
        case 31...60:
            return [.lw, .sw, .gw]
        case 61...90:
            return [.sw, .gw, .pw]
        case 91...120:
            return [.gw, .pw, .iron9]
        case 121...140:
            return [.pw, .iron9, .iron8]
        case 141...160:
            return [.iron9, .iron8, .iron7]
        case 161...180:
            return [.iron7, .iron6, .iron5]
        case 181...200:
            return [.iron5, .hybrid4, .iron6]
        case 201...220:
            return [.hybrid4, .hybrid3, .wood5]
        case 221...250:
            return [.wood3, .wood5, .hybrid3]
        default:
            return [.driver, .wood3, .wood5]
        }
    }
}
