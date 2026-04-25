import Foundation
import CoreLocation

// Abstraction over MyRealTrip partner API. When `useMockData` is true, returns
// deterministic samples so the UI flow is exercised end-to-end. When false,
// calls https://partner-ext-api.myrealtrip.com with Bearer auth.

protocol MRTClientProtocol {
    func searchFlights(
        from origin: String,
        to destination: String,
        departDate: Date,
        returnDate: Date,
        passengers: Int
    ) async throws -> [FlightOption]

    func searchHotelsNear(
        city: String,
        latitude: Double,
        longitude: Double,
        radiusMeters: Int,
        checkIn: Date,
        checkOut: Date,
        guests: Int
    ) async throws -> [HotelOption]

    func searchActivities(
        city: String,
        date: Date
    ) async throws -> [ActivityOption]

    func generateMyLink(targetURL: URL) async throws -> URL

    func fetchRecentReservations(
        from startDate: Date,
        to endDate: Date
    ) async throws -> [RemoteReservation]

    func fetchRevenues(
        from startDate: Date,
        to endDate: Date,
        dateType: RevenueDateType
    ) async throws -> [RevenueLine]

    func fetchFlightRevenues(
        from startDate: Date,
        to endDate: Date,
        dateType: RevenueDateType
    ) async throws -> [RevenueLine]

    // TNA detail / options / calendars / categories
    func fetchTNADetail(gid: String) async throws -> TNADetail
    func fetchTNAOptions(gid: String, selectedDate: Date) async throws -> TNAOptionsBundle
    func fetchTNACalendar(gid: String, selectedDate: Date) async throws -> TNACalendar
    func fetchTNACategories(city: String) async throws -> [TNACategory]

    // Bulk lowest flight fares from a single origin (international only)
    func fetchBulkLowestFlights(originCityCode: String, period: Int) async throws -> [BulkLowestFare]

    // Flight reservations (separate from TNA/hotel reservations)
    func fetchRecentFlightReservations(
        from startDate: Date,
        to endDate: Date
    ) async throws -> [RemoteFlightReservation]
}

struct RemoteReservation: Identifiable, Hashable {
    let id: String          // reservationNo
    let title: String
    let statusKor: String
    let reservedAt: Date?
    let tripStartedAt: Date?
    let salePriceKRW: Int
}

enum RevenueDateType: String, Hashable {
    case settlement = "SETTLEMENT"
    case payment = "PAYMENT"
}

struct RevenueLine: Identifiable, Hashable {
    let id: String          // reservationNo
    let productTitle: String
    let productCategory: String
    let statusKor: String
    let salePriceKRW: Int
    let commissionKRW: Int
    let commissionRate: Double
    let reservedAt: Date?
    let settlementDate: Date?
    let linkId: String?
    let city: String?
    let country: String?
    let utmContent: String?
}

struct TNADetail: Hashable {
    let gid: String
    let title: String
    let description: String?
    let reviewScore: Double?
    let reviewCount: Int?
    let included: [String]
    let excluded: [String]
    let itineraries: [TNAItineraryEntry]
}

struct TNAItineraryEntry: Hashable {
    let title: String?
    let description: String?
}

struct TNAOptionsBundle: Hashable {
    let selectedDate: String
    let options: [TNAOptionEntry]
}

struct TNAOptionEntry: Identifiable, Hashable {
    let id: Int64
    let name: String
    let salePriceKRW: Int
    let currency: String
    let minPurchaseQuantity: Int?
    let availablePurchaseQuantity: Int?
}

struct TNACalendar: Hashable {
    let date: String              // YYYY-MM
    let basePriceLabel: String?   // "9.3만"
    let blockDates: Set<String>   // YYYY-MM-DD
    let instantConfirm: Bool
}

struct TNACategory: Hashable {
    let name: String   // 표시명
    let value: String  // 검색용
}

struct BulkLowestFare: Identifiable, Hashable {
    var id: String { "\(fromCity)-\(toCity)-\(departureDate)" }
    let fromCity: String
    let toCity: String
    let period: Int
    let departureDate: String  // YYYY-MM-DD
    let returnDate: String
    let totalPriceKRW: Int
    let averagePriceKRW: Int?
}

struct RemoteFlightReservation: Identifiable, Hashable {
    var id: String { reservationNo }
    let reservationNo: String
    let pnr: String?
    let airlineCode: String
    let airlineName: String
    let operationScope: String   // INTERNATIONAL / DOMESTIC
    let tripType: String         // ROUND_TRIP / ONE_WAY / MULTI
    let statusKor: String
    let reservedAt: Date?
    let cancelledAt: Date?
    let issueNetKRW: Int
}

struct MRTClient: MRTClientProtocol {
    let apiKey: String
    let baseURL: URL
    let useMockData: Bool

