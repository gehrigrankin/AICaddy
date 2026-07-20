import Testing
import Foundation
import SwiftData
@testable import AICaddy

@Suite("Models & persistence")
struct ModelTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Course.self, Round.self, GolfBag.self, EquipmentLog.self,
                                  configurations: config)
    }

    // MARK: - JSON-backed properties

    @Test func roundHolesRoundTrip() {
        var hole = makeHole(1, par: 4, strokes: 5, putts: 2, fir: true, gir: false, yardage: 410)
        hole.shots = [
            Shot(shotNumber: 1, club: .driver, distanceYards: 250, result: .fairway),
            Shot(shotNumber: 2, club: .iron8, distanceYards: 150, result: .rough),
        ]
        let round = Round(courseId: "c", courseName: "T", teeName: "W", holes: [hole])

        let restored = round.holes
        #expect(restored.count == 1)
        #expect(restored[0].strokes == 5)
        #expect(restored[0].putts == 2)
        #expect(restored[0].fairwayHit == true)
        #expect(restored[0].greenInRegulation == false)
        #expect(restored[0].yardage == 410)
        #expect(restored[0].shots.count == 2)
        #expect(restored[0].shots[0].club == .driver)
        #expect(restored[0].shots[1].result == .rough)
    }

    @Test func courseTeeRoundTrip() {
        let gps = HoleGps(
            tee: GpsPoint(lat: 33.1, lng: -112.1),
            greenCenter: GpsPoint(lat: 33.2, lng: -112.2),
            greenFront: nil, greenBack: nil, fairwayCenter: nil, fairwayPath: nil,
            hazards: [HoleHazard(type: "water", position: GpsPoint(lat: 33.15, lng: -112.15), label: "Lake")]
        )
        let tee = CourseTee(name: "Blue", rating: 71.2, slope: 128,
                            holes: [CourseHoleData(holeNumber: 1, par: 4, yardage: 400, handicapIndex: 5, gps: gps)])
        let round = Round(courseId: "c", courseName: "T", teeName: "Blue", holes: [], courseTee: tee)

        let restored = round.courseTee
        #expect(restored?.name == "Blue")
        #expect(restored?.rating == 71.2)
        #expect(restored?.slope == 128)
        #expect(restored?.holes.first?.gps?.tee?.lat == 33.1)
        #expect(restored?.holes.first?.gps?.hazards?.first?.label == "Lake")
    }

    // MARK: - HoleScore

    @Test func scoreLabels() {
        #expect(makeHole(1, par: 4, strokes: 4).scoreLabel == "Par")
        #expect(makeHole(1, par: 4, strokes: 3).scoreLabel == "Birdie")
        #expect(makeHole(1, par: 5, strokes: 3).scoreLabel == "Eagle")
        #expect(makeHole(1, par: 4, strokes: 5).scoreLabel == "Bogey")
        #expect(makeHole(1, par: 4, strokes: 6).scoreLabel == "Double")
        #expect(makeHole(1, par: 4, strokes: 7).scoreLabel == "Triple")
        #expect(makeHole(1, par: 4, strokes: 8).scoreLabel == "+4")
        #expect(makeHole(1, par: 4, strokes: 0).scoreLabel == "")
    }

    @Test func scoreToParNilWhenUnplayed() {
        #expect(makeHole(1, par: 4, strokes: 0).scoreToPar == nil)
        #expect(makeHole(1, par: 4, strokes: 4).scoreToPar == 0)
    }

    // MARK: - GPS point

    @Test func gpsPointCoordinateBridge() {
        let p = GpsPoint(lat: 33.45, lng: -112.07)
        #expect(p.coordinate.latitude == 33.45)
        #expect(p.coordinate.longitude == -112.07)
        let q = GpsPoint(coordinate: p.coordinate)
        #expect(q == p)
    }

    // MARK: - Bag

    @Test func defaultBag() {
        let bag = GolfBag()
        #expect(bag.clubs.count == 13)
        #expect(bag.clubs.contains { $0.club == .driver })
        #expect(bag.clubs.contains { $0.club == .putter })
    }

    // MARK: - SwiftData container persistence

    @Test func roundPersistsCurrentHoleAndScores() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let round = Round(courseId: "c1", courseName: "Papago", teeName: "White",
                          holes: (1...18).map { makeHole($0, par: 4, strokes: 0) })
        context.insert(round)

        // Mid-round state: on hole 7 with some scores — what resume depends on
        round.currentHole = 7
        var holes = round.holes
        for i in 0..<6 { holes[i].strokes = 5 }
        round.holes = holes
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Round>())
        #expect(fetched.count == 1)
        #expect(fetched[0].currentHole == 7)
        #expect(fetched[0].holes.prefix(6).allSatisfy { $0.strokes == 5 })
        #expect(fetched[0].holes[6].strokes == 0)
        #expect(!fetched[0].isComplete)
    }

    @Test func inProgressQueryMirrorsHomeScreen() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let done = Round(courseId: "c1", courseName: "Done", teeName: "W",
                         holes: (1...18).map { makeHole($0, par: 4, strokes: 4) })
        done.isComplete = true
        let active = Round(courseId: "c2", courseName: "Active", teeName: "W",
                           holes: (1...18).map { makeHole($0, par: 4, strokes: 0) })
        context.insert(done)
        context.insert(active)
        try context.save()

        let descriptor = FetchDescriptor<Round>(predicate: #Predicate { !$0.isComplete })
        let inProgress = try context.fetch(descriptor)
        #expect(inProgress.count == 1)
        #expect(inProgress[0].courseName == "Active")
    }

    @Test("Discarding a broken in-progress round removes it for good")
    func discardInProgressRound() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let broken = Round(courseId: "c1", courseName: "Broken", teeName: "W",
                           holes: (1...18).map { makeHole($0, par: 4, strokes: 0) })
        let done = Round(courseId: "c2", courseName: "Done", teeName: "W",
                         holes: (1...18).map { makeHole($0, par: 4, strokes: 4) })
        done.isComplete = true
        context.insert(broken)
        context.insert(done)
        try context.save()

        // What the Discard Round button does
        context.delete(broken)
        try context.save()

        let inProgress = try context.fetch(FetchDescriptor<Round>(predicate: #Predicate { !$0.isComplete }))
        #expect(inProgress.isEmpty)  // home screen card is gone
        let remaining = try context.fetch(FetchDescriptor<Round>())
        #expect(remaining.count == 1)  // completed history untouched
        #expect(remaining[0].courseName == "Done")
    }

    @Test func cachedCourseCodable() throws {
        let cached = CachedCourse(
            id: "42", name: "Papago", city: "Phoenix", state: "AZ",
            location: GpsPoint(lat: 33.45, lng: -111.95),
            tees: [CourseTee(name: "White", rating: 71.8, slope: 132, holes: [])],
            downloadedAt: Date()
        )
        let data = try JSONEncoder().encode(cached)
        let decoded = try JSONDecoder().decode(CachedCourse.self, from: data)
        #expect(decoded.id == "42")
        #expect(decoded.tees.first?.slope == 132)
        #expect(decoded.location == cached.location)
    }
}
