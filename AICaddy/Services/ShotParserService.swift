import Foundation

/// Parsed result from voice/text input
struct ParsedShotInput {
    var shots: [Shot]
    var putts: Int?
    var totalStrokes: Int?
    var fairwayHit: Bool?
    var greenInRegulation: Bool?
    var confidence: Double
}

/// Parses natural language shot descriptions into structured data.
/// Uses Claude API when available, falls back to local regex parsing.
final class ShotParserService {
    private let apiKey: String?

    init(apiKey: String? = nil) {
        self.apiKey = apiKey ?? Bundle.main.object(forInfoDictionaryKey: "ANTHROPIC_API_KEY") as? String
    }

    func parse(
        input: String,
        holeNumber: Int,
        par: Int,
        yardage: Int?,
        currentShotNumber: Int
    ) async -> ParsedShotInput {
        // Try Claude API first
        if let apiKey, !apiKey.isEmpty {
            if let result = await parseWithClaude(
                input: input, apiKey: apiKey,
                holeNumber: holeNumber, par: par,
                yardage: yardage, currentShotNumber: currentShotNumber
            ) {
                return result
            }
        }

        // Fall back to local parser
        return localParse(input: input, par: par, currentShotNumber: currentShotNumber)
    }

    // MARK: - Claude API

    private func parseWithClaude(
        input: String, apiKey: String,
        holeNumber: Int, par: Int, yardage: Int?, currentShotNumber: Int
    ) async -> ParsedShotInput? {
        let systemPrompt = """
        You are a golf shot parser. Given a golfer's spoken description, extract structured data.
        Return ONLY valid JSON:
        {
          "shots": [{"shotNumber": N, "club": "string|null", "distanceYards": N|null, "result": "string|null", "isPenalty": bool, "isPutt": bool}],
          "putts": N|null, "totalStrokes": N|null, "fairwayHit": bool|null,
          "greenInRegulation": bool|null, "confidence": 0.0-1.0
        }
        Club values: driver, 3-wood, 5-wood, 7-wood, 2-hybrid through 5-hybrid, 2-iron through 9-iron, pw, gw, sw, lw, putter.
        Result values: fairway, rough, deep-rough, bunker, water, ob, green, fringe, trees, recovery, holed.
        If just a number like "4", that's totalStrokes. "par","bogey","birdie","eagle","double","triple" are relative to par.
        """

        let userMsg = "Hole \(holeNumber), Par \(par)\(yardage.map { ", \($0) yards" } ?? ""). Shot #\(currentShotNumber). Golfer says: \"\(input)\""

        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 512,
            "system": systemPrompt,
            "messages": [["role": "user", "content": userMsg]]
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return nil }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = bodyData

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = (json["content"] as? [[String: Any]])?.first,
              let text = content["text"] as? String,
              let jsonRange = text.range(of: "\\{[\\s\\S]*\\}", options: .regularExpression),
              let parsed = try? JSONSerialization.jsonObject(with: Data(text[jsonRange].utf8)) as? [String: Any]
        else { return nil }

