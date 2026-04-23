import SwiftUI
import SwiftData

struct WishlistView: View {
    @Query(sort: \SavedTrip.createdAt, order: .reverse) private var trips: [SavedTrip]
    @Environment(\.modelContext) private var context

    var body: some View {
        NavigationStack {
            Group {
                if trips.isEmpty {
                    ContentUnavailableView(
                        "No saved trips yet",
                        systemImage: "heart",
                        description: Text("Trips you save will show up here.")
                    )
                } else {
                    List {
                        ForEach(trips) { trip in
                            NavigationLink {
                                if let bundle = trip.bundle {
                                    BundleDetailView(bundle: bundle)
                                } else {
                                    Text("Could not load this trip")
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(trip.title).font(.headline)
                                    Text(trip.createdAt.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("Wishlist")
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            context.delete(trips[index])
        }
        try? context.save()
    }
}

#Preview {
    WishlistView()
        .modelContainer(for: [SavedTrip.self, BookedTrip.self], inMemory: true)
}
