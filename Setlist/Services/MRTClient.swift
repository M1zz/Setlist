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
}

struct RemoteReservation: Identifiable, Hashable {
    let id: String          // reservationNo
    let title: String
    let statusKor: String
    let reservedAt: Date?
    let tripStartedAt: Date?
    let salePriceKRW: Int
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
}
