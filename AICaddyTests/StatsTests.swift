import Testing
import Foundation
@testable import AICaddy

// MARK: - Helpers

func makeHole(
    _ n: Int, par: Int, strokes: Int,
    putts: Int? = nil, fir: Bool? = nil, gir: Bool? = nil,
    yardage: Int? = nil, shots: [Shot] = []
) -> HoleScore {
    var h = HoleScore(holeNumber: n, par: par, yardage: yardage)
    h.strokes = strokes
    h.putts = putts
    h.fairwayHit = fir
    h.greenInRegulation = gir
    h.shots = shots
    return h
}

@Suite("Stats calculator")
struct StatsCalculatorTests {

    /// A fully-known 18-hole round for exact-value assertions.
    private func standardRound() -> [HoleScore] {
        [
            makeHole(1, par: 4, strokes: 4, putts: 2, fir: true, gir: true),
            makeHole(2, par: 3, strokes: 3, putts: 2, gir: true),
            makeHole(3, par: 5, strokes: 5, putts: 2, fir: true, gir: true),
            makeHole(4, par: 4, strokes: 5, putts: 2, fir: false, gir: false),
            makeHole(5, par: 4, strokes: 3, putts: 1, fir: true, gir: true),   // birdie
            makeHole(6, par: 3, strokes: 4, putts: 2, gir: false),
            makeHole(7, par: 4, strokes: 6, putts: 3, fir: false, gir: false), // double
            makeHole(8, par: 5, strokes: 7, putts: 2, fir: false, gir: false),
            makeHole(9, par: 4, strokes: 4, putts: 2, fir: true, gir: true),
            makeHole(10, par: 4, strokes: 4, putts: 1, fir: true, gir: false),
            makeHole(11, par: 3, strokes: 3, putts: 2, gir: true),
            makeHole(12, par: 5, strokes: 6, putts: 2, fir: true, gir: false),
            makeHole(13, par: 4, strokes: 5, putts: 2, fir: false, gir: false),
            makeHole(14, par: 4, strokes: 4, putts: 2, fir: true, gir: true),
            makeHole(15, par: 3, strokes: 2, putts: 1, gir: true),             // birdie
            makeHole(16, par: 5, strokes: 5, putts: 2, fir: true, gir: true),
            makeHole(17, par: 4, strokes: 7, putts: 3, fir: false, gir: false), // triple
            makeHole(18, par: 4, strokes: 4, putts: 2, fir: true, gir: true),
        ]
    }

    @Test func totalsAndSplits() {
        let stats = StatsCalculator.calculate(holes: standardRound())
        #expect(stats.totalStrokes == 81)
        #expect(stats.totalPar == 72)
        #expect(stats.scoreToPar == 9)
        #expect(stats.frontNine == 41)
        #expect(stats.backNine == 40)
    }

    @Test func puttingStats() {
        let stats = StatsCalculator.calculate(holes: standardRound())
        #expect(stats.totalPutts == 35)
        #expect(stats.oneputts == 3)
        #expect(stats.threeputts == 2)
        #expect(abs(stats.puttsPerHole - 35.0 / 18.0) < 0.001)
    }

    @Test func girAndFairways() {
        let stats = StatsCalculator.calculate(holes: standardRound())
        #expect(stats.girHoles == 18)
        #expect(stats.greensInRegulation == 10)
        // Fairways only counted on par 4/5 — the 4 par-3s must be excluded
        #expect(stats.fairwayHoles == 14)
        #expect(stats.fairwaysHit == 9)
    }

    @Test func scoringDistribution() {
        let stats = StatsCalculator.calculate(holes: standardRound())
        #expect(stats.eagles == 0)
        #expect(stats.birdies == 2)
        #expect(stats.pars == 9)
        #expect(stats.bogeys == 4)
        #expect(stats.doubleBogeys == 2)
        #expect(stats.triplePlus == 1)
    }

