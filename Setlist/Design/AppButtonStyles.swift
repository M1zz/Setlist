import SwiftUI

// Buttons — primary (gradient fill), secondary (tinted), ghost (text-only),
// pill (capsule). Spring-press scale animation keeps every tap feeling alive.

struct PrimaryGradientButton: ButtonStyle {
    var fullWidth: Bool = true
    var height: CGFloat = 52

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.bodyBold)
            .foregroundStyle(.white)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: height)
            .padding(.horizontal, AppSpacing.lg)
            .background(AppColor.brandGradient)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            .appElevation(.medium)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

struct SecondaryTintedButton: ButtonStyle {
    var tint: Color = AppColor.brandPrimary
    var height: CGFloat = 52

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.bodyBold)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .padding(.horizontal, AppSpacing.lg)
            .background(tint.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

struct PillButton: ButtonStyle {
    var tint: Color = AppColor.ink
    var fillBackground: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.captionBold)
            .foregroundStyle(fillBackground ? Color.white : tint)
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, 8)
            .background {
                if fillBackground {
                    Capsule().fill(tint)
                } else {
                    Capsule().stroke(tint.opacity(0.3), lineWidth: 1)
                }
            }
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct GhostButton: ButtonStyle {
    var tint: Color = AppColor.brandPrimary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.captionBold)
            .foregroundStyle(tint)
            .padding(.vertical, AppSpacing.sm)
            .padding(.horizontal, AppSpacing.md)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct IconCircleButton: ButtonStyle {
    var size: CGFloat = 44
    var tint: Color = AppColor.ink
    var fillBackground: Color = AppColor.surfaceMuted

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(fillBackground, in: Circle())
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
