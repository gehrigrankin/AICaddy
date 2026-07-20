#if DEBUG
import SwiftUI
import CoreLocation

/// Debug-only bar for simulating GPS position at tee, fairway, approach, or green.
/// Lets you test distance calculations and the full round flow in the simulator.
struct DebugLocationBar: View {
    let locationService: LocationService
    let holeGps: HoleGps?
    /// Course center — teleport target when the hole has no GPS data.
    var courseLocation: CLLocationCoordinate2D? = nil
    /// Where the player marked their shot (the aim target) — the "ball".
    var ballTarget: CLLocationCoordinate2D? = nil

    @State private var expanded = false
    @State private var walkProgress: Double = 0 // 0 = tee, 1 = green

    var body: some View {
        VStack(spacing: 0) {
            // Toggle bar
            Button {
                withAnimation(.spring(duration: 0.25)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "location.viewfinder")
                        .font(.system(size: 10))
                    Text("SIM")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                    if locationService.simulatedLocation != nil {
                        Circle()
                            .fill(.orange)
                            .frame(width: 6, height: 6)
                    }
                    Image(systemName: expanded ? "chevron.down" : "chevron.up")
                        .font(.system(size: 8))
                }
                .foregroundStyle(.orange)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
            }

            if expanded {
                VStack(spacing: 8) {
                    if let gps = holeGps {
                        // Quick teleport buttons
                        HStack(spacing: 6) {
                            SimButton(label: "Tee Box", icon: "figure.golf") {
                                if let tee = gps.tee {
                                    walkProgress = 0
                                    locationService.simulatedLocation = tee.coordinate
                                }
                            }
                            .disabled(gps.tee == nil)

                            SimButton(label: "150 Out", icon: "scope") {
                                teleportToApproach(gps: gps, yardsOut: 150)
                            }
                            .disabled(gps.tee == nil || gps.greenCenter == nil)

                            SimButton(label: "50 Out", icon: "target") {
                                teleportToApproach(gps: gps, yardsOut: 50)
                            }
                            .disabled(gps.tee == nil || gps.greenCenter == nil)

                            SimButton(label: "Green", icon: "flag.fill") {
                                if let green = gps.greenCenter {
                                    walkProgress = 1
                                    locationService.simulatedLocation = green.coordinate
                                }
                            }
                            .disabled(gps.greenCenter == nil)
                        }

                        // Drive the cart to the marked ball (aim target)
                        if ballTarget != nil {
                            SimButton(label: "Drive to Ball", icon: "car.fill") {
                                if let ball = ballTarget {
                                    locationService.simulateDrive(to: ball)
                                }
                            }
                        }

                        // Walk slider — smoothly interpolate tee to green
                        if gps.tee != nil && gps.greenCenter != nil {
                            VStack(spacing: 2) {
                                HStack {
                                    Text("Tee").font(.system(size: 8)).foregroundStyle(.white.opacity(0.5))
                                    Slider(value: $walkProgress, in: 0...1)
                                        .tint(.orange)
                                        .onChange(of: walkProgress) { _, newValue in
                                            interpolatePosition(gps: gps, progress: newValue)
                                        }
                                    Text("Green").font(.system(size: 8)).foregroundStyle(.white.opacity(0.5))
                                }
                                if let dist = distanceToGreen(gps: gps) {
                                    Text("\(dist) yds to green")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(.orange.opacity(0.8))
                                }
                            }
                        }
                    } else {
                        Text("No GPS data for this hole")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.5))

                        HStack(spacing: 6) {
                            // Still useful without hole GPS: stand on the course
                            if let course = courseLocation {
                                SimButton(label: "Course", icon: "flag.circle") {
                                    locationService.simulatedLocation = course
                                }
                            }
                            SimButton(label: "Pebble Beach", icon: "mappin") {
                                // Hole 7 tee at Pebble Beach
                                locationService.simulatedLocation = CLLocationCoordinate2D(
                                    latitude: 36.5685, longitude: -121.9507
                                )
                            }
                            SimButton(label: "Augusta #12", icon: "mappin") {
                                // Golden Bell tee
                                locationService.simulatedLocation = CLLocationCoordinate2D(
                                    latitude: 33.5030, longitude: -82.0228
                                )
                            }
                        }
                    }

                    // Clear simulation
                    if locationService.simulatedLocation != nil {
                        Button {
                            locationService.simulatedLocation = nil
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 10))
                                Text("Use Real GPS")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundStyle(.red.opacity(0.8))
                        }
                    }
                }
                .padding(10)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 2)
    }

    // MARK: - Helpers

    private func teleportToApproach(gps: HoleGps, yardsOut: Int) {
        guard let tee = gps.tee, let green = gps.greenCenter else { return }
        let totalYards = LocationService.distanceYards(
            from: tee.coordinate, to: green.coordinate
        )
        guard totalYards > 0 else { return }
        let progress = max(0, min(1, Double(totalYards - yardsOut) / Double(totalYards)))
        walkProgress = progress
        interpolatePosition(gps: gps, progress: progress)
    }

    private func interpolatePosition(gps: HoleGps, progress: Double) {
        guard let tee = gps.tee, let green = gps.greenCenter else { return }
        let lat = tee.lat + (green.lat - tee.lat) * progress
        let lng = tee.lng + (green.lng - tee.lng) * progress
        locationService.simulatedLocation = CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    private func distanceToGreen(gps: HoleGps) -> Int? {
        guard let loc = locationService.simulatedLocation ?? locationService.location,
              let green = gps.greenCenter else { return nil }
        return LocationService.distanceYards(from: loc, to: green.coordinate)
    }
}

private struct SimButton: View {
    let label: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(label)
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(.orange.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}
#endif
