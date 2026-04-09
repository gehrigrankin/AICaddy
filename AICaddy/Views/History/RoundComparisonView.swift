import SwiftUI

struct RoundComparisonView: View {
    let round1: Round
    let round2: Round

    private var holes1: [HoleScore] { round1.holes }
    private var holes2: [HoleScore] { round2.holes }
    private var stats1: RoundStats { StatsCalculator.calculate(holes: holes1) }
    private var stats2: RoundStats { StatsCalculator.calculate(holes: holes2) }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection
                holeByHoleSection
                summaryStatsSection
                scoringDistributionSection
            }
            .padding()
        }
        .navigationTitle("Compare Rounds")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 0) {
            roundCard(courseName: round1.courseName, date: round1.date, score: stats1.totalStrokes, scoreToPar: stats1.scoreToPar)
            Text("VS")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
            roundCard(courseName: round2.courseName, date: round2.date, score: stats2.totalStrokes, scoreToPar: stats2.scoreToPar)
        }
    }

    private func roundCard(courseName: String, date: Date, score: Int, scoreToPar: Int) -> some View {
        VStack(spacing: 6) {
            Text(courseName)
                .font(.subheadline.bold())
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(date.formatted(date: .abbreviated, time: .omitted))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(score)")
                .font(.title.bold())
            ScoreText(scoreToPar: scoreToPar)
                .font(.caption.bold())
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Hole-by-Hole

    private var holeByHoleSection: some View {
        VStack(spacing: 0) {
            // Column headers
            HStack(spacing: 0) {
                Text("Hole")
                    .frame(width: 40, alignment: .leading)
                Text("Par")
                    .frame(width: 36, alignment: .center)
                Text("R1")
                    .frame(maxWidth: .infinity)
                Text("R2")
                    .frame(maxWidth: .infinity)
            }
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            let holeCount = max(holes1.count, holes2.count)
            ForEach(1...max(holeCount, 1), id: \.self) { holeNum in
                let h1 = holes1.first { $0.holeNumber == holeNum }
                let h2 = holes2.first { $0.holeNumber == holeNum }
                let par = h1?.par ?? h2?.par ?? 0

                holeRow(holeNumber: holeNum, par: par, score1: h1?.strokes ?? 0, score2: h2?.strokes ?? 0)

                if holeNum == 9 {
                    nineHoleTotalRow(label: "OUT", holes: 1...9)
                }

                if holeNum < holeCount || holeNum == 9 {
                    Divider().padding(.leading, 12)
                }
            }

            if holes1.count > 9 || holes2.count > 9 {
                Divider()
                nineHoleTotalRow(label: "IN", holes: 10...18)
            }

            Divider()
            totalRow
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func holeRow(holeNumber: Int, par: Int, score1: Int, score2: Int) -> some View {
        HStack(spacing: 0) {
            Text("\(holeNumber)")
                .frame(width: 40, alignment: .leading)
                .font(.subheadline)
            Text("\(par)")
                .frame(width: 36, alignment: .center)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            scoreCell(score: score1, par: par, otherScore: score2)
                .frame(maxWidth: .infinity)
            scoreCell(score: score2, par: par, otherScore: score1)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func scoreCell(score: Int, par: Int, otherScore: Int) -> some View {
        Group {
            if score > 0 {
                Text("\(score)")
                    .font(.subheadline.bold())
                    .foregroundStyle(comparisonColor(score: score, otherScore: otherScore))
            } else {
                Text("-")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func comparisonColor(score: Int, otherScore: Int) -> Color {
        guard score > 0, otherScore > 0 else { return .primary }
        if score < otherScore { return .green }
        if score > otherScore { return .red }
        return .primary
    }

    private func nineHoleTotalRow(label: String, holes range: ClosedRange<Int>) -> some View {
        let sum1 = holes1.filter { range.contains($0.holeNumber) && $0.strokes > 0 }.reduce(0) { $0 + $1.strokes }
        let sum2 = holes2.filter { range.contains($0.holeNumber) && $0.strokes > 0 }.reduce(0) { $0 + $1.strokes }

        return HStack(spacing: 0) {
            Text(label)
                .frame(width: 40, alignment: .leading)
                .font(.caption.bold())
            Text("")
                .frame(width: 36)
            Text(sum1 > 0 ? "\(sum1)" : "-")
                .frame(maxWidth: .infinity)
                .font(.subheadline.bold())
            Text(sum2 > 0 ? "\(sum2)" : "-")
                .frame(maxWidth: .infinity)
                .font(.subheadline.bold())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.systemGray5).opacity(0.5))
    }

    private var totalRow: some View {
        HStack(spacing: 0) {
            Text("TOT")
                .frame(width: 40, alignment: .leading)
                .font(.caption.bold())
            Text("")
                .frame(width: 36)
            Text("\(stats1.totalStrokes)")
                .frame(maxWidth: .infinity)
                .font(.subheadline.bold())
                .foregroundStyle(comparisonColor(score: stats1.totalStrokes, otherScore: stats2.totalStrokes))
            Text("\(stats2.totalStrokes)")
                .frame(maxWidth: .infinity)
                .font(.subheadline.bold())
                .foregroundStyle(comparisonColor(score: stats2.totalStrokes, otherScore: stats1.totalStrokes))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray5).opacity(0.5))
    }

    // MARK: - Summary Stats

    private var summaryStatsSection: some View {
        VStack(spacing: 12) {
            Text("Stats Comparison")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            statComparisonRow(label: "Total Putts", val1: "\(stats1.totalPutts)", val2: "\(stats2.totalPutts)", lowerIsBetter: true, num1: Double(stats1.totalPutts), num2: Double(stats2.totalPutts))
            statComparisonRow(label: "Putts/Hole", val1: String(format: "%.1f", stats1.puttsPerHole), val2: String(format: "%.1f", stats2.puttsPerHole), lowerIsBetter: true, num1: stats1.puttsPerHole, num2: stats2.puttsPerHole)
            statComparisonRow(label: "GIR %", val1: String(format: "%.0f%%", stats1.greensInRegulationPct), val2: String(format: "%.0f%%", stats2.greensInRegulationPct), lowerIsBetter: false, num1: stats1.greensInRegulationPct, num2: stats2.greensInRegulationPct)
            statComparisonRow(label: "Fairways %", val1: String(format: "%.0f%%", stats1.fairwaysPct), val2: String(format: "%.0f%%", stats2.fairwaysPct), lowerIsBetter: false, num1: stats1.fairwaysPct, num2: stats2.fairwaysPct)
            statComparisonRow(label: "Scrambling %", val1: String(format: "%.0f%%", stats1.scramblingPct), val2: String(format: "%.0f%%", stats2.scramblingPct), lowerIsBetter: false, num1: stats1.scramblingPct, num2: stats2.scramblingPct)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func statComparisonRow(label: String, val1: String, val2: String, lowerIsBetter: Bool, num1: Double, num2: Double) -> some View {
        HStack {
            Text(val1)
                .font(.subheadline.bold())
                .foregroundStyle(statColor(num1: num1, num2: num2, lowerIsBetter: lowerIsBetter))
                .frame(width: 60, alignment: .trailing)
            Spacer()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(val2)
                .font(.subheadline.bold())
                .foregroundStyle(statColor(num1: num2, num2: num1, lowerIsBetter: lowerIsBetter))
                .frame(width: 60, alignment: .leading)
        }
    }

    private func statColor(num1: Double, num2: Double, lowerIsBetter: Bool) -> Color {
        guard num1 != 0 || num2 != 0 else { return .primary }
        if num1 == num2 { return .primary }
        let isBetter = lowerIsBetter ? num1 < num2 : num1 > num2
        return isBetter ? .green : .red
    }

    // MARK: - Scoring Distribution

    private var scoringDistributionSection: some View {
        VStack(spacing: 12) {
            Text("Scoring Distribution")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            distributionRow(label: "Eagles+", count1: stats1.eagles, count2: stats2.eagles)
            distributionRow(label: "Birdies", count1: stats1.birdies, count2: stats2.birdies)
            distributionRow(label: "Pars", count1: stats1.pars, count2: stats2.pars)
            distributionRow(label: "Bogeys", count1: stats1.bogeys, count2: stats2.bogeys)
            distributionRow(label: "Double+", count1: stats1.doubleBogeys + stats1.triplePlus, count2: stats2.doubleBogeys + stats2.triplePlus)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func distributionRow(label: String, count1: Int, count2: Int) -> some View {
        HStack {
            Text("\(count1)")
                .font(.subheadline.bold())
                .frame(width: 30, alignment: .trailing)
            distributionBar(count: count1, maxCount: 18, alignment: .trailing)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 60)
            distributionBar(count: count2, maxCount: 18, alignment: .leading)
            Text("\(count2)")
                .font(.subheadline.bold())
                .frame(width: 30, alignment: .leading)
        }
    }

    private func distributionBar(count: Int, maxCount: Int, alignment: HorizontalAlignment) -> some View {
        GeometryReader { geo in
            let width = geo.size.width * CGFloat(count) / CGFloat(max(maxCount, 1))
            HStack {
                if alignment == .leading {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.green.opacity(0.7))
                        .frame(width: max(width, 0), height: 14)
                    Spacer(minLength: 0)
                } else {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.green.opacity(0.7))
                        .frame(width: max(width, 0), height: 14)
                }
            }
        }
        .frame(height: 14)
    }
}
