import Foundation
import CoreLocation
@testable import AICaddy

/// Simulates a golfer playing a full round continuously — walking to the tee,
/// hitting shots with realistic dispersion, riding the cart between shots,
/// putting out, and walking to the next tee — while driving the app's REAL
/// services: GPS ingestion/filtering, distance math, the voice-input parser,
/// hole-score updating, stat derivation, and auto-advance.
final class RoundSimEngine {

    // MARK: - Golfer model

    struct GolferProfile {
        /// club → average carry yards
        static let clubDistances: [(club: Club, avg: Double)] = [
            (.driver, 262), (.wood3, 238), (.hybrid4, 215),
            (.iron5, 195), (.iron6, 185), (.iron7, 172), (.iron8, 160), (.iron9, 148),
            (.pw, 135), (.gw, 120), (.sw, 100), (.lw, 80),
        ]

        static func club(forYards yards: Double) -> (club: Club, avg: Double) {
            // Longest club that doesn't badly overshoot; falls back to driver
            let sorted = clubDistances.sorted { $0.avg > $1.avg }
            for entry in sorted where entry.avg <= yards + 12 {
                return entry
            }
            return sorted.last!
        }
    }

    /// Ground truth for one simulated hole.
    struct HoleTruth {
        var swings = 0            // actual swings (including putts)
        var penalties = 0         // penalty strokes
        var putts = 0
        var teeShotResult: ShotResult?
        var reachedGreenAtStroke: Int?   // strokes used when ball first on green (incl. penalties)
        var totalStrokes: Int { swings + penalties }
        var hadPenalty: Bool { penalties > 0 }
    }

    /// One utterance the golfer "spoke" plus the state when they said it.
    struct SpokenInput {
        let text: String
        let holeNumber: Int
    }

    /// Everything the engine observed during the round, for test assertions.
    struct Report {
        var holes: [HoleScore] = []
        var truths: [HoleTruth] = []
        var utterances: [SpokenInput] = []
        var rejectedFixes = 0
        var acceptedFixes = 0
        var distanceJumps: [String] = []        // fix-to-fix teleports (should be empty)
        var autoAdvanceFailures: [String] = []  // missed or premature suggestions
        var strokeMismatches: [String] = []
        var midRoundPersistenceOK = true
    }

    let course: SimCourse
    let layout: CourseLayoutBuilder.Layout
    let locationService = LocationService()
    let autoAdvance = AutoAdvanceService()
    let parser = ShotParserService(apiKey: nil)

    private var rng: SeededRandom
    private var simTime: Date
    private var report = Report()

    /// Position the "phone" reports — updated continuously along the track.
    private var lastAcceptedPosition: CLLocationCoordinate2D?

    /// `seedSalt` varies play (shot outcomes) while keeping the same course layout —
    /// used to simulate different rounds at the same course.
    init(course: SimCourse, seedSalt: UInt64 = 0) {
        self.course = course
        self.layout = CourseLayoutBuilder.build(course)
        self.rng = SeededRandom(seed: course.seed &* 7919 &+ seedSalt)
        self.simTime = Date(timeIntervalSinceReferenceDate: 780_000_000)  // fixed epoch for determinism
    }

    // MARK: - Main entry

    func playFullRound() -> Report {
        var holes = layout.tee.holes.map { h in
            HoleScore(holeNumber: h.holeNumber, par: h.par, yardage: h.yardage)
        }

        // Start in the parking lot ~200y from hole 1's tee, walk to the tee box.
        let firstTee = layout.tee.holes[0].gps!.tee!.coordinate
        let parkingLot = GeoMath.offsetYards(firstTee, bearingDegrees: 200, yards: 200)
        travel(from: parkingLot, to: firstTee, speedMps: 1.4)

        for idx in 0..<holes.count {
            let holeData = layout.tee.holes[idx]
            let truth = playHole(holeData: holeData, holeScore: &holes[idx], holeIndex: idx)
            report.truths.append(truth)

            // Verify score integrity: the app's recorded strokes must equal ground truth.
            if holes[idx].strokes != truth.totalStrokes {
                report.strokeMismatches.append(
                    "\(course.name) H\(holeData.holeNumber): app=\(holes[idx].strokes) truth=\(truth.totalStrokes)")
            }

            // Walk to the next tee, checking auto-advance along the way.
            if idx + 1 < holes.count {
                walkToNextTeeAndCheckAdvance(fromHoleIndex: idx, holes: holes)
            }

            // Mid-round "app was killed" persistence check
            if idx == min(6, holes.count - 1) {
                verifyPersistence(holes: holes)
            }
        }

        report.holes = holes
        return report
    }

