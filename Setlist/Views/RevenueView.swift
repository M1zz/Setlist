import SwiftUI

struct RevenueView: View {
    @State private var lines: [RevenueLine] = []
    @State private var flightLines: [RevenueLine] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var rangeDays: Int = 30
    @State private var dateType: RevenueDateType = .payment

    private var allLines: [RevenueLine] {
        (lines + flightLines).sorted {
            ($0.reservedAt ?? .distantPast) > ($1.reservedAt ?? .distantPast)
        }
    }

    private var totalCommission: Int { allLines.map(\.commissionKRW).reduce(0, +) }
    private var totalSale: Int { allLines.map(\.salePriceKRW).reduce(0, +) }
    private var avgRate: Double {
        guard totalSale > 0 else { return 0 }
        return Double(totalCommission) / Double(totalSale)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    hero
                    filterBar
                    if AppEnvironment.useMockMRT {
                        mockBanner
                    }
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if allLines.isEmpty && !isLoading {
                        emptyState
                    } else {
                        linesList
                    }
                }
                .padding()
            }
            .navigationTitle("Revenue")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        if isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isLoading)
                }
            }
            .refreshable { await refresh() }
            .task { if allLines.isEmpty { await refresh() } }
            .onChange(of: rangeDays) { _, _ in Task { await refresh() } }
            .onChange(of: dateType) { _, _ in Task { await refresh() } }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Total commission")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("₩\(totalCommission.formatted())")
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .foregroundStyle(LinearGradient(
                    colors: [.purple, .pink],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            HStack(spacing: 16) {
                metric("Sales", "₩\(totalSale.formatted())")
                metric("Avg rate", totalSale > 0 ? String(format: "%.1f%%", avgRate * 100) : "—")
                metric("Bookings", "\(allLines.count)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.callout.bold())
        }
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Range", selection: $rangeDays) {
                Text("7d").tag(7)
                Text("30d").tag(30)
                Text("90d").tag(90)
            }
            .pickerStyle(.segmented)

            Picker("Date type", selection: $dateType) {
                Text("Booking date").tag(RevenueDateType.payment)
                Text("Settlement").tag(RevenueDateType.settlement)
            }
            .pickerStyle(.segmented)
        }
    }

    private var mockBanner: some View {
        Label("No API key — showing sample data. Add your MRT partner key via Keychain to fetch real revenue.", systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No revenue in this period", systemImage: "chart.line.uptrend.xyaxis")
        } description: {
            Text("Commissions from bookings made via your mylinks will show up here once MRT settles them (daily at 6 AM KST).")
        }
        .padding(.top, 40)
    }

    private var linesList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Line items")
                .font(.headline)
            ForEach(allLines) { line in
                lineRow(line)
            }
        }
    }

    private func lineRow(_ line: RevenueLine) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.productTitle)
                        .font(.callout.bold())
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        if !line.productCategory.isEmpty {
                            pill(line.productCategory, color: .blue)
                        }
                        if !line.statusKor.isEmpty {
                            pill(line.statusKor, color: .green)
                        }
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("+₩\(line.commissionKRW.formatted())")
                        .font(.callout.bold())
                        .foregroundStyle(line.commissionKRW >= 0 ? .green : .red)
                    Text(String(format: "%.1f%% of ₩\(line.salePriceKRW.formatted())", line.commissionRate * 100))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if line.city != nil || line.reservedAt != nil {
                HStack(spacing: 8) {
                    if let city = line.city, !city.isEmpty {
                        Label(city, systemImage: "location").labelStyle(.titleAndIcon)
                    }
                    if let reservedAt = line.reservedAt {
                        Label(reservedAt.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                            .labelStyle(.titleAndIcon)
                    }
                    if let utm = line.utmContent, !utm.isEmpty {
                        Label(utm, systemImage: "tag")
                            .labelStyle(.titleAndIcon)
                            .lineLimit(1)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func pill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
    }

    // MARK: - Data

    @MainActor
    private func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let cal = Calendar(identifier: .gregorian)
        let end = Date()
        let start = cal.date(byAdding: .day, value: -rangeDays, to: end) ?? end

        do {
            async let general = AppEnvironment.mrtClient.fetchRevenues(
                from: start, to: end, dateType: dateType
            )
            async let flight = AppEnvironment.mrtClient.fetchFlightRevenues(
                from: start, to: end, dateType: dateType
            )
            let (g, f) = try await (general, flight)
            lines = g
            flightLines = f
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    RevenueView()
}
