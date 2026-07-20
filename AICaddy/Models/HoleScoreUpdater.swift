import Foundation

/// Applies a parsed voice/text input to a hole score.
/// Shared by the UI and the test suite so on-course behavior is exactly what's tested.
enum HoleScoreUpdater {

    /// Apply a parsed input to the hole. Returns a short human-readable summary
    /// of what was recorded (shown as "Recorded: ..." in the UI).
    @discardableResult
    static func apply(_ parsed: ParsedShotInput, to hole: inout HoleScore) -> String {
        var summary = ""

        if let strokes = parsed.totalStrokes {
            hole.strokes = strokes
            summary = "Score: \(strokes)"
        }

        if !parsed.shots.isEmpty {
            hole.shots.append(contentsOf: parsed.shots)
            renumberShots(&hole)
            let desc = parsed.shots.map { s in
                [s.club?.displayName, s.distanceYards.map { "\($0)y" }, s.result?.displayName]
                    .compactMap { $0 }.joined(separator: " ")
            }.joined(separator: ", ")
            summary = desc.isEmpty ? "shots added" : desc
        }

        if let putts = parsed.putts { hole.putts = putts }
        if let fir = parsed.fairwayHit { hole.fairwayHit = fir }
        if let gir = parsed.greenInRegulation { hole.greenInRegulation = gir }

        if parsed.totalStrokes == nil {
            reconcileStrokes(&hole)
        }

        StatsCalculator.deriveHoleStats(&hole)
        return summary
    }

    /// Remove a single shot (e.g. a mis-parsed voice input), renumber the rest,
    /// and recompute the score from what remains. Manually-set flags stay
    /// untouched — this is surgical removal, not a reset.
    static func removeShot(id: UUID, from hole: inout HoleScore) {
        hole.shots.removeAll { $0.id == id }
        renumberShots(&hole)

        let nonPuttSwings = hole.shots.filter { !$0.isPutt }.count
        let puttSwings = hole.shots.filter { $0.isPutt }.count
        let penaltyStrokes = hole.shots.filter { $0.isPenalty }.count
        let putts = max(puttSwings, hole.putts ?? 0)
        hole.strokes = nonPuttSwings + putts + penaltyStrokes

        StatsCalculator.deriveHoleStats(&hole)
    }

    /// Wipe the hole back to unplayed — the escape hatch when parsing or GPS
    /// went sideways and the user wants a clean slate on this hole.
    static func reset(_ hole: inout HoleScore) {
        hole.shots = []
        hole.strokes = 0
        hole.putts = nil
        hole.fairwayHit = nil
        hole.greenInRegulation = nil
        hole.upAndDown = nil
        hole.sandSave = nil
        hole.notes = nil
    }

    /// Keep shot numbers sequential after appending parsed shots.
    private static func renumberShots(_ hole: inout HoleScore) {
        for i in hole.shots.indices {
            hole.shots[i].shotNumber = i + 1
        }
    }

    /// When the user hasn't stated a total, derive strokes from what's logged:
    /// swings + penalty strokes, using the stated putt count when it's larger
    /// than the number of logged putt swings. Fixes the classic undercount where
    /// "driver fairway, 8 iron green" + "2 putts" left the hole at 2 strokes.
    static func reconcileStrokes(_ hole: inout HoleScore) {
        // Don't invent a score from a putts-only entry on an otherwise empty hole.
        guard !hole.shots.isEmpty || hole.strokes > 0 else { return }

        let nonPuttSwings = hole.shots.filter { !$0.isPutt }.count
        let puttSwings = hole.shots.filter { $0.isPutt }.count
        let penaltyStrokes = hole.shots.filter { $0.isPenalty }.count
        let putts = max(puttSwings, hole.putts ?? 0)

        let computed = nonPuttSwings + putts + penaltyStrokes
        // Never lower an explicitly-entered total; partial shot logs shouldn't
        // clobber a stated score.
        hole.strokes = max(hole.strokes, computed)
    }
}
