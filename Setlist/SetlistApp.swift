import SwiftUI
import SwiftData

@main
struct SetlistApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [SavedTrip.self, BookedTrip.self, BookingIntent.self])
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("둘러보기", systemImage: "sparkles") }
            WishlistView()
                .tabItem { Label("찜", systemImage: "heart") }
            BookingsView()
                .tabItem { Label("내 여행", systemImage: "airplane") }
            RevenueView()
                .tabItem { Label("수익", systemImage: "chart.line.uptrend.xyaxis") }
        }
    }
}
