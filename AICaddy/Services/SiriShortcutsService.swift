import Foundation
import Intents
import AppIntents

// MARK: - "Start a Round" Shortcut

struct StartRoundIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Golf Round"
    static var description = IntentDescription("Start a new round at a golf course")
    static var openAppWhenRun = true

    @Parameter(title: "Course Name")
    var courseName: String?

    func perform() async throws -> some IntentResult {
        // The app will handle the course lookup when it opens
        // Store the intent data for the app to pick up
        UserDefaults.standard.set(courseName, forKey: "siri_start_round_course")
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "siri_start_round_time")
        return .result()
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Start a round at \(\.$courseName)")
    }
}

// MARK: - "Log Score" Shortcut

struct LogScoreIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Golf Score"
    static var description = IntentDescription("Log your score for the current hole")
    static var openAppWhenRun = false

    @Parameter(title: "Score")
    var scoreInput: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        // Store for the app to process
        UserDefaults.standard.set(scoreInput, forKey: "siri_score_input")
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "siri_score_time")
        return .result(value: "Logged: \(scoreInput)")
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Log score: \(\.$scoreInput)")
    }
}

// MARK: - "What's My Handicap" Shortcut

struct HandicapIntent: AppIntent {
    static var title: LocalizedStringResource = "What's My Golf Handicap"
    static var description = IntentDescription("Check your current handicap index")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        // Read handicap from shared UserDefaults or app group
        if let handicap = UserDefaults.standard.object(forKey: "current_handicap") as? Double {
            return .result(value: String(format: "Your handicap index is %.1f", handicap))
        }
        return .result(value: "Play at least 3 rounds with course rating and slope to calculate your handicap.")
    }
}

// MARK: - "How's My Round Going" Shortcut

struct RoundStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Golf Round Status"
    static var description = IntentDescription("Check your current round score and stats")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let score = UserDefaults.standard.integer(forKey: "current_round_score")
        let scoreToPar = UserDefaults.standard.integer(forKey: "current_round_to_par")
        let hole = UserDefaults.standard.integer(forKey: "current_round_hole")

        if hole > 0 {
            let parStr = scoreToPar == 0 ? "even par" : (scoreToPar > 0 ? "+\(scoreToPar)" : "\(scoreToPar)")
            return .result(value: "You're on hole \(hole) shooting \(score), \(parStr).")
        }
        return .result(value: "No round in progress. Start a round first!")
    }
}

// MARK: - App Shortcuts Provider

struct AICaddyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        return [
            AppShortcut(
                intent: StartRoundIntent(),
                phrases: [
                    "Start a round with \(.applicationName)",
                    "Begin golf round with \(.applicationName)"
                ],
                shortTitle: "Start Round",
                systemImageName: "flag.fill"
            ),
            AppShortcut(
                intent: LogScoreIntent(),
                phrases: [
                    "Log my golf score with \(.applicationName)",
                    "Record my score with \(.applicationName)"
                ],
                shortTitle: "Log Score",
                systemImageName: "plus.circle.fill"
            ),
            AppShortcut(
                intent: HandicapIntent(),
                phrases: [
                    "What's my handicap with \(.applicationName)",
                    "Check my golf handicap with \(.applicationName)"
                ],
                shortTitle: "Handicap",
                systemImageName: "number"
            ),
            AppShortcut(
                intent: RoundStatusIntent(),
                phrases: [
                    "How's my round going with \(.applicationName)",
                    "What's my golf score with \(.applicationName)"
                ],
                shortTitle: "Round Status",
                systemImageName: "chart.bar.fill"
            ),
        ]
    }
}
