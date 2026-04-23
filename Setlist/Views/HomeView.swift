import SwiftUI

struct HomeView: View {
    @State private var showConcertImport = false
    @State private var showContentImport = false
    @State private var prefillText: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    heroCard(
                        title: "From concert ticket",
                        subtitle: "Upload your ticket. We find flights and hotels by the venue before prices spike.",
                        systemImage: "ticket.fill",
                        tint: .purple
                    ) {
                        prefillText = ""
                        showConcertImport = true
                    }

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
                ConcertImportView(prefilledText: prefillText)
            }
            .sheet(isPresented: $showContentImport) { ContentImportView() }
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
            prefillText = "\(tour.artist), \(tour.city), \(tour.date.formatted(.iso8601.year().month().day()))"
            showConcertImport = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tour.artist).font(.subheadline.bold())
                    Text("\(tour.city) · \(tour.date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
