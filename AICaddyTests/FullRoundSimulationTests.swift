import Testing
import Foundation
import CoreLocation
@testable import AICaddy

/// Continuous full-round simulations over real Phoenix-metro public courses.
///
/// Each run walks up to the first tee, plays every hole in order with random
/// shot dispersion, rides the cart between shots, putts out, walks to the next
/// tee, and finishes the round — feeding the app's REAL services throughout:
/// GPS ingestion & filtering, distance math, the voice parser, hole scoring,
/// stat derivation, and auto-advance.
@Suite("Full round simulations — Phoenix metro")
struct FullRoundSimulationTests {

    // MARK: - Course data sanity

    @Test("Scorecard data is realistic", arguments: SimCourses.all)
    func courseDataIntegrity(course: SimCourse) {
        #expect(course.pars.count == course.yardages.count)
        #expect(course.holeCount == 18 || course.holeCount == 9)
        #expect(course.par >= 27 && course.par <= 74)

        for (par, yds) in zip(course.pars, course.yardages) {
            #expect((3...5).contains(par), "\(course.name): par \(par)")
            switch par {
            case 3: #expect((100...260).contains(yds), "\(course.name): par-3 of \(yds)y")
            case 4: #expect((260...500).contains(yds), "\(course.name): par-4 of \(yds)y")
            default: #expect((440...620).contains(yds), "\(course.name): par-5 of \(yds)y")
            }
        }
    }

    @Test("Generated layout matches the scorecard", arguments: SimCourses.all)
    func layoutGeometry(course: SimCourse) throws {
        let layout = CourseLayoutBuilder.build(course)
        #expect(layout.tee.holes.count == course.holeCount)

        for (i, hole) in layout.tee.holes.enumerated() {
            let gps = try #require(hole.gps)
            let tee = try #require(gps.tee)
            let green = try #require(gps.greenCenter)

            // Green center must be exactly the scorecard yardage from the tee
            let measured = LocationService.distanceYards(from: tee.coordinate, to: green.coordinate)
            #expect(abs(measured - course.yardages[i]) <= 2,
                    "\(course.name) H\(i + 1): measured \(measured)y vs card \(course.yardages[i])y")

            // Front/back should straddle the center
            let front = try #require(gps.greenFront)
            let back = try #require(gps.greenBack)
            let teeToFront = LocationService.distanceYards(from: tee.coordinate, to: front.coordinate)
            let teeToBack = LocationService.distanceYards(from: tee.coordinate, to: back.coordinate)
            #expect(teeToFront < measured)
            #expect(teeToBack > measured)
        }

        // Consecutive holes must be walkable: green N → tee N+1 within 30–80y
        for i in 0..<(layout.tee.holes.count - 1) {
            let green = layout.tee.holes[i].gps!.greenCenter!.coordinate
            let nextTee = layout.tee.holes[i + 1].gps!.tee!.coordinate
            let walk = LocationService.distanceYards(from: green, to: nextTee)
            #expect((30...80).contains(walk), "\(course.name) H\(i + 1)→H\(i + 2): \(walk)y walk")
        }
    }

    // MARK: - The main event

    @Test("Continuous full-round playthrough", arguments: SimCourses.all)
    func fullRound(course: SimCourse) {
        let engine = RoundSimEngine(course: course)
        let report = engine.playFullRound()

        // Every hole in order, every hole scored
        #expect(report.holes.count == course.holeCount)
        #expect(report.truths.count == course.holeCount)
        for hole in report.holes {
            #expect(hole.strokes > 0, "\(course.name) H\(hole.holeNumber) never scored")
        }

        // SCORE INTEGRITY — the whole point of the app. The strokes the app
        // recorded from voice inputs must equal the ground-truth swing count.
        #expect(report.strokeMismatches.isEmpty, "\(report.strokeMismatches)")

        // Putts recorded exactly
        for (hole, truth) in zip(report.holes, report.truths) {
            #expect(hole.putts == truth.putts,
                    "\(course.name) H\(hole.holeNumber): app putts \(String(describing: hole.putts)) vs truth \(truth.putts)")
        }

        // GPS integrity: garbage fixes rejected, position never teleported
        #expect(report.distanceJumps.isEmpty, "\(report.distanceJumps)")
        #expect(report.acceptedFixes > course.holeCount * 10, "suspiciously few GPS fixes accepted")

        // Auto-advance: suggested at every next tee, never prematurely
        #expect(report.autoAdvanceFailures.isEmpty, "\(report.autoAdvanceFailures)")

        // Mid-round app-kill persistence survived
        #expect(report.midRoundPersistenceOK, "hole data did not survive persistence round-trip")

        // Derived stats agree with ground truth (penalty holes excluded — shot
        // indices intentionally diverge from stroke counts there)
        for (hole, truth) in zip(report.holes, report.truths) where !truth.hadPenalty {
            if hole.par >= 4 {
                #expect(hole.fairwayHit == (truth.teeShotResult == .fairway),
                        "\(course.name) H\(hole.holeNumber) FIR mismatch")
            }
            if let reached = truth.reachedGreenAtStroke {
                #expect(hole.greenInRegulation == (reached <= hole.par - 2),
                        "\(course.name) H\(hole.holeNumber) GIR mismatch (on green in \(reached))")
            }
        }

        // Round-level stats must reconcile with ground truth
        let stats = StatsCalculator.calculate(holes: report.holes)
        #expect(stats.totalStrokes == report.truths.reduce(0) { $0 + $1.totalStrokes })
        #expect(stats.totalPutts == report.truths.reduce(0) { $0 + $1.putts })
        #expect(stats.totalPar == course.par)

        // A mid-handicap sim golfer shoots something plausible
        #expect(stats.totalStrokes >= course.par - 5, "\(course.name): impossibly low \(stats.totalStrokes)")
        #expect(stats.totalStrokes <= course.par + 45, "\(course.name): blowup \(stats.totalStrokes)")

        // Post-round pipeline must not crash and must reconcile
        let round = Round(courseId: "sim-\(course.seed)", courseName: course.name,
                          teeName: course.teeName, holes: report.holes,
                          courseTee: engine.layout.tee)
        round.isComplete = true
        let hcRound = HandicapRound.fromRound(round)
        #expect(hcRound != nil)
        #expect(hcRound!.adjustedScore <= stats.totalStrokes)
        #expect(hcRound!.slope == course.slope)
    }

    // MARK: - Distance display along the way

    @Test("Distances to green shrink as the golfer approaches")
    func distancesDecreaseTowardGreen() {
        let course = SimCourses.papago
        let layout = CourseLayoutBuilder.build(course)
        let hole = layout.tee.holes[0]
        let tee = hole.gps!.tee!.coordinate
        let green = hole.gps!.greenCenter!.coordinate
        let bearing = GeoMath.bearing(from: tee, to: green)

        var previous = Int.max
        for step in stride(from: 0.0, through: 1.0, by: 0.1) {
            let pos = GeoMath.offsetYards(tee, bearingDegrees: bearing, yards: Double(hole.yardage!) * step)
            let dist = LocationService.distanceYards(from: pos, to: green)
            #expect(dist <= previous, "distance increased while walking toward the green")
            previous = dist
        }
        #expect(previous <= 1, "should be on the green at the end")
    }
}
