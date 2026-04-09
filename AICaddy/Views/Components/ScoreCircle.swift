import SwiftUI

struct ScoreCircle: View {
    let strokes: Int
    let par: Int
    var size: CGFloat = 44

    private var diff: Int { strokes - par }

    private var bgColor: Color {
        guard strokes > 0 else { return Color(.systemGray5) }
        switch diff {
        case ...(-2): return .yellow
        case -1: return .red
        case 0: return .green
        case 1: return .cyan
        case 2: return .blue
        default: return Color(.systemGray3)
        }
    }

    private var textColor: Color {
        guard strokes > 0 else { return .secondary }
        switch diff {
        case ...(-2): return .black
        default: return .white
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(bgColor)
                .frame(width: size, height: size)
            Text(strokes > 0 ? "\(strokes)" : "-")
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(textColor)
        }
    }
}

struct ScoreText: View {
    let scoreToPar: Int

    var body: some View {
        Text(formatted)
            .foregroundStyle(color)
    }

    private var formatted: String {
        if scoreToPar == 0 { return "E" }
        return scoreToPar > 0 ? "+\(scoreToPar)" : "\(scoreToPar)"
    }

    private var color: Color {
        if scoreToPar < 0 { return .red }
        if scoreToPar > 0 { return .cyan }
        return .green
    }
}