    private let session: URLSession
    private let dayFormatter: DateFormatter
    private let dateTimeFormatter: DateFormatter
    private let jsonDecoder: JSONDecoder
    private let jsonEncoder: JSONEncoder

    init(
        apiKey: String,
        baseURL: URL = URL(string: "https://partner-ext-api.myrealtrip.com")!,
        useMockData: Bool = true,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.useMockData = useMockData
        self.session = session

        let day = DateFormatter()
        day.calendar = Calendar(identifier: .gregorian)
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = TimeZone(identifier: "Asia/Seoul")
        day.dateFormat = "yyyy-MM-dd"
        self.dayFormatter = day

        let dt = DateFormatter()
        dt.calendar = Calendar(identifier: .gregorian)
        dt.locale = Locale(identifier: "en_US_POSIX")
        dt.timeZone = TimeZone(identifier: "Asia/Seoul")
        dt.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        self.dateTimeFormatter = dt

        self.jsonDecoder = JSONDecoder()
        self.jsonEncoder = JSONEncoder()
    }

    // MARK: - Flights

    func searchFlights(
        from origin: String,
        to destination: String,
        departDate: Date,
        returnDate: Date,
        passengers: Int
    ) async throws -> [FlightOption] {
        if useMockData {
            return MRTMockData.flights(
                from: origin, to: destination,
                departDate: departDate, returnDate: returnDate
            )
        }

        let cal = Calendar(identifier: .gregorian)
        let nights = max(1, cal.dateComponents([.day], from: departDate, to: returnDate).day ?? 3)
        let period = min(7, max(3, nights))

        // Calendar query over a small window around the desired depart date.
        let windowEnd = cal.date(byAdding: .day, value: 3, to: departDate) ?? departDate
        let calendarItems: [FlightCalendarItem] = await (try? postForData(
            "/v1/products/flight/calendar",
            body: FlightCalendarRequest(
                depCityCd: origin,
                arrCityCd: destination,
                period: period,
                startDate: dayFormatter.string(from: departDate),
                endDate: dayFormatter.string(from: windowEnd)
            )
        )) ?? []

        // Landing URL for the user's exact dates (used as bookingURL).
        let landingString: String = (try? await postForData(
            "/v1/products/flight/fare-query-landing-url",
            body: FareQueryLandingRequest(
                depAirportCd: origin,
                arrAirportCd: destination,
                tripTypeCd: "RT",
                depDate: dayFormatter.string(from: departDate),
                arrDate: dayFormatter.string(from: returnDate),
                adult: passengers,
                child: 0,
                infant: 0,
                airline: nil,
                cabinClass: nil
            )
        )) ?? "https://www.myrealtrip.com"
        let landingURL = URL(string: landingString) ?? URL(string: "https://www.myrealtrip.com")!

        let topItems = calendarItems
            .sorted { $0.totalPrice < $1.totalPrice }
            .prefix(2)

        guard !topItems.isEmpty else {
            return [FlightOption(
                id: UUID(),
                airline: "MyRealTrip",
                flightNumber: "See fares",
                fromAirport: origin,
                toAirport: destination,
                departureTime: departDate,
                arrivalTime: returnDate,
                priceKRW: 0,
                mrtProductID: "flight-landing",
                bookingURL: landingURL
            )]
        }

        return topItems.map { item in
            FlightOption(
                id: UUID(),
                airline: airlineDisplayName(code: item.airline),
                flightNumber: "Best fare",
                fromAirport: origin,
                toAirport: destination,
                departureTime: dayFormatter.date(from: item.departureDate ?? "") ?? departDate,
                arrivalTime: dayFormatter.date(from: item.returnDate ?? "") ?? returnDate,
                priceKRW: Int(item.totalPrice),
                mrtProductID: "flight-\(item.airline ?? "any")",
                bookingURL: landingURL
            )
        }
    }

    // MARK: - Hotels

    func searchHotelsNear(
        city: String,
        latitude: Double,
        longitude: Double,
        radiusMeters: Int,
        checkIn: Date,
        checkOut: Date,
        guests: Int
    ) async throws -> [HotelOption] {
        if useMockData {
            return MRTMockData.hotels(
                near: .init(latitude: latitude, longitude: longitude),
                radius: radiusMeters
            )
        }

        let keyword = koreanCityName(for: city) ?? city
        let body = AccommodationSearchRequest(
            keyword: keyword,
            regionId: nil,
            checkIn: dayFormatter.string(from: checkIn),
            checkOut: dayFormatter.string(from: checkOut),
            adultCount: max(1, guests),
            childCount: 0,
            isDomestic: nil,
            starRating: nil,
            stayPoi: nil,
            order: "review_desc",
            minPrice: nil,
            maxPrice: nil,
            page: 0,
            size: 10
        )
        let data: AccommodationSearchData = try await postForData(
            "/v1/products/accommodation/search",
            body: body
        )

        return data.items.map { item in
            HotelOption(
                id: UUID(),
                name: item.itemName,
                address: "",
                latitude: latitude,
                longitude: longitude,
                distanceMetersFromAnchor: 0,
                starRating: Double(item.starRating ?? 0),
                userRating: Double(item.reviewScore ?? "0") ?? 0,
                pricePerNightKRW: Int(item.salePrice),
                freeCancellation: false,
                mrtProductID: String(item.itemId),
                bookingURL: productURL(itemId: item.itemId),
                thumbnailURL: nil
            )
        }
    }

