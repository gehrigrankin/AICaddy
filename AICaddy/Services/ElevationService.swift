import Foundation
import CoreLocation

/// Calculates "plays like" distance using elevation change
/// Rule of thumb: 1 yard per foot of elevation change
@Observable
final class ElevationService {
    var currentElevation: Double?   // meters
    var greenElevation: Double?     // meters (if known)
    var elevationDelta: Double?     // meters

    /// Adjusted "plays like" distance accounting for elevation
    /// Uphill = plays longer, downhill = plays shorter
    /// ~1 yard adjustment per 3 feet of elevation change
    func playsLikeDistance(actualYards: Int) -> Int? {
        guard let delta = elevationDelta else { return nil }
        let deltaFeet = delta * 3.28084  // meters to feet
        let adjustment = deltaFeet / 3.0  // ~1 yard per 3 feet
        return actualYards + Int(adjustment.rounded())
    }

    /// Update elevation from GPS altitude
    func updateElevation(from location: CLLocation) {
        // CLLocation provides altitude, but it can be noisy
        // Only update if vertical accuracy is reasonable
        if location.verticalAccuracy >= 0 && location.verticalAccuracy < 30 {
            currentElevation = location.altitude
            if let greenElev = greenElevation {
                elevationDelta = greenElev - location.altitude  // positive = uphill to green
            }
        }
    }

    /// Fetch elevation data for a coordinate using Apple Maps
    func fetchElevation(for coordinate: CLLocationCoordinate2D) async -> Double? {
        // Use CLGeocoder for a rough elevation estimate
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        do {
            _ = try await geocoder.reverseGeocodeLocation(location)
            // CLPlacemark doesn't directly provide elevation
            // We rely on CLLocation's altitude from the GPS instead
            return location.altitude
        } catch {
            return nil
        }
    }

    /// Get elevation description
    var elevationDescription: String? {
        guard let delta = elevationDelta else { return nil }
        let feet = Int(abs(delta * 3.28084))
        if feet < 3 { return nil }  // negligible
        return delta > 0 ? "\(feet)ft uphill" : "\(feet)ft downhill"
    }
}
