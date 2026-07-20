import Testing
import Foundation
import CoreLocation
@testable import AICaddy

@Suite("Location service")
struct LocationServiceTests {

    private let phoenix = CLLocationCoordinate2D(latitude: 33.4484, longitude: -112.0740)

    // MARK: - Distance math

    @Test func zeroDistance() {
        #expect(LocationService.distanceYards(from: phoenix, to: phoenix) == 0)
    }

    @Test func knownDistances() {
        for yards in [30.0, 100.0, 150.0, 250.0, 550.0] {
            for bearing in [0.0, 45.0, 90.0, 180.0, 270.0] {
                let dest = GeoMath.offsetYards(phoenix, bearingDegrees: bearing, yards: yards)
                let measured = LocationService.distanceYards(from: phoenix, to: dest)
                #expect(abs(Double(measured) - yards) <= 1.5,
                        "\(yards)y at \(bearing)°: measured \(measured)")
            }
        }
    }

    @Test func symmetric() {
        let dest = GeoMath.offsetYards(phoenix, bearingDegrees: 73, yards: 187)
        let ab = LocationService.distanceYards(from: phoenix, to: dest)
        let ba = LocationService.distanceYards(from: dest, to: phoenix)
        #expect(ab == ba)
    }

    @Test func matchesCoreLocationWithinHalfPercent() {
        let dest = CLLocationCoordinate2D(latitude: 33.5000, longitude: -112.0000)
        let haversine = Double(LocationService.distanceYards(from: phoenix, to: dest))
        let reference = GeoMath.preciseYards(from: phoenix, to: dest)
        #expect(abs(haversine - reference) / reference < 0.005)
    }

    // MARK: - Fix filtering (the wrong-yardage-on-hole-1 bug)

    private func fix(accuracy: Double, ageSeconds: TimeInterval = 0, at coord: CLLocationCoordinate2D? = nil, now: Date) -> CLLocation {
        CLLocation(
            coordinate: coord ?? phoenix, altitude: 350,
            horizontalAccuracy: accuracy, verticalAccuracy: 10,
            timestamp: now.addingTimeInterval(-ageSeconds)
        )
    }

    @Test func acceptsGoodFix() {
        let service = LocationService()
        let now = Date()
        #expect(service.ingest(fix(accuracy: 5, now: now), now: now))
        #expect(service.location != nil)
        #expect(service.accuracy == 5)
        #expect(service.fixCount == 1)
    }

    @Test("Regression: the ~1km cell-tower first fix must be rejected")
    func rejectsCoarseFix() {
        let service = LocationService()
        let now = Date()
        #expect(!service.ingest(fix(accuracy: 1000, now: now), now: now))
        #expect(!service.ingest(fix(accuracy: 51, now: now), now: now))
        #expect(service.location == nil)
        #expect(service.fixCount == 0)
    }

    @Test func rejectsInvalidFix() {
        let service = LocationService()
        let now = Date()
        #expect(!service.ingest(fix(accuracy: -1, now: now), now: now))
        #expect(service.location == nil)
    }

    @Test func rejectsStaleFix() {
        let service = LocationService()
        let now = Date()
        #expect(!service.ingest(fix(accuracy: 5, ageSeconds: 60, now: now), now: now))
        #expect(service.location == nil)
        // Fresh enough is fine
        #expect(service.ingest(fix(accuracy: 5, ageSeconds: 5, now: now), now: now))
    }

    @Test func badFixDoesNotClobberGoodPosition() {
        let service = LocationService()
        let now = Date()
        #expect(service.ingest(fix(accuracy: 5, now: now), now: now))
        let good = service.location

        let far = GeoMath.offsetYards(phoenix, bearingDegrees: 10, yards: 900)
        #expect(!service.ingest(fix(accuracy: 300, at: far, now: now), now: now))
        #expect(service.location?.latitude == good?.latitude)
        #expect(service.location?.longitude == good?.longitude)
    }
}

@Suite("Auto-advance")
struct AutoAdvanceTests {

