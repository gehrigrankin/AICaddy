import Foundation
import CoreLocation

/// The AI Caddy brain — pre-round strategy, in-round tips, predictive scoring,
/// natural conversation, and practice plan generation.
final class AICaddyService {
    private let apiKey: String?

    init(apiKey: String? = nil) {
        self.apiKey = apiKey ?? Bundle.main.object(forInfoDictionaryKey: "ANTHROPIC_API_KEY") as? String
    }

    // MARK: - Pre-Round Strategy

    /// Generate a game plan before you tee off
    func preRoundStrategy(
        courseName: String,
        holes: [CourseHoleData],
        playerStats: PeriodStats,
        clubAverages: [(club: Club, avg: Int, count: Int)]
    ) async -> PreRoundPlan? {
        guard let apiKey, !apiKey.isEmpty else { return nil }

        let clubStr = clubAverages.map { "\($0.club.displayName): \($0.avg)y" }.joined(separator: ", ")
        let holesStr = holes.map { h in
            "Hole \(h.holeNumber): Par \(h.par), \(h.yardage ?? 0)y"
        }.joined(separator: "\n")

        let prompt = """
        Create a game plan for a round at \(courseName).

        PLAYER PROFILE:
        - Avg score: \(String(format: "%.0f", playerStats.avgScore))
        - GIR: \(String(format: "%.0f", playerStats.avgGIR))%, FIR: \(String(format: "%.0f", playerStats.avgFIR))%
        - Avg driving: \(playerStats.avgDriving)y
        - Club distances: \(clubStr)

        COURSE:
        \(holesStr)

        Return JSON:
        {
          "overallStrategy": "2-3 sentence game plan",
          "keyHoles": [
            {"hole": N, "strategy": "what to do on this hole", "risk": "what to avoid"}
          ],
          "focusPoints": ["3 things to focus on during the round"],
          "targetScore": N
        }
        """

        return await callClaude(prompt: prompt, parse: { json in
            let keyHoles = (json["keyHoles"] as? [[String: Any]])?.map { h in
                HoleStrategy(
                    hole: h["hole"] as? Int ?? 0,
                    strategy: h["strategy"] as? String ?? "",
                    risk: h["risk"] as? String ?? ""
                )
            } ?? []

            return PreRoundPlan(
                overallStrategy: json["overallStrategy"] as? String ?? "",
                keyHoles: keyHoles,
                focusPoints: json["focusPoints"] as? [String] ?? [],
                targetScore: json["targetScore"] as? Int
            )
        })
    }

    // MARK: - In-Round Coaching Tips

    /// Get a coaching tip based on current round performance
    func inRoundTip(
        holesPlayed: [HoleScore],
        currentHole: Int,
        currentPar: Int,
        distToGreen: Int?,
        recentMisses: [ShotResult]
    ) -> InRoundTip? {
        // Local rule-based tips (no API needed, instant)
        let played = holesPlayed.filter { $0.strokes > 0 }

        // Detect patterns
        let last3 = played.suffix(3)
        let last3GIR = last3.filter { $0.greenInRegulation == true }.count
        let last3Putts = last3.compactMap(\.putts).reduce(0, +)

        // Missed greens same side repeatedly
        let missRight = recentMisses.suffix(3).filter { $0 == .rough || $0 == .bunker }.count
        if missRight >= 2 {
            return InRoundTip(
                message: "You've missed \(missRight) of your last 3 greens. Try aiming a little more towards the center of the green.",
                category: .approach,
                priority: .medium
            )
        }

        // 3-putts happening
        let recent3Putts = last3.filter { ($0.putts ?? 0) >= 3 }.count
        if recent3Putts >= 2 {
            return InRoundTip(
                message: "Two 3-putts in your last 3 holes. Focus on speed control — try to leave lag putts within 3 feet.",
                category: .putting,
                priority: .high
            )
        }

        // Hot streak
        let last3Score = last3.reduce(0) { $0 + $1.strokes - $1.par }
        if last3Score <= -2 {
            return InRoundTip(
                message: "You're on fire! \(last3Score) in your last 3 holes. Stay aggressive but smart.",
                category: .mental,
                priority: .low
            )
        }

        // Cold streak
        if last3Score >= 4 {
            return InRoundTip(
                message: "Rough stretch. Take a deep breath, commit to your process, and focus on making a par on this hole.",
                category: .mental,
                priority: .high
            )
        }

        // Par 5 tip
        if currentPar == 5 {
            return InRoundTip(
                message: "Par 5 — birdie opportunity. Focus on keeping your tee shot in play, then make a smart layup or go for it if you have the distance.",
                category: .strategy,
                priority: .low
            )
        }

        return nil
    }

