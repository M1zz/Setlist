import SwiftUI

struct TNADetailView: View {
    let activity: ActivityOption
    @Environment(\.modelContext) private var context

    @State private var detail: TNADetail?
    @State private var calendar: TNACalendar?
    @State private var options: TNAOptionsBundle?
    @State private var heroImage: OpenverseImage?
    @State private var selectedDate: Date = Date().addingTimeInterval(86400 * 14)
    @State private var isLoadingDetail = false
    @State private var isLoadingOptions = false
    @State private var error: String?
    @State private var isOpeningBooking = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                heroCard
                if isLoadingDetail {
                    ProgressView().frame(maxWidth: .infinity).padding()
                }
                if let detail {
                    descriptionCard(detail)
                    includedExcludedCard(detail)
                    if !detail.itineraries.isEmpty {
                        itineraryCard(detail.itineraries)
                    }
                }
                dateCard
                optionsCard
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.caption)
                        .padding()
                }
            }
            .padding()
            .padding(.bottom, 100)
        }
        .safeAreaInset(edge: .bottom) {
            stickyBookingBar
        }
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadDetail()
            await loadCalendar()
            await loadOptions()
        }
        .onChange(of: selectedDate) { _, _ in
            Task {
                await loadCalendar()
                await loadOptions()
            }
        }
    }

    // MARK: - Sections

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                if let url = activity.thumbnailURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().scaledToFill()
                        default:
                            RichImageView(topic: activity.title, fallbackTint: .pink)
                        }
                    }
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                } else {
                    RichImageView(topic: activity.title, fallbackTint: .pink) { heroImage = $0 }
                        .frame(height: 220)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    if let heroImage {
                        ImageAttributionLabel(image: heroImage).padding(8)
                    }
                }
            }
            Text(detail?.title ?? activity.title)
                .font(.title3.bold())
            HStack(spacing: 12) {
                if let score = detail?.reviewScore, score > 0 {
                    Label(String(format: "%.1f", score), systemImage: "star.fill")
                        .foregroundStyle(.orange)
                        .font(.subheadline.bold())
                }
                if let count = detail?.reviewCount, count > 0 {
                    Text("· \(count) reviews").foregroundStyle(.secondary).font(.caption)
                }
            }
        }
    }

    private func descriptionCard(_ d: TNADetail) -> some View {
        sectionCard(title: "About") {
            Text(d.description ?? "(No description)")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func includedExcludedCard(_ d: TNADetail) -> some View {
        sectionCard(title: "What's included") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(d.included, id: \.self) { item in
                    Label(item, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                        .labelStyle(.titleAndIcon)
                }
                if !d.excluded.isEmpty {
                    Divider().padding(.vertical, 4)
                    ForEach(d.excluded, id: \.self) { item in
                        Label(item, systemImage: "xmark.circle")
                            .foregroundStyle(.red.opacity(0.7))
                            .font(.subheadline)
                            .labelStyle(.titleAndIcon)
                    }
                }
            }
        }
    }

    private func itineraryCard(_ items: [TNAItineraryEntry]) -> some View {
        sectionCard(title: "Itinerary") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, entry in
                    VStack(alignment: .leading, spacing: 2) {
                        if let title = entry.title {
                            Text(title).font(.subheadline.bold())
                        }
                        if let desc = entry.description {
                            Text(desc).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var dateCard: some View {
        sectionCard(title: "Pick a date") {
            VStack(alignment: .leading, spacing: 8) {
                DatePicker(
                    "",
                    selection: $selectedDate,
                    in: Date()...,
                    displayedComponents: [.date]
                )
                .labelsHidden()
                .datePickerStyle(.compact)

                if let cal = calendar {
                    HStack(spacing: 8) {
                        if let label = cal.basePriceLabel {
                            pill("from \(label)", color: .blue)
                        }
                        if cal.instantConfirm {
                            pill("Instant confirm", color: .green)
                        }
                        if cal.blockDates.contains(dayString(selectedDate)) {
                            pill("Sold out", color: .gray)
                        }
                    }
                }
            }
        }
    }

    private var optionsCard: some View {
        sectionCard(title: "Available options") {
            VStack(spacing: 10) {
                if isLoadingOptions {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical)
                }
                if let options, options.options.isEmpty, !isLoadingOptions {
                    Text("No options available for this date.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let options {
                    ForEach(options.options) { option in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.name).font(.subheadline.bold())
                                if let avail = option.availablePurchaseQuantity {
                                    Text("\(avail) left").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text("₩\(option.salePriceKRW.formatted())")
                                .font(.subheadline.bold())
                        }
                        .padding(.vertical, 6)
                        Divider()
                    }
                }
            }
        }
    }

    private var stickyBookingBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Starting at").font(.caption).foregroundStyle(.secondary)
                Text("₩\(lowestOptionPriceKRW.formatted())")
                    .font(.title3.bold())
            }
            Spacer()
            Button {
                Task { await openBooking() }
            } label: {
                HStack {
                    if isOpeningBooking { ProgressView().tint(.white) }
                    Text(isOpeningBooking ? "Opening…" : "Book on MyRealTrip")
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 12)
                .frame(height: 44)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isOpeningBooking)
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func pill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
    }

    // MARK: - Helpers

    private var lowestOptionPriceKRW: Int {
        if let lowest = options?.options.map(\.salePriceKRW).min() {
            return lowest
        }
        return activity.priceKRW
    }

    private func dayString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Asia/Seoul")
        return f.string(from: date)
    }

    @MainActor
    private func loadDetail() async {
        isLoadingDetail = true
        defer { isLoadingDetail = false }
        do {
            detail = try await AppEnvironment.mrtClient.fetchTNADetail(gid: activity.mrtProductID)
        } catch {
            self.error = error.localizedDescription
        }
    }

    @MainActor
    private func loadCalendar() async {
        do {
            calendar = try await AppEnvironment.mrtClient.fetchTNACalendar(
                gid: activity.mrtProductID,
                selectedDate: selectedDate
            )
        } catch {
            // Silently ignore — calendar is informational
        }
    }

    @MainActor
    private func loadOptions() async {
        isLoadingOptions = true
        defer { isLoadingOptions = false }
        do {
            options = try await AppEnvironment.mrtClient.fetchTNAOptions(
                gid: activity.mrtProductID,
                selectedDate: selectedDate
            )
        } catch {
            self.error = error.localizedDescription
        }
    }

    @MainActor
    private func openBooking() async {
        isOpeningBooking = true
        defer { isOpeningBooking = false }

        let intent = BookingIntent(
            title: detail?.title ?? activity.title,
            productCategory: "TNA",
            productGid: activity.mrtProductID,
            targetURLString: activity.bookingURL.absoluteString,
            actualSalePriceKRW: lowestOptionPriceKRW
        )
        context.insert(intent)
        try? context.save()

        do {
            let tracked = try await AppEnvironment.mrtClient.generateMyLink(
                targetURL: activity.bookingURL,
                utmContent: intent.id.uuidString
            )
            _ = await UIApplication.shared.open(tracked)
        } catch {
            _ = await UIApplication.shared.open(activity.bookingURL)
        }
    }
}
