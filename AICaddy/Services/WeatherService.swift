import Foundation
import CoreLocation
import WeatherKit

/// Fetches wind and weather data for on-course adjustments
@Observable
final class WeatherService {
    var windSpeed: Double?        // mph
    var windDirection: Double?    // degrees, 0 = north
    var windDirectionLabel: String?
    var temperature: Int?         // Fahrenheit
    var conditions: String?
    var lastUpdated: Date?
    var error: String?

    /// Adjusted distance accounting for wind
    /// Headwind adds ~1% per mph, tailwind subtracts ~0.5% per mph
    func adjustedDistance(yards: Int, shotBearing: Double) -> Int {
        guard let windSpeed, let windDirection else { return yards }

        // Calculate wind component along shot direction
        let angleDiff = (windDirection - shotBearing) * .pi / 180
        let headwindComponent = cos(angleDiff) * windSpeed  // positive = headwind
        let crosswindComponent = abs(sin(angleDiff) * windSpeed)

        // Headwind: ~1 yard per mph, Tailwind: ~0.5 yard per mph
        var adjustment = 0.0
        if headwindComponent > 0 {
            adjustment = headwindComponent * 1.0  // headwind adds distance needed
        } else {
            adjustment = headwindComponent * 0.5  // tailwind reduces distance needed
        }

        // Crosswind has minor distance effect
        adjustment += crosswindComponent * 0.2

        return yards + Int(adjustment.rounded())
    }

    /// Wind direction as compass label
    static func compassDirection(_ degrees: Double) -> String {
        let directions = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                         "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let index = Int((degrees + 11.25).truncatingRemainder(dividingBy: 360) / 22.5)
        return directions[index % 16]
    }

    func fetchWeather(at location: CLLocationCoordinate2D) async {
        do {
            let weatherService = WeatherKit.WeatherService.shared
            let weather = try await weatherService.weather(for: CLLocation(latitude: location.latitude, longitude: location.longitude))

            await MainActor.run {
                let current = weather.currentWeather
                self.windSpeed = current.wind.speed.converted(to: .milesPerHour).value
                self.windDirection = current.wind.direction.converted(to: .degrees).value
                self.windDirectionLabel = Self.compassDirection(self.windDirection ?? 0)
                self.temperature = Int(current.temperature.converted(to: .fahrenheit).value)
                self.conditions = current.condition.description
                self.lastUpdated = Date()
                self.error = nil
            }
        } catch {
            await MainActor.run {
                self.error = "Weather unavailable"
                #if DEBUG
                // Seed mock wind so UI can be verified in simulator where WeatherKit often fails.
                if self.windSpeed == nil {
                    self.windSpeed = 12
                    self.windDirection = 315  // from NW
                    self.windDirectionLabel = Self.compassDirection(315)
                    self.temperature = 68
                    self.conditions = "Mock"
                    self.lastUpdated = Date()
                }
                #endif
            }
        }
    }

    /// Temperature-based distance adjustment
    /// Ball flies ~2 yards less per 10°F below 70°F, ~1 yard more per 10°F above
    func temperatureAdjustment(yards: Int) -> Int {
        guard let temp = temperature else { return yards }
        let diff = Double(temp - 70)
        if diff < 0 {
            return yards + Int((diff / 10.0 * 2.0).rounded())  // cold = shorter
        } else {
            return yards + Int((diff / 10.0 * 1.0).rounded())  // hot = longer
        }
    }
}
