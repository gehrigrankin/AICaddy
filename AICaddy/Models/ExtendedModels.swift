import Foundation
import SwiftData

// MARK: - Bag Management

@Model
final class GolfBag {
    @Attribute(.unique) var id: String
    var name: String
    var clubsData: Data  // JSON [BagClub]
    var createdAt: Date

    var clubs: [BagClub] {
        get { (try? JSONDecoder().decode([BagClub].self, from: clubsData)) ?? [] }
        set { clubsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    init(name: String = "My Bag", clubs: [BagClub] = BagClub.defaultBag) {
        self.id = UUID().uuidString
        self.name = name
        self.clubsData = (try? JSONEncoder().encode(clubs)) ?? Data()
        self.createdAt = Date()
    }
}

struct BagClub: Codable, Identifiable {
    let id: UUID
    var club: Club
    var brand: String?
    var model: String?
    var loft: Double?
    var swingThought: String?  // reminder that pops up when you use this club
    var manualYardage: Int?           // user-entered typical distance
    var learnedAvgYardage: Int?       // computed from tracked shots
    var learnedShotCount: Int?        // number of shots used for learned avg
    var dateAdded: Date

    /// The best available yardage: manual takes priority, then learned.
    var effectiveYardage: Int? {
        manualYardage ?? learnedAvgYardage
    }

    init(club: Club, brand: String? = nil, model: String? = nil, loft: Double? = nil, swingThought: String? = nil, manualYardage: Int? = nil, learnedAvgYardage: Int? = nil, learnedShotCount: Int? = nil) {
        self.id = UUID()
        self.club = club
        self.brand = brand
        self.model = model
        self.loft = loft
        self.swingThought = swingThought
        self.manualYardage = manualYardage
        self.learnedAvgYardage = learnedAvgYardage
        self.learnedShotCount = learnedShotCount
        self.dateAdded = Date()
    }

    static var defaultBag: [BagClub] {
        [.driver, .wood3, .hybrid4, .iron5, .iron6, .iron7, .iron8, .iron9, .pw, .gw, .sw, .lw, .putter]
            .map { BagClub(club: $0) }
    }
}

// MARK: - Equipment Tracking

@Model
final class EquipmentLog {
    @Attribute(.unique) var id: String
    var itemType: String     // "ball", "grip", "shaft", "club", "glove"
    var itemName: String     // "Pro V1", "Golf Pride MCC", etc.
    var club: String?        // which club if applicable
    var dateStarted: Date
    var dateEnded: Date?
    var notes: String?

    init(itemType: String, itemName: String, club: String? = nil, notes: String? = nil) {
        self.id = UUID().uuidString
        self.itemType = itemType
        self.itemName = itemName
        self.club = club
        self.dateStarted = Date()
        self.notes = notes
    }
}

// MARK: - Course Conditions

struct CourseCondition: Codable {
    var greenSpeed: GreenSpeed?
    var fairwayCondition: String?   // "firm", "soft", "wet"
    var windDirection: String?      // "N", "NE", etc.
    var windSpeedMph: Int?
    var temperature: Int?           // Fahrenheit
    var notes: String?

    enum GreenSpeed: String, Codable, CaseIterable {
        case slow, medium, fast, veryFast = "very-fast"
        var displayName: String {
            switch self {
            case .slow: return "Slow"
            case .medium: return "Medium"
            case .fast: return "Fast"
            case .veryFast: return "Very Fast"
            }
        }
    }
}

// MARK: - Pin Position

enum PinPosition: String, Codable, CaseIterable {
    case front, frontLeft = "front-left", frontRight = "front-right"
    case middle, middleLeft = "middle-left", middleRight = "middle-right"
    case back, backLeft = "back-left", backRight = "back-right"

    var shortLabel: String {
        switch self {
        case .front: return "F"
        case .frontLeft: return "FL"
        case .frontRight: return "FR"
        case .middle: return "M"
        case .middleLeft: return "ML"
        case .middleRight: return "MR"
        case .back: return "B"
        case .backLeft: return "BL"
        case .backRight: return "BR"
        }
    }
}

// MARK: - Shot with GPS location (for shot tracer)

struct ShotLocation: Codable {
    let start: GpsPoint
    let end: GpsPoint
    let club: Club?
    let distanceYards: Int
}