        return convertAPIResponse(parsed, currentShotNumber: currentShotNumber)
    }

    private func convertAPIResponse(_ json: [String: Any], currentShotNumber: Int) -> ParsedShotInput {
        var result = ParsedShotInput(shots: [], confidence: json["confidence"] as? Double ?? 0.7)

        result.totalStrokes = json["totalStrokes"] as? Int
        result.putts = json["putts"] as? Int
        result.fairwayHit = json["fairwayHit"] as? Bool
        result.greenInRegulation = json["greenInRegulation"] as? Bool

        if let shotsArr = json["shots"] as? [[String: Any]] {
            for (i, s) in shotsArr.enumerated() {
                let club = (s["club"] as? String).flatMap { Club(rawValue: $0) }
                let shotResult = (s["result"] as? String).flatMap { ShotResult(rawValue: $0) }
                let shot = Shot(
                    shotNumber: s["shotNumber"] as? Int ?? currentShotNumber + i,
                    club: club,
                    distanceYards: s["distanceYards"] as? Int,
                    result: shotResult,
                    isPenalty: s["isPenalty"] as? Bool ?? false,
                    isPutt: s["isPutt"] as? Bool ?? false
                )
                result.shots.append(shot)
            }
        }

        return result
    }

    // MARK: - Local Parser

    // Expanded aliases — speech recognition often returns number words, plurals, etc.
    private static let clubAliases: [(String, Club)] = [
        // Driver
        ("driver", .driver), ("drive", .driver), ("drove", .driver), ("big dog", .driver), ("big stick", .driver),
        // Woods
        ("3 wood", .wood3), ("3wood", .wood3), ("three wood", .wood3),
        ("5 wood", .wood5), ("5wood", .wood5), ("five wood", .wood5),
        ("7 wood", .wood7), ("7wood", .wood7), ("seven wood", .wood7),
        // Hybrids
        ("2 hybrid", .hybrid2), ("two hybrid", .hybrid2),
        ("3 hybrid", .hybrid3), ("three hybrid", .hybrid3),
        ("4 hybrid", .hybrid4), ("four hybrid", .hybrid4), ("hybrid", .hybrid4),
        ("5 hybrid", .hybrid5), ("five hybrid", .hybrid5),
        // Irons — include "iron" and just the number patterns
        ("2 iron", .iron2), ("two iron", .iron2),
        ("3 iron", .iron3), ("three iron", .iron3),
        ("4 iron", .iron4), ("four iron", .iron4),
        ("5 iron", .iron5), ("five iron", .iron5),
        ("6 iron", .iron6), ("six iron", .iron6),
        ("7 iron", .iron7), ("seven iron", .iron7),
        ("8 iron", .iron8), ("eight iron", .iron8),
        ("9 iron", .iron9), ("nine iron", .iron9),
        // Wedges — common spoken forms
        ("pitching wedge", .pw), ("pitch", .pw), ("pw", .pw), ("p w", .pw),
        ("gap wedge", .gw), ("gw", .gw), ("g w", .gw), ("52", .gw), ("52 degree", .gw),
        ("sand wedge", .sw), ("sw", .sw), ("s w", .sw), ("56", .sw), ("56 degree", .sw),
        ("lob wedge", .lw), ("lw", .lw), ("l w", .lw), ("lob", .lw), ("60", .lw), ("60 degree", .lw),
        // Putter
        ("putter", .putter), ("putt", .putter), ("putted", .putter), ("putting", .putter),
    ]

    private static let resultAliases: [(String, ShotResult)] = [
        // Fairway
        ("fairway", .fairway), ("in the fairway", .fairway), ("hit fairway", .fairway),
        ("found the fairway", .fairway), ("middle of the fairway", .fairway), ("split the fairway", .fairway),
        // Rough
        ("rough", .rough), ("in the rough", .rough), ("left rough", .rough), ("right rough", .rough),
        ("first cut", .rough), ("light rough", .rough),
        ("deep rough", .deepRough), ("thick rough", .deepRough), ("heavy rough", .deepRough),
        // Bunker
        ("bunker", .bunker), ("sand", .bunker), ("trap", .bunker), ("sand trap", .bunker),
        ("greenside bunker", .bunker), ("fairway bunker", .bunker), ("in the sand", .bunker),
        ("beach", .bunker),
        // Water
        ("water", .water), ("hazard", .water), ("in the water", .water), ("wet", .water),
        ("lake", .water), ("pond", .water), ("creek", .water),
        // OB
        ("ob", .ob), ("out of bounds", .ob), ("o.b.", .ob), ("o b", .ob),
        // Green
        ("green", .green), ("on the green", .green), ("on green", .green),
        ("pin high", .green), ("hit the green", .green), ("found the green", .green),
        ("on the dance floor", .green), ("gir", .green),
        // Fringe
        ("fringe", .fringe), ("on the fringe", .fringe), ("just off the green", .fringe),
        ("collar", .fringe), ("apron", .fringe),
        // Trees
        ("trees", .trees), ("in the trees", .trees), ("woods", .trees),
        // Recovery
        ("recovery", .recovery), ("punch", .recovery), ("punch out", .recovery),
        ("chip out", .recovery),
        // Holed
        ("holed", .holed), ("hole in one", .holed), ("holed out", .holed),
        ("jarred it", .holed), ("drained it", .holed),
    ]

    // Longest aliases first so specific phrases win over their substrings
    // (e.g. "on the green" must beat "sand" for "sand wedge on the green").
    private static let clubAliasesByLength = clubAliases.sorted { $0.0.count > $1.0.count }
    private static let resultAliasesByLength = resultAliases.sorted { $0.0.count > $1.0.count }

    /// Whole-word alias match. Plain `contains` corrupted data: the "52"/"56"/"60"
    /// wedge aliases matched inside distances ("152 yards" became a gap wedge).
    private static func aliasRange(_ alias: String, in text: String) -> Range<String.Index>? {
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: alias) + "\\b"
        return text.range(of: pattern, options: .regularExpression)
    }

    func localParse(input: String, par: Int, currentShotNumber: Int) -> ParsedShotInput {
        let lower = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        var result = ParsedShotInput(shots: [], confidence: 0.6)

        // Simple score: "4", "par", "bogey", "birdie 2 putts"
        if let simple = parseSimpleScore(lower, par: par) {
            result.totalStrokes = simple.strokes
            result.putts = simple.putts
            result.confidence = 0.8
            return result
        }

        // Putts only: "2 putts", "one putt", "3 putt" — but only when the input
        // is nothing BUT putts. Previously "par with 2 putts" landed here and the
        // score was silently dropped.
        if let match = lower.range(of: #"(\d|one|two|three|four)\s*putts?"#, options: .regularExpression) {
            let remainder = lower
                .replacingOccurrences(of: #"(\d|one|two|three|four)\s*putts?"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: #"[,.!?]"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: #"\b(i|had|made|just|only|took|with|a|an|the|and|then)\b"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            if remainder.isEmpty {
                result.putts = parseNumberWord(String(lower[match]))
                result.confidence = 0.9
                return result
            }
        }

        // "chip and a putt" / "up and down" patterns
        if lower.contains("chip and a putt") || lower.contains("chip and putt") ||
           lower.contains("up and down") || lower.contains("up-and-down") {
            var chip = Shot(shotNumber: currentShotNumber, isPutt: false)
            chip.result = .green
            var putt = Shot(shotNumber: currentShotNumber + 1, club: .putter, isPutt: true)
            putt.result = .holed
            result.shots = [chip, putt]
            result.putts = 1
            result.confidence = 0.85
            return result
        }

        // "chip and 2 putts" pattern
        if let match = lower.range(of: #"chip.*?(\d|one|two|three)\s*putts?"#, options: .regularExpression) {
            let matchStr = String(lower[match])
            let puttCount = parseNumberWord(matchStr) ?? 2
            var chip = Shot(shotNumber: currentShotNumber, isPutt: false)
            chip.result = .green
            result.shots = [chip]
            for i in 0..<puttCount {
                result.shots.append(Shot(shotNumber: currentShotNumber + 1 + i, club: .putter, isPutt: true))
            }
            result.putts = puttCount
            result.confidence = 0.85
            return result
        }

        // Parse individual shots from comma/semicolon/then-separated segments
        let segments = lower.components(separatedBy: CharacterSet(charactersIn: ",;"))
            .flatMap { $0.components(separatedBy: " then ") }
            .flatMap { $0.components(separatedBy: " and ") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var shotNum = currentShotNumber
        for seg in segments {
            if let shot = parseShotSegment(seg, shotNumber: shotNum) {
                result.shots.append(shot)
                shotNum += 1
            }
        }

        // Fairway detection — FIR is a tee-shot stat. Only set it when this
        // input describes the first shot; otherwise a par-5 layup that finds
        // the fairway would incorrectly mark the fairway as hit.
        if currentShotNumber == 1 {
            if lower.contains("fairway") { result.fairwayHit = true }
            if lower.contains("missed fairway") || lower.contains("miss fairway") ||
               lower.contains("missed the fairway") { result.fairwayHit = false }
        }

        // GIR detection
        if lower.contains("gir") || lower.contains("green in regulation") ||
           lower.contains("green in reg") { result.greenInRegulation = true }
        if lower.contains("missed the green") || lower.contains("missed green") { result.greenInRegulation = false }

        // Also extract putts mentioned anywhere in the input
        if result.putts == nil {
            if let match = lower.range(of: #"(\d|one|two|three|four)\s*putts?"#, options: .regularExpression) {
                result.putts = parseNumberWord(String(lower[match]))
            }
        }

        result.confidence = result.shots.isEmpty ? 0.4 : 0.7
        return result
    }

    /// Parse number words that speech recognition might return
    private func parseNumberWord(_ s: String) -> Int? {
        if s.contains("one") || s.contains("1") { return 1 }
        if s.contains("two") || s.contains("2") { return 2 }
        if s.contains("three") || s.contains("3") { return 3 }
        if s.contains("four") || s.contains("4") { return 4 }
        if s.contains("five") || s.contains("5") { return 5 }
        // Try extracting first digit
        if let digit = s.first(where: \.isNumber) { return Int(String(digit)) }
        return nil
    }

    private func parseShotSegment(_ seg: String, shotNumber: Int) -> Shot? {
        var club: Club?
        var dist: Int?
        var shotResult: ShotResult?
        var matched = false

        // Match the club first and strip its text, so numeric aliases ("52",
        // "56", "60") and words like "sand wedge" can't also be read as a
        // distance or a result ("sand" → bunker).
        var remainder = seg
        for (alias, c) in Self.clubAliasesByLength {
            if let range = Self.aliasRange(alias, in: remainder) {
                club = c
                matched = true
                remainder.replaceSubrange(range, with: " ")
                break
            }
        }

        if let match = remainder.range(of: #"\b(\d{2,3})\b\s*(?:yards?|yds?)?"#, options: .regularExpression) {
            let numStr = remainder[match].filter(\.isNumber)
            dist = Int(numStr)
            matched = true
        }

        for (alias, r) in Self.resultAliasesByLength {
            if Self.aliasRange(alias, in: remainder) != nil {
                shotResult = r
                matched = true
                break
            }
        }

        guard matched else { return nil }

        let isPenalty = shotResult == .water || shotResult == .ob
            || Self.aliasRange("penalty", in: seg) != nil

        return Shot(
            shotNumber: shotNumber,
            club: club,
            distanceYards: dist,
            result: shotResult,
            isPenalty: isPenalty,
            isPutt: club == .putter
        )
    }

    private func parseSimpleScore(_ input: String, par: Int) -> (strokes: Int, putts: Int?)? {
        // Normalize punctuation so "par, 2 putts" isn't rejected for the comma.
        let cleaned = input
            .replacingOccurrences(of: #"[,.!?]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        var putts: Int?
        if let match = cleaned.range(of: #"(\d|one|two|three|four)\s*putts?"#, options: .regularExpression) {
            putts = parseNumberWord(String(cleaned[match]))
        }

        let scorePart = cleaned
            .replacingOccurrences(of: #"(\d|one|two|three|four)\s*putts?"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\b(with|and)\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        let strokes: Int?
        switch scorePart {
        case "ace", "hole in one": strokes = 1
        case "albatross", "double eagle": strokes = par - 3
        case "eagle": strokes = par - 2
        case "birdie": strokes = par - 1
        case "par": strokes = par
        case "bogey": strokes = par + 1
        case "double", "double bogey": strokes = par + 2
        case "triple", "triple bogey": strokes = par + 3
        default:
            if let n = Int(scorePart), (1...15).contains(n) { strokes = n }
            else { strokes = nil }
        }

        guard let s = strokes else { return nil }
        return (s, putts)
    }
}
