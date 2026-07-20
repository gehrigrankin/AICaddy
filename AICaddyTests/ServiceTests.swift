import Testing
import Foundation
import CoreLocation
@testable import AICaddy

@Suite("Club recommendation")
struct ClubRecommendationTests {

    private func roundWithShots(_ shots: [(Club, Int)], complete: Bool = true) -> Round {
        var hole = makeHole(1, par: 4, strokes: shots.count)
        hole.shots = shots.enumerated().map { i, s in
            Shot(shotNumber: i + 1, club: s.0, distanceYards: s.1, result: .fairway)
        }
        let round = Round(courseId: "c", courseName: "Test", teeName: "W", holes: [hole])
        round.isComplete = complete
        return round
    }

    @Test func noDataNoRecommendation() {
        let service = ClubRecommendationService()
        #expect(!service.hasData)
        #expect(service.recommend(distanceYards: 150) == nil)
    }

    @Test func incompleteRoundsIgnored() {
        let service = ClubRecommendationService()
        service.loadHistory(rounds: [roundWithShots([(.iron7, 170), (.iron7, 174)], complete: false)])
        #expect(!service.hasData)
    }

    @Test func picksClosestClubByAverage() {
        let service = ClubRecommendationService()
        service.loadHistory(rounds: [
            roundWithShots([(.iron7, 170), (.iron7, 174), (.iron8, 158), (.iron8, 162), (.pw, 130), (.pw, 134)]),
        ])
        let rec = service.recommend(distanceYards: 160)
        #expect(rec?.primaryClub == .iron8)
        #expect(rec?.primaryAvg == 160)
        #expect(rec?.alternateClub == .iron7)

        let recFar = service.recommend(distanceYards: 132)
        #expect(recFar?.primaryClub == .pw)
    }

    @Test func requiresTwoSamplesPerClub() {
        let service = ClubRecommendationService()
        service.loadHistory(rounds: [roundWithShots([(.iron7, 170)])])  // one sample only
        #expect(service.recommend(distanceYards: 170) == nil)
    }

    @Test func puttsAndPenaltiesExcluded() {
        let service = ClubRecommendationService()
        var hole = makeHole(1, par: 4, strokes: 4)
        hole.shots = [
            Shot(shotNumber: 1, club: .driver, distanceYards: 250, result: .water, isPenalty: true),
            Shot(shotNumber: 2, club: .putter, distanceYards: 30, isPutt: true),
            Shot(shotNumber: 3, club: .iron9, distanceYards: 145, result: .green),
            Shot(shotNumber: 4, club: .iron9, distanceYards: 149, result: .green),
        ]
        let round = Round(courseId: "c", courseName: "T", teeName: "W", holes: [hole])
        round.isComplete = true
        service.loadHistory(rounds: [round])

        let rec = service.recommend(distanceYards: 147)
        #expect(rec?.primaryClub == .iron9)
        // Driver (penalty) and putter must not appear anywhere
        #expect(service.clubAverages.allSatisfy { $0.club == .iron9 })
    }
}

@Suite("Weather service math")
struct WeatherServiceTests {

    @Test func compassDirections() {
        #expect(WeatherService.compassDirection(0) == "N")
        #expect(WeatherService.compassDirection(90) == "E")
        #expect(WeatherService.compassDirection(180) == "S")
        #expect(WeatherService.compassDirection(270) == "W")
        #expect(WeatherService.compassDirection(45) == "NE")
        #expect(WeatherService.compassDirection(359) == "N")
        #expect(WeatherService.compassDirection(348.75) == "N")
        #expect(WeatherService.compassDirection(337) == "NNW")
    }

    @Test func headwindAddsDistance() {
        let service = WeatherService()
        service.windSpeed = 10
        service.windDirection = 0  // wind FROM the north
        // Hitting north = into the wind → plays longer
        #expect(service.adjustedDistance(yards: 150, shotBearing: 0) == 160)
        // Hitting south = downwind → plays shorter
        #expect(service.adjustedDistance(yards: 150, shotBearing: 180) == 145)
        // Pure crosswind → small adjustment only
        let cross = service.adjustedDistance(yards: 150, shotBearing: 90)
        #expect(abs(cross - 152) <= 1)
    }

    @Test func noWindDataNoAdjustment() {
        let service = WeatherService()
        #expect(service.adjustedDistance(yards: 150, shotBearing: 0) == 150)
    }

