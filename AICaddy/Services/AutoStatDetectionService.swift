import Foundation
import CoreLocation

/// Automatically detects fairway hits, greens in regulation, and on-green status
/// using GPS position data. All methods are static since no state is required.
struct AutoStatDetectionService {

    // MARK: - Fairway Hit Detection

    /// Determines whether the player hit the fairway after their tee shot.
    /// Only applicable to par 4+ holes. Returns nil when GPS data is insufficient.
    ///
    /// The fairway corridor is modelled as a rectangle ~40 yards wide centred on
    /// the tee-to-green line.
    static func detectFairwayHit(
        userLocation: CLLocationCoordinate2D,
        holeGps: HoleGps,
        par: Int
    ) -> Bool? {
        // Fairway hit only applies to par 4 and above
        guard par >= 4 else { return nil }

        guard let tee = holeGps.tee, let greenCenter = holeGps.greenCenter else {
            return nil
        }

        let teeCoord = tee.coordinate
        let greenCoord = greenCenter.coordinate

        // Build a vector from tee to green (in approximate yard units)
        let dx = longitudeDeltaYards(from: teeCoord, to: greenCoord)
        let dy = latitudeDeltaYards(from: teeCoord, to: greenCoord)
        let holeLength = sqrt(dx * dx + dy * dy)

        guard holeLength > 0 else { return nil }

        // Unit vector along the tee-to-green line
        let ux = dx / holeLength
        let uy = dy / holeLength

        // Vector from tee to user
        let px = longitudeDeltaYards(from: teeCoord, to: userLocation)
        let py = latitudeDeltaYards(from: teeCoord, to: userLocation)

        // Project user position onto the tee-to-green line
        let along = px * ux + py * uy          // distance along the line
        let perpendicular = abs(px * (-uy) + py * ux)  // distance off the line

        let corridorHalfWidth: Double = 20.0   // 40 yards total width

        // User must be between tee and green, and within the corridor
        let isAlongHole = along > 0 && along < holeLength
        let isInCorridor = perpendicular <= corridorHalfWidth

        return isAlongHole && isInCorridor
    }

    // MARK: - Green in Regulation Detection

    /// Determines whether the player reached the green in regulation.
    /// GIR requires the player to be on or very near the green (within ~20 yards
    /// of center) in at most `par - 2` strokes. Returns nil when GPS data is
    /// insufficient.
    static func detectGreenInRegulation(
        userLocation: CLLocationCoordinate2D,
        holeGps: HoleGps,
        strokesUsed: Int,
        par: Int
    ) -> Bool? {
        guard let greenCenter = holeGps.greenCenter else { return nil }

        let distanceToGreen = LocationService.distanceYards(
            from: userLocation,
            to: greenCenter.coordinate
        )

        let nearGreen = distanceToGreen <= 20
        let inRegulation = strokesUsed <= par - 2

        return nearGreen && inRegulation
    }

    // MARK: - On-Green Detection

    /// Simple check: is the user within ~15 yards of the green center?
    static func detectOnGreen(
        userLocation: CLLocationCoordinate2D,
        holeGps: HoleGps
    ) -> Bool {
        guard let greenCenter = holeGps.greenCenter else { return false }

        let distance = LocationService.distanceYards(
            from: userLocation,
            to: greenCenter.coordinate
        )

        return distance <= 15
    }

    // MARK: - Private Helpers

    /// Approximate east-west distance in yards between two coordinates.
    private static func longitudeDeltaYards(
        from a: CLLocationCoordinate2D,
        to b: CLLocationCoordinate2D
    ) -> Double {
        let midLat = (a.latitude + b.latitude) / 2.0 * .pi / 180.0
        let metersPerDegreeLng = 111_320.0 * cos(midLat)
        let deltaLng = b.longitude - a.longitude
        return deltaLng * metersPerDegreeLng / 0.9144
    }

    /// Approximate north-south distance in yards between two coordinates.
    private static func latitudeDeltaYards(
        from a: CLLocationCoordinate2D,
        to b: CLLocationCoordinate2D
    ) -> Double {
        let metersPerDegreeLat = 110_540.0
        let deltaLat = b.latitude - a.latitude
        return deltaLat * metersPerDegreeLat / 0.9144
    }
}