    // MARK: - Predictive Scoring

    /// Predict final score based on pace through current hole
    func predictedScore(holesPlayed: [HoleScore], totalPar: Int, totalHoles: Int = 18) -> ScorePrediction? {
        let played = holesPlayed.filter { $0.strokes > 0 }
        guard played.count >= 4 else { return nil }  // need at least 4 holes

        let playedStrokes = played.reduce(0) { $0 + $1.strokes }
        let remaining = max(0, totalHoles - played.count)

        // Simple pace projection
        let avgPerHole = Double(playedStrokes) / Double(played.count)
        let projected = playedStrokes + Int((avgPerHole * Double(remaining)).rounded())

        // Adjust for typical back-9 fatigue (+0.1 strokes/hole in back 9)
        let fatigueAdjustment: Int
        if played.count <= 9 {
            fatigueAdjustment = Int((Double(remaining) * 0.05).rounded())
        } else {
            fatigueAdjustment = 0
        }

        let finalProjected = projected + fatigueAdjustment

        // Confidence range
        let variance = max(2, remaining / 3)

        return ScorePrediction(
            projected: finalProjected,
            low: finalProjected - variance,
            high: finalProjected + variance,
            holesPlayed: played.count,
            currentPace: avgPerHole,
            projectedToPar: finalProjected - totalPar
        )
    }

    // MARK: - Natural Conversation Mode

    /// Chat with the AI caddy about anything golf-related
    func chat(
        message: String,
        roundContext: RoundContext?
    ) async -> String {
        guard let apiKey, !apiKey.isEmpty else {
            return localChatResponse(message: message, context: roundContext)
        }

        var systemPrompt = """
        You are an AI golf caddy helping a golfer during their round. Be concise, practical,
        and encouraging. Give specific actionable advice. Keep responses under 3 sentences
        unless they ask for detail.
        """

        if let ctx = roundContext {
            systemPrompt += """

            CURRENT ROUND: \(ctx.courseName), Hole \(ctx.currentHole), Par \(ctx.currentPar)
            Score so far: \(ctx.totalStrokes) (\(ctx.scoreToPar >= 0 ? "+" : "")\(ctx.scoreToPar))
            \(ctx.distToGreen.map { "Distance to green: \($0) yards" } ?? "")
            \(ctx.windInfo ?? "")
            Club averages: \(ctx.clubDistances.map { "\($0.key.displayName)=\($0.value)y" }.joined(separator: ", "))
            """
        }

        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 256,
            "system": systemPrompt,
            "messages": [["role": "user", "content": message]]
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            return "I couldn't process that. Try again?"
        }

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
              let text = content["text"] as? String
        else {
            return localChatResponse(message: message, context: roundContext)
        }

