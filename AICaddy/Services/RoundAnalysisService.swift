import Foundation

/// Post-round AI analysis — Claude reviews your stats and tells you what to work on.
final class RoundAnalysisService {
    private let apiKey: String?

    init(apiKey: String? = nil) {
        self.apiKey = apiKey ?? Bundle.main.object(forInfoDictionaryKey: "ANTHROPIC_API_KEY") as? String
    }

    /// Generate a detailed AI analysis of a completed round
    func analyze(round: Round, historicalStats: HistoricalContext? = nil) async -> RoundAnalysis {
        let stats = StatsCalculator.calculate(holes: round.holes)

        // Try Claude API first
        if let apiKey, !apiKey.isEmpty {
            if let aiAnalysis = await analyzeWithClaude(round: round, stats: stats, history: historicalStats, apiKey: apiKey) {
                return aiAnalysis
            }
        }

        // Fallback to local rule-based analysis
        return localAnalysis(stats: stats, holes: round.holes)
    }

    // MARK: - Claude Analysis

    private func analyzeWithClaude(round: Round, stats: RoundStats, history: HistoricalContext?, apiKey: String) async -> RoundAnalysis? {
        let prompt = buildAnalysisPrompt(round: round, stats: stats, history: history)

        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 1024,
            "system": """
            You are an expert golf coach analyzing a round. Be specific, encouraging but honest.
            Return JSON only:
            {
              "summary": "1-2 sentence overview of the round",
              "strengths": ["specific thing done well", ...],
              "weaknesses": ["specific area to improve", ...],
              "practiceAdvice": "What to work on at the range based on this round",
              "keyInsight": "One surprising or non-obvious takeaway from the data",
              "strokesLostBreakdown": {
                "driving": "brief assessment",
                "approach": "brief assessment",
                "shortGame": "brief assessment",
                "putting": "brief assessment"
              }
            }
            """,
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

        let breakdown = parsed["strokesLostBreakdown"] as? [String: String]

        return RoundAnalysis(
            summary: parsed["summary"] as? String ?? "",
            strengths: parsed["strengths"] as? [String] ?? [],
            weaknesses: parsed["weaknesses"] as? [String] ?? [],
            practiceAdvice: parsed["practiceAdvice"] as? String ?? "",
            keyInsight: parsed["keyInsight"] as? String,
            drivingAssessment: breakdown?["driving"],
            approachAssessment: breakdown?["approach"],
            shortGameAssessment: breakdown?["shortGame"],
            puttingAssessment: breakdown?["putting"],
            isAIGenerated: true
        )
    }

    private func buildAnalysisPrompt(round: Round, stats: RoundStats, history: HistoricalContext?) -> String {
        var prompt = """
        Analyze this golf round at \(round.courseName) (\(round.teeName) tees):

        SCORE: \(stats.totalStrokes) (Par \(stats.totalPar), \(stats.scoreToPar >= 0 ? "+" : "")\(stats.scoreToPar))
        Front 9: \(stats.frontNine) | Back 9: \(stats.backNine)

        PUTTING: \(stats.totalPutts) putts (avg \(String(format: "%.1f", stats.puttsPerHole))/hole)
        1-putts: \(stats.oneputts) | 3-putts: \(stats.threeputts)

        GREENS: \(stats.greensInRegulation)/\(stats.girHoles) GIR (\(String(format: "%.0f", stats.greensInRegulationPct))%)
        FAIRWAYS: \(stats.fairwaysHit)/\(stats.fairwayHoles) FIR (\(String(format: "%.0f", stats.fairwaysPct))%)

        SCRAMBLING: \(String(format: "%.0f", stats.scramblingPct))%
        UP & DOWN: \(stats.upAndDowns)/\(stats.upAndDownAttempts)

        SCORING: \(stats.eagles) eagles, \(stats.birdies) birdies, \(stats.pars) pars, \(stats.bogeys) bogeys, \(stats.doubleBogeys) doubles, \(stats.triplePlus) triple+

        PAR AVERAGES: Par 3: \(String(format: "%.1f", stats.par3Avg)) | Par 4: \(String(format: "%.1f", stats.par4Avg)) | Par 5: \(String(format: "%.1f", stats.par5Avg))
        """

        if stats.avgDrivingDistance > 0 {
            prompt += "\nDRIVING DISTANCE: avg \(stats.avgDrivingDistance)y"
        }

        // Hole-by-hole detail
        prompt += "\n\nHOLE BY HOLE:\n"
        for hole in round.holes where hole.strokes > 0 {
            let diff = hole.strokes - hole.par
            let diffStr = diff == 0 ? "E" : (diff > 0 ? "+\(diff)" : "\(diff)")
            var detail = "H\(hole.holeNumber) Par \(hole.par): \(hole.strokes) (\(diffStr))"
            if let p = hole.putts { detail += " \(p)P" }
            if hole.fairwayHit == true { detail += " FIR" }
            if hole.fairwayHit == false { detail += " miss-FIR" }
            if hole.greenInRegulation == true { detail += " GIR" }
            if hole.greenInRegulation == false { detail += " miss-GIR" }
            prompt += detail + "\n"
        }

        if let history {
            prompt += "\nHISTORICAL CONTEXT (last \(history.roundCount) rounds):\n"
            prompt += "Avg score: \(String(format: "%.0f", history.avgScore))\n"
            prompt += "Avg GIR: \(String(format: "%.0f", history.avgGIR))%\n"
            prompt += "Avg FIR: \(String(format: "%.0f", history.avgFIR))%\n"
            prompt += "Avg putts: \(String(format: "%.0f", history.avgPutts))\n"
        }

        return prompt
    }