    @Test func unplayedHolesExcluded() {
        var holes = standardRound()
        holes[17].strokes = 0  // never played 18
        let stats = StatsCalculator.calculate(holes: holes)
        #expect(stats.totalStrokes == 77)
        #expect(stats.totalPar == 68)
    }

    @Test func emptyRound() {
        let stats = StatsCalculator.calculate(holes: [])
        #expect(stats.totalStrokes == 0)
        #expect(stats.puttsPerHole == 0)
        #expect(stats.greensInRegulationPct == 0)
        #expect(stats.fairwaysPct == 0)
    }

    @Test func drivingDistance() {
        var holes = [
            makeHole(1, par: 4, strokes: 4),
            makeHole(2, par: 5, strokes: 5),
            makeHole(3, par: 3, strokes: 3),
        ]
        holes[0].shots = [Shot(shotNumber: 1, club: .driver, distanceYards: 260, result: .fairway)]
        holes[1].shots = [Shot(shotNumber: 1, club: .driver, distanceYards: 280, result: .rough)]
        // A par-3 tee shot is not a "drive"
        holes[2].shots = [Shot(shotNumber: 1, club: .iron7, distanceYards: 170, result: .green)]

        let stats = StatsCalculator.calculate(holes: holes)
        #expect(stats.driveCount == 2)
        #expect(stats.avgDrivingDistance == 270)
    }

    @Test func clubDistancesExcludePutts() {
        var hole = makeHole(1, par: 4, strokes: 4)
        hole.shots = [
            Shot(shotNumber: 1, club: .driver, distanceYards: 250, result: .fairway),
            Shot(shotNumber: 2, club: .iron8, distanceYards: 155, result: .green),
            Shot(shotNumber: 3, club: .putter, distanceYards: 10, isPutt: true),
        ]
        let stats = StatsCalculator.calculate(holes: [hole])
        #expect(stats.clubDistances[.driver]?.avg == 250)
        #expect(stats.clubDistances[.iron8]?.avg == 155)
        #expect(stats.clubDistances[.putter] == nil)
    }

    @Test func scrambling() {
        let holes = [
            makeHole(1, par: 4, strokes: 4, gir: false),  // scrambled
            makeHole(2, par: 4, strokes: 5, gir: false),  // failed
            makeHole(3, par: 4, strokes: 4, gir: true),   // not an attempt
            makeHole(4, par: 3, strokes: 2, gir: false),  // scrambled (birdie!)
        ]
        let stats = StatsCalculator.calculate(holes: holes)
        #expect(abs(stats.scramblingPct - (2.0 / 3.0 * 100)) < 0.01)
    }
}

@Suite("Hole stat derivation")
struct DeriveHoleStatsTests {

    @Test func derivesPuttsFromShots() {
        var hole = makeHole(1, par: 4, strokes: 4, shots: [
            Shot(shotNumber: 1, club: .driver, result: .fairway),
            Shot(shotNumber: 2, club: .iron8, result: .green),
            Shot(shotNumber: 3, club: .putter, isPutt: true),
            Shot(shotNumber: 4, club: .putter, isPutt: true),
        ])
        StatsCalculator.deriveHoleStats(&hole)
        #expect(hole.putts == 2)
        #expect(hole.fairwayHit == true)
        #expect(hole.greenInRegulation == true)
    }

    @Test func derivesGIRFalseWhenGreenMissedInRegulation() {
        var hole = makeHole(1, par: 4, strokes: 5, shots: [
            Shot(shotNumber: 1, club: .driver, result: .rough),
            Shot(shotNumber: 2, club: .iron7, result: .bunker),
            Shot(shotNumber: 3, club: .sw, result: .green),
            Shot(shotNumber: 4, club: .putter, isPutt: true),
            Shot(shotNumber: 5, club: .putter, isPutt: true),
        ])
        StatsCalculator.deriveHoleStats(&hole)
        #expect(hole.greenInRegulation == false)
        #expect(hole.fairwayHit == false)
        #expect(hole.sandSave == false)  // bunker + over par
    }

