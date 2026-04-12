import SwiftUI

struct WindCompass: View {
    /// Wind speed in mph. nil when weather data is unavailable.
    let speedMph: Double?
    /// Compass direction wind is blowing *from* (degrees, 0 = N, 90 = E).
    let fromDegrees: Double?
    /// Optional player bearing (degrees) — when provided the arrow rotates relative to the player's facing direction.
    var playerBearing: Double? = nil

    private var hasData: Bool { speedMph != nil && fromDegrees != nil }

    private var label: String {
        guard let fromDegrees else { return "--" }
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let normalized = (fromDegrees.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        let index = Int((normalized + 22.5) / 45) % 8
        return directions[index]
    }

    private var arrowRotation: Double {
        guard let fromDegrees else { return 0 }
        let toward = fromDegrees + 180
        let relative = toward - (playerBearing ?? 0)
        return relative
    }

    private var speedText: String {
        guard let speedMph else { return "--" }
        return "\(Int(speedMph.rounded()))"
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.Colors.surface)
            Circle()
                .strokeBorder(Theme.Colors.border, lineWidth: 1)

            // Faint cardinal ticks
            ForEach(0..<8) { i in
                Rectangle()
                    .fill(Theme.Colors.textMuted.opacity(0.35))
                    .frame(width: 1, height: i % 2 == 0 ? 4 : 2)
                    .offset(y: -19)
                    .rotationEffect(.degrees(Double(i) * 45))
            }

            // Speed + label stacked in the middle
            VStack(spacing: -1) {
                Text(speedText)
                    .font(Theme.Font.display(13))
                    .foregroundStyle(hasData ? Theme.Colors.textPrimary : Theme.Colors.textMuted)
                Text(label)
                    .font(Theme.Font.caption(7))
                    .foregroundStyle(hasData ? Theme.Colors.accent : Theme.Colors.textMuted)
                    .tracking(0.8)
            }

            // Arrow (hidden when no data)
            if hasData {
                Image(systemName: "arrow.up")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(Theme.Colors.accent)
                    .offset(y: -16)
                    .rotationEffect(.degrees(arrowRotation))
            }
        }
        .frame(width: 50, height: 50)
        .themeShadow(Theme.Shadow.pill)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        WindCompass(speedMph: 12, fromDegrees: 315)
    }
}
