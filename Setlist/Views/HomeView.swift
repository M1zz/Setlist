import SwiftUI

struct HomeView: View {
    @State private var showConcertImport = false
    @State private var showContentImport = false
    @State private var pendingBundle: TravelBundle?
    @State private var buildingTour: UpcomingTour?
    @State private var buildError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    heroCard(
                        title: "From concert ticket",
                        subtitle: "Upload your ticket. We find flights and hotels by the venue before prices spike.",
                        systemImage: "ticket.fill",
                        tint: .purple
                    ) { showConcertImport = true }

                    heroCard(
                        title: "From a reel or video",
                        subtitle: "Paste an Instagram, TikTok, or YouTube link. We turn it into a bookable trip.",
                        systemImage: "play.rectangle.fill",
                        tint: .pink
                    ) { showContentImport = true }

                    Divider().padding(.vertical, 8)

                    trendingSection
                }
                .padding()
            }
            .navigationTitle("Setlist")
            .sheet(isPresented: $showConcertImport) {
                ConcertImportView()
            }
            .sheet(isPresented: $showContentImport) { ContentImportView() }
            .navigationDestination(item: $pendingBundle) { bundle in
                BundleDetailView(bundle: bundle)
            }
            .alert(
                "Couldn't build trip",
                isPresented: Binding(
                    get: { buildError != nil },
                    set: { if !$0 { buildError = nil } }
                ),
                presenting: buildError
            ) { _ in
                Button("OK", role: .cancel) { buildError = nil }
            } message: { msg in
                Text(msg)
            }
        }
    }

    private func heroCard(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: systemImage)
                    .font(.system(size: 32))
                    .foregroundStyle(tint)
                    .frame(width: 56, height: 56)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var trendingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tours on fans' minds")
                .font(.title3.bold())
            ForEach(UpcomingTour.samples) { tour in
                tourRow(tour)
            }
        }
    }

    private func tourRow(_ tour: UpcomingTour) -> some View {
        Button {
            Task { await buildTour(tour) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tour.artist).font(.subheadline.bold())
                    Text("\(tour.city) · \(tour.date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if buildingTour?.id == tour.id {
                    ProgressView()
                } else {
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(buildingTour != nil)
    }

    @MainActor
    private func buildTour(_ tour: UpcomingTour) async {
        buildingTour = tour
        defer { buildingTour = nil }

        let coords = CityDB.coordinates(for: tour.city) ?? (35.6762, 139.6503)
        let country = CityDB.cities.first { $0.name == tour.city }?.country ?? "Japan"
        let concert = ConcertSource(
            artist: tour.artist,
            venueName: "\(tour.city) Venue",
            venueLatitude: coords.0,
            venueLongitude: coords.1,
            city: tour.city,
            country: country,
            showDate: tour.date
        )
        let builder = BundleBuilder(mrt: AppEnvironment.mrtClient)
        do {
            pendingBundle = try await builder.buildFromConcert(concert)
        } catch {
            buildError = error.localizedDescription
        }
    }
}

struct UpcomingTour: Identifiable {
    let id = UUID()
    let artist: String
    let city: String
    let date: Date

    static let samples: [UpcomingTour] = [
        .init(artist: "BTS ARIRANG", city: "Tokyo", date: .now.addingTimeInterval(86400 * 45)),
        .init(artist: "BTS ARIRANG", city: "London", date: .now.addingTimeInterval(86400 * 90)),
        .init(artist: "BLACKPINK", city: "Los Angeles", date: .now.addingTimeInterval(86400 * 60)),
        .init(artist: "Stray Kids", city: "Madrid", date: .now.addingTimeInterval(86400 * 75))
    ]
}

#Preview {
    HomeView()
}
