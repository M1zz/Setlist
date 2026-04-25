import SwiftUI

// Design tokens — colors, spacing, type, radius, shadows. Picked once,
// referenced everywhere, so the look stays coherent as the app grows.

// MARK: - Color

enum AppColor {
    // Text
    static let ink            = Color(red: 0.04, green: 0.04, blue: 0.12)
    static let inkSecondary   = Color(red: 0.36, green: 0.36, blue: 0.45)
    static let inkTertiary    = Color(red: 0.55, green: 0.55, blue: 0.64)
    static let inkInverse     = Color.white

    // Surfaces
    static let surface        = Color(red: 0.972, green: 0.967, blue: 0.984) // page bg, slightly purple-tinted
    static let surfaceElevated = Color.white                                  // cards
    static let surfaceMuted   = Color(red: 0.940, green: 0.929, blue: 0.965) // subtle fills
    static let surfaceInverse = Color(red: 0.10, green: 0.06, blue: 0.20)    // dark hero
    static let surfacePaper   = Color(red: 0.985, green: 0.975, blue: 0.94)  // ticket card

    // Brand
    static let brandPrimary   = Color(red: 0.36, green: 0.17, blue: 1.00)    // cosmic purple
    static let brandSecondary = Color(red: 1.00, green: 0.23, blue: 0.44)    // hot magenta
    static let brandTertiary  = Color(red: 1.00, green: 0.42, blue: 0.42)    // warm coral

    // Semantic
    static let success        = Color(red: 0.00, green: 0.72, blue: 0.50)
    static let warning        = Color(red: 0.96, green: 0.64, blue: 0.00)
    static let danger         = Color(red: 0.91, green: 0.30, blue: 0.25)

    // Hero gradient (purple → magenta) — used for primary CTAs and revenue hero
    static let brandGradient = LinearGradient(
        colors: [brandPrimary, brandSecondary],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let nightGradient = LinearGradient(
        colors: [Color(red: 0.10, green: 0.06, blue: 0.20),
                 Color(red: 0.20, green: 0.08, blue: 0.32)],
        startPoint: .top, endPoint: .bottom
    )

    static let warmGradient = LinearGradient(
        colors: [Color(red: 1.00, green: 0.42, blue: 0.42),
                 Color(red: 1.00, green: 0.27, blue: 0.55)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

// MARK: - Spacing (8-pt grid)

enum AppSpacing {
    static let xxs: CGFloat = 2
    static let xs:  CGFloat = 4
    static let sm:  CGFloat = 8
    static let md:  CGFloat = 12
    static let lg:  CGFloat = 16
    static let xl:  CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 48
}

// MARK: - Corner radius

enum AppRadius {
    static let sm:  CGFloat = 8
    static let md:  CGFloat = 12
    static let lg:  CGFloat = 16
    static let xl:  CGFloat = 20
    static let xxl: CGFloat = 28
    static let pill: CGFloat = 999
}

// MARK: - Typography

enum AppFont {
    static let display       = Font.system(size: 32, weight: .heavy, design: .default)
    static let displayMedium = Font.system(size: 28, weight: .bold,  design: .default)
    static let title1        = Font.system(size: 22, weight: .bold,  design: .default)
    static let title2        = Font.system(size: 19, weight: .bold,  design: .default)
    static let title3        = Font.system(size: 17, weight: .semibold)
    static let headline      = Font.system(size: 16, weight: .semibold)
    static let body          = Font.system(size: 15, weight: .regular)
    static let bodyBold      = Font.system(size: 15, weight: .semibold)
    static let caption       = Font.system(size: 13, weight: .regular)
    static let captionBold   = Font.system(size: 13, weight: .semibold)
    static let caption2      = Font.system(size: 11, weight: .regular)
    static let kicker        = Font.system(size: 11, weight: .heavy,  design: .default) // 1.5px tracking + uppercase
    static let badge         = Font.system(size: 11, weight: .bold)
    static let mono          = Font.system(size: 13, weight: .medium, design: .monospaced)
}

// MARK: - Shadow

enum AppShadow {
    case subtle, soft, medium, bold

    var color: Color {
        Color.black.opacity(opacity)
    }
    var opacity: Double {
        switch self {
        case .subtle: return 0.04
        case .soft:   return 0.06
        case .medium: return 0.10
        case .bold:   return 0.16
        }
    }
    var radius: CGFloat {
        switch self {
        case .subtle: return 2
        case .soft:   return 8
        case .medium: return 16
        case .bold:   return 28
        }
    }
    var offsetY: CGFloat {
        switch self {
        case .subtle: return 1
        case .soft:   return 2
        case .medium: return 4
        case .bold:   return 8
        }
    }
}

extension View {
    func appShadow(_ level: AppShadow = .soft) -> some View {
        shadow(color: level.color, radius: level.radius, x: 0, y: level.offsetY)
    }

    /// Two-layer shadow stack — close + far — for heavier surfaces.
    func appElevation(_ level: AppShadow = .medium) -> some View {
        self
            .shadow(color: .black.opacity(level.opacity), radius: level.radius, x: 0, y: level.offsetY)
            .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
    }
}
