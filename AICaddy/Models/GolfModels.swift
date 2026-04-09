import Foundation
import SwiftData
import CoreLocation

// MARK: - Enums

enum Club: String, Codable, CaseIterable, Identifiable {
    case driver
    case wood3 = "3-wood"
    case wood5 = "5-wood"
    case wood7 = "7-wood"
    case hybrid2 = "2-hybrid"
    case hybrid3 = "3-hybrid"
    case hybrid4 = "4-hybrid"
    case hybrid5 = "5-hybrid"
    case iron2 = "2-iron"
    case iron3 = "3-iron"
    case iron4 = "4-iron"
    case iron5 = "5-iron"
    case iron6 = "6-iron"
    case iron7 = "7-iron"
    case iron8 = "8-iron"
    case iron9 = "9-iron"
    case pw
    case gw
    case sw
    case lw
    case putter

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .driver: return "Driver"
        case .wood3: return "3 Wood"
        case .wood5: return "5 Wood"
        case .wood7: return "7 Wood"
        case .hybrid2: return "2 Hybrid"
        case .hybrid3: return "3 Hybrid"
        case .hybrid4: return "4 Hybrid"
        case .hybrid5: return "5 Hybrid"
        case .iron2: return "2 Iron"
        case .iron3: return "3 Iron"
        case .iron4: return "4 Iron"
        case .iron5: return "5 Iron"
        case .iron6: return "6 Iron"
        case .iron7: return "7 Iron"
        case .iron8: return "8 Iron"
        case .iron9: return "9 Iron"
        case .pw: return "PW"
        case .gw: return "GW"
        case .sw: return "SW"
        case .lw: return "LW"
        case .putter: return "Putter"
        }
    }

    var isPutter: Bool { self == .putter }
}

enum ShotResult: String, Codable, CaseIterable {
    case fairway, rough, deepRough = "deep-rough"
    case bunker, water, ob
    case green, fringe, trees
    case recovery, holed

    var displayName: String {
        switch self {
        case .fairway: return "Fairway"
        case .rough: return "Rough"
        case .deepRough: return "Deep Rough"
        case .bunker: return "Bunker"
        case .water: return "Water"
        case .ob: return "OB"
        case .green: return "Green"
        case .fringe: return "Fringe"
        case .trees: return "Trees"
        case .recovery: return "Recovery"
        case .holed: return "Holed"
        }
    }

    var color: String {
        switch self {
        case .fairway, .green: return "green"
        case .water, .ob: return "red"
        case .bunker: return "yellow"
        default: return "gray"
        }
    }
}

// MARK: - GPS

struct GpsPoint: Codable, Equatable {
    let lat: Double
    let lng: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    init(lat: Double, lng: Double) {
        self.lat = lat
        self.lng = lng
    }

    init(coordinate: CLLocationCoordinate2D) {
        self.lat = coordinate.latitude
        self.lng = coordinate.longitude
    }
}

struct HoleHazard: Codable {
    let type: String       // "bunker", "water", "trees"
    let position: GpsPoint
    let label: String?
}

struct HoleGps: Codable {
    var tee: GpsPoint?
    var greenCenter: GpsPoint?
    var greenFront: GpsPoint?
    var greenBack: GpsPoint?
    var fairwayCenter: GpsPoint?
    var hazards: [HoleHazard]?
}

// MARK: - Shot

struct Shot: Codable, Identifiable {
    let id: UUID
    var shotNumber: Int
    var club: Club?
    var distanceYards: Int?
    var result: ShotResult?
    var isPenalty: Bool
    var isPutt: Bool
    var notes: String?

    init(
        id: UUID = UUID(),
        shotNumber: Int,
        club: Club? = nil,
        distanceYards: Int? = nil,
        result: ShotResult? = nil,
        isPenalty: Bool = false,
        isPutt: Bool = false,
        notes: String? = nil
    ) {
        self.id = id
        self.shotNumber = shotNumber
        self.club = club
        self.distanceYards = distanceYards
        self.result = result
        self.isPenalty = isPenalty
        self.isPutt = isPutt
        self.notes = notes
    }
}

// MARK: - Course Hole

