import Testing
import Foundation
@testable import AICaddy

/// Multi-round "season" simulations: play several full rounds, then drive the
/// downstream pipeline — handicap, period stats, club recommendations, export.
/// This is where the 1-round handicap-trend crash used to live.
@Suite("Season simulations")
struct SeasonSimulationTests {

    private func playSeason(course: SimCourse, rounds count: Int) -> [Round] {
        var rounds: [Round] = []
        for i in 0..<count {
            let engine = RoundSimEngine(course: course, seedSalt: UInt64(i + 1) &* 65537)
            let report = engine.playFullRound()
            let round = Round(
                courseId: "sim-season-\(course.seed)",
                courseName: course.name,
                teeName: course.teeName,
                holes: report.holes,
                courseTee: engine.layout.tee
            )
            round.isComplete = true
            round.date = Date(timeIntervalSinceReferenceDate: 700_000_000 + Double(i) * 86_400 * 4)
            rounds.append(round)
        }
        return rounds
    }

    @Test("Regression: stats after exactly ONE completed round must not crash")
    func singleRoundPeriodStats() {
        let rounds = playSeason(course: SimCourses.kenMcDonald, rounds: 1)

        // This used to fatal-error in buildHandicapTrend (range 2..<1)
        let stats = AdvancedStatsCalculator.periodStats(rounds: rounds, label: "All Time")
        #expect(stats.roundCount == 1)
        #expect(stats.avgScore > 0)
        #expect(stats.handicapTrend.isEmpty)  // can't have a trend with 1 round

        // Two rounds — still under the handicap minimum, still must not crash
        let two = playSeason(course: SimCourses.dobsonRanch, rounds: 2)
        let stats2 = AdvancedStatsCalculator.periodStats(rounds: two, label: "All Time")
        #expect(stats2.roundCount == 2)
    }

    @Test("Six rounds at Ken McDonald: handicap, stats, recommendations")
    func fullSeason() {
        let course = SimCourses.kenMcDonald
        let rounds = playSeason(course: course, rounds: 6)

        // Handicap index computes and is sane
        let hcRounds = rounds.compactMap { HandicapRound.fromRound($0) }
        #expect(hcRounds.count == 6)
        let index = HandicapCalculator.calculateIndex(rounds: hcRounds)
        #expect(index != nil)
        #expect(index! > -5 && index! <= 54)

        // Period stats across the season
        let stats = AdvancedStatsCalculator.periodStats(rounds: rounds, label: "Season")
        #expect(stats.roundCount == 6)
        let scores = rounds.map { StatsCalculator.calculate(holes: $0.holes).totalStrokes }
        let expectedAvg = Double(scores.reduce(0, +)) / 6.0
        #expect(abs(stats.avgScore - expectedAvg) < 0.01)
        #expect(stats.bestScore == scores.min())
        #expect(!stats.handicapTrend.isEmpty)

        // Club recommendation learns from the season's shots
        let recommender = ClubRecommendationService()
        recommender.loadHistory(rounds: rounds)
        #expect(recommender.hasData)
        let rec = recommender.recommend(distanceYards: 160)
        #expect(rec != nil)
        #expect(abs(rec!.primaryAvg - 160) <= 30, "recommended \(rec!.primaryClub) avg \(rec!.primaryAvg) for 160y")

        // Par-type analysis reconciles with raw hole data
        let parSplits = AdvancedStatsCalculator.parTypeAnalysis(rounds: rounds)
        let par3HolesPlayed = rounds.flatMap { $0.holes }.filter { $0.par == 3 && $0.strokes > 0 }.count
        #expect(parSplits.par3.count == par3HolesPlayed)

        // Shot dispersion aggregates without crashing and covers hit clubs
        let dispersion = AdvancedStatsCalculator.shotDispersion(rounds: rounds)
        #expect(!dispersion.isEmpty)

        // Hole history for hole 1
        let history = AdvancedStatsCalculator.holeHistory(holeNumber: 1, courseId: rounds[0].courseId, rounds: rounds)
        #expect(history.timesPlayed == 6)
        #expect(history.bestScore <= history.worstScore)

        // CSV export includes every round
        let url = ExportService.exportCSV(rounds: rounds)
        #expect(url != nil)
        if let url {
            let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            #expect(content.contains(course.name))
            #expect(content.contains("HOLE BY HOLE DETAIL"))
            #expect(content.contains("CLUB DISTANCES"))
            try? FileManager.default.removeItem(at: url)
        }
    }

    @Test("Score prediction mid-round uses the round's real hole count")
    func midRoundPrediction() {
        let engine = RoundSimEngine(course: SimCourses.papago)
        let report = engine.playFullRound()
        let caddy = AICaddyService(apiKey: nil)

        // Prediction after 9 holes of an 18-hole round
        let nine = Array(report.holes.prefix(9))
        let nineStrokes = nine.reduce(0) { $0 + $1.strokes }
        let prediction = caddy.predictedScore(
            holesPlayed: nine,
            totalPar: SimCourses.papago.par,
            totalHoles: 18
        )
        #expect(prediction != nil)
        #expect(prediction!.holesPlayed == 9)
        #expect(prediction!.projected > nineStrokes)
        #expect(prediction!.low <= prediction!.projected && prediction!.projected <= prediction!.high)

        // Regression: on a 9-hole course the prediction must not assume 18
        let engine9 = RoundSimEngine(course: SimCourses.shalimar)
        let report9 = engine9.playFullRound()
        let firstFive = Array(report9.holes.prefix(5))
        let p9 = caddy.predictedScore(
            holesPlayed: firstFive,
            totalPar: SimCourses.shalimar.par,
            totalHoles: 9
        )
        #expect(p9 != nil)
        let fiveStrokes = firstFive.reduce(0) { $0 + $1.strokes }
        // 4 holes remain — projection must stay in a 9-hole ballpark, not add 13 phantom holes
        #expect(p9!.projected < fiveStrokes + 4 * 8)
    }

    @Test("9-hole course round completes and reports correctly (hardcoded-18 regression)")
    func nineHoleRound() {
        let course = SimCourses.shalimar
        let engine = RoundSimEngine(course: course)
        let report = engine.playFullRound()

        #expect(report.holes.count == 9)
        #expect(report.strokeMismatches.isEmpty, "\(report.strokeMismatches)")
        #expect(report.autoAdvanceFailures.isEmpty, "\(report.autoAdvanceFailures)")

        let stats = StatsCalculator.calculate(holes: report.holes)
        #expect(stats.totalPar == course.par)
        // Back nine of a 9-hole round is zero, not a duplicate of the front
        #expect(stats.backNine == 0)
        #expect(stats.frontNine == stats.totalStrokes)
    }
}
