import SwiftUI
import UIKit
import MapKit
import CoreLocation

// MARK: - Main View

struct HoleMapView: View {
    let holeGps: HoleGps?
    let holeNumber: Int
    let par: Int
    let userLocation: CLLocationCoordinate2D?
    var caddyTarget: CLLocationCoordinate2D? = nil

    @State private var dragTarget: CLLocationCoordinate2D?
    @State private var followUser = false
    @State private var showLayupRings = false
    @State private var mapStyle: MapStyle = .satellite

    enum MapStyle: CaseIterable {
        case satellite, standard, hybrid

        var next: MapStyle {
            switch self {
            case .satellite: return .standard
            case .standard: return .hybrid
            case .hybrid: return .satellite
            }
        }

        var mkMapType: MKMapType {
            switch self {
            case .satellite: return .satellite
            case .standard: return .mutedStandard
            case .hybrid: return .hybridFlyover
            }
        }

        var icon: String {
            switch self {
            case .satellite: return "globe.americas.fill"
            case .standard: return "map.fill"
            case .hybrid: return "square.stack.3d.up.fill"
            }
        }
    }

    private var distToTarget: Int? {
        guard let loc = userLocation, let target = dragTarget else { return nil }
        return LocationService.distanceYards(from: loc, to: target)
    }
    private var targetToGreen: Int? {
        guard let target = dragTarget, let green = holeGps?.greenCenter else { return nil }
        return LocationService.distanceYards(from: target, to: green.coordinate)
    }

    var body: some View {
        ZStack {
            // Full-screen satellite map
            NativeMapView(
                holeGps: holeGps,
                userLocation: userLocation,
                dragTarget: $dragTarget,
                followUser: followUser,
                showLayupRings: showLayupRings,
                mapStyle: mapStyle.mkMapType,
                caddyTarget: caddyTarget
            )
            .ignoresSafeArea()

            // Floating controls — right side, below safe area
            VStack {
                Spacer().frame(height: 140) // clear nav bar + top overlay
                VStack(spacing: 8) {
                    MapButton(icon: mapStyle.icon) {
                        withAnimation(.easeInOut(duration: 0.2)) { mapStyle = mapStyle.next }
                    }
                    MapButton(icon: followUser ? "location.fill" : "location") {
                        followUser.toggle()
                    }
                    MapButton(icon: "flag.fill") {
                        followUser = false
                        NotificationCenter.default.post(name: .fitHole, object: nil)
                    }
                    MapButton(icon: "circle.dashed") {
                        showLayupRings.toggle()
                    }
                    .opacity(showLayupRings ? 1.0 : 0.5)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 10)

            // Clear target button — small X floating near top
            if dragTarget != nil {
                VStack {
                    Spacer().frame(height: 140)
                    HStack {
                        Button {
                            withAnimation { dragTarget = nil }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                                Text("Clear target")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.6))
                            .clipShape(Capsule())
                        }
                        Spacer()
                    }
                    .padding(.leading, 10)
                    Spacer()
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: dragTarget != nil)
    }

}

// MARK: - Floating Map Button

private struct MapButton: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
        }
    }
}

// MARK: - Distance Pill

struct DistancePill: View {
    let label: String
    let yards: Int
    let color: Color

