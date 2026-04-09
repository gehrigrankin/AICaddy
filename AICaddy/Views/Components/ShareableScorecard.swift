import SwiftUI
import UIKit

/// Renders a scorecard as a shareable image
struct ShareableScorecard: View {
    let round: Round
    let stats: RoundStats

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Caddy")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.green)
                    Text(round.courseName)
                        .font(.headline)
                    Text("\(round.teeName) Tees · \(round.date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(stats.totalStrokes)")
                        .font(.system(size: 32, weight: .bold))
                    Text(stats.scoreToPar == 0 ? "Even" : (stats.scoreToPar > 0 ? "+\(stats.scoreToPar)" : "\(stats.scoreToPar)"))
                        .font(.subheadline.bold())
                        .foregroundStyle(stats.scoreToPar < 0 ? .red : stats.scoreToPar > 0 ? .cyan : .green)
                }
            }

            Divider()

            // Score grid
            VStack(spacing: 6) {
                // Front 9
                ScoreRow(label: "Hole", values: (1...9).map { "\($0)" }, total: "Out")
                ScoreRow(label: "Par", values: round.holes.prefix(9).map { "\($0.par)" },
                         total: "\(round.holes.prefix(9).reduce(0) { $0 + $1.par })")
                ScoreRow(label: "Score",
                         values: round.holes.prefix(9).map { $0.strokes > 0 ? "\($0.strokes)" : "-" },
                         total: "\(round.holes.prefix(9).reduce(0) { $0 + $1.strokes })",
                         pars: round.holes.prefix(9).map { $0.par },
                         scores: round.holes.prefix(9).map { $0.strokes },
                         isBold: true)

                Divider().padding(.vertical, 2)

                // Back 9
                ScoreRow(label: "Hole", values: (10...18).map { "\($0)" }, total: "In")
                ScoreRow(label: "Par", values: round.holes.suffix(9).map { "\($0.par)" },
                         total: "\(round.holes.suffix(9).reduce(0) { $0 + $1.par })")
                ScoreRow(label: "Score",
                         values: round.holes.suffix(9).map { $0.strokes > 0 ? "\($0.strokes)" : "-" },
                         total: "\(round.holes.suffix(9).reduce(0) { $0 + $1.strokes })",
                         pars: round.holes.suffix(9).map { $0.par },
                         scores: round.holes.suffix(9).map { $0.strokes },
                         isBold: true)
            }

            Divider()

            // Stats row
            HStack(spacing: 16) {
                MiniShareStat(label: "Putts", value: "\(stats.totalPutts)")
                MiniShareStat(label: "GIR", value: "\(stats.greensInRegulation)/\(stats.girHoles)")
                MiniShareStat(label: "FIR", value: "\(stats.fairwaysHit)/\(stats.fairwayHoles)")
                MiniShareStat(label: "Front", value: "\(stats.frontNine)")
                MiniShareStat(label: "Back", value: "\(stats.backNine)")
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .frame(width: 380)
    }

    /// Render the view as a UIImage for sharing
    @MainActor
    func renderImage() -> UIImage {
        let renderer = ImageRenderer(content: self.environment(\.colorScheme, .dark))
        renderer.scale = 3.0
        return renderer.uiImage ?? UIImage()
    }
}

private struct ScoreRow: View {
    let label: String
    let values: [String]
    let total: String
    var pars: [Int]?
    var scores: [Int]?
    var isBold: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.system(size: 9, weight: isBold ? .bold : .regular))
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .leading)
            ForEach(Array(values.enumerated()), id: \.offset) { i, val in
                Group {
                    if let pars, let scores, i < pars.count, i < scores.count, scores[i] > 0 {
                        Text(val)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(scoreColor(score: scores[i], par: pars[i]))
                    } else {
                        Text(val)
                            .font(.system(size: 10, weight: isBold ? .bold : .regular))
                            .foregroundStyle(isBold ? .primary : .secondary)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            Text(total)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 28, alignment: .trailing)
        }
    }

    private func scoreColor(score: Int, par: Int) -> Color {
        let diff = score - par
        if diff <= -2 { return .yellow }
        if diff == -1 { return .red }
        if diff == 0 { return .green }
        if diff == 1 { return .cyan }
        return .blue
    }
}

private struct MiniShareStat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 1) {
            Text(value).font(.system(size: 11, weight: .bold))
            Text(label).font(.system(size: 8)).foregroundStyle(.secondary)
        }
    }
}