    @Test func temperatureAdjustment() {
        let service = WeatherService()
        service.temperature = 40  // cold → shorter carry → plays longer
        #expect(service.temperatureAdjustment(yards: 150) == 144)
        service.temperature = 110  // Phoenix summer → plays shorter... i.e. flies longer
        #expect(service.temperatureAdjustment(yards: 150) == 154)
        service.temperature = 70
        #expect(service.temperatureAdjustment(yards: 150) == 150)
    }
}

@Suite("Elevation service")
struct ElevationServiceTests {

    @Test func playsLikeDistance() {
        let service = ElevationService()
        #expect(service.playsLikeDistance(actualYards: 150) == nil)  // no data

        service.elevationDelta = 9.144  // 30 ft uphill
        #expect(service.playsLikeDistance(actualYards: 150) == 160)

        service.elevationDelta = -9.144  // 30 ft downhill
        #expect(service.playsLikeDistance(actualYards: 150) == 140)
    }

    @Test func elevationDescription() {
        let service = ElevationService()
        #expect(service.elevationDescription == nil)
        service.elevationDelta = 9.144
        #expect(service.elevationDescription == "30ft uphill")
        service.elevationDelta = -9.144
        #expect(service.elevationDescription == "30ft downhill")
        service.elevationDelta = 0.5  // negligible
        #expect(service.elevationDescription == nil)
    }

    @Test("fetchElevation no longer fabricates altitude 0")
    func fetchElevationHonest() async {
        let service = ElevationService()
        let result = await service.fetchElevation(for: CLLocationCoordinate2D(latitude: 33.45, longitude: -112.07))
        #expect(result == nil)
    }
}

@Suite("AI caddy local logic")
struct AICaddyServiceTests {
    private let caddy = AICaddyService(apiKey: nil)

    @Test func predictionNeedsFourHoles() {
        let holes = (1...3).map { makeHole($0, par: 4, strokes: 5) }
        #expect(caddy.predictedScore(holesPlayed: holes, totalPar: 72) == nil)
    }

    @Test func predictionProjectsPace() {
        // 4 holes at exactly 5.0 average
        let holes = (1...4).map { makeHole($0, par: 4, strokes: 5) }
        let p = caddy.predictedScore(holesPlayed: holes, totalPar: 72)
        #expect(p != nil)
        // 20 + 5×14 = 90, +1 fatigue adjustment
        #expect(p!.projected == 91)
        #expect(p!.holesPlayed == 4)
        #expect(p!.low < p!.projected && p!.projected < p!.high)
    }

    @Test("Regression: prediction respects a 9-hole round")
    func predictionNineHoles() {
        let holes = (1...5).map { makeHole($0, par: 4, strokes: 5) }
        let p = caddy.predictedScore(holesPlayed: holes, totalPar: 34, totalHoles: 9)
        #expect(p != nil)
        // 25 + 5×4 = 45 (+0 fatigue: Int(4×0.05) rounds to 0)
        #expect(p!.projected == 45)
    }

    @Test func fullRoundPredictionIsJustTheTotal() {
        let holes = (1...18).map { makeHole($0, par: 4, strokes: 5) }
        let p = caddy.predictedScore(holesPlayed: holes, totalPar: 72)
        #expect(p?.projected == 90)
    }

    @Test func threePuttTipFires() {
        let holes = [
            makeHole(1, par: 4, strokes: 6, putts: 3),
            makeHole(2, par: 4, strokes: 6, putts: 3),
            makeHole(3, par: 4, strokes: 4, putts: 2),
        ]
        let tip = caddy.inRoundTip(holesPlayed: holes, currentHole: 4, currentPar: 4,
                                   distToGreen: nil, recentMisses: [])
        #expect(tip != nil)
        #expect(tip?.category == .putting)
        #expect(tip?.priority == .high)
    }

    @Test func coldStreakTipFires() {
        let holes = [
            makeHole(1, par: 4, strokes: 6, putts: 2),
            makeHole(2, par: 4, strokes: 6, putts: 2),
            makeHole(3, par: 4, strokes: 6, putts: 2),
        ]
        let tip = caddy.inRoundTip(holesPlayed: holes, currentHole: 4, currentPar: 4,
                                   distToGreen: nil, recentMisses: [])
        #expect(tip?.category == .mental)
    }

    @Test func localChatRecommendsClub() async {
        let context = RoundContext(
            courseName: "Papago", currentHole: 5, currentPar: 4,
            totalStrokes: 20, scoreToPar: 4, distToGreen: 155,
            windInfo: nil, clubDistances: [.iron7: 170, .iron8: 158]
        )
        let reply = await caddy.chat(message: "what club should I hit?", roundContext: context)
        #expect(reply.contains("8 Iron"))
        #expect(reply.contains("155"))
    }
}

