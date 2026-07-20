import Foundation
import CoreLocation

/// Geodesic helpers for building synthetic course layouts and GPS tracks.
enum GeoMath {
    static let earthRadiusMeters = 6_371_000.0
    static let metersPerYard = 0.9144

    /// Destination point given start, initial bearing (degrees) and distance (meters).
    static func offset(_ start: CLLocationCoordinate2D, bearingDegrees: Double, distanceMeters: Double) -> CLLocationCoordinate2D {
        let d = distanceMeters / earthRadiusMeters
        let brg = bearingDegrees * .pi / 180
        let lat1 = start.latitude * .pi / 180
        let lon1 = start.longitude * .pi / 180

        let lat2 = asin(sin(lat1) * cos(d) + cos(lat1) * sin(d) * cos(brg))
        let lon2 = lon1 + atan2(sin(brg) * sin(d) * cos(lat1), cos(d) - sin(lat1) * sin(lat2))

        return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
    }

    static func offsetYards(_ start: CLLocationCoordinate2D, bearingDegrees: Double, yards: Double) -> CLLocationCoordinate2D {
        offset(start, bearingDegrees: bearingDegrees, distanceMeters: yards * metersPerYard)
    }

    /// Initial bearing (degrees, 0 = north) from one point to another.
    static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180

        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let deg = atan2(y, x) * 180 / .pi
        return (deg + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Precise distance in yards (Double) via CLLocation, for ground-truth checks.
    static func preciseYards(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let l1 = CLLocation(latitude: a.latitude, longitude: a.longitude)
        let l2 = CLLocation(latitude: b.latitude, longitude: b.longitude)
        return l1.distance(from: l2) / metersPerYard
    }
}

/// Deterministic seeded RNG (SplitMix64) so every simulation run is reproducible.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1)
    mutating func double() -> Double {
        Double(next() >> 11) * (1.0 / 9007199254740992.0)
    }

    /// Gaussian via Box–Muller
    mutating func gaussian(mean: Double, sd: Double) -> Double {
        var u1 = double()
        if u1 < 1e-12 { u1 = 1e-12 }
        let u2 = double()
        let z = sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
        return mean + z * sd
    }

    mutating func int(in range: ClosedRange<Int>) -> Int {
        range.lowerBound + Int(next() % UInt64(range.count))
    }

    mutating func chance(_ probability: Double) -> Bool {
        double() < probability
    }
}
