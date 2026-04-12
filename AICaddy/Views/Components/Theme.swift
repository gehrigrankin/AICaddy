import SwiftUI

enum Theme {
    enum Colors {
        static let surface = Color(red: 0.118, green: 0.165, blue: 0.227)
        static let surfaceElevated = Color(red: 0.157, green: 0.212, blue: 0.290)
        static let surfaceDeep = Color(red: 0.078, green: 0.114, blue: 0.165)
        static let border = Color.white.opacity(0.08)
        static let divider = Color.white.opacity(0.14)

        static let textPrimary = Color.white
        static let textSecondary = Color.white.opacity(0.72)
        static let textMuted = Color.white.opacity(0.48)

        static let accent = Color(red: 0.961, green: 0.773, blue: 0.094)
        static let accentSoft = Color(red: 0.961, green: 0.773, blue: 0.094).opacity(0.18)
        static let positive = Color(red: 0.329, green: 0.851, blue: 0.565)
        static let negative = Color(red: 0.969, green: 0.380, blue: 0.416)

        static let backdrop = Color(red: 0.043, green: 0.071, blue: 0.114)
    }

    enum Radius {
        static let card: CGFloat = 14
        static let pill: CGFloat = 999
        static let tight: CGFloat = 8
    }

    enum Shadow {
        static let card = ShadowStyle(color: .black.opacity(0.35), radius: 14, x: 0, y: 6)
        static let pill = ShadowStyle(color: .black.opacity(0.28), radius: 8, x: 0, y: 3)
    }

    enum Font {
        static func display(_ size: CGFloat) -> SwiftUI.Font {
            .system(size: size, weight: .heavy, design: .rounded)
        }
        static func title(_ size: CGFloat) -> SwiftUI.Font {
            .system(size: size, weight: .bold, design: .rounded)
        }
        static func label(_ size: CGFloat) -> SwiftUI.Font {
            .system(size: size, weight: .semibold, design: .rounded)
        }
        static func mono(_ size: CGFloat) -> SwiftUI.Font {
            .system(size: size, weight: .bold, design: .monospaced)
        }
        static func caption(_ size: CGFloat = 11) -> SwiftUI.Font {
            .system(size: size, weight: .semibold, design: .rounded)
        }
    }
}

struct ShadowStyle {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

extension View {
    func themeShadow(_ style: ShadowStyle) -> some View {
        shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }
}
