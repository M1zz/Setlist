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
            List {
                if bookings.isEmpty && remoteReservations.isEmpty && !isRefreshing {
                    Section {
                        ContentUnavailableView(
                            "No booked trips",
                            systemImage: "airplane",
                            description: Text(AppEnvironment.useMockMRT
                                ? "Confirmed bookings will appear here once you connect your MyRealTrip partner key."
                                : "Pull to refresh — reservations from MyRealTrip show up automatically.")
                        )
                    }
                }

                if !bookings.isEmpty {
                    Section("Opened from this device") {
                        ForEach(bookings) { b in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(b.title).font(.headline)
                                Text("Ref: \(b.bookingReference)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(b.bookedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                if !remoteReservations.isEmpty {
                    Section("From MyRealTrip") {
                        ForEach(remoteReservations) { r in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(r.title).font(.headline)
                                HStack(spacing: 6) {
                                    Text(r.statusKor).font(.caption).foregroundStyle(.secondary)
                                    if r.salePriceKRW > 0 {
                                        Text("· ₩\(r.salePriceKRW.formatted())")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                if let t = r.tripStartedAt {
                                    Text("Trip: \(t.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                } else if let r = r.reservedAt {
                                    Text("Booked: \(r.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                if let refreshError {
                    Section {
                        Label(refreshError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
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