    private let tee = GpsPoint(lat: 33.4484, lng: -112.0740)
    private var nearTee: CLLocationCoordinate2D {
        GeoMath.offsetYards(tee.coordinate, bearingDegrees: 90, yards: 10)
    }
    private var farFromTee: CLLocationCoordinate2D {
        GeoMath.offsetYards(tee.coordinate, bearingDegrees: 90, yards: 100)
    }

    @Test func suggestsAtNextTee() {
        let service = AutoAdvanceService()
        service.checkForAdvance(currentHole: 3, userLocation: nearTee, nextTeebox: tee,
                                lastHole: 18, hasScoredCurrentHole: true, now: Date())
        #expect(service.suggestedAdvance == 4)
    }

    @Test func noSuggestionFarAway() {
        let service = AutoAdvanceService()
        service.checkForAdvance(currentHole: 3, userLocation: farFromTee, nextTeebox: tee,
                                lastHole: 18, hasScoredCurrentHole: true, now: Date())
        #expect(service.suggestedAdvance == nil)
    }

    @Test("Regression: no premature advance before the hole is scored")
    func gatedOnScore() {
        let service = AutoAdvanceService()
        service.checkForAdvance(currentHole: 3, userLocation: nearTee, nextTeebox: tee,
                                lastHole: 18, hasScoredCurrentHole: false, now: Date())
        #expect(service.suggestedAdvance == nil)
    }

    @Test func respectsLastHole() {
        let service = AutoAdvanceService()
        // On the final hole there is no "next" — 9-hole course
        service.checkForAdvance(currentHole: 9, userLocation: nearTee, nextTeebox: tee,
                                lastHole: 9, hasScoredCurrentHole: true, now: Date())
        #expect(service.suggestedAdvance == nil)
        // But hole 9 of an 18-hole round advances fine
        service.checkForAdvance(currentHole: 9, userLocation: nearTee, nextTeebox: tee,
                                lastHole: 18, hasScoredCurrentHole: true, now: Date())
        #expect(service.suggestedAdvance == 10)
    }

    @Test func disabledMeansSilent() {
        let service = AutoAdvanceService()
        service.isEnabled = false
        service.checkForAdvance(currentHole: 3, userLocation: nearTee, nextTeebox: tee,
                                lastHole: 18, hasScoredCurrentHole: true, now: Date())
        #expect(service.suggestedAdvance == nil)
    }

    @Test func noTeeboxMeansSilent() {
        let service = AutoAdvanceService()
        service.checkForAdvance(currentHole: 3, userLocation: nearTee, nextTeebox: nil,
                                lastHole: 18, hasScoredCurrentHole: true, now: Date())
        #expect(service.suggestedAdvance == nil)
    }

    @Test func cooldownAfterConfirm() {
        let service = AutoAdvanceService()
        let t0 = Date()
        service.checkForAdvance(currentHole: 3, userLocation: nearTee, nextTeebox: tee,
                                lastHole: 18, hasScoredCurrentHole: true, now: t0)
        #expect(service.suggestedAdvance == 4)
        service.confirmAdvance(now: t0)
        #expect(service.suggestedAdvance == nil)

        // Still inside cooldown → no new suggestion
        service.checkForAdvance(currentHole: 4, userLocation: nearTee, nextTeebox: tee,
                                lastHole: 18, hasScoredCurrentHole: true, now: t0.addingTimeInterval(60))
        #expect(service.suggestedAdvance == nil)

        // After cooldown → suggests again
        service.checkForAdvance(currentHole: 4, userLocation: nearTee, nextTeebox: tee,
                                lastHole: 18, hasScoredCurrentHole: true, now: t0.addingTimeInterval(121))
        #expect(service.suggestedAdvance == 5)
    }

    @Test func dismissAlsoStartsCooldown() {
        let service = AutoAdvanceService()
        let t0 = Date()
        service.checkForAdvance(currentHole: 3, userLocation: nearTee, nextTeebox: tee,
                                lastHole: 18, hasScoredCurrentHole: true, now: t0)
        service.dismissAdvance(now: t0)
        service.checkForAdvance(currentHole: 3, userLocation: nearTee, nextTeebox: tee,
                                lastHole: 18, hasScoredCurrentHole: true, now: t0.addingTimeInterval(30))
        #expect(service.suggestedAdvance == nil)
    }
}
