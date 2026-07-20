import SwiftUI

struct ScorecardView: View {
    let holes: [HoleScore]
    let courseName: String
    let teeName: String
    var onHoleTap: ((Int) -> Void)?

    private var front: [HoleScore] { holes.filter { $0.holeNumber <= 9 } }
    private var back: [HoleScore] { holes.filter { $0.holeNumber > 9 } }

    private var frontPar: Int { front.reduce(0) { $0 + $1.par } }
    private var backPar: Int { back.reduce(0) { $0 + $1.par } }
    private var frontScore: Int { front.reduce(0) { $0 + $1.strokes } }
    private var backScore: Int { back.reduce(0) { $0 + $1.strokes } }
    private var totalScore: Int { frontScore + backScore }
    private var totalPar: Int { frontPar + backPar }

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                if totalScore > 0 {
                    Text("\(totalScore)")
                        .font(Theme.Font.display(28))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    ScoreText(scoreToPar: totalScore - totalPar)
                        .font(Theme.Font.title(14))
                }
                Spacer()
                Text("\(courseName) · \(teeName)".uppercased())
                    .font(Theme.Font.caption(10))
                    .foregroundStyle(Theme.Colors.textMuted)
                    .tracking(0.5)
            }

            NineHoleGrid(
                label: "OUT",
                holes: front,
                totalPar: frontPar,
                totalScore: frontScore,
                onHoleTap: onHoleTap
            )

            NineHoleGrid(
                label: "IN",
                holes: back,
                totalPar: backPar,
                totalScore: backScore,
                onHoleTap: onHoleTap
            )
        }
    }
}

struct NineHoleGrid: View {
    let label: String
    let holes: [HoleScore]
    let totalPar: Int
    let totalScore: Int
    var onHoleTap: ((Int) -> Void)?

    var body: some View {
        VStack(spacing: 4) {
            holeNumbersRow
            parRow
            scoresRow
            puttsRow
            girRow
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Colors.border, lineWidth: 1)
        )
    }

    private var holeNumbersRow: some View {
        HStack(spacing: 0) {
            Text(label)
                .font(Theme.Font.caption(9))
                .foregroundStyle(Theme.Colors.accent)
                .tracking(1)
                .frame(width: 36, alignment: .leading)
            ForEach(holes) { hole in
                Text("\(hole.holeNumber)")
                    .font(Theme.Font.caption(10))
                    .foregroundStyle(Theme.Colors.textMuted)
                    .frame(maxWidth: .infinity)
            }
            Text("TOT")
                .font(Theme.Font.caption(9))
                .foregroundStyle(Theme.Colors.textMuted)
                .tracking(0.8)
                .frame(width: 36)
        }
    }

    private var parRow: some View {
        HStack(spacing: 0) {
            Text("PAR")
                .font(Theme.Font.caption(9))
                .foregroundStyle(Theme.Colors.textMuted)
                .tracking(0.8)
                .frame(width: 36, alignment: .leading)
            ForEach(holes) { hole in
                Text("\(hole.par)")
                    .font(Theme.Font.caption(10))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity)
            }
            Text("\(totalPar)")
                .font(Theme.Font.label(10))
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 36)
        }
    }

    private var scoresRow: some View {
        HStack(spacing: 0) {
            Text("SCORE")
                .font(Theme.Font.caption(9))
                .foregroundStyle(Theme.Colors.textMuted)
                .tracking(0.8)
                .frame(width: 36, alignment: .leading)
            ForEach(holes) { hole in
                Button { onHoleTap?(hole.holeNumber) } label: {
                    ScoreCircle(strokes: hole.strokes, par: hole.par, size: 26)
                }
                .frame(maxWidth: .infinity)
            }
            Text(totalScore > 0 ? "\(totalScore)" : "-")
                .font(Theme.Font.title(13))
                .foregroundStyle(Theme.Colors.textPrimary)
                .frame(width: 36)
        }
    }

    private var puttsRow: some View {
        HStack(spacing: 0) {
            Text("PUTT")
                .font(Theme.Font.caption(8))
                .foregroundStyle(Theme.Colors.textMuted)
                .tracking(0.8)
                .frame(width: 36, alignment: .leading)
            ForEach(holes) { hole in
                Text(hole.putts.map { "\($0)" } ?? "-")
                    .font(Theme.Font.caption(9))
                    .foregroundStyle(Theme.Colors.textMuted)
                    .frame(maxWidth: .infinity)
            }
            Text("\(holes.compactMap(\.putts).reduce(0, +))")
                .font(Theme.Font.caption(9))
                .foregroundStyle(Theme.Colors.textMuted)
                .frame(width: 36)
        }
    }

    private var girRow: some View {
        let girCount = holes.filter { $0.greenInRegulation == true }.count
        let girTotal = holes.filter { $0.greenInRegulation != nil }.count
        return HStack(spacing: 0) {
            Text("GIR")
                .font(Theme.Font.caption(8))
                .foregroundStyle(Theme.Colors.textMuted)
                .tracking(0.8)
                .frame(width: 36, alignment: .leading)
            ForEach(holes) { hole in
                let girText: String = hole.greenInRegulation == true ? "●" : (hole.greenInRegulation == false ? "○" : "-")
                let girColor: Color = hole.greenInRegulation == true ? Theme.Colors.positive : Theme.Colors.textMuted
                Text(girText)
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(girColor)
                    .frame(maxWidth: .infinity)
            }
            Text("\(girCount)/\(girTotal)")
                .font(Theme.Font.caption(9))
                .foregroundStyle(Theme.Colors.textMuted)
                .frame(width: 36)
        }
    }
}
