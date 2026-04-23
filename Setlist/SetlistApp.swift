import SwiftUI
import SwiftData

@main
struct SetlistApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [SavedTrip.self, BookedTrip.self])
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Discover", systemImage: "sparkles") }
            WishlistView()
                .tabItem { Label("Wishlist", systemImage: "heart") }
            BookingsView()
                .tabItem { Label("Trips", systemImage: "airplane") }
        }
    }
}
