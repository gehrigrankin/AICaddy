import Testing
import Foundation
@testable import AICaddy

/// Tests for the OSM course-data parsing — the path that loads hole GPS.
/// Elements mimic real Overpass responses (ways with node id lists + separate
/// node elements carrying coordinates).
@Suite("Course search parsing")
struct CourseSearchServiceTests {

    // MARK: - Fixture builders

    private func node(_ id: Int, _ lat: Double, _ lon: Double) -> [String: Any] {
        ["type": "node", "id": id, "lat": lat, "lon": lon]
    }

    private func holeWay(id: Int, ref: String, par: String? = nil, nodes: [Int],
                         handicap: String? = nil) -> [String: Any] {
        var tags: [String: String] = ["golf": "hole", "ref": ref]
        if let par { tags["par"] = par }
        if let handicap { tags["handicap"] = handicap }
        return ["type": "way", "id": id, "tags": tags, "nodes": nodes]
    }

    // MARK: - Hole parsing

    @Test func parsesHoleWayIntoTeeGreenAndYardage() {
        // Tee at origin-ish, green ~400y north (0.0033° lat ≈ 400y)
        let elements: [[String: Any]] = [
            node(1, 33.3000, -111.7600),
            node(2, 33.3017, -111.7600),  // mid fairway
            node(3, 33.30332, -111.7600), // green
            holeWay(id: 100, ref: "1", par: "4", nodes: [1, 2, 3], handicap: "7"),
        ]
        let holes = CourseSearchService.parseHoles(from: elements, courseLocation: GpsPoint(lat: 33.3, lng: -111.76))

        #expect(!holes.isEmpty)
        let h1 = holes[0]
        #expect(h1.holeNumber == 1)
        #expect(h1.par == 4)
        #expect(h1.handicapIndex == 7)
        #expect(h1.gps?.tee?.lat == 33.3000)
        #expect(h1.gps?.greenCenter?.lat == 33.30332)
        // Yardage derived from tee→green distance (~400y)
        #expect(h1.yardage != nil)
        #expect(abs(h1.yardage! - 400) <= 10)
        // Middle nodes become the fairway path
        #expect(h1.gps?.fairwayPath?.count == 1)
    }

    @Test("Regression: partially-mapped course fills gaps so every hole is playable")
    func partialMappingNormalized() {
        let elements: [[String: Any]] = [
            node(1, 33.3000, -111.7600), node(2, 33.3033, -111.7600),
            node(3, 33.3050, -111.7580), node(4, 33.3065, -111.7580),
            holeWay(id: 100, ref: "1", par: "4", nodes: [1, 2]),
            holeWay(id: 101, ref: "12", par: "3", nodes: [3, 4]),
        ]
        let raw = CourseSearchService.parseHoles(from: elements, courseLocation: nil)
        let holes = CourseSearchService.normalizedHoles(raw)

        // Mapped past hole 9 → 18-hole course, all holes exist
        #expect(holes.count == 18)
        #expect(holes.map(\.holeNumber) == Array(1...18))
        #expect(holes[0].gps != nil)      // real mapped hole
        #expect(holes[11].par == 3)       // real mapped hole 12
        #expect(holes[1].gps == nil)      // gap-filled placeholder
        #expect(holes[1].par == 4)
    }

    @Test func emptyDataBecomesStandardEighteen() {
        let holes = CourseSearchService.normalizedHoles([])
        #expect(holes.count == 18)
        #expect(holes.allSatisfy { $0.par == 4 && $0.gps == nil })
    }

    @Test func wellMappedNineStaysNine() {
        let nine = (1...9).map { CourseHoleData(holeNumber: $0, par: 4) }
        #expect(CourseSearchService.normalizedHoles(nine).count == 9)
        // Sparse data (2 holes) defaults to 18 even when max ≤ 9
        let sparse = [CourseHoleData(holeNumber: 1, par: 4), CourseHoleData(holeNumber: 3, par: 4)]
        #expect(CourseSearchService.normalizedHoles(sparse).count == 18)
    }

    @Test("Regression: adjacent course's holes must not overwrite ours")
    func dedupsAdjacentCourseHoles() {
        let courseCenter = GpsPoint(lat: 33.3000, lng: -111.7600)
        let elements: [[String: Any]] = [
            // Our hole 1: tee at the course center
            node(1, 33.3000, -111.7600), node(2, 33.3033, -111.7600),
            // Neighbor's hole 1: ~1.2km east
            node(3, 33.3000, -111.7470), node(4, 33.3033, -111.7470),
            // Neighbor appears FIRST in the response
            holeWay(id: 200, ref: "1", par: "5", nodes: [3, 4]),
            holeWay(id: 100, ref: "1", par: "4", nodes: [1, 2]),
        ]
        let holes = CourseSearchService.parseHoles(from: elements, courseLocation: courseCenter)

        let holeOnes = holes.filter { $0.holeNumber == 1 && $0.gps != nil }
        #expect(holeOnes.count == 1)
        #expect(holeOnes[0].par == 4)  // ours, not the neighbor's par 5
        #expect(abs(holeOnes[0].gps!.tee!.lng - (-111.7600)) < 0.0001)
    }

    @Test func refTaggedFeaturesAttachToHoles() {
        let elements: [[String: Any]] = [
            node(1, 33.3000, -111.7600), node(2, 33.3033, -111.7600),
            holeWay(id: 100, ref: "1", par: "4", nodes: [1, 2]),
            // A ref-tagged greenside bunker (node with coordinates)
            ["type": "node", "id": 50, "lat": 33.3030, "lon": -111.7598,
             "tags": ["golf": "bunker", "ref": "1"]],
        ]
        let holes = CourseSearchService.parseHoles(from: elements, courseLocation: nil)
        #expect(holes[0].gps?.hazards?.contains { $0.type == "bunker" } == true)
    }

    @Test func invalidRefsSkipped() {
        let elements: [[String: Any]] = [
            node(1, 33.3, -111.76), node(2, 33.303, -111.76),
            holeWay(id: 100, ref: "A", nodes: [1, 2]),   // non-numeric ref
        ]
        let raw = CourseSearchService.parseHoles(from: elements, courseLocation: nil)
        #expect(raw.isEmpty)
    }
}
