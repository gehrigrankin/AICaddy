import SwiftUI

struct ClubRecommendationView: View {
    let recommendation: ClubRecommendation

    @State private var expanded = false

    private var displayDistance: Int {
        recommendation.adjustedDistance ?? recommendation.targetDistance
    }

    private var powerFraction: CGFloat {
        guard recommendation.primaryAvg > 0 else { return 0 }
        let ratio = CGFloat(displayDistance) / CGFloat(recommendation.primaryAvg)
        return min(max(ratio, 0.05), 1.0)
    }

    var body: some View {
        Button { withAnimation(.spring(duration: 0.3)) { expanded.toggle() } } label: {
            VStack(spacing: 0) {
                // Top row: icon + club name + shot type
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Theme.Colors.surfaceElevated)
                            .frame(width: 44, height: 44)
                        Image(systemName: "figure.golf")
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(recommendation.primaryClub.displayName.uppercased())
                            .font(Theme.Font.title(16))
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .tracking(1)
                        Text("NORMAL")
                            .font(.system(size: 11, weight: .semibold, design: .rounded).italic())
                            .foregroundStyle(Theme.Colors.textMuted)
                            .tracking(1)
                    }

                    Spacer()

                    // Yardage readout with accent dot
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Theme.Colors.accent)
                            .frame(width: 8, height: 8)
                        Text("\(displayDistance)")
                            .font(Theme.Font.display(22))
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }
                }

                // Power bar
                VStack(spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Theme.Colors.surfaceDeep)
                                .frame(height: 6)
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Theme.Colors.accent, Color(red: 0.98, green: 0.67, blue: 0.06)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(6, geo.size.width * powerFraction), height: 6)
                        }
                    }
                    .frame(height: 6)
                }
                .padding(.top, 12)

                // Target label row
                HStack(spacing: 8) {
                    Image(systemName: "target")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Text(targetLabel.uppercased())
                        .font(Theme.Font.caption(11))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .tracking(1)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Theme.Colors.textMuted)
                }
                .padding(.top, 8)

                if expanded {
                    VStack(alignment: .leading, spacing: 10) {
                        Divider()
                            .overlay(Theme.Colors.divider)
                            .padding(.vertical, 2)

                        Text(recommendation.reasoning)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 10) {
                            ClubOption(
                                club: recommendation.primaryClub,
                                avg: recommendation.primaryAvg,
                                count: recommendation.primaryCount,
                                isPrimary: true
                            )
                            if let alt = recommendation.alternateClub,
                               let altAvg = recommendation.alternateAvg,
                               let altCount = recommendation.alternateCount {
                                ClubOption(
                                    club: alt,
                                    avg: altAvg,
                                    count: altCount,
                                    isPrimary: false
                                )
                            }
                        }
                    }
                    .padding(.top, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .gameCard(padding: 14)
        }
        .buttonStyle(.plain)
    }

    private var targetLabel: String {
        if let note = recommendation.adjustmentNote, !note.isEmpty {
            return note
        }
        return "\(recommendation.targetDistance)y to pin"
    }
}

private struct ClubOption: View {
    let club: Club
    let avg: Int
    let count: Int
    let isPrimary: Bool

    var body: some View {
        VStack(spacing: 4) {
            Text(club.displayName.uppercased())
                .font(Theme.Font.label(12))
                .foregroundStyle(isPrimary ? Theme.Colors.accent : Theme.Colors.textSecondary)
                .tracking(0.5)
            Text("AVG \(avg)y")
                .font(Theme.Font.caption(10))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text("\(count) SHOTS")
                .font(Theme.Font.caption(9))
                .foregroundStyle(Theme.Colors.textMuted)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.tight, style: .continuous)
                .fill(isPrimary ? Theme.Colors.accentSoft : Theme.Colors.surfaceDeep)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.tight, style: .continuous)
                .strokeBorder(isPrimary ? Theme.Colors.accent.opacity(0.3) : Theme.Colors.border, lineWidth: 1)
        )
    }
}
