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
            ZStack {
                AppColor.surface.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.xl) {
                        greeting
                            .padding(.horizontal, AppSpacing.lg)
                            .padding(.top, AppSpacing.sm)

                        VStack(spacing: AppSpacing.md) {
                            concertHero
                            reelHero
                        }
                        .padding(.horizontal, AppSpacing.lg)

                        cheapFaresSection
                            .padding(.horizontal, AppSpacing.lg)
                    }
                    .padding(.bottom, AppSpacing.xxl)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Setlist")
                        .font(AppFont.title2)
                        .foregroundStyle(AppColor.ink)
                }
            }
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

    // MARK: - Greeting

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("어디로 떠나볼까요")
                .font(AppFont.display)
                .foregroundStyle(AppColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text("티켓 한 장 또는 영상 링크 하나로 시작하세요")
                .font(AppFont.body)
                .foregroundStyle(AppColor.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
        }
    }

    // MARK: - Hero CTAs

    private var concertHero: some View {
        Button {
            showConcertImport = true
        } label: {
            ZStack {
                AppColor.nightGradient
                // soft brand glow
                Circle()
                    .fill(AppColor.brandPrimary.opacity(0.45))
                    .frame(width: 240, height: 240)
                    .blur(radius: 50)
                    .offset(x: 110, y: -50)
                    .blendMode(.screen)

                HStack(alignment: .center, spacing: AppSpacing.lg) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CONCERT")
                            .font(AppFont.kicker)
                            .tracking(2)
                            .foregroundStyle(AppColor.brandSecondary)
                        Text("티켓 한 장으로 시작")
                            .font(AppFont.title1)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Text("공연장 근처 항공·숙소 한 번에")
                            .font(AppFont.caption)
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "ticket.fill")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(16)
                        .background {
                            Circle().fill(.white.opacity(0.14))
                        }
                }
                .padding(AppSpacing.lg)
            }
            .frame(height: 132)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
            .appElevation(.medium)
        }
        .buttonStyle(PressableScale())
    }

    private var reelHero: some View {
        Button {
            showContentImport = true
        } label: {
            ZStack {
                AppColor.warmGradient
                Circle()
                    .fill(.white.opacity(0.25))
                    .frame(width: 200, height: 200)
                    .blur(radius: 40)
                    .offset(x: -120, y: 60)

                HStack(alignment: .center, spacing: AppSpacing.lg) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(16)
                        .background {
                            Circle().fill(.white.opacity(0.18))
                        }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("REEL · VIDEO")
                            .font(AppFont.kicker)
                            .tracking(2)
                            .foregroundStyle(.white.opacity(0.78))
                        Text("영상 한 줄로 여행 만들기")
                            .font(AppFont.title1)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Text("인스타·틱톡·유튜브 링크 붙여넣기")
                            .font(AppFont.caption)
                            .foregroundStyle(.white.opacity(0.78))
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .padding(AppSpacing.lg)
            }
            .frame(height: 132)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
            .appElevation(.medium)
        }
        .buttonStyle(PressableScale())
    }

    // MARK: - Cheap fares

    private var cheapFaresSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(kicker: "Today's deals", title: "인천 출발 최저가")
                Spacer(minLength: 0)
                if isLoadingFares {
                    ProgressView().controlSize(.small).tint(AppColor.brandPrimary)
                }
            }

            if fares.isEmpty && !isLoadingFares {
                Text("지금 가져올 수 있는 항공편이 없어요.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.inkSecondary)
            }

            VStack(spacing: AppSpacing.sm) {
                ForEach(fares.prefix(8)) { fare in
                    fareCard(fare)
                }
            }
        }
    }

    private func fareCard(_ fare: BulkLowestFare) -> some View {
        let city = displayCity(for: fare.toCity)
        let discountPct = discountPercent(for: fare)
        return Button {
            Task { await buildFare(fare) }
        } label: {
            HStack(spacing: AppSpacing.md) {
                RichImageView(topic: "\(city) cityscape", fallbackTint: AppColor.brandPrimary)
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: AppRadius.md)
                            .stroke(.black.opacity(0.06), lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: AppSpacing.sm) {
                        Text(city)
                            .font(AppFont.title3)
                            .foregroundStyle(AppColor.ink)
                            .lineLimit(1)
                        if let pct = discountPct {
                            StatusBadge(text: "-\(pct)%", variant: .success)
                        }
                    }
                    Text(fareDateLine(fare))
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.inkSecondary)
                        .lineLimit(1)
                    Text("ICN → \(fare.toCity)")
                        .font(AppFont.kicker)
                        .tracking(1.2)
                        .foregroundStyle(AppColor.inkTertiary)
                }
                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 4) {
                    if buildingFareID == fare.id {
                        ProgressView().controlSize(.small).tint(AppColor.brandPrimary)
                    }
                    Text("₩\(fare.totalPriceKRW.formatted())")
                        .font(AppFont.title3)
                        .foregroundStyle(AppColor.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text("최저가")
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.inkTertiary)
                }
            }
            .padding(AppSpacing.md)
            .background(AppColor.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.lg)
                    .stroke(.black.opacity(0.04), lineWidth: 1)
            }
            .appShadow(.soft)
        }
        .buttonStyle(PressableScale())
        .disabled(buildingFareID != nil)
    }

    // MARK: - Helpers

    private func discountPercent(for fare: BulkLowestFare) -> Int? {
        guard let avg = fare.averagePriceKRW, avg > fare.totalPriceKRW else { return nil }
        let pct = Int((1.0 - Double(fare.totalPriceKRW) / Double(avg)) * 100)
        return pct >= 5 ? pct : nil
    }

    private static let fareInputFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Seoul")
        return f
    }()

    private static let fareDisplayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        f.locale = Locale(identifier: "ko_KR")
        f.timeZone = TimeZone(identifier: "Asia/Seoul")
        return f
    }()

    private func fareDateLine(_ fare: BulkLowestFare) -> String {
        let nights = max(1, fare.period - 1)
        if let dep = Self.fareInputFormatter.date(from: fare.departureDate),
           let ret = Self.fareInputFormatter.date(from: fare.returnDate) {
            let depStr = Self.fareDisplayFormatter.string(from: dep)
            let retStr = Self.fareDisplayFormatter.string(from: ret)
            return "\(depStr) → \(retStr) · \(nights)박\(fare.period)일"
        }
        return "\(fare.departureDate) → \(fare.returnDate)"
    }

    private func displayCity(for code: String) -> String {
        let mapped = airportToCity[code] ?? code
        return koreanCityNames[mapped] ?? mapped
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
            fares = MRTMockData.bulkLowest(origin: "ICN")
                .sorted { $0.totalPriceKRW < $1.totalPriceKRW }
        }
    }

    @MainActor
    private func buildFare(_ fare: BulkLowestFare) async {
        buildingFareID = fare.id
        defer { buildingFareID = nil }

        let cityName = airportToCity[fare.toCity] ?? fare.toCity
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
}

// Generic press-scale wrapper used on hero cards / fare cards.
struct PressableScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.30, dampingFraction: 0.74), value: configuration.isPressed)
    }
}

#Preview {
    HomeView()
}
