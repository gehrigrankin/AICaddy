import Foundation
import CoreLocation

struct CourseSearchResult: Identifiable {
    let id: String
    let name: String
    let city: String?
    let state: String?
    let location: GpsPoint?
}

/// Searches for golf courses via OpenStreetMap (Nominatim + Overpass APIs)
final class CourseSearchService {
    private let nominatimBase = "https://nominatim.openstreetmap.org"
    private let overpassBase = "https://overpass-api.de/api/interpreter"
    private let userAgent = "AICaddy/1.0"

    var isConfigured: Bool { true }

    // MARK: - Search

    func searchByName(_ name: String) async throws -> [CourseSearchResult] {
        guard let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return []
        }
        let url = URL(string: "\(nominatimBase)/search?q=\(encoded)+golf+course&format=json&limit=20&addressdetails=1")!
        let data = try await fetch(url: url)
        let results = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []

        return results.compactMap { parseCourseFromNominatim($0) }
    }

    func searchNearby(lat: Double, lng: Double, radius: Int = 30) async throws -> [CourseSearchResult] {
        let radiusMeters = radius * 1609 // miles to meters
        let query = """
        [out:json][timeout:15];
        (
          way["leisure"="golf_course"](around:\(radiusMeters),\(lat),\(lng));
          relation["leisure"="golf_course"](around:\(radiusMeters),\(lat),\(lng));
          node["leisure"="golf_course"](around:\(radiusMeters),\(lat),\(lng));
        );
        out center tags;
        """
        let data = try await overpassQuery(query)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let elements = json["elements"] as? [[String: Any]] ?? []

        return elements.compactMap { parseCourseFromOverpass($0) }
    }

    // MARK: - Course Details

    func fetchCourseDetails(id: String) async throws -> (tees: [CourseTee], name: String, city: String?, state: String?, location: GpsPoint?) {
        // The id is "way/123" or "relation/123" or "node/123"
        let parts = id.split(separator: "/")
        guard parts.count == 2 else { throw CourseSearchError.invalidResponse }
        let osmType = String(parts[0])
        let osmId = String(parts[1])

        // Fetch the course boundary and all golf-related features within it
        let query: String
        if osmType == "relation" {
            query = """
            [out:json][timeout:25];
            rel(\(osmId));
            out body;
            >>;
            out skel qt;
            rel(\(osmId));
            map_to_area->.course;
            (
              way["golf"](area.course);
              node["golf"](area.course);
              way["natural"="water"](area.course);
              way["landuse"="reservoir"](area.course);
            );
            out body;
            >>;
            out skel qt;
            """
        } else {
            // For way-based courses, search within a bounding box around the course
            query = """
            [out:json][timeout:25];
            \(osmType)(\(osmId));
            out body;
            >>;
            out skel qt;
            """
        }

        let data = try await overpassQuery(query)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let elements = json["elements"] as? [[String: Any]] ?? []

        // Find the course element for metadata
        let courseElement = elements.first { el in
            let elId = el["id"] as? Int
            let elType = el["type"] as? String
            return elType == osmType && "\(elId ?? 0)" == osmId
        }

        let tags = courseElement?["tags"] as? [String: String] ?? [:]
        let courseName = tags["name"] ?? "Unknown Course"
        let city = tags["addr:city"]
        let state = tags["addr:state"]

        // Get course center point
        let location = extractCenter(from: courseElement, elements: elements)

        // Parse golf features into hole data
        let holeDataList = parseHoles(from: elements, courseLocation: location)

        // Build a single default tee (OSM doesn't have rating/slope data)
        var tees: [CourseTee]
        if holeDataList.isEmpty {
            // No hole data found — create 18 blank holes
            let blankHoles = (1...18).map { CourseHoleData(holeNumber: $0, par: 4) }
            tees = [CourseTee(name: "Default", holes: blankHoles)]
        } else {
            tees = [CourseTee(name: "Default", holes: holeDataList)]
        }

        return (tees, courseName, city, state, location)
    }

    // MARK: - Parsing

    private func parseCourseFromNominatim(_ item: [String: Any]) -> CourseSearchResult? {
        // Filter to golf-related results
        let type = item["type"] as? String ?? ""
        let category = item["class"] as? String ?? ""
        let displayName = item["display_name"] as? String ?? ""

        let isGolf = category == "leisure" || type == "golf_course" ||
            displayName.localizedCaseInsensitiveContains("golf")
        guard isGolf else { return nil }

        let osmType = item["osm_type"] as? String ?? "node"
        let osmId = item["osm_id"] as? Int ?? 0
        let typePrefix: String
        switch osmType {
        case "way": typePrefix = "way"
        case "relation": typePrefix = "relation"
        default: typePrefix = "node"
        }

        let address = item["address"] as? [String: Any]
        let name = item["name"] as? String ?? (address?["leisure"] as? String) ?? displayName.components(separatedBy: ",").first ?? "Unknown"

        var location: GpsPoint?
        if let latStr = item["lat"] as? String, let lngStr = item["lon"] as? String,
           let lat = Double(latStr), let lng = Double(lngStr) {
            location = GpsPoint(lat: lat, lng: lng)
        }

        let city = (address?["city"] as? String) ?? (address?["town"] as? String) ?? (address?["village"] as? String)
        let state = address?["state"] as? String

        return CourseSearchResult(
            id: "\(typePrefix)/\(osmId)",
            name: name,
            city: city,
            state: state,
            location: location
        )
    }

    private func parseCourseFromOverpass(_ element: [String: Any]) -> CourseSearchResult? {
        let tags = element["tags"] as? [String: String] ?? [:]
        guard let name = tags["name"] else { return nil }

        let type = element["type"] as? String ?? "node"
        let id = element["id"] as? Int ?? 0

        var location: GpsPoint?
        if let lat = element["lat"] as? Double, let lng = element["lon"] as? Double {
            location = GpsPoint(lat: lat, lng: lng)
        } else if let center = element["center"] as? [String: Double],
                  let lat = center["lat"], let lng = center["lon"] {
            location = GpsPoint(lat: lat, lng: lng)
        }

        let city = tags["addr:city"]
        let state = tags["addr:state"]

        return CourseSearchResult(
            id: "\(type)/\(id)",
            name: name,
            city: city,
            state: state,
            location: location
        )
    }

    private func parseHoles(from elements: [[String: Any]], courseLocation: GpsPoint?) -> [CourseHoleData] {
        // Collect all node coordinates for resolving way geometries
        var nodeCoords: [Int: GpsPoint] = [:]
        for el in elements where el["type"] as? String == "node" {
            if let id = el["id"] as? Int,
               let lat = el["lat"] as? Double,
               let lng = el["lon"] as? Double {
                nodeCoords[id] = GpsPoint(lat: lat, lng: lng)
            }
        }

        // Group golf features by hole number
        struct HoleFeatures {
            var par: Int = 4
            var handicap: Int?
            var tee: GpsPoint?
            var green: GpsPoint?
            var bunkers: [GpsPoint] = []
            var water: [GpsPoint] = []
            var fairway: GpsPoint?
        }

        var holeMap: [Int: HoleFeatures] = [:]

        for el in elements {
            let tags = el["tags"] as? [String: String] ?? [:]
            let golfTag = tags["golf"] ?? ""

            // Determine hole number
            var holeNumber: Int?
            if let ref = tags["ref"], let num = Int(ref) { holeNumber = num }

            // Get the centroid of this element
            let centroid = elementCentroid(el, nodeCoords: nodeCoords)

            switch golfTag {
            case "hole":
                if let num = holeNumber {
                    if holeMap[num] == nil { holeMap[num] = HoleFeatures() }
                    if let par = tags["par"].flatMap({ Int($0) }) { holeMap[num]?.par = par }
                    if let hcp = tags["handicap"].flatMap({ Int($0) }) { holeMap[num]?.handicap = hcp }
                    // Hole way — first node is tee area, last node is green area
                    if let nodes = el["nodes"] as? [Int], nodes.count >= 2 {
                        if let teeCoord = nodeCoords[nodes.first!] { holeMap[num]?.tee = teeCoord }
                        if let greenCoord = nodeCoords[nodes.last!] { holeMap[num]?.green = greenCoord }
                    }
                }

            case "tee":
                if let num = holeNumber, let c = centroid {
                    if holeMap[num] == nil { holeMap[num] = HoleFeatures() }
                    holeMap[num]?.tee = c
                }

            case "green":
                if let num = holeNumber, let c = centroid {
                    if holeMap[num] == nil { holeMap[num] = HoleFeatures() }
                    holeMap[num]?.green = c
                }

            case "bunker":
                if let num = holeNumber, let c = centroid {
                    if holeMap[num] == nil { holeMap[num] = HoleFeatures() }
                    holeMap[num]?.bunkers.append(c)
                }

            case "water_hazard", "lateral_water_hazard":
                if let num = holeNumber, let c = centroid {
                    if holeMap[num] == nil { holeMap[num] = HoleFeatures() }
                    holeMap[num]?.water.append(c)
                }

            case "fairway":
                if let num = holeNumber, let c = centroid {
                    if holeMap[num] == nil { holeMap[num] = HoleFeatures() }
                    holeMap[num]?.fairway = c
                }

            default:
                // Check for water features
                let natural = tags["natural"] ?? ""
                let landuse = tags["landuse"] ?? ""
                if natural == "water" || landuse == "reservoir" {
                    if let num = holeNumber, let c = centroid {
                        if holeMap[num] == nil { holeMap[num] = HoleFeatures() }
                        holeMap[num]?.water.append(c)
                    }
                }
            }
        }

        // Convert to CourseHoleData
        return holeMap.keys.sorted().map { num in
            let f = holeMap[num]!
            var hazards: [HoleHazard] = []
            for b in f.bunkers {
                hazards.append(HoleHazard(type: "bunker", position: b, label: nil))
            }
            for w in f.water {
                hazards.append(HoleHazard(type: "water", position: w, label: nil))
            }

            let gps = HoleGps(
                tee: f.tee,
                greenCenter: f.green,
                greenFront: nil,
                greenBack: nil,
                fairwayCenter: f.fairway,
                hazards: hazards.isEmpty ? nil : hazards
            )

            let hasGps = gps.tee != nil || gps.greenCenter != nil
            return CourseHoleData(
                holeNumber: num,
                par: f.par,
                yardage: yardageFromGps(tee: f.tee, green: f.green),
                handicapIndex: f.handicap,
                gps: hasGps ? gps : nil
            )
        }
    }

    private func elementCentroid(_ element: [String: Any], nodeCoords: [Int: GpsPoint]) -> GpsPoint? {
        if let lat = element["lat"] as? Double, let lng = element["lon"] as? Double {
            return GpsPoint(lat: lat, lng: lng)
        }
        if let center = element["center"] as? [String: Double],
           let lat = center["lat"], let lng = center["lon"] {
            return GpsPoint(lat: lat, lng: lng)
        }
        // For ways, average the node coordinates
        if let nodes = element["nodes"] as? [Int] {
            let coords = nodes.compactMap { nodeCoords[$0] }
            guard !coords.isEmpty else { return nil }
            let avgLat = coords.map(\.lat).reduce(0, +) / Double(coords.count)
            let avgLng = coords.map(\.lng).reduce(0, +) / Double(coords.count)
            return GpsPoint(lat: avgLat, lng: avgLng)
        }
        return nil
    }

    private func extractCenter(from element: [String: Any]?, elements: [[String: Any]]) -> GpsPoint? {
        guard let element else { return nil }
        if let lat = element["lat"] as? Double, let lng = element["lon"] as? Double {
            return GpsPoint(lat: lat, lng: lng)
        }
        if let center = element["center"] as? [String: Double],
           let lat = center["lat"], let lng = center["lon"] {
            return GpsPoint(lat: lat, lng: lng)
        }
        // Average all node coords from way members
        if let nodes = element["nodes"] as? [Int] {
            var nodeCoords: [GpsPoint] = []
            for el in elements where el["type"] as? String == "node" {
                if let id = el["id"] as? Int, nodes.contains(id),
                   let lat = el["lat"] as? Double, let lng = el["lon"] as? Double {
                    nodeCoords.append(GpsPoint(lat: lat, lng: lng))
                }
            }
            guard !nodeCoords.isEmpty else { return nil }
            let avgLat = nodeCoords.map(\.lat).reduce(0, +) / Double(nodeCoords.count)
            let avgLng = nodeCoords.map(\.lng).reduce(0, +) / Double(nodeCoords.count)
            return GpsPoint(lat: avgLat, lng: avgLng)
        }
        return nil
    }

    private func yardageFromGps(tee: GpsPoint?, green: GpsPoint?) -> Int? {
        guard let tee, let green else { return nil }
        let teeLocation = CLLocation(latitude: tee.lat, longitude: tee.lng)
        let greenLocation = CLLocation(latitude: green.lat, longitude: green.lng)
        let meters = teeLocation.distance(from: greenLocation)
        return Int(meters * 1.09361) // meters to yards
    }

    // MARK: - Networking

    private func overpassQuery(_ query: String) async throws -> Data {
        var request = URLRequest(url: URL(string: overpassBase)!)
        request.httpMethod = "POST"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "data=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")".data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw CourseSearchError.apiError
        }
        return data
    }

    private func fetch(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw CourseSearchError.apiError
        }
        return data
    }
}

enum CourseSearchError: LocalizedError {
    case apiError
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .apiError: return "Course search failed"
        case .invalidResponse: return "Invalid response from course API"
        }
    }
}
