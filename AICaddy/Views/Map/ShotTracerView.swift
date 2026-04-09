import SwiftUI
import MapKit
import CoreLocation

/// Overlay shot traces on the hole map — draw actual shot paths
struct ShotTracerView: View {
    let shots: [ShotLocation]
    let holeGps: HoleGps?

    @State private var mapPosition: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $mapPosition) {
            // Shot traces
            ForEach(Array(shots.enumerated()), id: \.offset) { i, shot in
                // Shot path line
                MapPolyline(coordinates: [
                    shot.start.coordinate,
                    shot.end.coordinate
                ])
                .stroke(colorForShot(i), lineWidth: 3)

                // Start point
                Annotation("Shot \(i + 1)", coordinate: shot.start.coordinate) {
                    ZStack {
                        Circle().fill(colorForShot(i)).frame(width: 12, height: 12)
                        Text("\(i + 1)")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }

                // End point with distance label
                Annotation("\(shot.distanceYards)y", coordinate: shot.end.coordinate) {
                    VStack(spacing: 1) {
                        Circle()
                            .fill(colorForShot(i).opacity(0.7))
                            .frame(width: 8, height: 8)
                        if shot.distanceYards > 0 {
                            Text("\(shot.distanceYards)y")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(.black.opacity(0.7))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }
                }
            }

            // Green marker
            if let green = holeGps?.greenCenter {
                Annotation("Green", coordinate: green.coordinate) {
                    ZStack {
                        Circle().fill(.green).frame(width: 16, height: 16)
                        Circle().fill(.white).frame(width: 4, height: 4)
                    }
                    .overlay(Circle().stroke(.white, lineWidth: 2).frame(width: 16, height: 16))
                }
            }

            // Tee marker
            if let tee = holeGps?.tee {
                Annotation("Tee", coordinate: tee.coordinate) {
                    Circle().fill(.white).frame(width: 8, height: 8)
                        .overlay(Circle().stroke(.gray, lineWidth: 1))
                }
            }
        }
        .mapStyle(.imagery)
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func colorForShot(_ index: Int) -> Color {
        let colors: [Color] = [.yellow, .cyan, .orange, .pink, .mint, .purple]
        return colors[index % colors.count]
    }
}

/// Record shot locations during play
@Observable
final class ShotTracerRecorder {
    var currentHoleShots: [ShotLocation] = []
    private var pendingStart: GpsPoint?

    /// Mark the start of a shot (where the ball is now)
    func markShotStart(location: GpsPoint) {
        pendingStart = location
    }

    /// Mark the end of a shot (where the ball landed)
    func markShotEnd(location: GpsPoint, club: Club?) {
        guard let start = pendingStart else { return }
        let dist = LocationService.distanceYards(from: start.coordinate, to: location.coordinate)
        let shotLoc = ShotLocation(start: start, end: location, club: club, distanceYards: dist)
        currentHoleShots.append(shotLoc)
        pendingStart = nil
    }

    /// Clear for next hole
    func nextHole() {
        currentHoleShots = []
        pendingStart = nil
    }
}