        return text
    }

    private func localChatResponse(message: String, context: RoundContext?) -> String {
        let lower = message.lowercased()

        if lower.contains("what should i hit") || lower.contains("what club") {
            if let dist = context?.distToGreen, let clubs = context?.clubDistances {
                let closest = clubs.min { abs($0.value - dist) < abs($1.value - dist) }
                if let c = closest {
                    return "You're \(dist) out. Your \(c.key.displayName) averages \(c.value)y — I'd go with that."
                }
            }
            return "I need your distance to the green to recommend a club."
        }

        if lower.contains("score") || lower.contains("how am i doing") {
            if let ctx = context {
                let pace = ctx.scoreToPar >= 0 ? "+\(ctx.scoreToPar)" : "\(ctx.scoreToPar)"
                return "You're at \(pace) through \(ctx.currentHole - 1). Keep grinding!"
            }
        }

        return "Focus on your next shot. Commit to your target and trust your swing."
    }

    // MARK: - Practice Plan Generation

    /// Generate a weekly practice plan based on recent rounds
    func generatePracticePlan(
        recentStats: PeriodStats,
        clubDistances: [(club: Club, avg: Int, count: Int)]
    ) async -> PracticePlan? {
        guard let apiKey, !apiKey.isEmpty else {
            return localPracticePlan(stats: recentStats)
        }

        let prompt = """
        Generate a weekly golf practice plan based on these stats from the last \(recentStats.roundCount) rounds:
        - Avg score: \(String(format: "%.0f", recentStats.avgScore))
        - GIR: \(String(format: "%.0f", recentStats.avgGIR))%, FIR: \(String(format: "%.0f", recentStats.avgFIR))%
        - Avg putts: \(String(format: "%.0f", recentStats.avgPutts))
        - Avg driving distance: \(recentStats.avgDriving)y

        Return JSON:
        {
          "summary": "1-2 sentence overview",
          "sessions": [
            {"day": "Monday", "focus": "Putting", "duration": "30 min", "drills": ["drill 1", "drill 2"]}
          ],
          "weeklyGoal": "One measurable goal for the week"
        }
        """

        return await callClaude(prompt: prompt, parse: { json in
            let sessions = (json["sessions"] as? [[String: Any]])?.map { s in
                PracticeSession(
                    day: s["day"] as? String ?? "",
                    focus: s["focus"] as? String ?? "",
                    duration: s["duration"] as? String ?? "",
                    drills: s["drills"] as? [String] ?? []
                )
            } ?? []

            return PracticePlan(
                summary: json["summary"] as? String ?? "",
                sessions: sessions,
                weeklyGoal: json["weeklyGoal"] as? String ?? ""
            )
        })
    }

    private func localPracticePlan(stats: PeriodStats) -> PracticePlan {
        var sessions: [PracticeSession] = []

        if stats.avgGIR < 40 {
            sessions.append(PracticeSession(day: "Tuesday", focus: "Iron Accuracy", duration: "45 min",
                drills: ["Hit 20 balls each with 7, 8, 9 iron to specific targets",
                         "Play 'closest to the pin' with yourself — track miss patterns"]))
        }

        if stats.avgPutts > 34 {
            sessions.append(PracticeSession(day: "Wednesday", focus: "Putting", duration: "30 min",
                drills: ["Lag putting: 30-40 footers, goal is within 3 feet",
                         "Gate drill: 2 tees just wider than the ball, 5 footers"]))
        }

        if stats.avgFIR < 50 {
            sessions.append(PracticeSession(day: "Thursday", focus: "Driving", duration: "30 min",
                drills: ["Hit 15 drives focusing on tempo, not distance",
                         "Pick a target and rate fairway/miss for each drive"]))
        }

        sessions.append(PracticeSession(day: "Saturday", focus: "Short Game", duration: "30 min",
            drills: ["Chip to 5 different pins from various lies",
                     "Up-and-down challenge: 10 attempts, track makes"]))

        return PracticePlan(
            summary: "Focus on your weakest areas this week to maximize improvement.",
            sessions: sessions,
            weeklyGoal: stats.avgGIR < 40 ? "Hit 2 more greens per round" : "Reduce putts per round by 2"
        )
    }

    // MARK: - Helpers

    private func callClaude<T>(prompt: String, parse: @escaping ([String: Any]) -> T) async -> T? {
        guard let apiKey else { return nil }

        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 1024,
            "system": "You are an expert golf coach. Return ONLY valid JSON.",
            "messages": [["role": "user", "content": prompt]]
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

        return parse(parsed)
    }
}

// MARK: - Supporting Models

struct PreRoundPlan {
    let overallStrategy: String
    let keyHoles: [HoleStrategy]
    let focusPoints: [String]
    let targetScore: Int?
}

struct HoleStrategy {
    let hole: Int
    let strategy: String
    let risk: String
}

struct InRoundTip {
    let message: String
    let category: TipCategory
    let priority: TipPriority

    enum TipCategory { case driving, approach, shortGame, putting, mental, strategy }
    enum TipPriority { case low, medium, high }
}

struct ScorePrediction {
    let projected: Int
    let low: Int
    let high: Int
    let holesPlayed: Int
    let currentPace: Double
    let projectedToPar: Int
}

struct RoundContext {
    let courseName: String
    let currentHole: Int
    let currentPar: Int
    let totalStrokes: Int
    let scoreToPar: Int
    let distToGreen: Int?
    let windInfo: String?
    let clubDistances: [Club: Int]
}

struct PracticePlan {
    let summary: String
    let sessions: [PracticeSession]
    let weeklyGoal: String
}

struct PracticeSession {
    let day: String
    let focus: String
    let duration: String
    let drills: [String]
}