    // MARK: - Hole play

    private func playHole(holeData: CourseHoleData, holeScore: inout HoleScore, holeIndex: Int) -> HoleTruth {
        var truth = HoleTruth()
        let gps = holeData.gps!
        let green = gps.greenCenter!.coordinate
        let par = holeData.par

        var ball = gps.tee!.coordinate
        var onGreen = false
        var firstPuttFeet = 0.0

        // The golfer stands on the tee; GPS should agree we're at the tee box.
        emitFix(at: ball)

        // Mid-hole: auto-advance must never fire before the hole is scored.
        checkNoPrematureAdvance(currentHole: holeData.holeNumber, holes: [holeScore])

        while !onGreen {
            simTime += 25  // pre-shot routine
            let distToPin = GeoMath.preciseYards(from: ball, to: green)
            let bearingToPin = GeoMath.bearing(from: ball, to: green)

            if distToPin <= 35 {
                // Chip / pitch onto the green
                truth.swings += 1
                let proximity = max(2.0, rng.gaussian(mean: 7, sd: 3))
                ball = GeoMath.offsetYards(green, bearingDegrees: rng.double() * 360, yards: proximity / 3.0)
                onGreen = true
                firstPuttFeet = proximity
                if truth.reachedGreenAtStroke == nil {
                    truth.reachedGreenAtStroke = truth.swings + truth.penalties
                }
                speak("\(chipClubName()) \(Int(distToPin.rounded())) on the green", holeNumber: holeData.holeNumber, holeScore: &holeScore)
            } else {
                // Full swing
                let choice = GolferProfile.club(forYards: distToPin)
                let carry = rng.gaussian(mean: min(choice.avg, distToPin + 5), sd: choice.avg * 0.05)
                let push = rng.gaussian(mean: 0, sd: 5)  // degrees offline
                ball = GeoMath.offsetYards(ball, bearingDegrees: bearingToPin + push, yards: max(30, carry))
                truth.swings += 1

                let newDist = GeoMath.preciseYards(from: ball, to: green)
                let lateralOffline = abs(push) / 180 * .pi * carry  // small-angle lateral miss, yards

                let isTeeShot = truth.swings == 1 && truth.penalties == 0
                var result: ShotResult
                if newDist <= 15 {
                    // Close enough to hole out or be on the green
                    result = .green
                    onGreen = true
                    firstPuttFeet = max(3.0, newDist * 3)
                    ball = GeoMath.offsetYards(green, bearingDegrees: rng.double() * 360, yards: newDist)
                    if truth.reachedGreenAtStroke == nil {
                        truth.reachedGreenAtStroke = truth.swings + truth.penalties
                    }
                } else if par >= 4 && isTeeShot && rng.chance(0.04) && holeHasWater(gps) {
                    // Splash — penalty stroke, drop near the hazard
                    result = .water
                    truth.penalties += 1
                    ball = GeoMath.offsetYards(ball, bearingDegrees: bearingToPin + 180, yards: 25)
                } else if lateralOffline > 22 {
                    result = .trees
                } else if lateralOffline > 12 {
                    result = .rough
                } else if newDist <= 40 && rng.chance(0.1) {
                    result = .bunker
                } else {
                    result = .fairway
                }

                if isTeeShot { truth.teeShotResult = result }

                let spokenDist = Int(carry.rounded())
                let phrase: String
                switch result {
                case .water:
                    phrase = "\(clubPhrase(choice.club)) in the water"
                case .green:
                    phrase = "\(clubPhrase(choice.club)) \(spokenDist) on the green"
                default:
                    phrase = "\(clubPhrase(choice.club)) \(spokenDist) \(resultPhrase(result))"
                }
                speak(phrase, holeNumber: holeData.holeNumber, holeScore: &holeScore)

                // Ride the cart to the ball
                travelToBall(ball)
            }
        }

        // Putt out (reading greens takes a while)
        simTime += 90
        let putts = simulatePutts(firstPuttFeet: firstPuttFeet)
        truth.putts = putts
        truth.swings += putts
        speak(puttPhrase(putts), holeNumber: holeData.holeNumber, holeScore: &holeScore)

        return truth
    }