@Suite("Export service")
struct ExportServiceTests {

    @Test func csvExportContainsRoundData() throws {
        var holes = (1...18).map { makeHole($0, par: 4, strokes: 5, putts: 2, fir: true, gir: false) }
        holes[0].shots = [Shot(shotNumber: 1, club: .driver, distanceYards: 255, result: .fairway)]
        // Course name with a comma — must stay quoted in the CSV
        let round = Round(courseId: "c", courseName: "Papago, North", teeName: "White", holes: holes)
        round.isComplete = true

        let url = try #require(ExportService.exportCSV(rounds: [round]))
        defer { try? FileManager.default.removeItem(at: url) }

        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(content.contains("Date,Course,Tee,Score"))
        #expect(content.contains("\"Papago, North\""))
        #expect(content.contains("90"))          // total score
        #expect(content.contains("HOLE BY HOLE DETAIL"))
        #expect(content.contains("CLUB DISTANCES"))
        #expect(content.contains("Driver,255,1"))
    }

    @Test func incompleteRoundsExcludedFromCSV() throws {
        let round = Round(courseId: "c", courseName: "Test Course", teeName: "W",
                          holes: (1...18).map { makeHole($0, par: 4, strokes: 4) })
        // not complete
        let url = try #require(ExportService.exportCSV(rounds: [round]))
        defer { try? FileManager.default.removeItem(at: url) }
        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(!content.contains("Test Course"))
    }
}

@Suite("Advanced stats")
struct AdvancedStatsTests {

    private func completedRound(strokesPerHole: Int, date: Date) -> Round {
        let tee = CourseTee(name: "W", rating: 70.0, slope: 120, holes: [])
        let round = Round(courseId: "c", courseName: "T", teeName: "W",
                          holes: (1...18).map { makeHole($0, par: 4, strokes: strokesPerHole) },
                          courseTee: tee)
        round.isComplete = true
        round.date = date
        return round
    }

    @Test("Regression: periodStats with 1–2 rounds must not crash")
    func periodStatsSmallCounts() {
        let one = [completedRound(strokesPerHole: 5, date: Date())]
        let stats1 = AdvancedStatsCalculator.periodStats(rounds: one, label: "T")
        #expect(stats1.roundCount == 1)
        #expect(stats1.avgScore == 90)
        #expect(stats1.handicapTrend.isEmpty)

        let two = one + [completedRound(strokesPerHole: 4, date: Date().addingTimeInterval(86400))]
        let stats2 = AdvancedStatsCalculator.periodStats(rounds: two, label: "T")
        #expect(stats2.roundCount == 2)
        #expect(stats2.bestScore == 72)
    }

    @Test func handicapTrendWithEnoughRounds() {
        let rounds = (0..<5).map { i in
            completedRound(strokesPerHole: 5, date: Date().addingTimeInterval(Double(i) * 86400))
        }
        let stats = AdvancedStatsCalculator.periodStats(rounds: rounds, label: "T")
        #expect(!stats.handicapTrend.isEmpty)
        #expect(stats.handicapTrend.count == 3)  // trend points from round 3 onward
    }

    @Test func streakDetection() {
        // Three consecutive birdies = hot streak
        let holes = [
            makeHole(1, par: 4, strokes: 3),
            makeHole(2, par: 4, strokes: 3),
            makeHole(3, par: 4, strokes: 3),
            makeHole(4, par: 4, strokes: 4),
        ]
        let analysis = AdvancedStatsCalculator.detectStreaks(holes: holes)
        #expect(!analysis.hotStreaks.isEmpty)
        #expect(analysis.currentStreak != nil)
    }

    @Test func streaksNeedThreeHoles() {
        let analysis = AdvancedStatsCalculator.detectStreaks(holes: [
            makeHole(1, par: 4, strokes: 3),
            makeHole(2, par: 4, strokes: 3),
        ])
        #expect(analysis.hotStreaks.isEmpty)
        #expect(analysis.currentStreak == nil)
    }

    @Test func strokesGainedIsFiniteAndSums() {
        let sg = AdvancedStatsCalculator.strokesGained(holes: [
            makeHole(1, par: 4, strokes: 4, putts: 2, yardage: 400,
                     shots: [Shot(shotNumber: 1, club: .driver, distanceYards: 250, result: .fairway)]),
            makeHole(2, par: 3, strokes: 3, putts: 2, yardage: 170),
        ])
        #expect(sg.total.isFinite)
        #expect(abs(sg.total - (sg.offTheTee + sg.approach + sg.aroundTheGreen + sg.putting)) < 0.0001)
    }
}
