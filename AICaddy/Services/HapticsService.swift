import UIKit

/// Haptic feedback for distance milestones and events
enum HapticsService {
    /// Vibrate when reaching distance milestones
    static func distanceMilestone(_ yards: Int) {
        switch yards {
        case 148...152:  // 150 out
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case 98...102:   // 100 out
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case 48...52:    // 50 out
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        default:
            break
        }
    }

    /// Check and fire distance milestone haptics
    static func checkMilestones(distToGreen: Int, lastCheckedDist: inout Int?) {
        let milestones = [200, 150, 100, 50]

        for milestone in milestones {
            // Fire when crossing the milestone threshold
            if let last = lastCheckedDist,
               last > milestone && distToGreen <= milestone && distToGreen >= milestone - 5 {
                distanceMilestone(distToGreen)
                break
            }
        }

        lastCheckedDist = distToGreen
    }

    /// Birdie or better celebration
    static func celebration() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Score entered confirmation
    static func scoreEntered() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Hole advanced
    static func holeAdvanced() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// Round completed
    static func roundComplete() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            generator.notificationOccurred(.success)
        }
    }
}
