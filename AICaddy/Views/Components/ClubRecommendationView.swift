import SwiftUI

struct ClubRecommendationView: View {
    let recommendation: ClubRecommendation

    @State private var expanded = false

    var body: some View {
        Button { withAnimation(.spring(duration: 0.3)) { expanded.toggle() } } label: {
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    // Club icon
                    Image(systemName: "figure.golf")
                        .font(.title3)
                        .foregroundStyle(.green)
                        .frame(width: 36, height: 36)
                        .background(Color.green.opacity(0.15))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text("AI Caddy says:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(recommendation.targetDistance)y out")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(recommendation.primaryClub.displayName)
                            .font(.title3.bold())
                            .foregroundStyle(.primary)
                    }

                    Spacer()

                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if expanded {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(recommendation.reasoning)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 16) {
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
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(12)
            .background(Color(.systemGray6).opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.green.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ClubOption: View {
    let club: Club
    let avg: Int
    let count: Int
    let isPrimary: Bool

    var body: some View {
        VStack(spacing: 4) {
            Text(club.displayName)
                .font(.subheadline.bold())
                .foregroundStyle(isPrimary ? .green : .secondary)
            Text("avg \(avg)y")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("(\(count) shots)")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(isPrimary ? Color.green.opacity(0.1) : Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