    @Test func girUndeterminedWithTooFewShots() {
        var hole = makeHole(1, par: 5, strokes: 0, shots: [
            Shot(shotNumber: 1, club: .driver, result: .fairway),
        ])
        StatsCalculator.deriveHoleStats(&hole)
        #expect(hole.greenInRegulation == nil)  // only 1 shot on a par 5 — can't know yet
    }

    @Test("Regression: up-and-down must recompute when the score changes")
    func upAndDownNotStale() {
        var hole = makeHole(1, par: 4, strokes: 4, gir: false)
        StatsCalculator.deriveHoleStats(&hole)
        #expect(hole.upAndDown == true)  // 4 on a par 4 after missing GIR

        // User corrects the score upward — up-and-down must flip, not stay stale
        hole.strokes = 5
        StatsCalculator.deriveHoleStats(&hole)
        #expect(hole.upAndDown == false)

        // And back down
        hole.strokes = 4
        StatsCalculator.deriveHoleStats(&hole)
        #expect(hole.upAndDown == true)
    }

    @Test func upAndDownNilWhenGIRHit() {
        var hole = makeHole(1, par: 4, strokes: 4, gir: true)
        StatsCalculator.deriveHoleStats(&hole)
        #expect(hole.upAndDown == nil)
        #expect(hole.sandSave == nil)
    }

    @Test func quickScoreEntryDerivesUpAndDownWithoutShots() {
        // Quick-input flow: user taps "Par", toggles GIR off, logs no shots
        var hole = makeHole(1, par: 4, strokes: 4, gir: false)
        StatsCalculator.deriveHoleStats(&hole)
        #expect(hole.upAndDown == true)
    }
}

@Suite("Hole score updater (voice-input application)")
struct HoleScoreUpdaterTests {

    private let parser = ShotParserService(apiKey: nil)

    private func apply(_ input: String, to hole: inout HoleScore) {
        let parsed = parser.localParse(input: input, par: hole.par, currentShotNumber: hole.shots.count + 1)
        HoleScoreUpdater.apply(parsed, to: &hole)
    }

    @Test("Regression: putts after logged shots must count toward strokes")
    func puttsAddToStrokes() {
        var hole = HoleScore(holeNumber: 1, par: 4)
        apply("driver 250 fairway", to: &hole)
        #expect(hole.strokes == 1)
        apply("8 iron 155 on the green", to: &hole)
        #expect(hole.strokes == 2)
        apply("2 putts", to: &hole)
        // The old code left this at 2 — the scorecard undercounted every hole
        #expect(hole.strokes == 4)
        #expect(hole.putts == 2)
        #expect(hole.greenInRegulation == true)
        #expect(hole.fairwayHit == true)
    }

    @Test("Regression: penalty strokes count toward the total")
    func penaltyStrokesCounted() {
        var hole = HoleScore(holeNumber: 1, par: 4)
        apply("driver in the water", to: &hole)
        // 1 swing + 1 penalty = hitting 3 from the drop
        #expect(hole.strokes == 2)
        apply("8 iron 150 on the green", to: &hole)
        #expect(hole.strokes == 3)
        apply("2 putts", to: &hole)
        #expect(hole.strokes == 5)
    }

    @Test func explicitTotalWins() {
        var hole = HoleScore(holeNumber: 1, par: 4)
        apply("driver 250 fairway", to: &hole)
        apply("6", to: &hole)
        #expect(hole.strokes == 6)
        // A later partial log must not lower an explicit total
        apply("2 putts", to: &hole)
        #expect(hole.strokes == 6)
    }

    @Test func puttsOnlyOnEmptyHoleDoesNotInventScore() {
        var hole = HoleScore(holeNumber: 1, par: 4)
        apply("2 putts", to: &hole)
        #expect(hole.strokes == 0)
        #expect(hole.putts == 2)
    }