    // MARK: - Activities

    func searchActivities(city: String, date: Date) async throws -> [ActivityOption] {
        if useMockData {
            return MRTMockData.activities(city: city)
        }
        let keyword = koreanCityName(for: city) ?? city
        let body = TNASearchRequest(
            keyword: keyword,
            city: nil,  // Sending both keyword+city over-filters to ~0 results.
            category: nil,
            minPrice: nil,
            maxPrice: nil,
            sort: "review_score_desc",
            page: 1,
            perPage: 6
        )
        let data: TNASearchData = try await postForData(
            "/v1/products/tna/search",
            body: body
        )
        return data.items.map { item in
            ActivityOption(
                id: UUID(),
                title: item.itemName,
                durationHours: 0,
                priceKRW: Int(item.salePrice),
                rating: item.reviewScore ?? 0,
                thumbnailURL: item.imageUrl.flatMap(URL.init(string:)),
                mrtProductID: item.gid,
                bookingURL: URL(string: item.productUrl) ?? URL(string: "https://www.myrealtrip.com")!
            )
        }
    }

    // MARK: - MyLink (partner-attributed short URL)

    func generateMyLink(targetURL: URL) async throws -> URL {
        if useMockData { return targetURL }
        let body = MyLinkRequest(targetUrl: targetURL.absoluteString)
        let data: MyLinkData = try await postForData("/v1/mylink", body: body)
        return URL(string: data.mylink) ?? targetURL
    }

    // MARK: - Reservations

    func fetchRecentReservations(from startDate: Date, to endDate: Date) async throws -> [RemoteReservation] {
        if useMockData {
            return MRTMockData.reservations()
        }
        let env: MRTEnvelope<[ReservationItem]> = try await get(
            "/v1/reservations",
            query: [
                URLQueryItem(name: "dateSearchType", value: "RESERVATION_DATE"),
                URLQueryItem(name: "startDate", value: dayFormatter.string(from: startDate)),
                URLQueryItem(name: "endDate", value: dayFormatter.string(from: endDate)),
                URLQueryItem(name: "pageSize", value: "50")
            ]
        )
        let items = env.data ?? []
        return items.map { item in
            RemoteReservation(
                id: item.reservationNo,
                title: item.productTitle ?? "Trip",
                statusKor: item.statusKor ?? item.status ?? "",
                reservedAt: dateTimeFormatter.date(from: item.reservedAt ?? ""),
                tripStartedAt: dateTimeFormatter.date(from: item.tripStartedAt ?? ""),
                salePriceKRW: Int(item.salePrice ?? 0)
            )
        }
    }

    // MARK: - TNA detail / options / calendars / categories

    func fetchTNADetail(gid: String) async throws -> TNADetail {
        if useMockData { return MRTMockData.tnaDetail(gid: gid) }
        let body = TNADetailRequest(gid: gid)
        let raw: TNADetailRaw = try await postForData("/v1/products/tna/detail", body: body)
        return TNADetail(
            gid: raw.gid,
            title: raw.title,
            description: raw.description,
            reviewScore: raw.reviewScore,
            reviewCount: raw.reviewCount,
            included: raw.included ?? [],
            excluded: raw.excluded ?? [],
            itineraries: (raw.itineraries ?? []).map {
                TNAItineraryEntry(title: $0.title, description: $0.description)
            }
        )
    }

    func fetchTNAOptions(gid: String, selectedDate: Date) async throws -> TNAOptionsBundle {
        if useMockData {
            return MRTMockData.tnaOptions(gid: gid, date: dayFormatter.string(from: selectedDate))
        }
        let body = TNAOptionsRequest(gid: gid, selectedDate: dayFormatter.string(from: selectedDate))
        let raw: TNAOptionsRaw = try await postForData("/v1/products/tna/options", body: body)
        return TNAOptionsBundle(
            selectedDate: raw.selectedDate ?? dayFormatter.string(from: selectedDate),
            options: (raw.options ?? []).map {
                TNAOptionEntry(
                    id: $0.id,
                    name: $0.name,
                    salePriceKRW: Int($0.salePrice),
                    currency: $0.currency ?? "KRW",
                    minPurchaseQuantity: $0.minPurchaseQuantity,
                    availablePurchaseQuantity: $0.availablePurchaseQuantity
                )
            }
        )
    }

