import SwiftUI
import SwiftData
import UIKit

@main
struct SetlistApp: App {
    init() {
        configureNavigationBarAppearance()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [SavedTrip.self, BookedTrip.self, BookingIntent.self])
    }

    private func configureNavigationBarAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = UIColor(AppColor.surface).withAlphaComponent(0.96)
        appearance.shadowColor = .clear
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
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
            MoreView()
                .tabItem { Label("더보기", systemImage: "person.crop.circle") }
        }
        .tint(AppColor.brandPrimary)
    }
}
