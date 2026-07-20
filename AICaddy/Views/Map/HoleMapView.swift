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
    /// Point to measure distances from (tee before first shot, user GPS after)
    var distanceMeasurePoint: CLLocationCoordinate2D? = nil
    /// Course center — the framing fallback when a hole has no GPS data.
    /// Without it the camera centered on the USER, which at home/in the
    /// simulator meant a random city instead of the golf course.
    var courseLocation: CLLocationCoordinate2D? = nil
    var caddyTarget: CLLocationCoordinate2D? = nil
    var caddyTargetLabel: String? = nil
    var onCaddyTargetDragged: ((CLLocationCoordinate2D) -> Void)? = nil
    /// Hole-mapping mode: taps place the tee then the green
    var isMappingMode: Bool = false
    var onMapTap: ((CLLocationCoordinate2D) -> Void)? = nil
    var mappingPreviewTee: CLLocationCoordinate2D? = nil
    /// Reports the long-press target — "my ball is here" (nil when cleared)
    var onTargetPlaced: ((CLLocationCoordinate2D?) -> Void)? = nil

    @State private var dragTarget: CLLocationCoordinate2D?
    @State private var followUser = false
    @State private var showLayupRings = false
    @State private var mapStyle: MapStyle = .satellite
    @State private var is3DView = false

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
            // Plain .standard/.hybrid — the muted/flyover variants render
            // through a different GPU path that draws solid red in the
            // simulator (and flaky on some devices).
            case .standard: return .standard
            case .hybrid: return .hybrid
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
                mapStyle: is3DView ? .satelliteFlyover : mapStyle.mkMapType,
                distanceMeasurePoint: distanceMeasurePoint,
                courseLocation: courseLocation,
                caddyTarget: caddyTarget,
                caddyTargetLabel: caddyTargetLabel,
                onCaddyTargetDragged: onCaddyTargetDragged,
                is3DView: is3DView,
                isMappingMode: isMappingMode,
                onMapTap: onMapTap,
                mappingPreviewTee: mappingPreviewTee
            )
            .ignoresSafeArea()

            // Floating controls — right side
            VStack {
                Spacer().frame(height: 160)
                VStack(spacing: 6) {
                    MapButton(icon: mapStyle.icon) {
                        withAnimation(.easeInOut(duration: 0.2)) { mapStyle = mapStyle.next }
                    }
                    MapButton(icon: is3DView ? "view.3d" : "view.2d") {
                        is3DView.toggle()
                        // Re-frame the hole with the new perspective
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            NotificationCenter.default.post(name: .fitHole, object: nil)
                        }
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
            .padding(.trailing, 8)

            // Clear target button — small X floating near top
            if dragTarget != nil {
                VStack {
                    Spacer().frame(height: 140)
                    HStack {
                        Button {
                            withAnimation { dragTarget = nil }
                            onTargetPlaced?(nil)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                                Text("Clear ball mark")
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
            } else if !isMappingMode && holeGps != nil {
                // Discoverability: nobody knew the long-press marker existed
                VStack {
                    Spacer()
                    Text("HOLD MAP TO MARK YOUR BALL")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.4))
                        .clipShape(Capsule())
                        .padding(.bottom, 210)
                }
                .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: dragTarget != nil)
        .onChange(of: dragTarget?.latitude) { _, _ in
            onTargetPlaced?(dragTarget)
        }
    }

}

// MARK: - Floating Map Button

private struct MapButton: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Color.black.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - Distance Pill

struct DistancePill: View {
    let label: String
    let yards: Int
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(label.uppercased())
                .font(Theme.Font.caption(9))
                .foregroundStyle(Theme.Colors.textMuted)
                .tracking(1)
            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text("\(yards)")
                    .font(Theme.Font.display(22))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .contentTransition(.numericText())
                Text("y")
                    .font(Theme.Font.label(11))
                    .foregroundStyle(Theme.Colors.textMuted)
                    .baselineOffset(-2)
            }
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
    var distanceMeasurePoint: CLLocationCoordinate2D? = nil
    var courseLocation: CLLocationCoordinate2D? = nil
    var caddyTarget: CLLocationCoordinate2D? = nil
    var caddyTargetLabel: String? = nil
    var onCaddyTargetDragged: ((CLLocationCoordinate2D) -> Void)? = nil
    var is3DView: Bool = false
    var flyoverOnAppear: Bool = true
    /// Hole-mapping mode: single taps report coordinates (for placing tee/green)
    var isMappingMode: Bool = false
    var onMapTap: ((CLLocationCoordinate2D) -> Void)? = nil
    /// Shows the just-tapped tee while the user picks the green
    var mappingPreviewTee: CLLocationCoordinate2D? = nil

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

        // Single tap for hole-mapping mode (placing tee/green)
        let singleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleSingleTap(_:))
        )
        singleTap.isEnabled = isMappingMode
        mapView.addGestureRecognizer(singleTap)
        context.coordinator.mappingTapRecognizer = singleTap

        // Double tap to zoom (ensure it doesn't conflict)
        for gesture in mapView.gestureRecognizers ?? [] {
            if let doubleTap = gesture as? UITapGestureRecognizer, doubleTap.numberOfTapsRequired == 2 {
                longPress.require(toFail: doubleTap)
                singleTap.require(toFail: doubleTap)
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
        // Track initial hole so updateUIView doesn't double-trigger
        context.coordinator.currentHoleTee = holeGps?.tee
        context.coordinator.currentHoleGreen = holeGps?.greenCenter

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
        context.coordinator.mappingTapRecognizer?.isEnabled = isMappingMode
        if mapView.mapType != mapStyle {
            mapView.mapType = mapStyle
        }

        // Detect hole change and reframe the camera
        let newTee = holeGps?.tee
        let newGreen = holeGps?.greenCenter
        let coord = context.coordinator
        if newTee != coord.currentHoleTee || newGreen != coord.currentHoleGreen {
            coord.currentHoleTee = newTee
            coord.currentHoleGreen = newGreen
            coord.hasFlyoverPlayed = false
            // Small delay so the view settles before animating
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                if self.flyoverOnAppear {
                    coord.flyoverHole()
                } else {
                    coord.fitHole()
                }
            }
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
        } else {
            // Continuous reframe as the player moves down the hole: the player
            // stays at the bottom of the screen with the target ahead, instead
            // of the camera sitting wherever the hole started.
            coord.reframeIfPlayerMoved(on: mapView)
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: NativeMapView
        weak var mapView: MKMapView?
        weak var mappingTapRecognizer: UITapGestureRecognizer?
        private var targetAnnotation: MKPointAnnotation?
        private var isDraggingTarget = false
        var hasFlyoverPlayed = false
        /// Track current hole identity so we can reframe when the hole changes
        var currentHoleTee: GpsPoint?
        var currentHoleGreen: GpsPoint?
        /// The origin (player position) the camera last framed from
        var lastFramedOrigin: CLLocationCoordinate2D?

        init(parent: NativeMapView) {
            self.parent = parent
        }

        /// Re-run the hole framing when the player has moved meaningfully.
        /// Skipped while the user is actively touching the map so we don't
        /// fight their pan/zoom.
        func reframeIfPlayerMoved(on mapView: MKMapView) {
            guard let origin = parent.distanceMeasurePoint ?? parent.userLocation,
                  let last = lastFramedOrigin else { return }
            let moved = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
                .distance(from: CLLocation(latitude: last.latitude, longitude: last.longitude))
            guard moved > 15 else { return }
            guard !isUserInteracting(mapView) else { return }
            fitHole()
        }

        private func isUserInteracting(_ mapView: MKMapView) -> Bool {
            let recognizers = (mapView.gestureRecognizers ?? [])
                + (mapView.subviews.first?.gestureRecognizers ?? [])
            return recognizers.contains { $0.state == .began || $0.state == .changed }
        }

        // MARK: Single tap → hole mapping (place tee/green)

        @objc func handleSingleTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView, parent.isMappingMode else { return }
            let point = gesture.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            parent.onMapTap?(coordinate)
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

        // MARK: Fit hole — frame from current position to target

        @objc func fitHole() {
            guard let mapView else { return }

            guard let gps = parent.holeGps, let tee = gps.tee, let green = gps.greenCenter else {
                // No hole GPS data — show the COURSE, never the user's location
                // (at home or in the simulator that's a random city).
                lastFramedOrigin = parent.distanceMeasurePoint ?? parent.userLocation
                if let course = parent.courseLocation {
                    let region = MKCoordinateRegion(center: course, latitudinalMeters: 1200, longitudinalMeters: 1200)
                    mapView.setRegion(region, animated: true)
                } else if let loc = parent.userLocation {
                    let region = MKCoordinateRegion(center: loc, latitudinalMeters: 300, longitudinalMeters: 300)
                    mapView.setRegion(region, animated: true)
                }
                return
            }

            // Bottom of screen: where the player is (user location or tee).
            // If the player is nowhere near this hole (previewing from home,
            // browsing holes, GPS hiccup), frame the hole itself — the view
            // must always open as the hole overview, not wherever you're standing.
            var bottomPoint = parent.distanceMeasurePoint ?? parent.userLocation ?? tee.coordinate
            let bottomLoc = CLLocation(latitude: bottomPoint.latitude, longitude: bottomPoint.longitude)
            let distToTee = bottomLoc.distance(from: CLLocation(latitude: tee.lat, longitude: tee.lng))
            let distToGreenRef = bottomLoc.distance(from: CLLocation(latitude: green.lat, longitude: green.lng))
            if min(distToTee, distToGreenRef) > 1000 {  // >1000m from the hole = not playing it
                bottomPoint = tee.coordinate
            }
            lastFramedOrigin = bottomPoint

            // Distance from player to green
            let distToGreen = CLLocation(latitude: bottomPoint.latitude, longitude: bottomPoint.longitude)
                .distance(from: CLLocation(latitude: green.lat, longitude: green.lng))

            // Top of screen: pick the target we're hitting toward
            // If within ~275y (250m) of green, frame to the green
            // Otherwise use caddy target if available, or a point ~300y ahead along the hole line
            let topPoint: CLLocationCoordinate2D
            let inGreenRange = distToGreen < 250 // meters (~275 yards)

            if inGreenRange {
                topPoint = green.coordinate
            } else if let caddy = parent.caddyTarget {
                topPoint = caddy
            } else {
                // No caddy target and far from green — frame ~300y (275m) ahead along tee→green line
                let holeDist = CLLocation(latitude: tee.lat, longitude: tee.lng)
                    .distance(from: CLLocation(latitude: green.lat, longitude: green.lng))
                let fraction = min(275.0 / max(holeDist, 1), 1.0)
                let aheadLat = bottomPoint.latitude + (green.lat - tee.lat) / max(holeDist, 1) * 275
                let aheadLng = bottomPoint.longitude + (green.lng - tee.lng) / max(holeDist, 1) * 275
                topPoint = CLLocationCoordinate2D(latitude: aheadLat, longitude: aheadLng)
            }

            // Bearing: point toward the current target (tee → caddy aim when present,
            // falling back to tee → green). This keeps doglegs oriented along the
            // fairway the player is actually aiming down.
            let bearingDest = parent.caddyTarget ?? green.coordinate
            let bearing = Self.bearing(from: tee.coordinate, to: bearingDest)

            // Distance between the two frame points
            let frameDist = CLLocation(latitude: bottomPoint.latitude, longitude: bottomPoint.longitude)
                .distance(from: CLLocation(latitude: topPoint.latitude, longitude: topPoint.longitude))

            // Bottom chrome is slim (club button + thin panel). Push the midpoint
            // closer to the top so the tee sits just above the bottom chrome and
            // the target hugs the top overlay.
            let centerLat = bottomPoint.latitude + (topPoint.latitude - bottomPoint.latitude) * 0.48
            let centerLng = bottomPoint.longitude + (topPoint.longitude - bottomPoint.longitude) * 0.48
            let center = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLng)

            // Tighter altitude so the hole fills more of the visible map
            let altitude = max(frameDist * 3.2, 380)

            let camera: MKMapCamera
            if parent.is3DView {
                let eyePoint = bottomPoint  // same far-from-hole guard as 2D
                let lookAt = green.coordinate
                let behindLat = eyePoint.latitude - (lookAt.latitude - eyePoint.latitude) * 0.15
                let behindLng = eyePoint.longitude - (lookAt.longitude - eyePoint.longitude) * 0.15
                let behindPoint = CLLocationCoordinate2D(latitude: behindLat, longitude: behindLng)

                camera = MKMapCamera(
                    lookingAtCenter: behindPoint,
                    fromDistance: max(frameDist * 1.8, 300),
                    pitch: 55,
                    heading: bearing
                )
            } else {
                camera = MKMapCamera(
                    lookingAtCenter: center,
                    fromDistance: altitude,
                    pitch: 0,
                    heading: bearing
                )
            }
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

            // Camera 3: Settle into the standard fitHole view (arrives at 3s)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
                self?.fitHole()
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

            // Mapping preview: show the tee the user just placed
            if let previewTee = parent.mappingPreviewTee {
                mapView.addAnnotation(GolfAnnotation(coordinate: previewTee, type: .tee))
            }

            guard let gps = parent.holeGps else { return }

            // Tee
            if let tee = gps.tee {
                mapView.addAnnotation(GolfAnnotation(coordinate: tee.coordinate, type: .tee))
            }

            // Green with distance labels (from tee before first shot, from user after)
            if let green = gps.greenCenter {
                let measureFrom = parent.distanceMeasurePoint ?? parent.userLocation
                let ann = GolfAnnotation(coordinate: green.coordinate, type: .greenCenter)
                ann.distance = measureFrom.map {
                    LocationService.distanceYards(from: $0, to: green.coordinate)
                }
                ann.frontDistance = measureFrom.flatMap { loc in
                    gps.greenFront.map { LocationService.distanceYards(from: loc, to: $0.coordinate) }
                }
                ann.backDistance = measureFrom.flatMap { loc in
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
                let measureFrom = parent.distanceMeasurePoint ?? parent.userLocation
                ann.title = hazard.label
                ann.distance = measureFrom.map {
                    LocationService.distanceYards(from: $0, to: hazard.position.coordinate)
                }
                mapView.addAnnotation(ann)
            }

            // AI Caddy suggested target (stays visible alongside a manual target)
            if let caddy = parent.caddyTarget {
                let measureFrom = parent.distanceMeasurePoint ?? parent.userLocation
                let ann = GolfAnnotation(coordinate: caddy, type: .caddyTarget)
                ann.distance = measureFrom.map {
                    LocationService.distanceYards(from: $0, to: caddy)
                }
                ann.secondaryDistance = gps.greenCenter.map {
                    LocationService.distanceYards(from: caddy, to: $0.coordinate)
                }
                ann.label = parent.caddyTargetLabel
                mapView.addAnnotation(ann)
            }

            // Drag target
            if let target = parent.dragTarget {
                let measureFrom = parent.distanceMeasurePoint ?? parent.userLocation
                let ann = GolfAnnotation(coordinate: target, type: .target)
                ann.distance = measureFrom.map {
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

            // Use tee as origin before first shot, user GPS after
            guard let origin = parent.distanceMeasurePoint ?? parent.userLocation else { return }

            // Line: origin → green (3-layer glow)
            if let green = parent.holeGps?.greenCenter {
                let coords = [origin, green.coordinate]
                for layer in GolfPolyline.GlowLayer.allCases {
                    let line = GolfPolyline(coordinates: coords, count: coords.count)
                    line.lineType = .userToGreen
                    line.glowLayer = layer
                    mapView.addOverlay(line)
                }
            }

            // Line: origin → caddy target (always shown when a caddy target exists)
            if let caddy = parent.caddyTarget {
                let coords = [origin, caddy]
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

            // Manual drag target: no lines — just the floating scope/distance card.

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

            // ── Green: rendered flag with pin-distance pill above ──
            case .greenCenter:
                let flagW: CGFloat = 28
                let flagH: CGFloat = 38
                let pillH: CGFloat = 16
                let pillGap: CGFloat = 3
                let accentGold = UIColor(red: 0.961, green: 0.773, blue: 0.094, alpha: 1)
                let navyFill = UIColor(red: 0.118, green: 0.165, blue: 0.227, alpha: 0.95)
                let borderColor = UIColor.white.withAlphaComponent(0.15)

                let pinText: String? = golfAnn.distance.map { "\($0)YDS" }
                let pillAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 9, weight: .heavy),
                    .foregroundColor: accentGold,
                    .kern: 0.5
                ]
                let pillTextSize = pinText.map { NSAttributedString(string: $0, attributes: pillAttrs).size() } ?? .zero
                let pillW = pinText == nil ? 0 : max(flagW + 6, pillTextSize.width + 14)

                let totalW = max(flagW, pillW)
                let totalH = flagH + (pinText == nil ? 0 : pillGap + pillH)

                let img = UIGraphicsImageRenderer(size: CGSize(width: totalW, height: totalH)).image { ctx in
                    let c = ctx.cgContext

                    // Pin-distance pill (above the flag)
                    if let pinText {
                        let pillX = (totalW - pillW) / 2
                        let pillY: CGFloat = 0
                        let pillRect = CGRect(x: pillX, y: pillY, width: pillW, height: pillH)
                        c.setFillColor(navyFill.cgColor)
                        let pillPath = UIBezierPath(roundedRect: pillRect, cornerRadius: pillH / 2)
                        c.addPath(pillPath.cgPath)
                        c.fillPath()
                        c.setStrokeColor(borderColor.cgColor)
                        c.setLineWidth(1)
                        c.addPath(pillPath.cgPath)
                        c.strokePath()

                        let str = NSAttributedString(string: pinText, attributes: pillAttrs)
                        let strSize = str.size()
                        str.draw(at: CGPoint(x: pillX + (pillW - strSize.width) / 2, y: pillY + (pillH - strSize.height) / 2))
                    }

                    // Flag (below the pill)
                    let flagX = (totalW - flagW) / 2
                    let flagY = pinText == nil ? 0 : pillH + pillGap
                    // Pole
                    c.setStrokeColor(UIColor.white.cgColor)
                    c.setLineWidth(2)
                    c.move(to: CGPoint(x: flagX + flagW / 2, y: flagY + 4))
                    c.addLine(to: CGPoint(x: flagX + flagW / 2, y: flagY + flagH - 2))
                    c.strokePath()
                    // Flag
                    c.setFillColor(UIColor.systemRed.cgColor)
                    c.move(to: CGPoint(x: flagX + flagW / 2 + 1, y: flagY + 4))
                    c.addLine(to: CGPoint(x: flagX + flagW / 2 + 13, y: flagY + 10))
                    c.addLine(to: CGPoint(x: flagX + flagW / 2 + 1, y: flagY + 16))
                    c.closePath()
                    c.fillPath()
                    // Base
                    c.setFillColor(UIColor.systemGreen.withAlphaComponent(0.4).cgColor)
                    c.fillEllipse(in: CGRect(x: flagX + flagW / 2 - 8, y: flagY + flagH - 10, width: 16, height: 10))
                    c.setFillColor(UIColor.white.cgColor)
                    c.fillEllipse(in: CGRect(x: flagX + flagW / 2 - 3, y: flagY + flagH - 6, width: 6, height: 4))
                }
                view.image = img
                view.frame.size = CGSize(width: totalW, height: totalH)
                // Anchor so the flag base sits on the green center coordinate
                view.centerOffset = CGPoint(x: 0, y: -totalH / 2 + 4)

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

            // ── AI Caddy target: gold ring with yards + yards-to-pin pills below ──
            case .caddyTarget:
                let img = Self.makeCaddyTargetImage(
                    distance: golfAnn.distance,
                    secondaryDistance: golfAnn.secondaryDistance
                )
                view.image = img
                view.frame.size = img.size
                // Anchor so the ring center sits on the target coordinate
                view.centerOffset = CGPoint(
                    x: 0,
                    y: img.size.height / 2 - (Self.caddyRingPad + Self.caddyRingSize / 2)
                )
                view.isUserInteractionEnabled = true
                view.gestureRecognizers?.forEach { view.removeGestureRecognizer($0) }
                // Zero-duration long press fires on touch-down and beats the map's own pan.
                let touch = UILongPressGestureRecognizer(target: self, action: #selector(handleCaddyDrag(_:)))
                touch.minimumPressDuration = 0
                touch.allowableMovement = .greatestFiniteMagnitude
                touch.cancelsTouchesInView = true
                touch.delaysTouchesBegan = false
                view.addGestureRecognizer(touch)

            // ── Manual target: white ring with compact yards pill below ──
            case .target:
                let ringSize: CGFloat = 28
                let pillH: CGFloat = 16
                let pillGap: CGFloat = 3
                let navyFill = UIColor(red: 0.118, green: 0.165, blue: 0.227, alpha: 0.95)
                let borderColor = UIColor.white.withAlphaComponent(0.15)

                let pillText: String? = golfAnn.distance.map { "\($0)YDS" }
                let pillAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 9, weight: .heavy),
                    .foregroundColor: UIColor.white,
                    .kern: 0.5
                ]
                let pillTextSize = pillText.map { NSAttributedString(string: $0, attributes: pillAttrs).size() } ?? .zero
                let pillW = pillText == nil ? 0 : max(ringSize + 4, pillTextSize.width + 14)

                let totalW = max(ringSize, pillW)
                let totalH = ringSize + (pillText == nil ? 0 : pillGap + pillH)

                let img = UIGraphicsImageRenderer(size: CGSize(width: totalW, height: totalH)).image { ctx in
                    let c = ctx.cgContext

                    // Ring
                    let ringX = (totalW - ringSize) / 2
                    c.setFillColor(UIColor.white.withAlphaComponent(0.15).cgColor)
                    c.fillEllipse(in: CGRect(x: ringX, y: 0, width: ringSize, height: ringSize))
                    c.setStrokeColor(UIColor.white.cgColor)
                    c.setLineWidth(2.5)
                    c.strokeEllipse(in: CGRect(x: ringX + 3, y: 3, width: ringSize - 6, height: ringSize - 6))
                    let dotS: CGFloat = 5
                    c.setFillColor(UIColor.white.cgColor)
                    c.fillEllipse(in: CGRect(x: ringX + (ringSize - dotS) / 2, y: (ringSize - dotS) / 2, width: dotS, height: dotS))

                    // Pill
                    if let pillText {
                        let pillX = (totalW - pillW) / 2
                        let pillY = ringSize + pillGap
                        let pillRect = CGRect(x: pillX, y: pillY, width: pillW, height: pillH)
                        c.setFillColor(navyFill.cgColor)
                        let pillPath = UIBezierPath(roundedRect: pillRect, cornerRadius: pillH / 2)
                        c.addPath(pillPath.cgPath)
                        c.fillPath()
                        c.setStrokeColor(borderColor.cgColor)
                        c.setLineWidth(1)
                        c.addPath(pillPath.cgPath)
                        c.strokePath()
                        let str = NSAttributedString(string: pillText, attributes: pillAttrs)
                        let strSize = str.size()
                        str.draw(at: CGPoint(x: pillX + (pillW - strSize.width) / 2, y: pillY + (pillH - strSize.height) / 2))
                    }
                }

                view.image = img
                view.frame.size = CGSize(width: totalW, height: totalH)
                view.centerOffset = CGPoint(x: 0, y: (totalH - ringSize) / 2)
            }

            return view
        }

        // MARK: - Rendering helpers

        // MARK: - Caddy target rendering

        static let caddyRingSize: CGFloat = 30
        static let caddyRingPad: CGFloat = 22

        static func makeCaddyTargetImage(distance: Int?, secondaryDistance: Int?) -> UIImage {
            let ringSize = caddyRingSize
            let ringPad = caddyRingPad
            let pillH: CGFloat = 16
            let pillGap: CGFloat = 3
            let pillSpacing: CGFloat = 2
            let accentGold = UIColor(red: 0.961, green: 0.773, blue: 0.094, alpha: 1)
            let navyFill = UIColor(red: 0.118, green: 0.165, blue: 0.227, alpha: 0.95)
            let borderColor = UIColor.white.withAlphaComponent(0.15)

            let yardsText: String? = distance.map { "\($0)YDS" }
            let pinText: String? = secondaryDistance.map { "\($0) TO PIN" }

            let pillAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 9, weight: .heavy),
                .foregroundColor: accentGold,
                .kern: 0.5
            ]
            let subAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 8, weight: .heavy),
                .foregroundColor: UIColor.white.withAlphaComponent(0.7),
                .kern: 0.3
            ]

            let yardsSize = yardsText.map { NSAttributedString(string: $0, attributes: pillAttrs).size() } ?? .zero
            let pinSize = pinText.map { NSAttributedString(string: $0, attributes: subAttrs).size() } ?? .zero
            let yardsPillW = yardsText == nil ? 0 : max(ringSize + 4, yardsSize.width + 14)
            let pinPillW = pinText == nil ? 0 : pinSize.width + 12

            let ringBoxSize = ringSize + ringPad * 2
            let totalW = max(ringBoxSize, max(yardsPillW, pinPillW))
            var totalH = ringBoxSize
            if yardsText != nil { totalH += pillGap + pillH }
            if pinText != nil { totalH += pillSpacing + pillH }

            return UIGraphicsImageRenderer(size: CGSize(width: totalW, height: totalH)).image { ctx in
                let c = ctx.cgContext

                // Ring (centered within padded box)
                let ringX = (totalW - ringSize) / 2
                let ringY = ringPad
                c.setFillColor(accentGold.withAlphaComponent(0.18).cgColor)
                c.fillEllipse(in: CGRect(x: ringX, y: ringY, width: ringSize, height: ringSize))
                c.setStrokeColor(accentGold.cgColor)
                c.setLineWidth(2.5)
                c.strokeEllipse(in: CGRect(x: ringX + 3, y: ringY + 3, width: ringSize - 6, height: ringSize - 6))
                let dotS: CGFloat = 5
                c.setFillColor(accentGold.cgColor)
                c.fillEllipse(in: CGRect(x: ringX + (ringSize - dotS) / 2, y: ringY + (ringSize - dotS) / 2, width: dotS, height: dotS))

                var cursorY: CGFloat = ringBoxSize + pillGap

                // Yards pill
                if let yardsText {
                    let pillX = (totalW - yardsPillW) / 2
                    let pillRect = CGRect(x: pillX, y: cursorY, width: yardsPillW, height: pillH)
                    c.setFillColor(navyFill.cgColor)
                    let pillPath = UIBezierPath(roundedRect: pillRect, cornerRadius: pillH / 2)
                    c.addPath(pillPath.cgPath)
                    c.fillPath()
                    c.setStrokeColor(borderColor.cgColor)
                    c.setLineWidth(1)
                    c.addPath(pillPath.cgPath)
                    c.strokePath()
                    let str = NSAttributedString(string: yardsText, attributes: pillAttrs)
                    let strSize = str.size()
                    str.draw(at: CGPoint(x: pillX + (yardsPillW - strSize.width) / 2, y: cursorY + (pillH - strSize.height) / 2))
                    cursorY += pillH + pillSpacing
                }

                // To-pin pill
                if let pinText {
                    let pillX = (totalW - pinPillW) / 2
                    let pillRect = CGRect(x: pillX, y: cursorY, width: pinPillW, height: pillH)
                    c.setFillColor(navyFill.withAlphaComponent(0.75).cgColor)
                    let pillPath = UIBezierPath(roundedRect: pillRect, cornerRadius: pillH / 2)
                    c.addPath(pillPath.cgPath)
                    c.fillPath()
                    let str = NSAttributedString(string: pinText, attributes: subAttrs)
                    let strSize = str.size()
                    str.draw(at: CGPoint(x: pillX + (pinPillW - strSize.width) / 2, y: cursorY + (pillH - strSize.height) / 2))
                }
            }
        }

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

        // MARK: Draggable caddy target (immediate touch-down)

        @objc func handleCaddyDrag(_ gesture: UILongPressGestureRecognizer) {
            guard let view = gesture.view as? MKAnnotationView,
                  let mapView = self.mapView,
                  let ann = view.annotation as? GolfAnnotation,
                  ann.type == .caddyTarget else { return }

            let point = gesture.location(in: mapView)
            let coord = mapView.convert(point, toCoordinateFrom: mapView)

            switch gesture.state {
            case .began:
                mapView.isScrollEnabled = false
                mapView.isZoomEnabled = false
                ann.coordinate = coord
                refreshCaddyTargetImage(view: view, ann: ann, coord: coord)
            case .changed:
                ann.coordinate = coord
                refreshCaddyTargetImage(view: view, ann: ann, coord: coord)
            case .ended, .cancelled, .failed:
                mapView.isScrollEnabled = true
                mapView.isZoomEnabled = true
                parent.onCaddyTargetDragged?(coord)
            default:
                break
            }
        }

        private func refreshCaddyTargetImage(view: MKAnnotationView, ann: GolfAnnotation, coord: CLLocationCoordinate2D) {
            let origin = parent.distanceMeasurePoint ?? parent.userLocation
            let newDistance = origin.map { LocationService.distanceYards(from: $0, to: coord) }
            let newPinDist = parent.holeGps?.greenCenter.map {
                LocationService.distanceYards(from: coord, to: $0.coordinate)
            }
            ann.distance = newDistance
            ann.secondaryDistance = newPinDist
            view.image = Self.makeCaddyTargetImage(distance: newDistance, secondaryDistance: newPinDist)
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
    var label: String?

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