struct CourseHoleData: Codable, Identifiable {
    var id: Int { holeNumber }
    let holeNumber: Int
    var par: Int
    var yardage: Int?
    var handicapIndex: Int?
    var gps: HoleGps?
}

// MARK: - Course Tee

struct CourseTee: Codable, Identifiable {
    var id: String { name }
    let name: String
    var rating: Double?
    var slope: Int?
    var holes: [CourseHoleData]
}

// MARK: - SwiftData Models

@Model
final class Course {
    @Attribute(.unique) var id: String
    var name: String
    var city: String?
    var state: String?
    var locationLat: Double?
    var locationLng: Double?
    var teesData: Data  // JSON-encoded [CourseTee]
    var createdAt: Date

    var tees: [CourseTee] {
        get {
            (try? JSONDecoder().decode([CourseTee].self, from: teesData)) ?? []
        }
        set {
            teesData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    var location: GpsPoint? {
        guard let lat = locationLat, let lng = locationLng else { return nil }
        return GpsPoint(lat: lat, lng: lng)
    }

    init(id: String = UUID().uuidString, name: String, city: String? = nil, state: String? = nil,
         location: GpsPoint? = nil, tees: [CourseTee] = []) {
        self.id = id
        self.name = name
        self.city = city
        self.state = state
        self.locationLat = location?.lat
        self.locationLng = location?.lng
        self.teesData = (try? JSONEncoder().encode(tees)) ?? Data()
        self.createdAt = Date()
    }
}

@Model
final class Round {
    @Attribute(.unique) var id: String
    var courseId: String
    var courseName: String
    var teeName: String
    var date: Date
    var holesData: Data  // JSON-encoded [HoleScore]
    var isComplete: Bool
    var currentHole: Int
    var createdAt: Date
    var updatedAt: Date

    // Store course tee data for GPS access during round
    var courseTeeData: Data?  // JSON-encoded CourseTee

    var holes: [HoleScore] {
        get {
            (try? JSONDecoder().decode([HoleScore].self, from: holesData)) ?? []
        }
        set {
            holesData = (try? JSONEncoder().encode(newValue)) ?? Data()
            updatedAt = Date()
        }
    }

    var courseTee: CourseTee? {
        get {
            guard let data = courseTeeData else { return nil }
            return try? JSONDecoder().decode(CourseTee.self, from: data)
        }
        set {
            courseTeeData = newValue.flatMap { try? JSONEncoder().encode($0) }
        }
    }

    init(id: String = UUID().uuidString, courseId: String, courseName: String, teeName: String,
         holes: [HoleScore], courseTee: CourseTee? = nil) {
        self.id = id
        self.courseId = courseId
        self.courseName = courseName
        self.teeName = teeName
        self.date = Date()
        self.holesData = (try? JSONEncoder().encode(holes)) ?? Data()
        self.isComplete = false
        self.currentHole = 1
        self.createdAt = Date()
        self.updatedAt = Date()
        self.courseTeeData = courseTee.flatMap { try? JSONEncoder().encode($0) }
    }
}

// MARK: - Hole Score (stored as JSON within Round)

struct HoleScore: Codable, Identifiable {
    var id: Int { holeNumber }
    let holeNumber: Int
    let par: Int
    var yardage: Int?
    var strokes: Int
    var putts: Int?
    var fairwayHit: Bool?
    var greenInRegulation: Bool?
    var upAndDown: Bool?
    var sandSave: Bool?
    var shots: [Shot]
    var notes: String?

    init(holeNumber: Int, par: Int, yardage: Int? = nil) {
        self.holeNumber = holeNumber
        self.par = par
        self.yardage = yardage
        self.strokes = 0
        self.shots = []
    }

    var scoreToPar: Int? {
        guard strokes > 0 else { return nil }
        return strokes - par
    }

    var scoreLabel: String {
        guard let diff = scoreToPar else { return "" }
        switch diff {
        case ...(-3): return "Albatross"
        case -2: return "Eagle"
        case -1: return "Birdie"
        case 0: return "Par"
        case 1: return "Bogey"
        case 2: return "Double"
        case 3: return "Triple"
        default: return "+\(diff)"
        }
    }
}
