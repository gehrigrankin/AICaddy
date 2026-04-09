import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Activity Attributes

/// Live Activity attributes for showing round progress on lock screen and Dynamic Island.
struct RoundActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var currentHole: Int
        var par: Int
        var score: Int
        var scoreToPar: Int
        var distanceToGreen: Int?
    }

    // Fixed attributes (don't change during the activity)
    let courseName: String
    let teeName: String
}

// MARK: - Theme Helpers

private enum RoundActivityTheme {
    static let accentGreen = Color(red: 0.18, green: 0.80, blue: 0.44)
    static let dimGreen = Color(red: 0.18, green: 0.80, blue: 0.44).opacity(0.6)

    static func scoreColor(for scoreToPar: Int) -> Color {
        if scoreToPar < 0 { return Color.red }
        if scoreToPar > 0 { return Color(red: 0.4, green: 0.7, blue: 1.0) }
        return accentGreen
    }

    static func scoreToParText(_ scoreToPar: Int) -> String {
        if scoreToPar == 0 { return "E" }
        return scoreToPar > 0 ? "+\(scoreToPar)" : "\(scoreToPar)"
    }
}

// MARK: - Lock Screen View

/// Full lock screen / banner presentation of the Live Activity.
struct RoundLockScreenView: View {
    let context: ActivityViewContext<RoundActivityAttributes>

    private var state: RoundActivityAttributes.ContentState { context.state }

    var body: some View {
        HStack(spacing: 0) {
            // Left: Hole and Par
            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.courseName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                Text("H\(state.currentHole)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Par \(state.par)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .frame(minWidth: 70, alignment: .leading)

            Spacer()

            // Center: Distance to green
            if let dist = state.distanceToGreen {
                VStack(spacing: 0) {
                    Text("\(dist)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(RoundActivityTheme.accentGreen)
                    Text("yards")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(RoundActivityTheme.dimGreen)
                }
            } else {
                VStack(spacing: 0) {
                    Text("--")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.3))
                    Text("yards")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.2))
                }
            }

            Spacer()

            // Right: Score
            VStack(alignment: .trailing, spacing: 2) {
                if state.score > 0 {
                    Text("\(state.score)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                Text(RoundActivityTheme.scoreToParText(state.scoreToPar))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(RoundActivityTheme.scoreColor(for: state.scoreToPar))
            }
            .frame(minWidth: 50, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .activityBackgroundTint(.black)
    }
}

// MARK: - Dynamic Island Compact Views

/// Leading compact view for Dynamic Island (left pill).
struct RoundCompactLeadingView: View {
    let state: RoundActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "flag.fill")
                .font(.system(size: 9))
                .foregroundStyle(RoundActivityTheme.accentGreen)
            Text("H\(state.currentHole)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}

/// Trailing compact view for Dynamic Island (right pill).
struct RoundCompactTrailingView: View {
    let state: RoundActivityAttributes.ContentState

    var body: some View {
        if let dist = state.distanceToGreen {
            Text("\(dist)y")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(RoundActivityTheme.accentGreen)
        } else {
            Text(RoundActivityTheme.scoreToParText(state.scoreToPar))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(RoundActivityTheme.scoreColor(for: state.scoreToPar))
        }
    }
}

// MARK: - Dynamic Island Expanded View

/// Expanded Dynamic Island presentation with full round info.
struct RoundExpandedView: View {
    let context: ActivityViewContext<RoundActivityAttributes>

    private var state: RoundActivityAttributes.ContentState { context.state }

    var body: some View {
        VStack(spacing: 8) {
            // Top row: course name
            HStack {
                Text(context.attributes.courseName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                Spacer()
                Text(context.attributes.teeName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
            }

            // Main content row
            HStack(spacing: 0) {
                // Hole + Par
                VStack(spacing: 2) {
                    Text("HOLE")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                    Text("\(state.currentHole)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Par \(state.par)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity)

                // Distance
                VStack(spacing: 2) {
                    Text("DISTANCE")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                    if let dist = state.distanceToGreen {
                        Text("\(dist)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(RoundActivityTheme.accentGreen)
                    } else {
                        Text("--")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    Text("yards")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(RoundActivityTheme.dimGreen)
                }
                .frame(maxWidth: .infinity)

                // Score
                VStack(spacing: 2) {
                    Text("SCORE")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                    if state.score > 0 {
                        Text("\(state.score)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    } else {
                        Text("--")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    Text(RoundActivityTheme.scoreToParText(state.scoreToPar))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(RoundActivityTheme.scoreColor(for: state.scoreToPar))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Widget Configuration

/// The Widget that provides the Live Activity UI.
/// This must be included in a Widget Extension target.
struct RoundLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RoundActivityAttributes.self) { context in
            // Lock screen / banner presentation
            RoundLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded regions
                DynamicIslandExpandedRegion(.leading) {
                    EmptyView()
                }
                DynamicIslandExpandedRegion(.trailing) {
                    EmptyView()
                }
                DynamicIslandExpandedRegion(.center) {
                    RoundExpandedView(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    EmptyView()
                }
            } compactLeading: {
                RoundCompactLeadingView(state: context.state)
            } compactTrailing: {
                RoundCompactTrailingView(state: context.state)
            } minimal: {
                Image(systemName: "flag.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(RoundActivityTheme.accentGreen)
            }
        }
    }
}
