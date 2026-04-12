import SwiftUI

struct GameCardStyle: ViewModifier {
    var padding: CGFloat = 14
    var radius: CGFloat = Theme.Radius.card
    var fill: Color = Theme.Colors.surface
    var stroke: Color = Theme.Colors.border
    var shadow: ShadowStyle = Theme.Shadow.card

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 1)
            )
            .themeShadow(shadow)
    }
}

extension View {
    func gameCard(
        padding: CGFloat = 14,
        radius: CGFloat = Theme.Radius.card,
        fill: Color = Theme.Colors.surface,
        stroke: Color = Theme.Colors.border,
        shadow: ShadowStyle = Theme.Shadow.card
    ) -> some View {
        modifier(GameCardStyle(padding: padding, radius: radius, fill: fill, stroke: stroke, shadow: shadow))
    }

    func gamePill(fill: Color = Theme.Colors.surface) -> some View {
        modifier(GameCardStyle(padding: 10, radius: Theme.Radius.pill, fill: fill, shadow: Theme.Shadow.pill))
    }
}