    func fetchTNACalendar(gid: String, selectedDate: Date) async throws -> TNACalendar {
        if useMockData {
            return MRTMockData.tnaCalendar(date: dayFormatter.string(from: selectedDate))
        }
        let body = TNACalendarRequest(gid: gid, selectedDate: dayFormatter.string(from: selectedDate))
        let raw: TNACalendarRaw = try await postForData("/v1/products/tna/calendars", body: body)
        return TNACalendar(
            date: raw.date ?? "",
            basePriceLabel: raw.basePrice,
            blockDates: Set(raw.blockDates ?? []),
            instantConfirm: raw.instantConfirm ?? false
        )
    }

    func fetchTNACategories(city: String) async throws -> [TNACategory] {
        if useMockData { return MRTMockData.tnaCategories() }
        let keyword = TripParsingHelpers.koreanCityName(for: city) ?? city
        let body = TNACategoriesRequest(city: keyword)
        let raw: TNACategoriesRaw = try await postForData("/v1/products/tna/categories", body: body)
        return (raw.categories ?? []).map { TNACategory(name: $0.name, value: $0.value) }
    }

    // MARK: - Bulk lowest flight fares

    func fetchBulkLowestFlights(originCityCode: String, period: Int) async throws -> [BulkLowestFare] {
        if useMockData { return MRTMockData.bulkLowest(origin: originCityCode) }
        let body = BulkLowestRequest(depCityCd: originCityCode, period: max(3, min(7, period)))
        let raw: [BulkLowestItem] = try await postForData(
            "/v1/products/flight/calendar/bulk-lowest",
            body: body
        )
        return raw.compactMap { item in
            guard let dep = item.departureDate, let ret = item.returnDate else { return nil }
            return BulkLowestFare(
                fromCity: item.fromCity ?? originCityCode,
                toCity: item.toCity ?? "",
                period: item.period ?? period,
                departureDate: dep,
                returnDate: ret,
                totalPriceKRW: Int(item.totalPrice),
                averagePriceKRW: item.averagePrice.map(Int.init)
            )
        }
    }

    // MARK: - Flight reservations

    func fetchRecentFlightReservations(from startDate: Date, to endDate: Date) async throws -> [RemoteFlightReservation] {
        if useMockData { return [] }
        let env: MRTEnvelope<[FlightReservationItem]> = try await get(
            "/v1/reservations/flight",
            query: [
                URLQueryItem(name: "startDate", value: dayFormatter.string(from: startDate)),
                URLQueryItem(name: "endDate", value: dayFormatter.string(from: endDate))
            ]
        )
        let items = env.data ?? []
        return items.map { item in
            RemoteFlightReservation(
                reservationNo: item.reservationNo,
                pnr: item.flightReservationNo,
                airlineCode: item.airline ?? "",
                airlineName: item.airlineName ?? "",
                operationScope: item.operationScope ?? "",
                tripType: item.tripType ?? "",
                statusKor: item.statusKor ?? item.status ?? "",
                reservedAt: dateTimeFormatter.date(from: item.reservedAt ?? ""),
                cancelledAt: dateTimeFormatter.date(from: item.cancelledAt ?? ""),
                issueNetKRW: Int(item.issueNet ?? 0)
            )
        }
    }

    // MARK: - Revenues

    func fetchRevenues(
        from startDate: Date,
        to endDate: Date,
        dateType: RevenueDateType
    ) async throws -> [RevenueLine] {
        if useMockData { return MRTMockData.revenues() }
        let env: MRTEnvelope<[RevenueItem]> = try await get(
            "/v1/revenues",
            query: [
                URLQueryItem(name: "dateSearchType", value: dateType.rawValue),
                URLQueryItem(name: "startDate", value: dayFormatter.string(from: startDate)),
                URLQueryItem(name: "endDate", value: dayFormatter.string(from: endDate))
            ]
        )
        return (env.data ?? []).map { toLine($0) }
    }

    func fetchFlightRevenues(
        from startDate: Date,
        to endDate: Date,
        dateType: RevenueDateType
    ) async throws -> [RevenueLine] {
        if useMockData { return [] }
        let env: MRTEnvelope<[RevenueItem]> = try await get(
            "/v1/revenues/flight",
            query: [
                URLQueryItem(name: "dateSearchType", value: dateType.rawValue),
                URLQueryItem(name: "startDate", value: dayFormatter.string(from: startDate)),
                URLQueryItem(name: "endDate", value: dayFormatter.string(from: endDate))
            ]
        )
        return (env.data ?? []).map { toLine($0) }
    }