    private func simulatePutts(firstPuttFeet: Double) -> Int {
        if firstPuttFeet <= 6 {
            return rng.chance(0.65) ? 1 : 2
        } else if firstPuttFeet <= 25 {
            let r = rng.double()
            if r < 0.08 { return 1 }
            if r < 0.90 { return 2 }
            return 3
        } else {
            return rng.chance(0.55) ? 2 : 3
        }
    }

    private func holeHasWater(_ gps: HoleGps) -> Bool {
        gps.hazards?.contains { $0.type == "water" } ?? false
    }

    // MARK: - Speech → parser → hole score (the app's real input path)

    private func speak(_ text: String, holeNumber: Int, holeScore: inout HoleScore) {
        report.utterances.append(SpokenInput(text: text, holeNumber: holeNumber))
        let parsed = parser.localParse(
            input: text,
            par: holeScore.par,
            currentShotNumber: holeScore.shots.count + 1
        )
        HoleScoreUpdater.apply(parsed, to: &holeScore)
    }

    private func clubPhrase(_ club: Club) -> String {
        switch club {
        case .driver: return "driver"
        case .wood3: return "3 wood"
        case .hybrid4: return "hybrid"
        case .iron5: return "5 iron"
        case .iron6: return "6 iron"
        case .iron7: return "7 iron"
        case .iron8: return "8 iron"
        case .iron9: return "9 iron"
        case .pw: return "pitching wedge"
        case .gw: return "gap wedge"
        case .sw: return "sand wedge"
        case .lw: return "lob wedge"
        default: return club.displayName.lowercased()
        }
    }

    private func chipClubName() -> String {
        rng.chance(0.5) ? "lob wedge" : "sand wedge"
    }

    private func resultPhrase(_ result: ShotResult) -> String {
        switch result {
        case .fairway: return "fairway"
        case .rough: return "in the rough"
        case .trees: return "in the trees"
        case .bunker: return "bunker"
        default: return result.rawValue
        }
    }

    private func puttPhrase(_ putts: Int) -> String {
        switch putts {
        case 1: return "1 putt"
        case 2: return "2 putts"
        default: return "\(putts) putts"
        }
    }

    // MARK: - GPS track

    /// Emit a fix with realistic noise; occasionally emit garbage that the
    /// LocationService must reject.
    private func emitFix(at coordinate: CLLocationCoordinate2D) {
        // Occasionally: a garbage fix (huge inaccuracy + teleport) → must be rejected
        if rng.chance(0.05) {
            let garbagePos = GeoMath.offsetYards(coordinate, bearingDegrees: rng.double() * 360, yards: 400)
            let garbage = CLLocation(
                coordinate: garbagePos, altitude: 350,
                horizontalAccuracy: 250 + rng.double() * 800, verticalAccuracy: 50,
                timestamp: simTime
            )
            if locationService.ingest(garbage, now: simTime) {
                report.distanceJumps.append("accepted a \(Int(garbage.horizontalAccuracy))m-accuracy fix")
            } else {
                report.rejectedFixes += 1
            }
        }
        // Occasionally: a stale cached fix → must be rejected
        if rng.chance(0.03) {
            let stale = CLLocation(
                coordinate: coordinate, altitude: 350,
                horizontalAccuracy: 8, verticalAccuracy: 20,
                timestamp: simTime.addingTimeInterval(-120)
            )
            if locationService.ingest(stale, now: simTime) {
                report.distanceJumps.append("accepted a 120s-old fix")
            } else {
                report.rejectedFixes += 1
            }
        }

        // The real fix: a few meters of GPS noise
        let noise = abs(rng.gaussian(mean: 0, sd: 2.5))
        let noisyPos = GeoMath.offset(coordinate, bearingDegrees: rng.double() * 360, distanceMeters: noise)
        let fix = CLLocation(
            coordinate: noisyPos, altitude: 350,
            horizontalAccuracy: 4 + rng.double() * 8, verticalAccuracy: 15,
            timestamp: simTime
        )
        if locationService.ingest(fix, now: simTime) {
            report.acceptedFixes += 1
            // The reported position must never teleport: chips are ≤35y and all
            // longer movement emits fixes every 15m, so >60m between accepted
            // fixes means a garbage fix slipped through the filter.
            if let last = lastAcceptedPosition {
                let jump = GeoMath.preciseYards(from: last, to: noisyPos) * GeoMath.metersPerYard
                if jump > 60 {
                    report.distanceJumps.append("position jumped \(Int(jump))m between accepted fixes")
                }
            }
            lastAcceptedPosition = noisyPos
        }
    }

