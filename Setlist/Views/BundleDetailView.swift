import SwiftUI
import SwiftData

struct BundleDetailView: View {
    let bundle: TravelBundle
    let ticketImageData: Data?
    @Environment(\.modelContext) private var context
    @State private var savedConfirmation = false
    @State private var isOpeningBooking = false
    @State private var bookingError: String?

    init(bundle: TravelBundle, ticketImageData: Data? = nil) {
        self.bundle = bundle
        self.ticketImageData = ticketImageData
    }

    var body: some View {
        ZStack {
            AppColor.surface.ignoresSafeArea()
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    headerCard
                    flightsSection
                    hotelsSection
                    activitiesSection
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.sm)
                .padding(.bottom, 140)
            }
        }
        .safeAreaInset(edge: .bottom) {
            stickyBookingBar
        }
        .navigationTitle("여행 일정")
        .navigationBarTitleDisplayMode(.inline)
        .alert("찜에 저장됐어요", isPresented: $savedConfirmation) {
            Button("확인", role: .cancel) { }
        }
        .alert(
            "예약 페이지를 열 수 없어요",
            isPresented: Binding(
                get: { bookingError != nil },
                set: { if !$0 { bookingError = nil } }
            ),
            presenting: bookingError
        ) { _ in
            Button("확인", role: .cancel) { bookingError = nil }
        } message: { msg in
            Text(msg)
        }
    }

    private var stickyBookingBar: some View {
        HStack(spacing: AppSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("예상 총액")
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.inkSecondary)
                    .tracking(0.5)
                Text("₩\(bundle.estimatedTotalKRW.formatted())")
                    .font(AppFont.title2)
                    .foregroundStyle(AppColor.ink)
            }
            Spacer(minLength: 0)
            Button {
                saveToWishlist()
            } label: {
                Image(systemName: savedConfirmation ? "heart.fill" : "heart")
            }
            .buttonStyle(IconCircleButton(tint: savedConfirmation ? AppColor.brandSecondary : AppColor.ink))

            Button {
                Task { await openBooking() }
            } label: {
                HStack(spacing: AppSpacing.sm) {
                    if isOpeningBooking { ProgressView().tint(.white) }
                    Text(isOpeningBooking ? "여는 중..." : "예약하기")
                }
            }
            .buttonStyle(PrimaryGradientButton(fullWidth: false))
            .disabled(isOpeningBooking)
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.md)
        .background {
            Rectangle()
                .fill(AppColor.surfaceElevated)
                .overlay(alignment: .top) {
                    Rectangle().fill(.black.opacity(0.06)).frame(height: 0.5)
                }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: - Subviews

    @State private var headerImage: OpenverseImage?

    private var headerCard: some View {
        ZStack(alignment: .bottomLeading) {
            RichImageView(topic: heroTopic, fallbackTint: heroTint) { headerImage = $0 }
                .frame(height: 260)
                .frame(maxWidth: .infinity)

            LinearGradient(
                colors: [.black.opacity(0.05), .black.opacity(0.65)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 260)

            VStack(alignment: .leading, spacing: 10) {
                if case .concert(let c) = bundle.source {
                    HStack(spacing: 6) {
                        Image(systemName: "music.mic")
                            .font(.system(size: 11, weight: .heavy))
                        Text("공연 \(c.showDate.formatted(.dateTime.locale(Locale(identifier: "ko_KR")).month().day().hour().minute()))")
                            .font(AppFont.kicker)
                            .tracking(1.2)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.18), in: Capsule())
                    .lineLimit(1)
                }
                Text(headline)
                    .font(AppFont.display)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text(headerDateRange)
                    .font(AppFont.headline)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
            }
            .padding(AppSpacing.lg)

            if let headerImage {
                ImageAttributionLabel(image: headerImage)
                    .padding(AppSpacing.sm)
                    .frame(maxWidth: .infinity, alignment: .topTrailing)
                    .frame(height: 260, alignment: .topTrailing)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
        .appElevation(.medium)
    }

    private func flightTimeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "M/d HH:mm"
        f.locale = Locale(identifier: "ko_KR")
        f.timeZone = TimeZone(identifier: "Asia/Seoul")
        return f.string(from: date)
    }

    private var headerDateRange: String {
        let f = DateFormatter()
        f.dateFormat = "M/d(E)"
        f.locale = Locale(identifier: "ko_KR")
        f.timeZone = TimeZone(identifier: "Asia/Seoul")
        let d = f.string(from: bundle.suggestedDepartureDate)
        let r = f.string(from: bundle.suggestedReturnDate)
        return "\(d) – \(r)"
    }

    private var heroTopic: String {
        switch bundle.source {
        case .concert(let c):
            return "\(c.city) skyline night"
        case .content(let c):
            if let place = c.detectedPlaceName, !place.isEmpty { return place }
            return "\(c.detectedCity) travel"
        case .manual:
            return "travel"
        }
    }

    private var heroTint: Color {
        switch bundle.source {
        case .concert: return .purple
        case .content: return .pink
        case .manual:  return .blue
        }
    }

    private var flightsSection: some View {
        sectionCard(title: "항공편") {
            if bundle.flights.isEmpty {
                Text("이 날짜의 항공 운임을 가져오지 못했어요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(bundle.flights.enumerated()), id: \.element.id) { index, f in
                Button {
                    Task { await openItem(
                        url: f.bookingURL,
                        title: "\(f.airline) \(f.fromAirport)→\(f.toAirport)",
                        category: "FLIGHT",
                        gid: f.mrtProductID
                    ) }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("\(f.airline) \(f.flightNumber)").bold()
                            Spacer()
                            if f.priceKRW > 0 {
                                Text("₩\(f.priceKRW.formatted())")
                            } else {
                                Text("운임 보기").foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary).font(.caption)
                        }
                        Text("\(f.fromAirport) → \(f.toAirport) · \(flightTimeString(f.departureTime))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 6)
                if index < bundle.flights.count - 1 { Divider() }
            }
        }
    }

    private var hotelsSection: some View {
        sectionCard(title: "근처 숙소") {
            if bundle.hotels.isEmpty {
                Text("이 날짜에 가져올 수 있는 숙소가 없어요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(bundle.hotels.enumerated()), id: \.element.id) { index, h in
                Button {
                    Task { await openItem(
                        url: h.bookingURL,
                        title: h.name,
                        category: "HOTEL",
                        gid: h.mrtProductID
                    ) }
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(h.name)
                                .bold()
                                .lineLimit(2)
                                .minimumScaleFactor(0.9)
                            Spacer(minLength: 8)
                            Text("₩\(h.pricePerNightKRW.formatted())/박")
                                .lineLimit(1)
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary).font(.caption)
                        }
                        Text(hotelCaption(h))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if h.freeCancellation {
                            Label("무료 취소", systemImage: "checkmark.seal")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 6)
                if index < bundle.hotels.count - 1 { Divider() }
            }
        }
    }

    private func hotelCaption(_ h: HotelOption) -> String {
        var parts: [String] = []
        if h.distanceMetersFromAnchor > 0 {
            parts.append("\(h.distanceMetersFromAnchor)m 거리")
        }
        if h.starRating > 0 {
            parts.append(String(format: "%.1f★", h.starRating))
        }
        if h.userRating > 0 {
            parts.append(String(format: "투숙객 %.1f", h.userRating))
        }
        return parts.joined(separator: " · ")
    }

    private var activitiesSection: some View {
        sectionCard(title: "추천 액티비티") {
            if bundle.activities.isEmpty {
                Text("이 도시의 액티비티가 없어요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(bundle.activities.enumerated()), id: \.element.id) { index, a in
                NavigationLink {
                    TNADetailView(activity: a)
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        if let url = a.thumbnailURL {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let img):
                                    img.resizable().scaledToFill()
                                default:
                                    Color.gray.opacity(0.1)
                                }
                            }
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.title).bold().lineLimit(2)
                                .foregroundStyle(.primary)
                            Text(activityCaption(a))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("₩\(a.priceKRW.formatted())")
                                .foregroundStyle(.primary)
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary).font(.caption)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 6)
                if index < bundle.activities.count - 1 { Divider() }
            }
        }
    }

    private func activityCaption(_ a: ActivityOption) -> String {
        var parts: [String] = []
        if a.durationHours > 0 { parts.append(String(format: "%.1f시간", a.durationHours)) }
        if a.rating > 0 { parts.append(String(format: "★ %.1f", a.rating)) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func sectionCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text(title)
                .font(AppFont.headline)
                .foregroundStyle(AppColor.ink)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.lg)
        .background(AppColor.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.lg)
                .stroke(.black.opacity(0.04), lineWidth: 1)
        }
        .appShadow(.soft)
    }

    // MARK: - Helpers

    private var headline: String {
        switch bundle.source {
        case .concert(let c): return "\(c.artist) · \(c.city)"
        case .content(let c): return c.detectedPlaceName ?? c.detectedCity
        case .manual: return "여행"
        }
    }

    private func saveToWishlist() {
        do {
            let data = try JSONEncoder.setlist.encode(bundle)
            let trip = SavedTrip(
                bundleData: data,
                title: headline,
                ticketImageData: ticketImageData
            )
            context.insert(trip)
            try context.save()
            savedConfirmation = true
        } catch {
            print("Save failed: \(error)")
        }
    }

    @MainActor
    private func openBooking() async {
        guard let target = primaryBookingURL else { return }
        isOpeningBooking = true
        defer { isOpeningBooking = false }

        // "Book all" picks the most-trackable item: hotel > activity > flight,
        // because MRT's flight reservation API doesn't surface utm_content.
        let intent: BookingIntent? = {
            if let h = bundle.hotels.first {
                return BookingIntent(
                    title: h.name,
                    productCategory: "HOTEL",
                    productGid: h.mrtProductID,
                    targetURLString: h.bookingURL.absoluteString,
                    ticketImageData: ticketImageData
                )
            }
            if let a = bundle.activities.first {
                return BookingIntent(
                    title: a.title,
                    productCategory: "TNA",
                    productGid: a.mrtProductID,
                    targetURLString: a.bookingURL.absoluteString,
                    ticketImageData: ticketImageData
                )
            }
            return nil
        }()

        let urlToOpen: URL
        if let intent {
            context.insert(intent)
            try? context.save()
            urlToOpen = URL(string: intent.targetURLString) ?? target
        } else {
            urlToOpen = target  // flight-only — no utm tracking possible
        }

        do {
            let trackedURL = try await AppEnvironment.mrtClient.generateMyLink(
                targetURL: urlToOpen,
                utmContent: intent?.id.uuidString
            )
            _ = await UIApplication.shared.open(trackedURL)
            recordBooking(url: trackedURL)
        } catch {
            _ = await UIApplication.shared.open(urlToOpen)
            bookingError = error.localizedDescription
        }
    }

    @MainActor
    private func openItem(url: URL, title: String, category: String, gid: String) async {
        let intent = BookingIntent(
            title: title,
            productCategory: category,
            productGid: gid,
            targetURLString: url.absoluteString,
            ticketImageData: ticketImageData
        )
        context.insert(intent)
        try? context.save()

        do {
            let tracked = try await AppEnvironment.mrtClient.generateMyLink(
                targetURL: url,
                utmContent: intent.id.uuidString
            )
            _ = await UIApplication.shared.open(tracked)
        } catch {
            _ = await UIApplication.shared.open(url)
        }
    }

    private var primaryBookingURL: URL? {
        // Prefer the flight landing URL because it encodes the whole trip
        // parameters; hotels/activities are per-item fallbacks.
        bundle.flights.first?.bookingURL
            ?? bundle.hotels.first?.bookingURL
            ?? bundle.activities.first?.bookingURL
    }

    private func recordBooking(url: URL) {
        do {
            let data = try JSONEncoder.setlist.encode(bundle)
            let ref = url.lastPathComponent.isEmpty ? UUID().uuidString.prefix(8).uppercased() : url.lastPathComponent
            let booked = BookedTrip(
                bundleData: data,
                title: headline,
                bookingReference: String(ref),
                ticketImageData: ticketImageData
            )
            context.insert(booked)
            try context.save()
        } catch {
            // Logging only — booking already opened in browser.
            print("Record booking failed: \(error)")
        }
    }
}