    // MARK: - Local Rule-Based Analysis

    private func localAnalysis(stats: RoundStats, holes: [HoleScore]) -> RoundAnalysis {
        var strengths: [String] = []
        var weaknesses: [String] = []
        var practiceAdvice: [String] = []

        // Putting
        if stats.puttsPerHole <= 1.8 {
            strengths.append("Excellent putting — \(String(format: "%.1f", stats.puttsPerHole)) putts per hole")
        } else if stats.puttsPerHole >= 2.2 {
            weaknesses.append("Putting needs work — \(String(format: "%.1f", stats.puttsPerHole)) putts per hole")
            practiceAdvice.append("Spend time on lag putting to reduce 3-putts")
        }

        if stats.threeputts >= 3 {
            weaknesses.append("\(stats.threeputts) three-putts — speed control is costing you strokes")
        }

        if stats.oneputts >= 5 {
            strengths.append("\(stats.oneputts) one-putts — you're draining putts when it counts")
        }

        // GIR
        if stats.greensInRegulationPct >= 55 {
            strengths.append("Solid iron play — \(String(format: "%.0f", stats.greensInRegulationPct))% greens in regulation")
        } else if stats.greensInRegulationPct < 35 && stats.girHoles > 0 {
            weaknesses.append("Approach shots need attention — only \(String(format: "%.0f", stats.greensInRegulationPct))% GIR")
            practiceAdvice.append("Focus on mid-iron accuracy at the range")
        }

        // Fairways
        if stats.fairwaysPct >= 65 {
            strengths.append("Keeping it in play — \(String(format: "%.0f", stats.fairwaysPct))% fairways")
        } else if stats.fairwaysPct < 45 && stats.fairwayHoles > 0 {
            weaknesses.append("Finding only \(String(format: "%.0f", stats.fairwaysPct))% of fairways — missing fairways makes GIR harder")
            practiceAdvice.append("Consider a more consistent tee shot — maybe 3-wood off tight holes")
        }

        // Scrambling
        if stats.upAndDownAttempts > 0 && stats.upAndDownPct >= 50 {
            strengths.append("Great short game — \(String(format: "%.0f", stats.upAndDownPct))% up-and-down")
        } else if stats.upAndDownAttempts >= 5 && stats.upAndDownPct < 30 {
            weaknesses.append("Short game is leaking strokes — only \(String(format: "%.0f", stats.upAndDownPct))% up-and-down")
            practiceAdvice.append("Practice chipping and pitching from 20-50 yards")
        }

        // Scoring patterns
        if stats.doubleBogeys + stats.triplePlus >= 4 {
            weaknesses.append("Big numbers are hurting you — \(stats.doubleBogeys + stats.triplePlus) doubles or worse")
            practiceAdvice.append("Focus on course management to avoid blow-up holes — take your medicine when in trouble")
        }

        if stats.birdies >= 3 {
            strengths.append("\(stats.birdies) birdies — you can go low when you're on")
        }

        // Par performance
        if stats.par5Avg > 0 && stats.par5Avg <= 5.2 {
            strengths.append("Taking advantage of par 5s (avg \(String(format: "%.1f", stats.par5Avg)))")
        } else if stats.par5Avg > 6.0 {
            weaknesses.append("Struggling on par 5s (avg \(String(format: "%.1f", stats.par5Avg))) — these should be birdie opportunities")
        }

        // Build summary
        let summary: String
        if stats.scoreToPar <= 0 {
            summary = "Great round! You shot \(stats.scoreToPar == 0 ? "even par" : "\(stats.scoreToPar)") with solid play across the board."
        } else if stats.scoreToPar <= 10 {
            summary = "Decent round at +\(stats.scoreToPar). A few areas to tighten up and you'll break through."
        } else {
            summary = "Tough day at +\(stats.scoreToPar), but every round is data. Focus on the areas below and you'll improve."
        }

        return RoundAnalysis(
            summary: summary,
            strengths: strengths.isEmpty ? ["You finished the round — that's always a win!"] : strengths,
            weaknesses: weaknesses.isEmpty ? ["No major red flags — keep grinding!"] : weaknesses,
            practiceAdvice: practiceAdvice.joined(separator: ". "),
            keyInsight: nil,
            drivingAssessment: stats.fairwayHoles > 0 ? "\(String(format: "%.0f", stats.fairwaysPct))% fairways, avg \(stats.avgDrivingDistance)y" : nil,
            approachAssessment: stats.girHoles > 0 ? "\(String(format: "%.0f", stats.greensInRegulationPct))% GIR" : nil,
            shortGameAssessment: stats.upAndDownAttempts > 0 ? "\(String(format: "%.0f", stats.upAndDownPct))% up-and-down from \(stats.upAndDownAttempts) attempts" : nil,
            puttingAssessment: "\(stats.totalPutts) putts (\(String(format: "%.1f", stats.puttsPerHole))/hole), \(stats.oneputts) one-putts, \(stats.threeputts) three-putts",
            isAIGenerated: false
        )
    }
}

// MARK: - Models

struct RoundAnalysis {
    let summary: String
    let strengths: [String]
    let weaknesses: [String]
    let practiceAdvice: String
    let keyInsight: String?
    let drivingAssessment: String?
    let approachAssessment: String?
    let shortGameAssessment: String?
    let puttingAssessment: String?
    let isAIGenerated: Bool
}

struct HistoricalContext {
    let roundCount: Int
    let avgScore: Double
    let avgGIR: Double
    let avgFIR: Double
    let avgPutts: Double
}