    var body: some View {
        VStack(spacing: 0) {
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(color.opacity(0.7))
            Text("\(yards)")
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(color)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Notification for reframing

extension Notification.Name {
    static let fitHole = Notification.Name("fitHoleToScreen")
    static let flyoverHole = Notification.Name("flyoverHoleAnimation")
}

// MARK: - Native MKMapView Wrapper (the real deal)

struct NativeMapView: UIViewRepresentable {
    let holeGps: HoleGps?
    let userLocation: CLLocationCoordinate2D?
    @Binding var dragTarget: CLLocationCoordinate2D?
    let followUser: Bool
    var showLayupRings: Bool = false
    var mapStyle: MKMapType = .satellite
    var caddyTarget: CLLocationCoordinate2D? = nil
    var flyoverOnAppear: Bool = true

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.mapType = .satellite
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.isPitchEnabled = true
        mapView.isRotateEnabled = true
        mapView.isZoomEnabled = true
        mapView.isScrollEnabled = true
        mapView.pointOfInterestFilter = .excludingAll

        // Smooth momentum scrolling
        mapView.isUserInteractionEnabled = true

        // Long press to place target
        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPress.minimumPressDuration = 0.4
        mapView.addGestureRecognizer(longPress)

        // Double tap to zoom (ensure it doesn't conflict)
        for gesture in mapView.gestureRecognizers ?? [] {
            if let doubleTap = gesture as? UITapGestureRecognizer, doubleTap.numberOfTapsRequired == 2 {
                longPress.require(toFail: doubleTap)
            }
        }

        // Listen for fit-hole notification
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.fitHole),
            name: .fitHole,
            object: nil
        )

        // Listen for flyover notification
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.flyoverHole),
            name: .flyoverHole,
            object: nil
        )
        context.coordinator.mapView = mapView

        // Initial framing: flyover if enabled, otherwise standard fit
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if self.flyoverOnAppear && !context.coordinator.hasFlyoverPlayed {
                context.coordinator.flyoverHole()
            } else {
                context.coordinator.fitHole()
            }
        }

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self
        if mapView.mapType != mapStyle {
            mapView.mapType = mapStyle
        }
        context.coordinator.updateAnnotations(on: mapView)
        context.coordinator.updateOverlays(on: mapView)

        if followUser, let loc = userLocation {
            let region = MKCoordinateRegion(
                center: loc,
                latitudinalMeters: 150,
                longitudinalMeters: 150
            )
            mapView.setRegion(region, animated: true)
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: NativeMapView
        weak var mapView: MKMapView?
        private var targetAnnotation: MKPointAnnotation?
        private var isDraggingTarget = false
        var hasFlyoverPlayed = false

        init(parent: NativeMapView) {
            self.parent = parent
        }

        // MARK: Long press → place/move target

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard let mapView else { return }
            let point = gesture.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)

            switch gesture.state {
            case .began:
                // Place or start dragging the target
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                parent.dragTarget = coordinate
                isDraggingTarget = true

            case .changed:
                // Continuously update target position as finger moves
                if isDraggingTarget {
                    parent.dragTarget = coordinate
                }

            case .ended, .cancelled:
                isDraggingTarget = false
                if let coord = parent.dragTarget {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    parent.dragTarget = coord
                }

            default:
                break
            }
        }

        // MARK: Fit hole tee-to-green

        @objc func fitHole() {
            guard let mapView, let gps = parent.holeGps else { return }

            guard let tee = gps.tee, let green = gps.greenCenter else {
                // Fallback: just fit whatever points we have
                var coords: [CLLocationCoordinate2D] = []
                if let t = gps.tee { coords.append(t.coordinate) }
                if let g = gps.greenCenter { coords.append(g.coordinate) }
                if let loc = parent.userLocation { coords.append(loc) }
                guard coords.count >= 1 else { return }
                let region = MKCoordinateRegion(center: coords[0], latitudinalMeters: 400, longitudinalMeters: 400)
                mapView.setRegion(region, animated: true)
                return
            }

            // Calculate bearing from tee to green so green is at the top of the screen
            let bearing = Self.bearing(from: tee.coordinate, to: green.coordinate)

            // Center between tee and green, biased 55% toward green
            // so the green + its annotation label aren't clipped by the top overlay/Dynamic Island
            let centerLat = tee.lat + (green.lat - tee.lat) * 0.55
            let centerLng = tee.lng + (green.lng - tee.lng) * 0.55
            let center = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLng)

            // Calculate distance to determine altitude
            let distance = CLLocation(latitude: tee.lat, longitude: tee.lng)
                .distance(from: CLLocation(latitude: green.lat, longitude: green.lng))
            // Altitude ~2.5x the hole distance to leave room for overlays at top and bottom
            let altitude = max(distance * 2.5, 350)

            let camera = MKMapCamera(
                lookingAtCenter: center,
                fromDistance: altitude,
                pitch: 0,
                heading: bearing
            )
            mapView.setCamera(camera, animated: true)
        }

        // MARK: Flyover animation tee → green

        @objc func flyoverHole() {
            guard let mapView, let gps = parent.holeGps,
                  let tee = gps.tee, let green = gps.greenCenter else {
                fitHole()
                return
            }

            hasFlyoverPlayed = true

            let bearing = Self.bearing(from: tee.coordinate, to: green.coordinate)
            let holeDistance = CLLocation(latitude: tee.lat, longitude: tee.lng)
                .distance(from: CLLocation(latitude: green.lat, longitude: green.lng))

            // Camera 1: Low altitude at the tee, pitched, looking toward green
            let cam1 = MKMapCamera(
                lookingAtCenter: tee.coordinate,
                fromDistance: max(holeDistance * 0.6, 200),
                pitch: 45,
                heading: bearing
            )
            mapView.setCamera(cam1, animated: false)

            // Camera 2: Mid-hole, medium altitude, pitched (arrives at 1.5s)
            let midLat = tee.lat + (green.lat - tee.lat) * 0.5
            let midLng = tee.lng + (green.lng - tee.lng) * 0.5
            let midPoint = CLLocationCoordinate2D(latitude: midLat, longitude: midLng)

            let cam2 = MKMapCamera(
                lookingAtCenter: midPoint,
                fromDistance: max(holeDistance * 1.2, 300),
                pitch: 35,
                heading: bearing
            )

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                UIView.animate(withDuration: 1.5, delay: 0, options: .curveEaseInOut) {
                    mapView.setCamera(cam2, animated: false)
                }
            }

            // Camera 3: Pull back to standard fitHole view (arrives at 3s)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                // Build the same camera fitHole() uses
                let centerLat = tee.lat + (green.lat - tee.lat) * 0.55
                let centerLng = tee.lng + (green.lng - tee.lng) * 0.55
                let center = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLng)
                let altitude = max(holeDistance * 2.5, 350)

                let cam3 = MKMapCamera(
                    lookingAtCenter: center,
                    fromDistance: altitude,
                    pitch: 0,
                    heading: bearing
                )

                UIView.animate(withDuration: 1.5, delay: 0, options: .curveEaseOut) {
                    mapView.setCamera(cam3, animated: false)
                }
            }
        }

        /// Bearing in degrees from point A to point B (0 = north, 90 = east)
        private static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
            let lat1 = a.latitude * .pi / 180
            let lat2 = b.latitude * .pi / 180
            let dLng = (b.longitude - a.longitude) * .pi / 180

            let y = sin(dLng) * cos(lat2)
            let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLng)
            let bearing = atan2(y, x) * 180 / .pi

            return (bearing + 360).truncatingRemainder(dividingBy: 360)
        }

        // MARK: Annotations

        func updateAnnotations(on mapView: MKMapView) {
            mapView.removeAnnotations(mapView.annotations)

            // User location (custom, not MKUserLocation)
            if let loc = parent.userLocation {
                let ann = GolfAnnotation(coordinate: loc, type: .user)
                mapView.addAnnotation(ann)
            }

            guard let gps = parent.holeGps else { return }

            // Tee
            if let tee = gps.tee {
                mapView.addAnnotation(GolfAnnotation(coordinate: tee.coordinate, type: .tee))
            }

            // Green with distance labels (front/center/back)
            if let green = gps.greenCenter {
                let ann = GolfAnnotation(coordinate: green.coordinate, type: .greenCenter)
                ann.distance = parent.userLocation.map {
                    LocationService.distanceYards(from: $0, to: green.coordinate)
                }
                ann.frontDistance = parent.userLocation.flatMap { loc in
                    gps.greenFront.map { LocationService.distanceYards(from: loc, to: $0.coordinate) }
                }
                ann.backDistance = parent.userLocation.flatMap { loc in
                    gps.greenBack.map { LocationService.distanceYards(from: loc, to: $0.coordinate) }
                }
                mapView.addAnnotation(ann)
            }
            if let front = gps.greenFront {
                mapView.addAnnotation(GolfAnnotation(coordinate: front.coordinate, type: .greenFront))
            }
            if let back = gps.greenBack {
                mapView.addAnnotation(GolfAnnotation(coordinate: back.coordinate, type: .greenBack))
            }

            // Hazards
            for hazard in gps.hazards ?? [] {
                let ann = GolfAnnotation(coordinate: hazard.position.coordinate,
                                        type: hazard.type == "water" ? .water : .bunker)
                ann.title = hazard.label
                ann.distance = parent.userLocation.map {
                    LocationService.distanceYards(from: $0, to: hazard.position.coordinate)
                }
                mapView.addAnnotation(ann)
            }

            // AI Caddy suggested target (only when user hasn't placed their own)
            if parent.dragTarget == nil, let caddy = parent.caddyTarget {
                let ann = GolfAnnotation(coordinate: caddy, type: .caddyTarget)
                ann.distance = parent.userLocation.map {
                    LocationService.distanceYards(from: $0, to: caddy)
                }
                ann.secondaryDistance = gps.greenCenter.map {
                    LocationService.distanceYards(from: caddy, to: $0.coordinate)
                }
                mapView.addAnnotation(ann)
            }

            // Drag target
            if let target = parent.dragTarget {
                let ann = GolfAnnotation(coordinate: target, type: .target)
                ann.distance = parent.userLocation.map {
                    LocationService.distanceYards(from: $0, to: target)
                }
                ann.secondaryDistance = gps.greenCenter.map {
                    LocationService.distanceYards(from: target, to: $0.coordinate)
                }
                mapView.addAnnotation(ann)
            }
        }

        // MARK: Overlays (multi-layer lines with glow)

        func updateOverlays(on mapView: MKMapView) {
            mapView.removeOverlays(mapView.overlays)

            guard let loc = parent.userLocation else { return }

            // Line: user → green (3-layer glow)
            if let green = parent.holeGps?.greenCenter {
                let coords = [loc, green.coordinate]
                for layer in GolfPolyline.GlowLayer.allCases {
                    let line = GolfPolyline(coordinates: coords, count: coords.count)
                    line.lineType = .userToGreen
                    line.glowLayer = layer
                    mapView.addOverlay(line)
                }
            }

            // Line: user → caddy target (when no manual target placed)
            if parent.dragTarget == nil, let caddy = parent.caddyTarget {
                let coords = [loc, caddy]
                for layer in GolfPolyline.GlowLayer.allCases {
                    let line = GolfPolyline(coordinates: coords, count: coords.count)
                    line.lineType = .userToTarget
                    line.glowLayer = layer
                    mapView.addOverlay(line)
                }
                // Caddy target → green (dashed)
                if let green = parent.holeGps?.greenCenter {
                    let coords2 = [caddy, green.coordinate]
                    let line2 = GolfPolyline(coordinates: coords2, count: coords2.count)
                    line2.lineType = .targetToGreen
                    line2.glowLayer = .core
                    mapView.addOverlay(line2)
                }
            }

            // Line: user → manual target (3-layer glow)
            if let target = parent.dragTarget {
                let coords = [loc, target]
                for layer in GolfPolyline.GlowLayer.allCases {
                    let line = GolfPolyline(coordinates: coords, count: coords.count)
                    line.lineType = .userToTarget
                    line.glowLayer = layer
                    mapView.addOverlay(line)
                }

                // Line: target → green (subtle)
                if let green = parent.holeGps?.greenCenter {
                    let coords2 = [target, green.coordinate]
                    let line2 = GolfPolyline(coordinates: coords2, count: coords2.count)
                    line2.lineType = .targetToGreen
                    line2.glowLayer = .core
                    mapView.addOverlay(line2)
                }
            }

            // Layup rings (100y, 150y, 200y circles around green)
            if parent.showLayupRings, let green = parent.holeGps?.greenCenter {
                let rings = LayupRing.createRings(greenCenter: green.coordinate)
                for ring in rings {
                    mapView.addOverlay(ring)
                }
                let labels = LayupRingLabel.labels(for: rings, greenCenter: green.coordinate)
                mapView.addAnnotations(labels)
            }
        }

        // MARK: MKMapViewDelegate

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let label = annotation as? LayupRingLabel {
                return LayupRingLabel.annotationView(for: label, on: mapView)
            }

            guard let golfAnn = annotation as? GolfAnnotation else { return nil }

            let id = "\(golfAnn.type.rawValue)_\(golfAnn.distance ?? 0)_\(golfAnn.secondaryDistance ?? 0)_\(arc4random())"
            let view = MKAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation
            view.canShowCallout = false
            view.subviews.forEach { $0.removeFromSuperview() }

            switch golfAnn.type {

            // ── User: rendered SF Symbol with glow ──
            case .user:
                let size: CGFloat = 44
                let img = UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { ctx in
                    // Outer glow
                    let glowRect = CGRect(x: 2, y: 2, width: size - 4, height: size - 4)
                    UIColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 0.12).setFill()
                    ctx.cgContext.fillEllipse(in: glowRect)
                    UIColor(red: 0.3, green: 0.7, blue: 1.0, alpha: 0.3).setStroke()
                    ctx.cgContext.setLineWidth(1.5)
                    ctx.cgContext.strokeEllipse(in: glowRect)
                    // Inner dot
                    let dotSize: CGFloat = 14
                    let dotRect = CGRect(x: (size - dotSize) / 2, y: (size - dotSize) / 2, width: dotSize, height: dotSize)
                    UIColor(red: 0.25, green: 0.65, blue: 1.0, alpha: 1).setFill()
                    ctx.cgContext.fillEllipse(in: dotRect)
                    UIColor.white.setStroke()
                    ctx.cgContext.setLineWidth(2.5)
                    ctx.cgContext.strokeEllipse(in: dotRect.insetBy(dx: 1.25, dy: 1.25))
                }
                view.image = img
                view.frame.size = CGSize(width: size, height: size)
                view.centerOffset = .zero

            // ── Tee: SF Symbol rendered ──
            case .tee:
                let img = UIGraphicsImageRenderer(size: CGSize(width: 36, height: 20)).image { ctx in
                    let rect = CGRect(x: 0, y: 0, width: 36, height: 20)
                    UIColor.white.setFill()
                    UIBezierPath(roundedRect: rect, cornerRadius: 10).fill()
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 10, weight: .heavy),
                        .foregroundColor: UIColor.black
                    ]
                    let str = NSAttributedString(string: "TEE", attributes: attrs)
                    let strSize = str.size()
                    str.draw(at: CGPoint(x: (36 - strSize.width) / 2, y: (20 - strSize.height) / 2))
                }
                view.image = img
                view.frame.size = CGSize(width: 36, height: 20)

            // ── Green: rendered flag with distance ──
            case .greenCenter:
                let w: CGFloat = 90
                let flagH: CGFloat = 38
                let hasDistances = golfAnn.distance != nil
                let labelH: CGFloat = hasDistances ? 34 : 0
                let h = flagH + labelH

                let img = UIGraphicsImageRenderer(size: CGSize(width: w, height: h)).image { ctx in
                    let c = ctx.cgContext
                    // Pole
                    c.setStrokeColor(UIColor.white.cgColor)
                    c.setLineWidth(2)
                    c.move(to: CGPoint(x: w / 2, y: 4))
                    c.addLine(to: CGPoint(x: w / 2, y: flagH - 2))
                    c.strokePath()
                    // Flag
                    c.setFillColor(UIColor.systemRed.cgColor)
                    c.move(to: CGPoint(x: w / 2 + 1, y: 4))
                    c.addLine(to: CGPoint(x: w / 2 + 16, y: 10))
                    c.addLine(to: CGPoint(x: w / 2 + 1, y: 16))
                    c.closePath()
                    c.fillPath()
                    // Base
                    c.setFillColor(UIColor.systemGreen.withAlphaComponent(0.4).cgColor)
                    c.fillEllipse(in: CGRect(x: w / 2 - 8, y: flagH - 10, width: 16, height: 10))
                    c.setFillColor(UIColor.white.cgColor)
                    c.fillEllipse(in: CGRect(x: w / 2 - 3, y: flagH - 6, width: 6, height: 4))

                    // Distance card below flag: front | center | back
                    if hasDistances {
                        let cardY = flagH + 2
                        let cardW: CGFloat = 86
                        let cardH: CGFloat = 30
                        let cardX = (w - cardW) / 2

                        UIColor(white: 0.05, alpha: 0.88).setFill()
                        UIBezierPath(roundedRect: CGRect(x: cardX, y: cardY, width: cardW, height: cardH), cornerRadius: 8).fill()

                        let colW = cardW / 3

                        // Front (green)
                        if let front = golfAnn.frontDistance {
                            let fLabel = NSAttributedString(string: "F", attributes: [
                                .font: UIFont.systemFont(ofSize: 7, weight: .bold),
                                .foregroundColor: UIColor.systemGreen.withAlphaComponent(0.6)
                            ])
                            let fNum = NSAttributedString(string: "\(front)", attributes: [
                                .font: UIFont.systemFont(ofSize: 11, weight: .heavy),
                                .foregroundColor: UIColor.systemGreen
                            ])
                            let fLabelSize = fLabel.size()
                            let fNumSize = fNum.size()
                            fLabel.draw(at: CGPoint(x: cardX + (colW - fLabelSize.width) / 2, y: cardY + 3))
                            fNum.draw(at: CGPoint(x: cardX + (colW - fNumSize.width) / 2, y: cardY + 13))
                        }

                        // Center (white, big)
                        if let center = golfAnn.distance {
                            let cNum = NSAttributedString(string: "\(center)", attributes: [
                                .font: UIFont.systemFont(ofSize: 13, weight: .heavy),
                                .foregroundColor: UIColor.white
                            ])
                            let cNumSize = cNum.size()
                            cNum.draw(at: CGPoint(x: cardX + colW + (colW - cNumSize.width) / 2, y: cardY + 8))
                        }

                        // Back (red)
                        if let back = golfAnn.backDistance {
                            let bLabel = NSAttributedString(string: "B", attributes: [
                                .font: UIFont.systemFont(ofSize: 7, weight: .bold),
                                .foregroundColor: UIColor.systemRed.withAlphaComponent(0.6)
                            ])
                            let bNum = NSAttributedString(string: "\(back)", attributes: [
                                .font: UIFont.systemFont(ofSize: 11, weight: .heavy),
                                .foregroundColor: UIColor.systemRed
                            ])
                            let bLabelSize = bLabel.size()
                            let bNumSize = bNum.size()
                            bLabel.draw(at: CGPoint(x: cardX + colW * 2 + (colW - bLabelSize.width) / 2, y: cardY + 3))
                            bNum.draw(at: CGPoint(x: cardX + colW * 2 + (colW - bNumSize.width) / 2, y: cardY + 13))
                        }
                    }
                }
                view.image = img
                view.frame.size = CGSize(width: w, height: h)
                view.centerOffset = CGPoint(x: 0, y: -flagH / 2 + 4)

            case .greenFront:
                view.image = Self.makeRingImage(size: 12, color: .systemGreen)
                view.frame.size = CGSize(width: 12, height: 12)

            case .greenBack:
                view.image = Self.makeRingImage(size: 12, color: .systemRed)
                view.frame.size = CGSize(width: 12, height: 12)

            // ── Bunker ──
            case .bunker:
                let img = Self.makeHazardImage(
                    color: UIColor(red: 0.93, green: 0.83, blue: 0.5, alpha: 1),
                    symbol: "diamond.fill",
                    distance: golfAnn.distance
                )
                view.image = img
                view.frame.size = img.size

            // ── Water ──
            case .water:
                let img = Self.makeHazardImage(
                    color: UIColor(red: 0.3, green: 0.65, blue: 1.0, alpha: 1),
                    symbol: "drop.fill",
                    distance: golfAnn.distance
                )
                view.image = img
                view.frame.size = img.size

            // ── Target: frosted glass card ──
            // ── AI Caddy target: green-tinted scope with "Aim here" card ──
            case .caddyTarget:
                let cardW: CGFloat = 120
                let cardH: CGFloat = 48
                let pinSize: CGFloat = 22
                let gap: CGFloat = 4
                let totalH = cardH + gap + pinSize

                let img = UIGraphicsImageRenderer(size: CGSize(width: cardW, height: totalH)).image { ctx in
                    let c = ctx.cgContext

                    // Card
                    let cardRect = CGRect(x: 0, y: 0, width: cardW, height: cardH)
                    c.setFillColor(UIColor(red: 0.1, green: 0.3, blue: 0.15, alpha: 0.9).cgColor)
                    let cardPath = UIBezierPath(roundedRect: cardRect, cornerRadius: 12)
                    c.addPath(cardPath.cgPath)
                    c.fillPath()
                    c.setStrokeColor(UIColor.systemGreen.withAlphaComponent(0.4).cgColor)
                    c.setLineWidth(1)
                    c.addPath(cardPath.cgPath)
                    c.strokePath()

                    // "AIM HERE" label
                    let aimStr = NSAttributedString(string: "AIM HERE", attributes: [
                        .font: UIFont.systemFont(ofSize: 8, weight: .heavy),
                        .foregroundColor: UIColor.systemGreen.withAlphaComponent(0.7)
                    ])
                    let aimSize = aimStr.size()
                    aimStr.draw(at: CGPoint(x: (cardW - aimSize.width) / 2, y: 4))

                    // Distance text
                    if let d = golfAnn.distance {
                        let mainStr = NSAttributedString(string: "\(d)", attributes: [
                            .font: UIFont.systemFont(ofSize: 18, weight: .heavy),
                            .foregroundColor: UIColor.white
                        ])
                        let yardStr = NSAttributedString(string: "y", attributes: [
                            .font: UIFont.systemFont(ofSize: 10, weight: .medium),
                            .foregroundColor: UIColor.white.withAlphaComponent(0.5)
                        ])
                        let full = NSMutableAttributedString()
                        full.append(mainStr)
                        full.append(yardStr)

                        if let d2 = golfAnn.secondaryDistance {
                            let arrow = NSAttributedString(string: "  → \(d2)y pin", attributes: [
                                .font: UIFont.systemFont(ofSize: 9, weight: .semibold),
                                .foregroundColor: UIColor.white.withAlphaComponent(0.35)
                            ])
                            full.append(arrow)
                        }

                        let fullSize = full.size()
                        full.draw(at: CGPoint(x: (cardW - fullSize.width) / 2, y: 16))
                    }

                    // Connector
                    c.setStrokeColor(UIColor.systemGreen.withAlphaComponent(0.4).cgColor)
                    c.setLineWidth(1)
                    c.move(to: CGPoint(x: cardW / 2, y: cardH))
                    c.addLine(to: CGPoint(x: cardW / 2, y: cardH + gap))
                    c.strokePath()

                    // Ring
                    let ringY = cardH + gap
                    let pinX = (cardW - pinSize) / 2
                    c.setFillColor(UIColor.systemGreen.withAlphaComponent(0.1).cgColor)
                    c.fillEllipse(in: CGRect(x: pinX - 4, y: ringY - 4, width: pinSize + 8, height: pinSize + 8))
                    c.setStrokeColor(UIColor.systemGreen.cgColor)
                    c.setLineWidth(2.5)
                    c.strokeEllipse(in: CGRect(x: pinX + 1, y: ringY + 1, width: pinSize - 2, height: pinSize - 2))
                    let dotS: CGFloat = 5
                    c.setFillColor(UIColor.systemGreen.cgColor)
                    c.fillEllipse(in: CGRect(x: (cardW - dotS) / 2, y: ringY + (pinSize - dotS) / 2, width: dotS, height: dotS))
                }

                view.image = img
                view.frame.size = img.size
                let ringCenterY = cardH + gap + pinSize / 2
                view.centerOffset = CGPoint(x: 0, y: -totalH / 2 + pinSize / 2)

            // ── Manual target: white scope with distance card ──
            case .target:
                let cardW: CGFloat = 140
                let cardH: CGFloat = 56
                let pinSize: CGFloat = 20
                let gap: CGFloat = 4
                // Layout: card on top, then gap, then ring at bottom
                let totalH = cardH + gap + pinSize

                let img = UIGraphicsImageRenderer(size: CGSize(width: cardW, height: totalH)).image { ctx in
                    let c = ctx.cgContext

                    // ── Card background (at top) ──
                    let cardRect = CGRect(x: 0, y: 0, width: cardW, height: cardH)
                    c.setFillColor(UIColor(white: 0.08, alpha: 0.92).cgColor)
                    let cardPath = UIBezierPath(roundedRect: cardRect, cornerRadius: 14)
                    c.addPath(cardPath.cgPath)
                    c.fillPath()
                    c.setStrokeColor(UIColor.white.withAlphaComponent(0.12).cgColor)
                    c.setLineWidth(1)
                    c.addPath(cardPath.cgPath)
                    c.strokePath()

                    // ── Distance text ──
                    if let d = golfAnn.distance {
                        let mainStr = NSAttributedString(string: "\(d)", attributes: [
                            .font: UIFont.systemFont(ofSize: 24, weight: .heavy),
                            .foregroundColor: UIColor.white
                        ])
                        let yardStr = NSAttributedString(string: " yds", attributes: [
                            .font: UIFont.systemFont(ofSize: 11, weight: .medium),
                            .foregroundColor: UIColor.white.withAlphaComponent(0.5)
                        ])
                        let full = NSMutableAttributedString()
                        full.append(mainStr)
                        full.append(yardStr)
                        let fullSize = full.size()
                        full.draw(at: CGPoint(x: (cardW - fullSize.width) / 2, y: 6))
                    }

                    if let d2 = golfAnn.secondaryDistance {
                        let subStr = NSAttributedString(string: "\(d2) yds to pin", attributes: [
                            .font: UIFont.systemFont(ofSize: 10, weight: .semibold),
                            .foregroundColor: UIColor.white.withAlphaComponent(0.35)
                        ])
                        let subSize = subStr.size()
                        subStr.draw(at: CGPoint(x: (cardW - subSize.width) / 2, y: 34))
                    }

                    // ── Connector line ──
                    c.setStrokeColor(UIColor.white.withAlphaComponent(0.3).cgColor)
                    c.setLineWidth(1)
                    c.move(to: CGPoint(x: cardW / 2, y: cardH))
                    c.addLine(to: CGPoint(x: cardW / 2, y: cardH + gap))
                    c.strokePath()

                    // ── Pin ring at bottom ──
                    let ringY = cardH + gap
                    let pinX = (cardW - pinSize) / 2
                    // Outer glow
                    c.setFillColor(UIColor.white.withAlphaComponent(0.15).cgColor)
                    c.fillEllipse(in: CGRect(x: pinX - 6, y: ringY - 6, width: pinSize + 12, height: pinSize + 12))
                    // Ring
                    c.setStrokeColor(UIColor.white.cgColor)
                    c.setLineWidth(2.5)
                    c.strokeEllipse(in: CGRect(x: pinX + 1, y: ringY + 1, width: pinSize - 2, height: pinSize - 2))
                    // Center dot
                    let dotS: CGFloat = 5
                    c.setFillColor(UIColor.white.cgColor)
                    c.fillEllipse(in: CGRect(x: (cardW - dotS) / 2, y: ringY + (pinSize - dotS) / 2, width: dotS, height: dotS))
                }

                view.image = img
                view.frame.size = img.size
                // Place the bottom edge of the image (where the ring is) at the coordinate.
                // centerOffset.y of -totalH/2 puts the bottom of the image at the coordinate.
                // But we want the ring CENTER (pinSize/2 up from bottom), so add pinSize/2.
                view.centerOffset = CGPoint(x: 0, y: -totalH / 2 + pinSize / 2)
            }

            return view
        }

        // MARK: - Rendering helpers

        private static func makeRingImage(size: CGFloat, color: UIColor) -> UIImage {
            UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { ctx in
                color.withAlphaComponent(0.3).setFill()
                ctx.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: size, height: size))
                color.setStroke()
                ctx.cgContext.setLineWidth(2)
                ctx.cgContext.strokeEllipse(in: CGRect(x: 1, y: 1, width: size - 2, height: size - 2))
            }
        }

        private static func makeHazardImage(color: UIColor, symbol: String, distance: Int?) -> UIImage {
            let hasLabel = distance != nil
            let w: CGFloat = hasLabel ? 48 : 18
            let h: CGFloat = hasLabel ? 32 : 18
            return UIGraphicsImageRenderer(size: CGSize(width: w, height: h)).image { ctx in
                let iconS: CGFloat = 16
                let iconX = (w - iconS) / 2
                // Glow
                color.withAlphaComponent(0.25).setFill()
                ctx.cgContext.fillEllipse(in: CGRect(x: iconX - 3, y: -3, width: iconS + 6, height: iconS + 6))
                // Icon circle
                color.setFill()
                ctx.cgContext.fillEllipse(in: CGRect(x: iconX, y: 0, width: iconS, height: iconS))
                UIColor.white.withAlphaComponent(0.8).setStroke()
                ctx.cgContext.setLineWidth(1.5)
                ctx.cgContext.strokeEllipse(in: CGRect(x: iconX + 0.75, y: 0.75, width: iconS - 1.5, height: iconS - 1.5))

                if let dist = distance {
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 9, weight: .heavy),
                        .foregroundColor: color
                    ]
                    let str = NSAttributedString(string: "\(dist)y", attributes: attrs)
                    let strSize = str.size()
                    // Background pill
                    let pillW = strSize.width + 8
                    let pillH = strSize.height + 3
                    let pillX = (w - pillW) / 2
                    let pillY = iconS + 2
                    UIColor(white: 0.05, alpha: 0.8).setFill()
                    UIBezierPath(roundedRect: CGRect(x: pillX, y: pillY, width: pillW, height: pillH), cornerRadius: pillH / 2).fill()
                    str.draw(at: CGPoint(x: (w - strSize.width) / 2, y: pillY + 1.5))
                }
            }
        }

        // MARK: Line renderer

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let ring = overlay as? LayupRing {
                return LayupRingRenderer.renderer(for: ring)
            }

            guard let polyline = overlay as? GolfPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }

            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.lineCap = .round
            renderer.lineJoin = .round

            switch (polyline.lineType, polyline.glowLayer) {

            // ── User to green: green laser glow ──
            case (.userToGreen, .outerGlow):
                renderer.strokeColor = UIColor.systemGreen.withAlphaComponent(0.08)
                renderer.lineWidth = 18
            case (.userToGreen, .innerGlow):
                renderer.strokeColor = UIColor.systemGreen.withAlphaComponent(0.2)
                renderer.lineWidth = 6
            case (.userToGreen, .core):
                renderer.strokeColor = UIColor.systemGreen.withAlphaComponent(0.85)
                renderer.lineWidth = 2.5

            // ── User to target: white laser ──
            case (.userToTarget, .outerGlow):
                renderer.strokeColor = UIColor.white.withAlphaComponent(0.06)
                renderer.lineWidth = 20
            case (.userToTarget, .innerGlow):
                renderer.strokeColor = UIColor.white.withAlphaComponent(0.15)
                renderer.lineWidth = 8
            case (.userToTarget, .core):
                renderer.strokeColor = UIColor.white.withAlphaComponent(0.9)
                renderer.lineWidth = 2.5

            // ── Target to green: faint dashed ──
            case (.targetToGreen, _):
                renderer.strokeColor = UIColor.white.withAlphaComponent(0.25)
                renderer.lineWidth = 1.5
                renderer.lineDashPattern = [6, 6]

            default:
                renderer.strokeColor = UIColor.white.withAlphaComponent(0.15)
                renderer.lineWidth = 1
            }

            return renderer
        }
    }
}

// MARK: - Custom Annotation

class GolfAnnotation: MKPointAnnotation {
    enum AnnotationType: String {
        case user, tee, greenCenter, greenFront, greenBack, bunker, water, target, caddyTarget
    }

    let type: AnnotationType
    var distance: Int?
    var secondaryDistance: Int?
    var frontDistance: Int?
    var backDistance: Int?

    init(coordinate: CLLocationCoordinate2D, type: AnnotationType) {
        self.type = type
        super.init()
        self.coordinate = coordinate
    }
}

// MARK: - Custom Polyline

class GolfPolyline: MKPolyline {
    enum LineType { case userToGreen, userToTarget, targetToGreen, none }
    enum GlowLayer: CaseIterable { case outerGlow, innerGlow, core }
    var lineType: LineType = .none
    var glowLayer: GlowLayer = .core
}

