import SwiftUI

// "더보기" 탭. 사용자에게 보이는 1차 화면이지만, 진짜 핵심 기능 (수익
// 대시보드)은 파트너에게만 의미가 있어서 메뉴 안쪽 한 단계로 넣어둔다.

struct MoreView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.surface.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.lg) {
                        partnerCard
                        partnerMenu
                        infoMenu
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.top, AppSpacing.sm)
                    .padding(.bottom, AppSpacing.xxl)
                }
            }
            .navigationTitle("더보기")
        }
    }

    // MARK: - Partner status hero

    private var partnerCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: AppEnvironment.useMockMRT
                      ? "circle.dashed"
                      : "checkmark.seal.fill")
                    .font(.system(size: 12, weight: .heavy))
                Text("MARKETING PARTNER")
                    .font(AppFont.kicker)
                    .tracking(1.5)
            }
            .foregroundStyle(AppEnvironment.useMockMRT
                             ? AppColor.inkSecondary
                             : AppColor.brandPrimary)

            Text(AppEnvironment.useMockMRT
                 ? "샘플 모드"
                 : "마이리얼트립 연결됨")
                .font(AppFont.title1)
                .foregroundStyle(AppColor.ink)

            Text(AppEnvironment.useMockMRT
                 ? "Keychain에 파트너 키를 저장하면 실데이터가 들어와요. 빌드 스크립트가 자동으로 주입합니다."
                 : "내 마이링크로 발생한 예약과 커미션이 자동 추적됩니다. 정산은 매일 오전 6시(KST).")
                .font(AppFont.body)
                .foregroundStyle(AppColor.inkSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.lg)
        .background(AppColor.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.xl)
                .stroke(.black.opacity(0.04), lineWidth: 1)
        }
        .appShadow(.soft)
    }

    // MARK: - Menus

    private var partnerMenu: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            SectionHeader(kicker: "Partner", title: "파트너 도구")
            menuList {
                MenuRow(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "내 수익 현황",
                    subtitle: "마이링크로 발생한 커미션 정산",
                    accent: AppColor.brandPrimary,
                    destination: AnyView(RevenueView())
                )
                Divider().padding(.leading, 64)
                MenuRow(
                    icon: "link",
                    title: "마이링크 가이드",
                    subtitle: "예약 추적 방식 · 24시간 쿠키",
                    accent: AppColor.brandSecondary,
                    externalURL: URL(string: "https://docs.myrealtrip.com/#/api/partner-api/마이-링크")
                )
                Divider().padding(.leading, 64)
                MenuRow(
                    icon: "doc.text",
                    title: "MRT 파트너 API 문서",
                    subtitle: "docs.myrealtrip.com",
                    accent: AppColor.success,
                    externalURL: URL(string: "https://docs.myrealtrip.com")
                )
            }
        }
    }

    private var infoMenu: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            SectionHeader(title: "지원")
            menuList {
                MenuRow(
                    icon: "envelope",
                    title: "파트너 문의",
                    subtitle: "marketing_partner@myrealtrip.com",
                    accent: AppColor.warning,
                    externalURL: URL(string: "mailto:marketing_partner@myrealtrip.com")
                )
                Divider().padding(.leading, 64)
                MenuRow(
                    icon: "info.circle",
                    title: "앱 정보",
                    subtitle: "Setlist · 버전 1.0",
                    accent: AppColor.inkSecondary,
                    destination: nil,
                    externalURL: nil
                )
            }
        }
    }

    @ViewBuilder
    private func menuList<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0, content: content)
            .background(AppColor.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.lg)
                    .stroke(.black.opacity(0.04), lineWidth: 1)
            }
            .appShadow(.soft)
    }
}

private struct MenuRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let accent: Color
    var destination: AnyView? = nil
    var externalURL: URL? = nil

    @Environment(\.openURL) private var openURL

    var body: some View {
        Group {
            if let destination {
                NavigationLink {
                    destination
                } label: { rowContent(showChevron: true) }
                .buttonStyle(.plain)
            } else if let externalURL {
                Button {
                    openURL(externalURL)
                } label: { rowContent(showChevron: true) }
                .buttonStyle(.plain)
            } else {
                rowContent(showChevron: false)
            }
        }
    }

    private func rowContent(showChevron: Bool) -> some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 36, height: 36)
                .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.bodyBold)
                    .foregroundStyle(AppColor.ink)
                Text(subtitle)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(AppColor.inkTertiary)
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

#Preview {
    MoreView()
}