    @Test func quickScoreButtons() {
        var hole = HoleScore(holeNumber: 1, par: 4)
        apply("birdie", to: &hole)
        #expect(hole.strokes == 3)
        apply("double bogey", to: &hole)
        #expect(hole.strokes == 6)
    }

    @Test func shotNumbersStaySequential() {
        var hole = HoleScore(holeNumber: 1, par: 5)
        apply("driver 260 fairway", to: &hole)
        apply("3 wood 220 in the rough", to: &hole)
        apply("sand wedge 85 on the green", to: &hole)
        apply("1 putt", to: &hole)
        #expect(hole.shots.map(\.shotNumber) == Array(1...hole.shots.count))
        #expect(hole.strokes == 4)  // eagle chance converted — 3 swings + 1 putt
    }

    @Test func chipAndPuttSequenceCounts() {
        var hole = HoleScore(holeNumber: 1, par: 4)
        apply("driver 250 fairway", to: &hole)
        apply("8 iron 140 bunker", to: &hole)
        apply("chip and 2 putts", to: &hole)
        #expect(hole.strokes == 5)
        #expect(hole.putts == 2)
        #expect(hole.greenInRegulation == false)
        #expect(hole.sandSave == false)
    }

    // MARK: - Escape hatches (undo / remove shot / reset)

    @Test("Removing a mis-parsed shot renumbers and fixes the score")
    func removeShotRecovers() {
        var hole = HoleScore(holeNumber: 1, par: 4)
        apply("driver 250 fairway", to: &hole)
        apply("8 iron 155 on the green", to: &hole)
        // The parser heard the same shot twice — classic on-course mis-parse
        apply("8 iron 155 on the green", to: &hole)
        apply("2 putts", to: &hole)
        #expect(hole.strokes == 5)  // one stroke too many

        let duplicate = hole.shots[2]
        HoleScoreUpdater.removeShot(id: duplicate.id, from: &hole)

        #expect(hole.strokes == 4)
        #expect(hole.shots.count == 2)
        #expect(hole.shots.map(\.shotNumber) == [1, 2])
        #expect(hole.putts == 2)
    }

    @Test func removePenaltyShotDropsPenaltyStroke() {
        var hole = HoleScore(holeNumber: 1, par: 4)
        apply("driver in the water", to: &hole)
        #expect(hole.strokes == 2)  // swing + penalty

        HoleScoreUpdater.removeShot(id: hole.shots[0].id, from: &hole)
        #expect(hole.strokes == 0)
        #expect(hole.shots.isEmpty)
    }

    @Test func removingNonexistentShotIsHarmless() {
        var hole = HoleScore(holeNumber: 1, par: 4)
        apply("driver 250 fairway", to: &hole)
        HoleScoreUpdater.removeShot(id: UUID(), from: &hole)
        #expect(hole.shots.count == 1)
        #expect(hole.strokes == 1)
    }

    @Test("Reset wipes the hole completely — even without logged shots")
    func resetClearsEverything() {
        var hole = HoleScore(holeNumber: 1, par: 4)
        // Quick-score path: no shots logged, so the old shots-gated Clear
        // button would never have appeared
        apply("bogey 2 putts", to: &hole)
        hole.fairwayHit = false
        #expect(hole.strokes == 5)

        HoleScoreUpdater.reset(&hole)
        #expect(hole.strokes == 0)
        #expect(hole.putts == nil)
        #expect(hole.fairwayHit == nil)
        #expect(hole.greenInRegulation == nil)
        #expect(hole.upAndDown == nil)
        #expect(hole.sandSave == nil)
        #expect(hole.shots.isEmpty)
        #expect(hole.scoreToPar == nil)  // reads as unplayed everywhere
    }

