import SwiftUI
import SwiftData

struct BookingsView: View {
    @Query(sort: \BookedTrip.bookedAt, order: .reverse) private var bookings: [BookedTrip]

    @State private var remoteReservations: [RemoteReservation] = []
    @State private var isRefreshing = false
    @State private var refreshError: String?
    @State private var didAutoRefresh = false

    var body: some View {
        NavigationStack {
            Group {
                if bookings.isEmpty && remoteReservations.isEmpty && !isRefreshing {
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
        }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                if !bookings.isEmpty {
                    sectionHeader("Opened from this device")
                    ForEach(bookings) { trip in
                        localTicketRow(trip)
                            .padding(.horizontal, 16)
                    }
                }
                if !remoteReservations.isEmpty {
                    sectionHeader("From MyRealTrip")
                    ForEach(remoteReservations) { reservation in
                        remoteTicketRow(reservation)
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
            let start = cal.date(byAdding: .month, value: -6, to: end) ?? end
            remoteReservations = try await AppEnvironment.mrtClient.fetchRecentReservations(
                from: start,
                to: end
            )
        } catch {
            refreshError = error.localizedDescription
        }
    }
}

#Preview {
    BookingsView()
        .modelContainer(for: [SavedTrip.self, BookedTrip.self], inMemory: true)
}
