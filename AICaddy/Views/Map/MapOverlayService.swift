import Foundation
import MapKit
import CoreLocation

// MARK: - Layup Ring Overlay

/// An `MKCircle` subclass that carries a yardage distance label.
/// Use `LayupRing.createRings(greenCenter:)` to generate the standard
/// 100 / 150 / 200-yard rings for a given green location.
final class LayupRing: MKCircle {

    /// The yardage this ring represents (e.g. 100, 150, 200).
    private(set) var distance: Int = 0

    /// Factory: create a single ring at the given yardage from the green.
    /// - Parameters:
    ///   - center: The green-center coordinate.
    ///   - yards: Distance in yards.
    /// - Returns: A configured `LayupRing`.
    static func ring(center: CLLocationCoordinate2D, yards: Int) -> LayupRing {
        let meters = Double(yards) * 0.9144
        let ring = LayupRing(center: center, radius: meters)
        ring.distance = yards
        return ring
    }

    /// Create the standard set of layup rings (100y, 150y, 200y) around a green.
    static func createRings(greenCenter: CLLocationCoordinate2D) -> [LayupRing] {
        [100, 150, 200].map { ring(center: greenCenter, yards: $0) }
    }
}

// MARK: - Layup Ring Renderer

/// Provides a pre-configured `MKCircleRenderer` for a `LayupRing`.
/// The style is very subtle: near-transparent fill and stroke so the rings
/// stay visible on satellite imagery without obscuring the course.
enum LayupRingRenderer {

    static func renderer(for ring: LayupRing) -> MKCircleRenderer {
        let r = MKCircleRenderer(circle: ring)
        r.fillColor = UIColor.white.withAlphaComponent(0.08)
        r.strokeColor = UIColor.white.withAlphaComponent(0.15)
        r.lineWidth = 1
        return r
    }
}

// MARK: - Layup Ring Label Annotation

/// A lightweight annotation placed at the edge of a layup ring so the
/// yardage is readable on the map.  Position it at the southern-most
/// point of each ring so labels don't overlap with the green flag.
final class LayupRingLabel: MKPointAnnotation {

    let yards: Int

    init(yards: Int, ringCenter: CLLocationCoordinate2D) {
        self.yards = yards
        super.init()
        // Place the label at the southern edge of the ring.
        let metersOffset = Double(yards) * 0.9144
        let earthRadius = 6_371_000.0
        let latOffset = (metersOffset / earthRadius) * (180.0 / .pi)
        self.coordinate = CLLocationCoordinate2D(
            latitude: ringCenter.latitude - latOffset,
            longitude: ringCenter.longitude
        )
        self.title = "\(yards)y"
    }

    /// Create label annotations for a set of layup rings.
    static func labels(for rings: [LayupRing], greenCenter: CLLocationCoordinate2D) -> [LayupRingLabel] {
        rings.map { LayupRingLabel(yards: $0.distance, ringCenter: greenCenter) }
    }

    /// Returns an `MKAnnotationView` styled as a small distance pill.
    static func annotationView(for label: LayupRingLabel, on mapView: MKMapView) -> MKAnnotationView {
        let id = "LayupRingLabel"
        let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
            ?? MKAnnotationView(annotation: label, reuseIdentifier: id)
        view.annotation = label
        view.canShowCallout = false

        let text = "\(label.yards)y"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9, weight: .bold),
            .foregroundColor: UIColor.white.withAlphaComponent(0.6)
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let strSize = str.size()
        let pillW = strSize.width + 8
        let pillH = strSize.height + 4

        let img = UIGraphicsImageRenderer(size: CGSize(width: pillW, height: pillH)).image { _ in
            UIColor(white: 0.05, alpha: 0.7).setFill()
            UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: pillW, height: pillH),
                         cornerRadius: pillH / 2).fill()
            str.draw(at: CGPoint(x: 4, y: 2))
        }
        view.image = img
        view.frame.size = img.size
        return view
    }
}

// MARK: - Shot Dispersion Heatmap

/// Holds categorised shot coordinates for heatmap generation.
struct ShotDispersionData {
    /// Landing positions of tee shots.
    var teeShots: [CLLocationCoordinate2D]
    /// Landing positions of approach shots.
    var approaches: [CLLocationCoordinate2D]
}

/// Overlay subclass that carries a shot category so the renderer can
/// pick the correct colour (yellow for tee, cyan for approach).
final class ShotDispersionCircle: MKCircle {
    enum ShotCategory { case tee, approach }
    private(set) var category: ShotCategory = .tee

    static func circle(at coordinate: CLLocationCoordinate2D,
                       category: ShotCategory,
                       radius: CLLocationDistance = 5) -> ShotDispersionCircle {
        let c = ShotDispersionCircle(center: coordinate, radius: radius)
        c.category = category
        return c
    }
}

/// Renderer factory for shot-dispersion circles.
enum ShotDispersionRenderer {

    static func renderer(for circle: ShotDispersionCircle) -> MKCircleRenderer {
        let r = MKCircleRenderer(circle: circle)
        switch circle.category {
        case .tee:
            r.fillColor = UIColor.systemYellow.withAlphaComponent(0.25)
            r.strokeColor = UIColor.systemYellow.withAlphaComponent(0.45)
        case .approach:
            r.fillColor = UIColor.cyan.withAlphaComponent(0.25)
            r.strokeColor = UIColor.cyan.withAlphaComponent(0.45)
        }
        r.lineWidth = 0.5
        return r
    }
}

// MARK: - Heatmap Overlay Generation

enum ShotDispersionService {

    /// Classify an array of `ShotLocation` into tee-shot and approach
    /// landing coordinates, then return dispersion data.
    static func classify(shots: [ShotLocation]) -> ShotDispersionData {
        var tee: [CLLocationCoordinate2D] = []
        var approach: [CLLocationCoordinate2D] = []

        for shot in shots {
            // The first shot of any hole is a tee shot; everything else is
            // an approach (putts are typically not GPS-tracked, so they
            // won't appear in ShotLocation data).
            //
            // Heuristic: tee shots usually travel > 150 yards.
            if shot.distanceYards > 150 {
                tee.append(shot.end.coordinate)
            } else {
                approach.append(shot.end.coordinate)
            }
        }

        return ShotDispersionData(teeShots: tee, approaches: approach)
    }

    /// Generate `MKOverlay` circles from raw `ShotLocation` data.
    /// Each shot produces a small semi-transparent circle at its landing
    /// point, colour-coded by category.
    static func generateHeatmapOverlays(shots: [ShotLocation]) -> [MKOverlay] {
        let data = classify(shots: shots)
        var overlays: [MKOverlay] = []

        for coord in data.teeShots {
            overlays.append(ShotDispersionCircle.circle(at: coord, category: .tee))
        }
        for coord in data.approaches {
            overlays.append(ShotDispersionCircle.circle(at: coord, category: .approach))
        }

        return overlays
    }

    /// Convenience: generate overlays from pre-classified dispersion data.
    static func generateHeatmapOverlays(from data: ShotDispersionData) -> [MKOverlay] {
        var overlays: [MKOverlay] = []

        for coord in data.teeShots {
            overlays.append(ShotDispersionCircle.circle(at: coord, category: .tee))
        }
        for coord in data.approaches {
            overlays.append(ShotDispersionCircle.circle(at: coord, category: .approach))
        }

        return overlays
    }
}
