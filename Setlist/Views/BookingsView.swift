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
                        "No booked trips",
                        systemImage: "ticket",
                        description: Text(AppEnvironment.useMockMRT
                            ? "Confirmed bookings will appear here once you connect your MyRealTrip partner key."
                            : "Pull to refresh — reservations from MyRealTrip show up as tickets.")
                    )
                } else {
                    content
                }
            }
            .navigationTitle("Trips")
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
                    sectionHeader("My recent bookings")
                    ForEach(intents) { intent in
                        intentTicketRow(intent)
                            .padding(.horizontal, 16)
                    }
                }
                if !bookings.isEmpty {
                    sectionHeader("Opened from this device")
                    ForEach(bookings) { trip in
                        localTicketRow(trip)
                            .padding(.horizontal, 16)
                    }
                }
                if !remoteReservations.isEmpty {
                    sectionHeader("From MyRealTrip · Tours & stays")
                    ForEach(remoteReservations) { reservation in
                        remoteTicketRow(reservation)
                            .padding(.horizontal, 16)
                    }
                }
                if !remoteFlightReservations.isEmpty {
                    sectionHeader("From MyRealTrip · Flights")
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
                accent: accent
            )
        } bottom: {
            TicketBottomSection(
                leading: "REF",
                leadingValue: trip.bookingReference,
                trailing: "BOOKED",
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
                leading: "RESERVED",
                leadingValue: r.reservedAt?.formatted(date: .abbreviated, time: .omitted) ?? "—",
                trailing: "PRICE",
                trailingValue: r.salePriceKRW > 0 ? "₩\(r.salePriceKRW.formatted())" : "—",
                seedForBarcode: r.id
            )
        }
        .frame(height: 190)
    }

    private func intentTicketRow(_ intent: BookingIntent) -> some View {
        let (label, accent): (String, Color) = {
            switch intent.status {
            case "confirmed": return ("CONFIRMED · \(intent.statusKor ?? "예약확정")", .green)
            case "expired":   return ("PENDING · attribution lapsed", .orange)
            default:
                return (intent.isAttributionWindowOpen ? "PENDING" : "PENDING · cookie expired", .blue)
            }
        }()
        return TicketCard(accent: accent) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    statusPill(label, color: accent)
                    Spacer()
                    Text(intent.productCategory)
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }
                Text(intent.title)
                    .font(.title3.bold())
                    .lineLimit(2)
                    .padding(.top, 2)
                Text("Tagged \(intent.id.uuidString.prefix(8))…")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        } bottom: {
            TicketBottomSection(
                leading: "STARTED",
                leadingValue: intent.createdAt.formatted(date: .abbreviated, time: .shortened),
                trailing: intent.status == "confirmed" ? "PRICE" : "STATUS",
                trailingValue: intent.status == "confirmed"
                    ? (intent.actualSalePriceKRW > 0 ? "₩\(intent.actualSalePriceKRW.formatted())" : "—")
                    : intent.status.uppercased(),
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

    private func flightTicketRow(_ r: RemoteFlightReservation) -> some View {
        let accent: Color = r.statusKor.contains("취소") ? .gray : .indigo
        return TicketCard(accent: accent) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    statusPill(r.statusKor, color: accent)
                    Spacer()
                    Text(r.tripType.replacingOccurrences(of: "_", with: " "))
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
                        Text("\(r.operationScope) · \(r.airlineCode)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } bottom: {
            TicketBottomSection(
                leading: "PNR",
                leadingValue: r.pnr ?? r.reservationNo,
                trailing: "FARE",
                trailingValue: r.issueNetKRW > 0 ? "₩\(r.issueNetKRW.formatted())" : "—",
                seedForBarcode: r.id
            )
        }
        .frame(height: 190)
    }

    private func statusPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
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
