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
    /// Overpass is a free, per-IP rate-limited service — one busy mirror must
    /// not kill course search, so fall through the list on failure.
    private let overpassMirrors = [
        "https://overpass-api.de/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter",
    ]
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

        // Fetch the course element plus all golf features near its geometry.
        // `around.course` works for ways, relations AND nodes — the old
        // way-branch only fetched the course boundary itself, so way-mapped
        // courses (most of them) loaded with ZERO hole data and the map fell
        // back to the user's location.
        let query = """
        [out:json][timeout:25];
        \(osmType)(\(osmId))->.course;
        .course out center tags;
        .course out body;
        .course >;
        out skel qt;
        (
          way["golf"](around.course:100);
          node["golf"](around.course:100);
          way["natural"="water"](around.course:100);
          way["landuse"="reservoir"](around.course:100);
        );
        out body;
        >>;
        out skel qt;
        """

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

        // Fill gaps so every hole 1...N exists — a round that lands on an
        // unmapped hole number renders a blank screen. Empty data becomes a
        // standard 18 blank holes.
        let normalizedHoles = Self.normalizedHoles(holeDataList)

        let tees = [CourseTee(name: "Default", holes: normalizedHoles)]
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
            var fairwayPath: [GpsPoint] = []  // intermediate nodes of the hole way
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
                    // A neighboring course's holes can land inside the fetch
                    // buffer — if this ref is already populated, keep whichever
                    // hole way sits nearer the course center.
                    if let existingTee = holeMap[num]?.tee, let courseLoc = courseLocation,
                       let newTee = (el["nodes"] as? [Int]).flatMap({ $0.first.flatMap { nodeCoords[$0] } }) {
                        let existingDist = LocationService.distanceYards(
                            from: existingTee.coordinate, to: courseLoc.coordinate)
                        let newDist = LocationService.distanceYards(
                            from: newTee.coordinate, to: courseLoc.coordinate)
                        if newDist >= existingDist { break }
                        holeMap[num] = HoleFeatures()
                    }
                    if holeMap[num] == nil { holeMap[num] = HoleFeatures() }
                    if let par = tags["par"].flatMap({ Int($0) }) { holeMap[num]?.par = par }
                    if let hcp = tags["handicap"].flatMap({ Int($0) }) { holeMap[num]?.handicap = hcp }
                    // Hole way — first node is tee, last is green, middle nodes trace fairway centerline
                    if let nodes = el["nodes"] as? [Int], nodes.count >= 2 {
                        if let teeCoord = nodeCoords[nodes.first!] { holeMap[num]?.tee = teeCoord }
                        if let greenCoord = nodeCoords[nodes.last!] { holeMap[num]?.green = greenCoord }
                        // Capture intermediate nodes as fairway path
                        if nodes.count > 2 {
                            let middleNodes = nodes.dropFirst().dropLast()
                            holeMap[num]?.fairwayPath = middleNodes.compactMap { nodeCoords[$0] }
                        }
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
                fairwayPath: f.fairwayPath.isEmpty ? nil : f.fairwayPath,
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

    /// Fill gaps in partially-mapped courses so every hole 1...N is playable.
    /// A well-mapped nine (5+ holes, none past 9) stays 9; sparse data
    /// defaults to 18 — capping a real 18-hole course would lose the back nine.
    static func normalizedHoles(_ holes: [CourseHoleData]) -> [CourseHoleData] {
        guard let maxNumber = holes.map(\.holeNumber).max() else {
            return (1...18).map { CourseHoleData(holeNumber: $0, par: 4) }
        }
        let looksLikeNine = maxNumber <= 9 && holes.count >= 5
        let target = looksLikeNine ? 9 : max(maxNumber, 18)

        var byNumber: [Int: CourseHoleData] = [:]
        for hole in holes where (1...36).contains(hole.holeNumber) {
            byNumber[hole.holeNumber] = hole
        }
        return (1...target).map { byNumber[$0] ?? CourseHoleData(holeNumber: $0, par: 4) }
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
        var lastError: Error = CourseSearchError.apiError
        for (index, mirror) in overpassMirrors.enumerated() {
            do {
                return try await overpassRequest(base: mirror, query: query)
            } catch {
                lastError = error
                // Give the next mirror a beat — most failures are rate limits
                if index + 1 < overpassMirrors.count {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                }
            }
        }
        throw lastError
    }

    private func overpassRequest(base: String, query: String) async throws -> Data {
        var request = URLRequest(url: URL(string: base)!)
        request.httpMethod = "POST"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        // Strict form encoding — .urlQueryAllowed leaves characters like '+'
        // and '&' unescaped, which corrupts the body.
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        request.httpBody = "data=\(encoded)".data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            // 429/504 = rate limited or overloaded — worth telling the user
            // it's temporary rather than "failed"
            throw (status == 429 || status == 504) ? CourseSearchError.busy : CourseSearchError.apiError
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
    case busy
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .apiError: return "Course search failed — check your connection"
        case .busy: return "Course data service is busy — try again in a minute"
        case .invalidResponse: return "Invalid response from course API"
        }
    }
}
