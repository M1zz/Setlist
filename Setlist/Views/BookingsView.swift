import SwiftUI
import SwiftData

struct BookingsView: View {
    @Query(sort: \BookedTrip.bookedAt, order: .reverse) private var bookings: [BookedTrip]
    @Query(sort: \BookingIntent.createdAt, order: .reverse) private var intents: [BookingIntent]
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    @State private var remoteReservations: [RemoteReservation] = []
    @State private var remoteFlightReservations: [RemoteFlightReservation] = []
    @State private var isRefreshing = false
    @State private var refreshError: String?
    @State private var didAutoRefresh = false

    var body: some View {
        NavigationStack {
            Group {
                if bookings.isEmpty && remoteReservations.isEmpty && remoteFlightReservations.isEmpty && intents.isEmpty && !isRefreshing {
                    ContentUnavailableView(
                        "예약 내역이 없어요",
                        systemImage: "ticket",
                        description: Text(AppEnvironment.useMockMRT
                            ? "마이리얼트립 파트너 키를 연결하면 확정된 예약이 여기에 표시돼요."
                            : "당겨서 새로고침하면 마이리얼트립 예약이 티켓으로 보여요.")
                    )
                } else {
                    content
                }
            }
            .navigationTitle("내 여행")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        if isRefreshing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isRefreshing || AppEnvironment.useMockMRT)
                }
            }
            .refreshable { await refresh() }
            .task {
                guard !didAutoRefresh, !AppEnvironment.useMockMRT else { return }
                didAutoRefresh = true
                await refresh()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active && !AppEnvironment.useMockMRT {
                    Task { await refresh() }
                }
            }
        }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                if !intents.isEmpty {
                    sectionHeader("내가 시작한 예약")
                    ForEach(intents) { intent in
                        intentTicketRow(intent)
                            .padding(.horizontal, 16)
                    }
                }
                if !bookings.isEmpty {
                    sectionHeader("이 기기에서 연 예약")
                    ForEach(bookings) { trip in
                        localTicketRow(trip)
                            .padding(.horizontal, 16)
                    }
                }
                if !remoteReservations.isEmpty {
                    sectionHeader("마이리얼트립 · 투어/숙소")
                    ForEach(remoteReservations) { reservation in
                        remoteTicketRow(reservation)
                            .padding(.horizontal, 16)
                    }
                }
                if !remoteFlightReservations.isEmpty {
                    sectionHeader("마이리얼트립 · 항공")
                    ForEach(remoteFlightReservations) { reservation in
                        flightTicketRow(reservation)
                            .padding(.horizontal, 16)
                    }
                }
                if let refreshError {
                    Label(refreshError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.caption)
                        .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 16)
        }
        .background(Color(red: 0.95, green: 0.94, blue: 0.91))
    }

    private func sectionHeader(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .kerning(1)
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.top, 4)
    }

    private func localTicketRow(_ trip: BookedTrip) -> some View {
        let bundle = trip.bundle
        let accent: Color = .purple
        return TicketCard(accent: accent) {
            TicketTopSection(
                title: trip.title,
                subtitle: bundle.map(subtitle(for:)) ?? "",
                detail: bundle.map(dateRangeString(for:)) ?? "",
                ticketImageData: trip.ticketImageData,
                accent: accent,
                fallbackTopic: bundle.flatMap(topicHint(for:))
            )
        } bottom: {
            TicketBottomSection(
                leading: "예약번호",
                leadingValue: trip.bookingReference,
                trailing: "예약일시",
                trailingValue: trip.bookedAt.formatted(date: .abbreviated, time: .shortened),
                seedForBarcode: trip.id.uuidString
            )
        }
        .frame(height: 190)
    }

    private func remoteTicketRow(_ r: RemoteReservation) -> some View {
        let accent: Color = r.statusKor.contains("취소") ? .gray : .teal
        return TicketCard(accent: accent) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    statusPill(r.statusKor, color: accent)
                    Spacer()
                }
                Text(r.title)
                    .font(.title3.bold())
                    .lineLimit(2)
                    .padding(.top, 2)
                if let tripStartedAt = r.tripStartedAt {
                    Label(
                        tripStartedAt.formatted(date: .abbreviated, time: .omitted),
                        systemImage: "airplane"
                    )
                    .font(.caption2.bold())
                    .foregroundStyle(accent)
                    .labelStyle(.titleAndIcon)
                }
            }
        } bottom: {
            TicketBottomSection(
                leading: "예약일",
                leadingValue: r.reservedAt?.formatted(date: .abbreviated, time: .omitted) ?? "—",
                trailing: "결제금액",
                trailingValue: r.salePriceKRW > 0 ? "₩\(r.salePriceKRW.formatted())" : "—",
                seedForBarcode: r.id
            )
        }
        .frame(height: 190)
    }

    private func intentTicketRow(_ intent: BookingIntent) -> some View {
        let (label, accent): (String, Color) = {
            switch intent.status {
            case "confirmed": return ("확정 · \(intent.statusKor ?? "예약확정")", .green)
            case "expired":   return ("만료됨 (24시간 경과)", .orange)
            default:
                return (intent.isAttributionWindowOpen ? "진행중" : "쿠키 만료", .blue)
            }
        }()
        return TicketCard(accent: accent) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    statusPill(label, color: accent)
                    Spacer()
                    Text(categoryLabel(intent.productCategory))
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }
                Text(intent.title)
                    .font(.title3.bold())
                    .lineLimit(2)
                    .padding(.top, 2)
                Text("태그 \(intent.id.uuidString.prefix(8))…")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        } bottom: {
            TicketBottomSection(
                leading: "시작",
                leadingValue: intent.createdAt.formatted(date: .abbreviated, time: .shortened),
                trailing: intent.status == "confirmed" ? "결제금액" : "상태",
                trailingValue: intent.status == "confirmed"
                    ? (intent.actualSalePriceKRW > 0 ? "₩\(intent.actualSalePriceKRW.formatted())" : "—")
                    : statusValue(intent.status),
                seedForBarcode: intent.id.uuidString
            )
        }
        .frame(height: 190)
        .swipeActions {
            Button(role: .destructive) {
                context.delete(intent)
                try? context.save()
            } label: { Image(systemName: "trash") }
        }
    }

    private func categoryLabel(_ raw: String) -> String {
        switch raw {
        case "TNA": return "투어/티켓"
        case "HOTEL": return "숙소"
        case "FLIGHT": return "항공"
        default: return raw
        }
    }

    private func statusValue(_ raw: String) -> String {
        switch raw {
        case "pending": return "진행중"
        case "expired": return "만료"
        default: return raw
        }
    }

    private func flightTicketRow(_ r: RemoteFlightReservation) -> some View {
        let accent: Color = r.statusKor.contains("취소") ? .gray : .indigo
        return TicketCard(accent: accent) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    statusPill(r.statusKor, color: accent)
                    Spacer()
                    Text(tripTypeLabel(r.tripType))
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    Image(systemName: "airplane.departure")
                        .font(.title2)
                        .foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.airlineName.isEmpty ? r.airlineCode : r.airlineName)
                            .font(.title3.bold())
                            .lineLimit(1)
                        Text("\(scopeLabel(r.operationScope)) · \(r.airlineCode)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } bottom: {
            TicketBottomSection(
                leading: "PNR",
                leadingValue: r.pnr ?? r.reservationNo,
                trailing: "운임",
                trailingValue: r.issueNetKRW > 0 ? "₩\(r.issueNetKRW.formatted())" : "—",
                seedForBarcode: r.id
            )
        }
        .frame(height: 190)
    }

    private func tripTypeLabel(_ raw: String) -> String {
        switch raw {
        case "ROUND_TRIP": return "왕복"
        case "ONE_WAY": return "편도"
        case "MULTI": return "다구간"
        default: return raw
        }
    }

    private func scopeLabel(_ raw: String) -> String {
        switch raw {
        case "INTERNATIONAL": return "국제선"
        case "DOMESTIC": return "국내선"
        default: return raw
        }
    }

    private func statusPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
    }

    private func topicHint(for bundle: TravelBundle) -> String? {
        switch bundle.source {
        case .concert(let c): return "\(c.city) skyline"
        case .content(let c): return c.detectedPlaceName ?? "\(c.detectedCity) cityscape"
        case .manual:         return nil
        }
    }

    private func subtitle(for bundle: TravelBundle) -> String {
        switch bundle.source {
        case .concert(let c): return "\(c.venueName) · \(c.city)"
        case .content(let c): return c.detectedPlaceName ?? c.detectedCity
        case .manual:         return ""
        }
    }

    private func dateRangeString(for bundle: TravelBundle) -> String {
        let start = bundle.suggestedDepartureDate.formatted(date: .abbreviated, time: .omitted)
        let end = bundle.suggestedReturnDate.formatted(date: .abbreviated, time: .omitted)
        return "\(start) – \(end)"
    }

    @MainActor
    private func refresh() async {
        guard !AppEnvironment.useMockMRT else { return }
        isRefreshing = true
        refreshError = nil
        defer { isRefreshing = false }
        do {
            let cal = Calendar(identifier: .gregorian)
            let end = Date()
            let start6m = cal.date(byAdding: .month, value: -6, to: end) ?? end
            // Flight reservation API caps at 1 month
            let start1m = cal.date(byAdding: .month, value: -1, to: end) ?? end
            async let general = AppEnvironment.mrtClient.fetchRecentReservations(
                from: start6m, to: end
            )
            async let flight = AppEnvironment.mrtClient.fetchRecentFlightReservations(
                from: start1m, to: end
            )
            let (g, f) = try await (general, flight)
            remoteReservations = g
            remoteFlightReservations = f
            reconcileIntents(against: g)
        } catch {
            refreshError = error.localizedDescription
        }
    }

    private func reconcileIntents(against reservations: [RemoteReservation]) {
        guard !intents.isEmpty else { return }
        let byUtm: [String: RemoteReservation] = Dictionary(
            uniqueKeysWithValues: reservations
                .compactMap { r in r.utmContent.map { ($0, r) } }
        )
        var dirty = false
        for intent in intents where intent.status == "pending" {
            if let r = byUtm[intent.id.uuidString] {
                intent.status = "confirmed"
                intent.reservationNo = r.id
                intent.statusKor = r.statusKor
                intent.actualSalePriceKRW = r.salePriceKRW
                intent.resolvedAt = .now
                dirty = true
            } else if !intent.isAttributionWindowOpen {
                intent.status = "expired"
                dirty = true
            }
        }
        if dirty { try? context.save() }
    }
}

#Preview {
    BookingsView()
        .modelContainer(for: [SavedTrip.self, BookedTrip.self], inMemory: true)
}