    @Test("Undo pattern: a snapshot restores the exact pre-input state")
    func snapshotRestoresState() {
        var hole = HoleScore(holeNumber: 1, par: 4)
        apply("driver 250 fairway", to: &hole)
        apply("8 iron 155 on the green", to: &hole)
        let snapshot = hole  // what HolePlayView stores before each input

        apply("triple bogey", to: &hole)  // garbage input wrecks the hole
        #expect(hole.strokes == 7)

        hole = snapshot  // undo
        #expect(hole.strokes == 2)
        #expect(hole.shots.count == 2)
        #expect(hole.greenInRegulation == true)
    }
}

@Suite("Handicap calculator")
struct HandicapTests {

    private func hcRound(_ score: Int, rating: Double = 70.0, slope: Int = 113) -> HandicapRound {
        HandicapRound(date: Date(), adjustedScore: score, slope: slope, rating: rating, courseName: "Test")
    }

    @Test func needsThreeRounds() {
        #expect(HandicapCalculator.calculateIndex(rounds: []) == nil)
        #expect(HandicapCalculator.calculateIndex(rounds: [hcRound(85)]) == nil)
        #expect(HandicapCalculator.calculateIndex(rounds: [hcRound(85), hcRound(90)]) == nil)
    }

    @Test func threeRoundsUsesLowestDifferential() {
        // Differentials at slope 113 / rating 70: 20, 15, 25 → lowest is 15 → ×0.96 = 14.4
        let index = HandicapCalculator.calculateIndex(rounds: [hcRound(90), hcRound(85), hcRound(95)])
        #expect(index == 14.4)
    }

    @Test func twentyRoundsUsesBestEight() {
        // Scores 80...99 → differentials 10...29; best 8 average = 13.5 → ×0.96 = 12.96 → 13.0
        let rounds = (80...99).map { hcRound($0) }
        let index = HandicapCalculator.calculateIndex(rounds: rounds)
        #expect(index == 13.0)
    }

    @Test func slopeAdjustsDifferential() {
        // (113/140) × (95 − 70) = 20.18 → single lowest → ×0.96 = 19.37 → 19.4
        let rounds = [hcRound(95, slope: 140), hcRound(96, slope: 140), hcRound(97, slope: 140)]
        let index = HandicapCalculator.calculateIndex(rounds: rounds)
        #expect(index == 19.4)
    }

    @Test func missingSlopeRatingExcluded() {
        let rounds = [
            hcRound(85),
            hcRound(90),
            HandicapRound(date: Date(), adjustedScore: 80, slope: nil, rating: nil, courseName: "No rating"),
        ]
        #expect(HandicapCalculator.calculateIndex(rounds: rounds) == nil)  // only 2 valid
    }

    @Test func capAt54() {
        let rounds = [hcRound(150), hcRound(155), hcRound(160)]
        let index = HandicapCalculator.calculateIndex(rounds: rounds)
        #expect(index == 54.0)
    }

    @Test func courseHandicap() {
        // 10 × (130/113) + (71.8 − 72) = 11.5 − 0.2 = 11.3 → 11
        let ch = HandicapCalculator.courseHandicap(index: 10.0, slope: 130, rating: 71.8, par: 72)
        #expect(ch == 11)
    }

    @Test func netDoubleBogeyCapInFromRound() {
        var holes = (1...18).map { makeHole($0, par: 4, strokes: 4) }
        holes[0].strokes = 12  // blow-up hole must be capped at par+3 = 7
        let round = Round(courseId: "c", courseName: "Test", teeName: "White", holes: holes,
                          courseTee: CourseTee(name: "White", rating: 70.0, slope: 120, holes: []))
        round.isComplete = true

        let hc = HandicapRound.fromRound(round)
        #expect(hc != nil)
        #expect(hc!.adjustedScore == 17 * 4 + 7)
        #expect(hc!.slope == 120)
        #expect(hc!.rating == 70.0)
    }

    @Test func incompleteRoundExcluded() {
        let round = Round(courseId: "c", courseName: "Test", teeName: "White",
                          holes: (1...18).map { makeHole($0, par: 4, strokes: 4) })
        // isComplete defaults to false
        #expect(HandicapRound.fromRound(round) == nil)
    }
}