    /// Travel between two points emitting fixes along the way.
    private func travel(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, speedMps: Double) {
        let totalMeters = GeoMath.preciseYards(from: from, to: to) * GeoMath.metersPerYard
        guard totalMeters > 1 else {
            emitFix(at: to)
            return
        }
        let bearing = GeoMath.bearing(from: from, to: to)
        let stepMeters = 15.0
        var traveled = 0.0

        while traveled < totalMeters {
            traveled = min(totalMeters, traveled + stepMeters)
            simTime += stepMeters / speedMps
            let pos = GeoMath.offset(from, bearingDegrees: bearing, distanceMeters: traveled)
            emitFix(at: pos)
        }
    }

    private func travelToBall(_ ball: CLLocationCoordinate2D) {
        guard let current = locationService.location else {
            emitFix(at: ball)
            return
        }
        simTime += 15  // stow the club, hop in the cart
        travel(from: current, to: ball, speedMps: 6.5)  // cart pace
    }

    // MARK: - Auto-advance

    private func checkNoPrematureAdvance(currentHole: Int, holes: [HoleScore]) {
        guard let loc = locationService.location else { return }
        let scored = (holes.first { $0.holeNumber == currentHole }?.strokes ?? 0) > 0
        autoAdvance.checkForAdvance(
            currentHole: currentHole,
            userLocation: loc,
            nextTeebox: nextTee(after: currentHole),
            lastHole: course.holeCount,
            hasScoredCurrentHole: scored,
            now: simTime
        )
        if let suggestion = autoAdvance.suggestedAdvance, !scored {
            report.autoAdvanceFailures.append(
                "H\(currentHole): premature suggestion of hole \(suggestion) before scoring")
        }
    }

    private func nextTee(after hole: Int) -> GpsPoint? {
        layout.tee.holes.first { $0.holeNumber == hole + 1 }?.gps?.tee
    }

    private func walkToNextTeeAndCheckAdvance(fromHoleIndex idx: Int, holes: [HoleScore]) {
        let currentHoleNumber = layout.tee.holes[idx].holeNumber
        guard let green = layout.tee.holes[idx].gps?.greenCenter?.coordinate,
              let nextTeePoint = nextTee(after: currentHoleNumber)?.coordinate
        else { return }

        // Standing on the green having just scored: the next tee is 45+ yards
        // away, so no suggestion should fire yet.
        autoAdvance.checkForAdvance(
            currentHole: currentHoleNumber,
            userLocation: green,
            nextTeebox: nextTee(after: currentHoleNumber),
            lastHole: course.holeCount,
            hasScoredCurrentHole: true,
            now: simTime
        )
        if let s = autoAdvance.suggestedAdvance {
            report.autoAdvanceFailures.append(
                "H\(currentHoleNumber): suggested hole \(s) while still on the green")
        }

        // Walk to the next tee
        travel(from: green, to: nextTeePoint, speedMps: 1.4)

        // Now standing on the next tee: suggestion must fire.
        guard let loc = locationService.location else { return }
        autoAdvance.checkForAdvance(
            currentHole: currentHoleNumber,
            userLocation: loc,
            nextTeebox: nextTee(after: currentHoleNumber),
            lastHole: course.holeCount,
            hasScoredCurrentHole: true,
            now: simTime
        )
        if autoAdvance.suggestedAdvance == currentHoleNumber + 1 {
            autoAdvance.confirmAdvance(now: simTime)
        } else {
            report.autoAdvanceFailures.append(
                "H\(currentHoleNumber): no suggestion standing on hole \(currentHoleNumber + 1) tee")
        }
    }

    // MARK: - Persistence

    /// Simulate the app being killed mid-round: the holes array must survive a
    /// JSON round-trip exactly (this is what Round persists via SwiftData).
    private func verifyPersistence(holes: [HoleScore]) {
        guard let data = try? JSONEncoder().encode(holes),
              let decoded = try? JSONDecoder().decode([HoleScore].self, from: data)
        else {
            report.midRoundPersistenceOK = false
            return
        }
        guard decoded.count == holes.count else {
            report.midRoundPersistenceOK = false
            return
        }
        for (a, b) in zip(holes, decoded) {
            if a.holeNumber != b.holeNumber || a.strokes != b.strokes
                || a.putts != b.putts || a.shots.count != b.shots.count
                || a.fairwayHit != b.fairwayHit || a.greenInRegulation != b.greenInRegulation {
                report.midRoundPersistenceOK = false
                return
            }
        }
    }
}
