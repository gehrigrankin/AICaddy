import Foundation
import CoreLocation
@testable import AICaddy

/// Builds a geometrically-consistent `CourseTee` (tee/green/fairway/hazard GPS)
/// for a SimCourse, anchored at the course's real-world location.
///
/// Layout rules that matter to the tests:
/// - green center is exactly the scorecard yardage from the tee
/// - green front/back are ±12y along the hole axis
/// - the next hole's tee is 45–60y beyond the previous green (typical walk),
///   which exercises auto-advance without triggering it from the green itself
enum CourseLayoutBuilder {

    struct Layout {
        let tee: CourseTee
        let holeBearings: [Double]  // tee→green bearing per hole
    }

    static func build(_ course: SimCourse) -> Layout {
        var rng = SeededRandom(seed: course.seed)
        var holes: [CourseHoleData] = []
        var bearings: [Double] = []

        var teePoint = CLLocationCoordinate2D(latitude: course.lat, longitude: course.lng)
        var bearing = rng.double() * 360

        for i in 0..<course.holeCount {
            let par = course.pars[i]
            let yardage = course.yardages[i]

            let green = GeoMath.offsetYards(teePoint, bearingDegrees: bearing, yards: Double(yardage))
            let greenFront = GeoMath.offsetYards(green, bearingDegrees: bearing + 180, yards: 12)
            let greenBack = GeoMath.offsetYards(green, bearingDegrees: bearing, yards: 12)
            let fairwayCenter = GeoMath.offsetYards(teePoint, bearingDegrees: bearing, yards: Double(yardage) * 0.55)

            var hazards: [HoleHazard] = []
            // Sprinkle hazards on longer holes: a bunker near the green, water on some
            if par >= 4 {
                let bunkerPos = GeoMath.offsetYards(green, bearingDegrees: bearing + 90, yards: 18)
                hazards.append(HoleHazard(type: "bunker", position: GpsPoint(coordinate: bunkerPos), label: "Greenside bunker"))
            }
            let hasWater = rng.chance(0.3) && par >= 4
            if hasWater {
                let waterPos = GeoMath.offsetYards(teePoint, bearingDegrees: bearing + 25, yards: Double(yardage) * 0.6)
                hazards.append(HoleHazard(type: "water", position: GpsPoint(coordinate: waterPos), label: "Water"))
            }

            let gps = HoleGps(
                tee: GpsPoint(coordinate: teePoint),
                greenCenter: GpsPoint(coordinate: green),
                greenFront: GpsPoint(coordinate: greenFront),
                greenBack: GpsPoint(coordinate: greenBack),
                fairwayCenter: GpsPoint(coordinate: fairwayCenter),
                fairwayPath: nil,
                hazards: hazards
            )

            holes.append(CourseHoleData(
                holeNumber: i + 1,
                par: par,
                yardage: yardage,
                handicapIndex: nil,
                gps: gps
            ))
            bearings.append(bearing)

            // Route to the next tee: turn between 60° and 120° left or right,
            // tee box 45–60 yards past the green.
            let turn = (rng.chance(0.5) ? 1.0 : -1.0) * (60 + rng.double() * 60)
            bearing = (bearing + turn + 360).truncatingRemainder(dividingBy: 360)
            teePoint = GeoMath.offsetYards(green, bearingDegrees: bearing, yards: 45 + rng.double() * 15)
        }

        let tee = CourseTee(name: course.teeName, rating: course.rating, slope: course.slope, holes: holes)
        return Layout(tee: tee, holeBearings: bearings)
    }
}
