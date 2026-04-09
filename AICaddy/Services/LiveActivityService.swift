import ActivityKit
import Foundation

/// Service that manages the Live Activity lifecycle for an active golf round.
///
/// Call `startActivity` when a round begins, `updateActivity` as the player
/// progresses through holes, and `endActivity` when the round is complete.
///
/// - Note: Requires ActivityKit capability and a Widget Extension target that
///   includes `RoundLiveActivityWidget` in its `WidgetBundle`.
@Observable
final class LiveActivityService {

    // MARK: - State

    private var currentActivity: Activity<RoundActivityAttributes>?

    /// Whether a Live Activity is currently running.
    var isActive: Bool { currentActivity != nil }

    // MARK: - Start

    /// Starts a new Live Activity for the current round.
    /// - Parameters:
    ///   - courseName: The name of the course being played.
    ///   - teeName: The tee being played (e.g. "Blue", "White").
    ///   - hole: The starting hole number (typically 1).
    ///   - par: The par for the starting hole.
    ///   - score: The player's current total score (typically 0).
    func startActivity(
        courseName: String,
        teeName: String,
        hole: Int = 1,
        par: Int = 4,
        score: Int = 0
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("[LiveActivityService] Activities not enabled")
            return
        }

        // End any stale activity first
        if currentActivity != nil {
            endActivity()
        }

        let attributes = RoundActivityAttributes(
            courseName: courseName,
            teeName: teeName
        )

        let initialState = RoundActivityAttributes.ContentState(
            currentHole: hole,
            par: par,
            score: score,
            scoreToPar: 0,
            distanceToGreen: nil
        )

        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: initialState, staleDate: nil),
                pushType: nil
            )
            print("[LiveActivityService] Started activity: \(currentActivity?.id ?? "nil")")
        } catch {
            print("[LiveActivityService] Failed to start: \(error.localizedDescription)")
        }
    }

    // MARK: - Update

    /// Updates the Live Activity with the latest round state.
    /// - Parameters:
    ///   - hole: Current hole number (1-18).
    ///   - par: Par for the current hole.
    ///   - score: Total strokes so far.
    ///   - scoreToPar: Cumulative score relative to par (negative = under par).
    ///   - distanceToGreen: Distance in yards to the green center, or nil if unavailable.
    func updateActivity(
        hole: Int,
        par: Int,
        score: Int,
        scoreToPar: Int,
        distanceToGreen: Int?
    ) {
        guard let activity = currentActivity else { return }

        let state = RoundActivityAttributes.ContentState(
            currentHole: hole,
            par: par,
            score: score,
            scoreToPar: scoreToPar,
            distanceToGreen: distanceToGreen
        )

        Task {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    // MARK: - End

    /// Ends the current Live Activity. The banner remains visible for one hour
    /// after dismissal so the player can review their final score.
    func endActivity() {
        guard let activity = currentActivity else { return }

        Task {
            let finalContent = activity.content
            await activity.end(
                finalContent,
                dismissalPolicy: .after(.now + 3600)
            )
            await MainActor.run {
                currentActivity = nil
            }
            print("[LiveActivityService] Ended activity")
        }
    }
}
