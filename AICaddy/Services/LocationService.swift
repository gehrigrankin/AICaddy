import Foundation
import CoreLocation

@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    var location: CLLocationCoordinate2D?
    var accuracy: Double?
    var heading: Double?
    var error: String?
    var isTracking = false

    // MARK: - Geofencing (nearby course detection)
    var nearbyCourseName: String?
    var nearbyCourseId: String?
    private var monitoredRegionIds: Set<String> = []

    /// Set this to override GPS with a simulated position (debug/testing)
    var simulatedLocation: CLLocationCoordinate2D? {
        didSet {
            if let sim = simulatedLocation {
                location = sim
                accuracy = 5.0
            }
        }
    }

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
        manager.distanceFilter = 2  // update every 2 meters
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func startTracking() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
        isTracking = true
    }

    func stopTracking() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        isTracking = false
    }

    // MARK: - Geofence Monitoring

    /// Sets up geofences around saved courses so the app can prompt the user
    /// when they arrive at a course.  iOS caps monitored regions at 20.
    func startMonitoringCourses(_ courses: [CourseGeofenceInfo]) {
        // Remove any previously monitored course regions
        for region in manager.monitoredRegions {
            if monitoredRegionIds.contains(region.identifier) {
                manager.stopMonitoring(for: region)
            }
        }
        monitoredRegionIds.removeAll()

        courseGeofenceNames.removeAll()
        let geofenceRadius: CLLocationDistance = 200 // meters
        let maxRegions = 20 // iOS limit

        for course in courses.prefix(maxRegions) {
            courseGeofenceNames[course.id] = course.name
            let region = CLCircularRegion(
                center: course.coordinate,
                radius: geofenceRadius,
                identifier: course.id
            )
            region.notifyOnEntry = true
            region.notifyOnExit = true
            manager.startMonitoring(for: region)
            monitoredRegionIds.insert(course.id)
        }
    }

    func stopMonitoringCourses() {
        for region in manager.monitoredRegions {
            if monitoredRegionIds.contains(region.identifier) {
                manager.stopMonitoring(for: region)
            }
        }
        monitoredRegionIds.removeAll()
        nearbyCourseName = nil
        nearbyCourseId = nil
    }

    func dismissNearbyCourse() {
        nearbyCourseName = nil
        nearbyCourseId = nil
    }

    // Lightweight struct so callers don't need to pass SwiftData models directly
    struct CourseGeofenceInfo {
        let id: String
        let name: String
        let coordinate: CLLocationCoordinate2D
    }

    // MARK: - Distance calculation

    /// Haversine distance in yards between two coordinates
    static func distanceYards(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Int {
        let R = 6_371_000.0 / 0.9144  // Earth radius in yards

        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLng = (b.longitude - a.longitude) * .pi / 180

        let sinLat = sin(dLat / 2)
        let sinLng = sin(dLng / 2)

        let h = sinLat * sinLat +
            cos(a.latitude * .pi / 180) * cos(b.latitude * .pi / 180) * sinLng * sinLng

        return Int(2 * R * asin(sqrt(h)))
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Don't override simulated location with real GPS
        guard simulatedLocation == nil, let loc = locations.last else { return }
        location = loc.coordinate
        accuracy = loc.horizontalAccuracy
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        heading = newHeading.trueHeading
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        self.error = error.localizedDescription
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            self.error = nil
        case .denied, .restricted:
            self.error = "Location access denied"
        default:
            break
        }
    }

    // MARK: - Region monitoring delegate

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard monitoredRegionIds.contains(region.identifier) else { return }
        // Store the region identifier; the name is encoded in courseGeofenceNames
        nearbyCourseId = region.identifier
        nearbyCourseName = courseGeofenceNames[region.identifier]
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard region.identifier == nearbyCourseId else { return }
        nearbyCourseName = nil
        nearbyCourseId = nil
    }

    /// Name lookup populated during startMonitoringCourses
    private var courseGeofenceNames: [String: String] = [:]
}
