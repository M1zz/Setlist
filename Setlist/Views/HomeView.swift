import SwiftUI

struct HomeView: View {
    @State private var showConcertImport = false
    @State private var showContentImport = false
    @State private var pendingBundle: TravelBundle?
    @State private var buildingFareID: String?
    @State private var buildError: String?

    @State private var fares: [BulkLowestFare] = []
    @State private var isLoadingFares = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    heroCard(
                        title: "콘서트 티켓으로 시작",
                        subtitle: "티켓 사진을 올리면 공연장 근처 항공·호텔을 가격 오르기 전에 찾아드려요.",
                        systemImage: "ticket.fill",
                        tint: .purple
                    ) { showConcertImport = true }

                    heroCard(
                        title: "릴스/영상에서 시작",
                        subtitle: "인스타·틱톡·유튜브 링크를 붙여넣으면 바로 예약 가능한 여행으로 만들어드려요.",
                        systemImage: "play.rectangle.fill",
                        tint: .pink
                    ) { showContentImport = true }

                    Divider().padding(.vertical, 8)

                    cheapTripsSection
                }
                .padding()
            }
            .navigationTitle("Setlist")
            .sheet(isPresented: $showConcertImport) { ConcertImportView() }
            .sheet(isPresented: $showContentImport) { ContentImportView() }
            .navigationDestination(item: $pendingBundle) { bundle in
                BundleDetailView(bundle: bundle)
            }
            .alert(
                "여행을 만들지 못했어요",
                isPresented: Binding(
                    get: { buildError != nil },
                    set: { if !$0 { buildError = nil } }
                ),
                presenting: buildError
            ) { _ in
                Button("확인", role: .cancel) { buildError = nil }
            } message: { msg in
                Text(msg)
            }
            .task { await loadFares() }
            .refreshable { await loadFares() }
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
    private var cheapTripsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("인천 출발 최저가")
                    .font(.title3.bold())
                Spacer()
                if isLoadingFares { ProgressView().controlSize(.small) }
            }
            if fares.isEmpty && !isLoadingFares {
                Text("지금 가져올 수 있는 항공편이 없어요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(fares.prefix(8)) { fare in
                fareRow(fare)
            }
        }
    }

    private func fareRow(_ fare: BulkLowestFare) -> some View {
        let city = displayCity(for: fare.toCity)
        return Button {
            Task { await buildFare(fare) }
        } label: {
            HStack(spacing: 12) {
                RichImageView(topic: "\(city) cityscape", fallbackTint: .blue)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.black.opacity(0.06), lineWidth: 1)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(city)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    Text("\(fare.departureDate) → \(fare.returnDate) · \(fare.period)d")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let avg = fare.averagePriceKRW, avg > fare.totalPriceKRW {
                    let pct = Int((1.0 - Double(fare.totalPriceKRW) / Double(avg)) * 100)
                    if pct >= 5 {
                        Text("-\(pct)%")
                            .font(.caption2.bold())
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15), in: Capsule())
                    }
                }
                VStack(alignment: .trailing, spacing: 0) {
                    Text("₩\(fare.totalPriceKRW.formatted())")
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                }
                if buildingFareID == fare.id {
                    ProgressView()
                } else {
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(buildingFareID != nil)
    }

    @MainActor
    private func loadFares() async {
        isLoadingFares = true
        defer { isLoadingFares = false }
        do {
            let fetched = try await AppEnvironment.mrtClient.fetchBulkLowestFlights(
                originCityCode: "ICN",
                period: 5
            )
            fares = fetched.sorted { $0.totalPriceKRW < $1.totalPriceKRW }
        } catch {
            // Use mock fallback if real call fails
            fares = MRTMockData.bulkLowest(origin: "ICN")
                .sorted { $0.totalPriceKRW < $1.totalPriceKRW }
        }
    }

    @MainActor
    private func buildFare(_ fare: BulkLowestFare) async {
        buildingFareID = fare.id
        defer { buildingFareID = nil }

        let cityName = cityName(forAirportOrCity: fare.toCity)
        let coords = CityDB.coordinates(for: cityName) ?? (35.6762, 139.6503)
        let country = CityDB.cities.first { $0.name == cityName }?.country ?? "Japan"

        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Asia/Seoul")
        guard let depart = f.date(from: fare.departureDate),
              let ret = f.date(from: fare.returnDate) else {
            buildError = "날짜 정보가 올바르지 않아요"
            return
        }

        let builder = BundleBuilder(mrt: AppEnvironment.mrtClient)
        do {
            pendingBundle = try await builder.buildForCity(
                city: cityName,
                country: country,
                latitude: coords.0,
                longitude: coords.1,
                departDate: depart,
                returnDate: ret,
                originAirport: fare.fromCity
            )
        } catch {
            buildError = error.localizedDescription
        }
    }

    private func displayCity(for code: String) -> String {
        let mapped = airportToCity[code] ?? code
        return koreanCityNames[mapped] ?? mapped
    }

    // 도시명 한국어 표기. 매핑 없으면 영문 그대로.
    private let koreanCityNames: [String: String] = [
        "Tokyo": "도쿄", "Osaka": "오사카", "Kyoto": "교토", "Fukuoka": "후쿠오카",
        "Sapporo": "삿포로", "Okinawa": "오키나와", "Nagoya": "나고야",
        "Yufuin": "유후인", "Hiroshima": "히로시마", "Yonago": "요나고",
        "Takamatsu": "타카마츠", "Kumamoto": "쿠마모토", "Nagasaki": "나가사키",
        "Kagoshima": "가고시마", "Matsuyama": "마츠야마", "Miyazaki": "미야자키",
        "Shizuoka": "시즈오카", "Aomori": "아오모리", "Akita": "아키타",
        "Yamagata": "야마가타", "Hawaii": "하와이",
        "Bangkok": "방콕", "Phuket": "푸켓", "Chiang Mai": "치앙마이",
        "Singapore": "싱가포르", "Hanoi": "하노이", "Ho Chi Minh City": "호치민",
        "Da Nang": "다낭", "Bali": "발리", "Manila": "마닐라", "Cebu": "세부",
        "Taipei": "타이베이", "Kaohsiung": "가오슝",
        "London": "런던", "Paris": "파리", "Rome": "로마",
        "Barcelona": "바르셀로나", "Madrid": "마드리드", "Amsterdam": "암스테르담",
        "Berlin": "베를린", "New York": "뉴욕", "Los Angeles": "로스앤젤레스",
        "Las Vegas": "라스베이거스", "San Francisco": "샌프란시스코",
        "Honolulu": "호놀룰루", "Guam": "괌", "Dubai": "두바이", "Istanbul": "이스탄불",
        "Seoul": "서울", "Jeju": "제주", "Busan": "부산"
    ]

    private func cityName(forAirportOrCity code: String) -> String {
        airportToCity[code] ?? code
    }

    // Reverse map of common IATA airport / city codes returned by bulk-lowest.
    private let airportToCity: [String: String] = [
        "NRT": "Tokyo", "HND": "Tokyo", "TYO": "Tokyo",
        "KIX": "Osaka", "ITM": "Osaka", "OSA": "Osaka",
        "FUK": "Fukuoka", "CTS": "Sapporo", "OKA": "Okinawa",
        "NGO": "Nagoya", "OIT": "Yufuin", "HIJ": "Hiroshima",
        "YGJ": "Yonago", "TAK": "Takamatsu", "KMJ": "Kumamoto",
        "NGS": "Nagasaki", "KOJ": "Kagoshima", "MYJ": "Matsuyama",
        "KMI": "Miyazaki", "FSZ": "Shizuoka", "KOA": "Hawaii",
        "AOJ": "Aomori", "AXT": "Akita", "GAJ": "Yamagata",
        "BKK": "Bangkok", "HKT": "Phuket", "CNX": "Chiang Mai",
        "SIN": "Singapore", "HAN": "Hanoi", "SGN": "Ho Chi Minh City",
        "DAD": "Da Nang", "DPS": "Bali", "MNL": "Manila",
        "CEB": "Cebu", "TPE": "Taipei", "KHH": "Kaohsiung",
        "LHR": "London", "CDG": "Paris", "FCO": "Rome",
        "BCN": "Barcelona", "MAD": "Madrid", "AMS": "Amsterdam",
        "BER": "Berlin", "JFK": "New York", "LAX": "Los Angeles",
        "LAS": "Las Vegas", "SFO": "San Francisco", "HNL": "Honolulu",
        "GUM": "Guam", "DXB": "Dubai", "IST": "Istanbul",
        "ICN": "Seoul", "CJU": "Jeju", "PUS": "Busan"
    ]
}

#Preview {
    HomeView()
}