    private func toLine(_ item: RevenueItem) -> RevenueLine {
        RevenueLine(
            id: item.reservationNo,
            productTitle: item.productTitle ?? "(Unknown product)",
            productCategory: item.productCategory ?? "",
            statusKor: item.statusKor ?? item.status ?? "",
            salePriceKRW: Int(item.commissionBase ?? item.salePrice ?? 0),
            commissionKRW: Int(item.commission ?? 0),
            commissionRate: item.commissionRate ?? 0,
            reservedAt: dateTimeFormatter.date(from: item.reservedAt ?? ""),
            settlementDate: dayFormatter.date(from: item.settlementCriteriaDate ?? ""),
            linkId: item.linkId,
            city: item.city,
            country: item.country,
            utmContent: item.utmContent
        )
    }

    // MARK: - Transport

    private func postForData<Body: Encodable, Payload: Decodable>(_ path: String, body: Body) async throws -> Payload {
        let env: MRTEnvelope<Payload> = try await post(path, body: body)
        guard let payload = env.data else {
            throw MRTAPIError(status: env.result?.status ?? 200, message: env.result?.message ?? "Empty response")
        }
        return payload
    }

    private func post<Body: Encodable, Response: Decodable>(_ path: String, body: Body) async throws -> Response {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("ko-KR", forHTTPHeaderField: "Accept-Language")
        req.httpBody = try jsonEncoder.encode(body)
        let (data, response) = try await session.data(for: req)
        try validate(response: response, data: data)
        return try jsonDecoder.decode(Response.self, from: data)
    }

    private func get<Response: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> Response {
        var comps = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        guard let url = comps.url else { throw MRTAPIError(status: 0, message: "Bad URL") }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("ko-KR", forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await session.data(for: req)
        try validate(response: response, data: data)
        return try jsonDecoder.decode(Response.self, from: data)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let decoded = try? jsonDecoder.decode(MRTEnvelope<JSONNull>.self, from: data)
            throw MRTAPIError(
                status: http.statusCode,
                message: decoded?.result?.message ?? "HTTP \(http.statusCode)"
            )
        }
    }

    private func productURL(itemId: Int) -> URL {
        URL(string: "https://www.myrealtrip.com/offers/\(itemId)")
            ?? URL(string: "https://www.myrealtrip.com")!
    }

    private func airlineDisplayName(code: String?) -> String {
        guard let code, !code.isEmpty else { return "MyRealTrip" }
        let names: [String: String] = [
            "KE": "Korean Air", "OZ": "Asiana", "7C": "Jeju Air", "LJ": "Jin Air",
            "TW": "T'way Air", "BX": "Air Busan", "RS": "Air Seoul", "ZE": "Eastar Jet",
            "JL": "JAL", "NH": "ANA", "TG": "Thai Airways", "VN": "Vietnam Airlines",
            "SQ": "Singapore Airlines", "CX": "Cathay Pacific", "QR": "Qatar Airways",
            "EK": "Emirates", "LH": "Lufthansa", "AF": "Air France", "BA": "British Airways",
            "UA": "United", "AA": "American", "DL": "Delta", "SL": "Lion Air",
            "AK": "AirAsia", "MH": "Malaysia Airlines", "PR": "Philippine Airlines"
        ]
        return names[code] ?? code
    }

    private func koreanCityName(for city: String) -> String? {
        TripParsingHelpers.koreanCityName(for: city)
    }
}

enum TripParsingHelpers {
    static func koreanCityName(for city: String) -> String? {
        let lookup: [String: String] = [
            "tokyo": "도쿄", "osaka": "오사카", "kyoto": "교토", "fukuoka": "후쿠오카",
            "sapporo": "삿포로", "okinawa": "오키나와", "nagoya": "나고야", "hiroshima": "히로시마",
            "yufuin": "유후인", "oita": "오이타", "beppu": "벳푸",
            "seoul": "서울", "busan": "부산", "jeju": "제주", "gangneung": "강릉", "yeosu": "여수",
            "bangkok": "방콕", "phuket": "푸켓", "chiang mai": "치앙마이",
            "singapore": "싱가포르", "hanoi": "하노이", "ho chi minh city": "호치민", "da nang": "다낭",
            "bali": "발리", "denpasar": "발리", "manila": "마닐라", "cebu": "세부",
            "taipei": "타이베이", "kaohsiung": "가오슝",
            "paris": "파리", "london": "런던", "rome": "로마", "madrid": "마드리드",
            "barcelona": "바르셀로나", "amsterdam": "암스테르담", "berlin": "베를린",
            "los angeles": "로스앤젤레스", "new york": "뉴욕", "las vegas": "라스베이거스",
            "san francisco": "샌프란시스코", "honolulu": "호놀룰루", "guam": "괌",
            "dubai": "두바이", "istanbul": "이스탄불"
        ]
        return lookup[city.lowercased()]
    }
}

// MARK: - DTOs (private)

private struct FlightCalendarRequest: Encodable {
    let depCityCd: String
    let arrCityCd: String
    let period: Int
    let startDate: String
    let endDate: String
}

