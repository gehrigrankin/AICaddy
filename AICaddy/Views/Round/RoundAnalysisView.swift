import SwiftUI

struct RoundAnalysisView: View {
    let analysis: RoundAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(.green)
                Text(analysis.isAIGenerated ? "AI Coach Analysis" : "Round Analysis")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                if analysis.isAIGenerated {
                    Text("Powered by Claude")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }

            // Summary
            Text(analysis.summary)
                .font(.subheadline)

            // Strokes breakdown
            if analysis.drivingAssessment != nil || analysis.approachAssessment != nil {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Game Breakdown").font(.caption.bold()).foregroundStyle(.secondary)
                    if let d = analysis.drivingAssessment {
                        AssessmentRow(icon: "figure.golf", label: "Driving", value: d)
                    }
                    if let a = analysis.approachAssessment {
                        AssessmentRow(icon: "scope", label: "Approach", value: a)
                    }
                    if let s = analysis.shortGameAssessment {
                        AssessmentRow(icon: "arrow.up.right", label: "Short Game", value: s)
                    }
                    if let p = analysis.puttingAssessment {
                        AssessmentRow(icon: "circle.circle", label: "Putting", value: p)
                    }
                }
            }

            // Strengths
            if !analysis.strengths.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Strengths", systemImage: "checkmark.circle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                    ForEach(analysis.strengths, id: \.self) { s in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•").foregroundStyle(.green)
                            Text(s).font(.caption)
                        }
                    }
                }
            }

            // Weaknesses
            if !analysis.weaknesses.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Work On", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                    ForEach(analysis.weaknesses, id: \.self) { w in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•").foregroundStyle(.orange)
                            Text(w).font(.caption)
                        }
                    }
                }
            }

            // Practice advice
            if !analysis.practiceAdvice.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Range Session Plan", systemImage: "figure.strengthtraining.traditional")
                        .font(.caption.bold())
                        .foregroundStyle(.blue)
                    Text(analysis.practiceAdvice)
                        .font(.caption)
                }
            }

            // Key insight
            if let insight = analysis.keyInsight, !insight.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption)
                    Text(insight)
                        .font(.caption)
                        .italic()
                }
                .padding(10)
                .background(Color.yellow.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct AssessmentRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(label)
                .font(.caption.bold())
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
