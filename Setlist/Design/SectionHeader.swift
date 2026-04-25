import SwiftUI

// Editorial section header — small kicker (tracked uppercase brand color)
// + bold title, optional trailing action.

struct SectionHeader: View {
    var kicker: String? = nil
    let title: String
    var actionLabel: String? = nil
    var actionHandler: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            if let kicker {
                Text(kicker.uppercased())
                    .font(AppFont.kicker)
                    .tracking(1.6)
                    .foregroundStyle(AppColor.brandPrimary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(AppFont.title1)
                    .foregroundStyle(AppColor.ink)
                Spacer()
                if let label = actionLabel, let handler = actionHandler {
                    Button(label, action: handler)
                        .buttonStyle(GhostButton())
                }
            }
        }
    }
}

// Lightweight subheader (used inside section content blocks).
struct SubsectionLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(AppFont.headline)
            .foregroundStyle(AppColor.ink)
    }
}

// Status badge — pill with semantic color.
struct StatusBadge: View {
    enum Variant { case success, warning, danger, info, neutral, brand }
    let text: String
    var variant: Variant = .info

    var body: some View {
        Text(text)
            .font(AppFont.badge)
            .foregroundStyle(textColor)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, 4)
            .background(backgroundColor, in: Capsule())
    }

    private var textColor: Color {
        switch variant {
        case .success: return AppColor.success
        case .warning: return AppColor.warning
        case .danger:  return AppColor.danger
        case .info:    return AppColor.brandPrimary
        case .neutral: return AppColor.inkSecondary
        case .brand:   return .white
        }
    }
    private var backgroundColor: Color {
        switch variant {
        case .success: return AppColor.success.opacity(0.14)
        case .warning: return AppColor.warning.opacity(0.14)
        case .danger:  return AppColor.danger.opacity(0.12)
        case .info:    return AppColor.brandPrimary.opacity(0.12)
        case .neutral: return AppColor.surfaceMuted
        case .brand:   return AppColor.brandPrimary
        }
    }
}