private struct FlightCalendarItem: Decodable {
    let fromCity: String?
    let toCity: String?
    let period: Int?
    let departureDate: String?
    let returnDate: String?
    let totalPrice: Int64
    let airline: String?
    let transfer: Int?
    let averagePrice: Int64?
}

private struct FareQueryLandingRequest: Encodable {
    let depAirportCd: String
    let arrAirportCd: String
    let tripTypeCd: String
    let depDate: String?
    let arrDate: String?
    let adult: Int?
    let child: Int?
    let infant: Int?
    let airline: String?
    let cabinClass: String?
}

private struct AccommodationSearchRequest: Encodable {
    let keyword: String
    let regionId: Int?
    let checkIn: String
    let checkOut: String
    let adultCount: Int
    let childCount: Int
    let isDomestic: Bool?
    let starRating: String?
    let stayPoi: Int?
    let order: String?
    let minPrice: Int?
    let maxPrice: Int?
    let page: Int
    let size: Int
}

private struct AccommodationSearchData: Decodable {
    let items: [AccommodationItem]
    let totalCount: Int?
    let page: Int?
    let size: Int?
}

private struct AccommodationItem: Decodable {
    let itemId: Int
    let itemName: String
    let salePrice: Int64
    let originalPrice: Int64?
    let starRating: Int?
    let reviewScore: String?
    let reviewCount: Int?
}

private struct TNASearchRequest: Encodable {
    let keyword: String
    let city: String?
    let category: String?
    let minPrice: Int?
    let maxPrice: Int?
    let sort: String?
    let page: Int
    let perPage: Int
}

private struct TNASearchData: Decodable {
    let items: [TNAItem]
    let totalCount: Int?
    let page: Int?
    let perPage: Int?
    let hasNextPage: Bool?
}

private struct TNAItem: Decodable {
    let gid: String
    let itemName: String
    let description: String?
    let salePrice: Int64
    let priceDisplay: String?
    let category: String?
    let reviewScore: Double?
    let reviewCount: Int?
    let imageUrl: String?
    let productUrl: String
    let deepLink: String?
    let tags: [String]?
}

private struct MyLinkRequest: Encodable {
    let targetUrl: String
}

private struct MyLinkData: Decodable {
    let mylink: String
}

// TNA detail
private struct TNADetailRequest: Encodable {
    let gid: String
}

private struct TNADetailRaw: Decodable {
    let gid: String
    let title: String
    let description: String?
    let reviewScore: Double?
    let reviewCount: Int?
    let included: [String]?
    let excluded: [String]?
    let itineraries: [TNAItineraryRaw]?
}

private struct TNAItineraryRaw: Decodable {
    let title: String?
    let description: String?
}

// TNA options
private struct TNAOptionsRequest: Encodable {
    let gid: String
    let selectedDate: String
}

private struct TNAOptionsRaw: Decodable {
    let selectedDate: String?
    let options: [TNAOptionRaw]?
}

private struct TNAOptionRaw: Decodable {
    let id: Int64
    let name: String
    let salePrice: Int64
    let currency: String?
    let minPurchaseQuantity: Int?
    let availablePurchaseQuantity: Int?
}

// TNA calendar
private struct TNACalendarRequest: Encodable {
    let gid: String
    let selectedDate: String
}

private struct TNACalendarRaw: Decodable {
    let date: String?
    let basePrice: String?
    let blockDates: [String]?
    let excludedOptionDates: [String]?
    let instantConfirm: Bool?
}

// TNA categories
private struct TNACategoriesRequest: Encodable {
    let city: String
}

private struct TNACategoriesRaw: Decodable {
    let categories: [TNACategoryRaw]?
    let totalCount: Int?
}

private struct TNACategoryRaw: Decodable {
    let name: String
    let value: String
}

// Bulk lowest flight fares
private struct BulkLowestRequest: Encodable {
    let depCityCd: String
    let period: Int
}

private struct BulkLowestItem: Decodable {
    let fromCity: String?
    let toCity: String?
    let period: Int?
    let departureDate: String?
    let returnDate: String?
    let totalPrice: Int64
    let airline: String?
    let transfer: Int?
    let averagePrice: Int64?
}

// Flight reservations
private struct FlightReservationItem: Decodable {
    let reservationNo: String
    let flightReservationNo: String?
    let operationScope: String?
    let tripType: String?
    let status: String?
    let statusKor: String?
    let airline: String?
    let airlineName: String?
    let reservedAt: String?
    let cancelledAt: String?
    let gid: Int64?
    let categoryCode: String?
    let linkId: String?
    let issueNet: Int64?
}

private struct RevenueItem: Decodable {
    let reservationNo: String
    let salePrice: Int64?
    let commissionBase: Int64?
    let commission: Int64?
    let commissionRate: Double?
    let utmContent: String?
    let closingType: String?
    let reservedAt: String?
    let settlementCriteriaDate: String?
    let productTitle: String?
    let productCategory: String?
    let status: String?
    let statusKor: String?
    let linkId: String?
    let city: String?
    let country: String?
}

private struct ReservationItem: Decodable {
    let reservedAt: String?
    let reservationNo: String
    let status: String?
    let statusKor: String?
    let salePrice: Int64?
    let productTitle: String?
    let productCategory: String?
    let tripStartedAt: String?
    let tripEndedAt: String?
    let canceledAt: String?
    let finishedAt: String?
    let linkId: String?
    let gid: Int64?
    let quantity: Int?
    let city: String?
    let country: String?
}

// MARK: - Envelope

private struct MRTEnvelope<T: Decodable>: Decodable {
    let data: T?
    let meta: MRTMeta?
    let result: MRTResult?
}

private struct MRTMeta: Decodable {
    let totalCount: Int?
}

private struct MRTResult: Decodable {
    let status: Int?
    let message: String?
    let code: String?
}

private struct JSONNull: Decodable {}

struct MRTAPIError: Error, LocalizedError {
    let status: Int
    let message: String
    var errorDescription: String? { "MRT API \(status): \(message)" }
}

// MARK: - Mock data

enum MRTMockData {
    static func flights(
        from origin: String,
        to destination: String,
        departDate: Date,
        returnDate: Date
    ) -> [FlightOption] {
        [
            FlightOption(
                id: UUID(),
                airline: "Korean Air",
                flightNumber: "KE123",
                fromAirport: origin,
                toAirport: destination,
                departureTime: departDate.addingTimeInterval(3600 * 10),
                arrivalTime: departDate.addingTimeInterval(3600 * 14),
                priceKRW: 720_000,
                mrtProductID: "mock-flight-1",
                bookingURL: URL(string: "https://www.myrealtrip.com")!
            ),
            FlightOption(
                id: UUID(),
                airline: "Asiana",
                flightNumber: "OZ456",
                fromAirport: origin,
                toAirport: destination,
                departureTime: departDate.addingTimeInterval(3600 * 7),
                arrivalTime: departDate.addingTimeInterval(3600 * 11),
                priceKRW: 680_000,
                mrtProductID: "mock-flight-2",
                bookingURL: URL(string: "https://www.myrealtrip.com")!
            )
        ]
    }

    static func hotels(near anchor: CLLocationCoordinate2D, radius: Int) -> [HotelOption] {
        [
            HotelOption(
                id: UUID(),
                name: "Venue Front Hotel",
                address: "1-2-3 Near Venue St",
                latitude: anchor.latitude + 0.001,
                longitude: anchor.longitude + 0.001,
                distanceMetersFromAnchor: 450,
                starRating: 4.0,
                userRating: 4.6,
                pricePerNightKRW: 180_000,
                freeCancellation: true,
                mrtProductID: "mock-hotel-1",
                bookingURL: URL(string: "https://www.myrealtrip.com")!,
                thumbnailURL: nil
            ),
            HotelOption(
                id: UUID(),
                name: "Stadium View Residence",
                address: "4-5-6 Stadium Rd",
                latitude: anchor.latitude - 0.002,
                longitude: anchor.longitude,
                distanceMetersFromAnchor: 920,
                starRating: 3.5,
                userRating: 4.2,
                pricePerNightKRW: 130_000,
                freeCancellation: true,
                mrtProductID: "mock-hotel-2",
                bookingURL: URL(string: "https://www.myrealtrip.com")!,
                thumbnailURL: nil
            ),
            HotelOption(
                id: UUID(),
                name: "Budget Inn City Center",
                address: "7-8-9 Central Ave",
                latitude: anchor.latitude + 0.004,
                longitude: anchor.longitude - 0.003,
                distanceMetersFromAnchor: 1450,
                starRating: 3.0,
                userRating: 4.0,
                pricePerNightKRW: 85_000,
                freeCancellation: false,
                mrtProductID: "mock-hotel-3",
                bookingURL: URL(string: "https://www.myrealtrip.com")!,
                thumbnailURL: nil
            )
        ]
    }

    static func activities(city: String) -> [ActivityOption] {
        [
            ActivityOption(
                id: UUID(),
                title: "\(city) City Walking Tour",
                durationHours: 3,
                priceKRW: 45_000,
                rating: 4.7,
                thumbnailURL: nil,
                mrtProductID: "mock-act-1",
                bookingURL: URL(string: "https://www.myrealtrip.com")!
            ),
            ActivityOption(
                id: UUID(),
                title: "Local Food Experience in \(city)",
                durationHours: 4,
                priceKRW: 89_000,
                rating: 4.8,
                thumbnailURL: nil,
                mrtProductID: "mock-act-2",
                bookingURL: URL(string: "https://www.myrealtrip.com")!
            )
        ]
    }

    static func reservations() -> [RemoteReservation] { [] }

    static func tnaDetail(gid: String) -> TNADetail {
        TNADetail(
            gid: gid,
            title: "샘플 투어 상품",
            description: "이건 mock 모드 더미 데이터입니다. 실제 데이터는 MRT 파트너 키 연결 후 표시됩니다.",
            reviewScore: 4.7,
            reviewCount: 128,
            included: ["가이드 동행", "교통편 제공", "입장료"],
            excluded: ["식사", "개인 경비"],
            itineraries: [
                TNAItineraryEntry(title: "오전 09:00", description: "호텔 픽업 후 첫 일정 시작"),
                TNAItineraryEntry(title: "오후 14:00", description: "메인 명소 관광"),
                TNAItineraryEntry(title: "오후 18:00", description: "호텔 샌딩")
            ]
        )
    }

    static func tnaOptions(gid: String, date: String) -> TNAOptionsBundle {
        TNAOptionsBundle(
            selectedDate: date,
            options: [
                TNAOptionEntry(id: 1, name: "성인 1인", salePriceKRW: 89_000, currency: "KRW", minPurchaseQuantity: 1, availablePurchaseQuantity: 8),
                TNAOptionEntry(id: 2, name: "성인 2인 (커플)", salePriceKRW: 168_000, currency: "KRW", minPurchaseQuantity: 1, availablePurchaseQuantity: 4)
            ]
        )
    }

    static func tnaCalendar(date: String) -> TNACalendar {
        let prefix = date.prefix(7)  // YYYY-MM
        return TNACalendar(
            date: String(prefix),
            basePriceLabel: "8.9만",
            blockDates: [],
            instantConfirm: true
        )
    }

    static func tnaCategories() -> [TNACategory] {
        [
            TNACategory(name: "전체", value: "all"),
            TNACategory(name: "티켓·입장권", value: "ticket_v2"),
            TNACategory(name: "투어", value: "tour"),
            TNACategory(name: "이동·교통", value: "transportation_v2"),
            TNACategory(name: "체험·클래스", value: "activity_class")
        ]
    }

    static func bulkLowest(origin: String) -> [BulkLowestFare] {
        let cal = Calendar(identifier: .gregorian)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let dep = cal.date(byAdding: .day, value: 30, to: .now) ?? .now
        let ret = cal.date(byAdding: .day, value: 35, to: .now) ?? .now
        let depStr = f.string(from: dep)
        let retStr = f.string(from: ret)
        return [
            BulkLowestFare(fromCity: origin, toCity: "NRT", period: 5, departureDate: depStr, returnDate: retStr, totalPriceKRW: 472_300, averagePriceKRW: 580_000),
            BulkLowestFare(fromCity: origin, toCity: "FUK", period: 5, departureDate: depStr, returnDate: retStr, totalPriceKRW: 326_800, averagePriceKRW: 420_000),
            BulkLowestFare(fromCity: origin, toCity: "KIX", period: 5, departureDate: depStr, returnDate: retStr, totalPriceKRW: 388_000, averagePriceKRW: 510_000),
            BulkLowestFare(fromCity: origin, toCity: "BKK", period: 5, departureDate: depStr, returnDate: retStr, totalPriceKRW: 326_300, averagePriceKRW: 549_000),
            BulkLowestFare(fromCity: origin, toCity: "DAD", period: 5, departureDate: depStr, returnDate: retStr, totalPriceKRW: 412_000, averagePriceKRW: 580_000),
            BulkLowestFare(fromCity: origin, toCity: "TPE", period: 5, departureDate: depStr, returnDate: retStr, totalPriceKRW: 298_500, averagePriceKRW: 380_000)
        ]
    }

    static func revenues() -> [RevenueLine] {
        [
            RevenueLine(
                id: "TNA-MOCK-0001",
                productTitle: "오사카 유니버설 스튜디오 재팬 1일권",
                productCategory: "TICKET",
                statusKor: "예약확정",
                salePriceKRW: 128_000,
                commissionKRW: 8_960,
                commissionRate: 0.07,
                reservedAt: .now.addingTimeInterval(-86400 * 3),
                settlementDate: .now.addingTimeInterval(-86400 * 2),
                linkId: "mock-link-1",
                city: "Osaka",
                country: "Japan",
                utmContent: "k-pop-fan-club"
            ),
            RevenueLine(
                id: "TNA-MOCK-0002",
                productTitle: "도쿄 신주쿠 호텔 그레이서리 2박",
                productCategory: "HOTEL_V2",
                statusKor: "예약확정",
                salePriceKRW: 420_000,
                commissionKRW: 29_400,
                commissionRate: 0.07,
                reservedAt: .now.addingTimeInterval(-86400 * 7),
                settlementDate: .now.addingTimeInterval(-86400 * 6),
                linkId: "mock-link-2",
                city: "Tokyo",
                country: "Japan",
                utmContent: "reel-parser"
            )
        ]
    }
}
