import Foundation
import UIKit
import Vision

// On-device trip parsing. Zero network calls to any LLM — concert tickets are
// OCR'd with Vision, then matched against local artist / venue databases and
// a multi-format date extractor. Content links are fetched directly, scraped
// for OpenGraph meta, then matched against a city keyword table. Everything
// falls back to sensible defaults so the user always reaches a bundle.

protocol TripParsingServiceProtocol {
    func parseContentLink(_ url: URL) async throws -> ContentSource
    func parseConcertTicket(image: UIImage) async throws -> ConcertSource
    func parseConcertTicket(rawText: String) async throws -> ConcertSource
}

struct TripParsingService: TripParsingServiceProtocol {
    let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    // MARK: - Concert ticket parsing

    func parseConcertTicket(image: UIImage) async throws -> ConcertSource {
        let text = try await recognizeText(from: image)
        return extractConcert(from: text)
    }

    func parseConcertTicket(rawText: String) async throws -> ConcertSource {
        extractConcert(from: rawText)
    }

    private func extractConcert(from text: String) -> ConcertSource {
        let venue = VenueDB.firstMatch(in: text)
        let cityMatch = CityDB.firstMatch(in: text)
        let artist = ArtistDB.firstMatch(in: text) ?? "Concert"
        let city = venue?.city ?? cityMatch?.name ?? "Tokyo"
        let country = venue?.country ?? cityMatch?.country ?? "Japan"
        let coords: (Double, Double) = venue.map { ($0.lat, $0.lng) }
            ?? cityMatch.map { ($0.lat, $0.lng) }
            ?? (35.6762, 139.6503)
        let date = DateExtractor.firstDate(in: text) ?? Date().addingTimeInterval(86400 * 30)

        return ConcertSource(
            artist: artist,
            venueName: venue?.name ?? "\(city) Venue",
            venueLatitude: coords.0,
            venueLongitude: coords.1,
            city: city,
            country: country,
            showDate: date
        )
    }

    // MARK: - Content link parsing

    struct LinkMetadata {
        let title: String
        let description: String
        let image: String?
    }

    func parseContentLink(_ url: URL) async throws -> ContentSource {
        let metadata = (try? await fetchMetadata(from: url))
            ?? LinkMetadata(title: "", description: "", image: nil)
        let haystack = [metadata.title, metadata.description, url.absoluteString]
            .joined(separator: "\n")

        let cityMatch = CityDB.firstMatch(in: haystack)
        let venue = VenueDB.firstMatch(in: haystack)

        let cityName = cityMatch?.name ?? venue?.city ?? "Tokyo"
        let country = cityMatch?.country ?? venue?.country ?? "Japan"
        let coords: (Double, Double) = venue.map { ($0.lat, $0.lng) }
            ?? cityMatch.map { ($0.lat, $0.lng) }
            ?? (35.6762, 139.6503)

        let captionParts = [metadata.title, metadata.description].filter { !$0.isEmpty }
        let caption = captionParts.isEmpty ? nil : captionParts.joined(separator: " · ")

        return ContentSource(
            originalURL: url,
            detectedPlaceName: venue?.name,
            detectedCity: cityName,
            detectedCountry: country,
            detectedLatitude: coords.0,
            detectedLongitude: coords.1,
            caption: caption
        )
    }

    // MARK: - Vision OCR

    private func recognizeText(from image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else { return "" }
        return try await withCheckedThrowingContinuation { cont in
            let request = VNRecognizeTextRequest { req, err in
                if let err = err { cont.resume(throwing: err); return }
                let results = (req.results as? [VNRecognizedTextObservation]) ?? []
                let text = results
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                cont.resume(returning: text)
            }
            request.recognitionLanguages = ["ko-KR", "en-US", "ja-JP"]
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                cont.resume(throwing: error)
            }
        }
    }

    // MARK: - URL metadata scraping

    private func fetchMetadata(from url: URL) async throws -> LinkMetadata {
        var req = URLRequest(url: url)
        req.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        req.timeoutInterval = 8
        let (data, _) = try await urlSession.data(for: req)
        guard let html = String(data: data, encoding: .utf8) else {
            return LinkMetadata(title: "", description: "", image: nil)
        }

        let title = metaContent(in: html, attribute: "property", value: "og:title")
            ?? metaContent(in: html, attribute: "name", value: "twitter:title")
            ?? titleTag(in: html)
            ?? ""
        let description = metaContent(in: html, attribute: "property", value: "og:description")
            ?? metaContent(in: html, attribute: "name", value: "description")
            ?? metaContent(in: html, attribute: "name", value: "twitter:description")
            ?? ""
        let image = metaContent(in: html, attribute: "property", value: "og:image")
        return LinkMetadata(
            title: decodeHTMLEntities(title),
            description: decodeHTMLEntities(description),
            image: image
        )
    }

    private func metaContent(in html: String, attribute: String, value: String) -> String? {
        let esc = NSRegularExpression.escapedPattern(for: value)
        let patterns = [
            #"<meta[^>]*\#(attribute)=["']\#(esc)["'][^>]*content=["']([^"']+)["']"#,
            #"<meta[^>]*content=["']([^"']+)["'][^>]*\#(attribute)=["']\#(esc)["']"#
        ]
        for pat in patterns {
            if let found = firstCaptureGroup(in: html, pattern: pat) {
                return found
            }
        }
        return nil
    }

    private func titleTag(in html: String) -> String? {
        firstCaptureGroup(in: html, pattern: #"<title[^>]*>([^<]+)</title>"#)
    }

    private func firstCaptureGroup(in text: String, pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = re.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let r = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func decodeHTMLEntities(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }
}

// MARK: - Artist DB

enum ArtistDB {
    private static let aliases: [(match: String, display: String)] = [
        ("방탄소년단", "BTS"), ("BTS", "BTS"),
        ("블랙핑크", "BLACKPINK"), ("BLACKPINK", "BLACKPINK"),
        ("투모로우바이투게더", "TXT"), ("TOMORROW X TOGETHER", "TXT"), ("TXT", "TXT"),
        ("스트레이 키즈", "Stray Kids"), ("스트레이키즈", "Stray Kids"), ("Stray Kids", "Stray Kids"),
        ("뉴진스", "NewJeans"), ("NewJeans", "NewJeans"),
        ("르 세라핌", "LE SSERAFIM"), ("르세라핌", "LE SSERAFIM"), ("LE SSERAFIM", "LE SSERAFIM"),
        ("에스파", "aespa"), ("aespa", "aespa"),
        ("트와이스", "TWICE"), ("TWICE", "TWICE"),
        ("있지", "ITZY"), ("ITZY", "ITZY"),
        ("세븐틴", "SEVENTEEN"), ("SEVENTEEN", "SEVENTEEN"),
        ("에이티즈", "ATEEZ"), ("ATEEZ", "ATEEZ"),
        ("엔하이픈", "ENHYPEN"), ("ENHYPEN", "ENHYPEN"),
        ("아이브", "IVE"),
        ("라이즈", "RIIZE"), ("RIIZE", "RIIZE"),
        ("제로베이스원", "ZEROBASEONE"), ("ZEROBASEONE", "ZEROBASEONE"),
        ("보이넥스트도어", "BOYNEXTDOOR"), ("BOYNEXTDOOR", "BOYNEXTDOOR"),
        ("데이식스", "DAY6"), ("DAY6", "DAY6"),
        ("몬스타엑스", "MONSTA X"), ("MONSTA X", "MONSTA X"),
        ("NCT DREAM", "NCT DREAM"), ("NCT 127", "NCT 127"), ("NCT U", "NCT U"),
        ("샤이니", "SHINee"), ("SHINee", "SHINee"),
        ("엑소", "EXO"), ("EXO", "EXO"),
        ("빅뱅", "BIGBANG"), ("BIGBANG", "BIGBANG"),
        ("(G)I-DLE", "(G)I-DLE"), ("여자아이들", "(G)I-DLE"),
        ("아일릿", "ILLIT"), ("ILLIT", "ILLIT"),
        ("KISS OF LIFE", "KISS OF LIFE"),
        ("BABYMONSTER", "BABYMONSTER"), ("베이비몬스터", "BABYMONSTER"),
        ("아이유", "IU"),
        ("태연", "TAEYEON"), ("TAEYEON", "TAEYEON"),
        ("정국", "JUNG KOOK"), ("JUNG KOOK", "JUNG KOOK"), ("JUNGKOOK", "JUNG KOOK"),
        ("지민", "JIMIN"), ("JIMIN", "JIMIN")
    ]

    static func firstMatch(in text: String) -> String? {
        let sorted = aliases.sorted { $0.match.count > $1.match.count }
        for item in sorted {
            if text.range(of: item.match, options: .caseInsensitive) != nil {
                return item.display
            }
        }
        return nil
    }
}

// MARK: - Venue DB

struct KnownVenue {
    let name: String
    let aliases: [String]
    let city: String
    let country: String
    let lat: Double
    let lng: Double
}

enum VenueDB {
    static let venues: [KnownVenue] = [
        .init(name: "Tokyo Dome", aliases: ["도쿄돔", "東京ドーム"],
              city: "Tokyo", country: "Japan", lat: 35.7056, lng: 139.7519),
        .init(name: "Tokyo Dome City Hall", aliases: [],
              city: "Tokyo", country: "Japan", lat: 35.7038, lng: 139.7553),
        .init(name: "Saitama Super Arena", aliases: ["사이타마 슈퍼 아레나", "さいたまスーパーアリーナ"],
              city: "Saitama", country: "Japan", lat: 35.8952, lng: 139.6302),
        .init(name: "Ajinomoto Stadium", aliases: ["아지노모토 스타디움", "味の素スタジアム"],
              city: "Tokyo", country: "Japan", lat: 35.6643, lng: 139.5269),
        .init(name: "Kyocera Dome Osaka", aliases: ["교세라돔", "京セラドーム", "Kyocera Dome"],
              city: "Osaka", country: "Japan", lat: 34.6668, lng: 135.4767),
        .init(name: "Osaka-jō Hall", aliases: ["오사카성홀", "大阪城ホール"],
              city: "Osaka", country: "Japan", lat: 34.6874, lng: 135.5352),
        .init(name: "Nagoya Dome", aliases: ["나고야돔", "バンテリンドーム"],
              city: "Nagoya", country: "Japan", lat: 35.1867, lng: 136.9468),
        .init(name: "Fukuoka PayPay Dome", aliases: ["후쿠오카돔", "福岡ドーム"],
              city: "Fukuoka", country: "Japan", lat: 33.5953, lng: 130.3617),
        .init(name: "KSPO Dome", aliases: ["올림픽체조경기장", "KSPO DOME", "케이스포돔"],
              city: "Seoul", country: "Korea, Republic of", lat: 37.5200, lng: 127.0730),
        .init(name: "Gocheok Sky Dome", aliases: ["고척스카이돔", "고척 스카이돔"],
              city: "Seoul", country: "Korea, Republic of", lat: 37.4981, lng: 126.8672),
        .init(name: "Inspire Arena", aliases: ["인스파이어 아레나"],
              city: "Incheon", country: "Korea, Republic of", lat: 37.4464, lng: 126.4567),
        .init(name: "Jamsil Arena", aliases: ["잠실실내체육관", "잠실 실내체육관"],
              city: "Seoul", country: "Korea, Republic of", lat: 37.5156, lng: 127.0734),
        .init(name: "Goyang Stadium", aliases: ["고양종합운동장"],
              city: "Goyang", country: "Korea, Republic of", lat: 37.6502, lng: 126.7706),
        .init(name: "O2 Arena", aliases: ["The O2", "오투 아레나"],
              city: "London", country: "United Kingdom", lat: 51.5030, lng: 0.0032),
        .init(name: "Wembley Stadium", aliases: ["웸블리"],
              city: "London", country: "United Kingdom", lat: 51.5560, lng: -0.2795),
        .init(name: "Madison Square Garden", aliases: ["MSG", "매디슨 스퀘어 가든"],
              city: "New York", country: "United States", lat: 40.7505, lng: -73.9934),
        .init(name: "Kia Forum", aliases: ["The Forum", "포럼"],
              city: "Los Angeles", country: "United States", lat: 33.9581, lng: -118.3417),
        .init(name: "SoFi Stadium", aliases: ["소파이 스타디움"],
              city: "Los Angeles", country: "United States", lat: 33.9535, lng: -118.3392),
        .init(name: "BMO Stadium", aliases: ["비엠오 스타디움"],
              city: "Los Angeles", country: "United States", lat: 34.0129, lng: -118.2855),
        .init(name: "Allegiant Stadium", aliases: ["얼리전트 스타디움"],
              city: "Las Vegas", country: "United States", lat: 36.0908, lng: -115.1831),
        .init(name: "Accor Arena", aliases: ["AccorHotels Arena", "아코르 아레나", "베르시"],
              city: "Paris", country: "France", lat: 48.8386, lng: 2.3783),
        .init(name: "Mercedes-Benz Arena", aliases: ["메르세데스 벤츠 아레나"],
              city: "Berlin", country: "Germany", lat: 52.5084, lng: 13.4430),
        .init(name: "Impact Arena", aliases: ["임팩트 아레나"],
              city: "Bangkok", country: "Thailand", lat: 13.9066, lng: 100.5687),
        .init(name: "Singapore National Stadium", aliases: ["싱가포르 내셔널 스타디움", "National Stadium"],
              city: "Singapore", country: "Singapore", lat: 1.3048, lng: 103.8753),
        .init(name: "Singapore Indoor Stadium", aliases: ["싱가포르 인도어 스타디움"],
              city: "Singapore", country: "Singapore", lat: 1.3018, lng: 103.8744)
    ]

    static func firstMatch(in text: String) -> KnownVenue? {
        let sorted = venues.sorted { $0.name.count > $1.name.count }
        for v in sorted {
            for name in [v.name] + v.aliases where !name.isEmpty {
                if text.range(of: name, options: .caseInsensitive) != nil {
                    return v
                }
            }
        }
        return nil
    }
}

// MARK: - City DB

struct KnownCity {
    let name: String
    let aliases: [String]
    let country: String
    let lat: Double
    let lng: Double
}

enum CityDB {
    static let cities: [KnownCity] = [
        .init(name: "Tokyo", aliases: ["도쿄", "東京"], country: "Japan", lat: 35.6762, lng: 139.6503),
        .init(name: "Osaka", aliases: ["오사카", "大阪"], country: "Japan", lat: 34.6937, lng: 135.5023),
        .init(name: "Kyoto", aliases: ["교토", "京都"], country: "Japan", lat: 35.0116, lng: 135.7681),
        .init(name: "Fukuoka", aliases: ["후쿠오카", "福岡"], country: "Japan", lat: 33.5902, lng: 130.4017),
        .init(name: "Sapporo", aliases: ["삿포로", "札幌"], country: "Japan", lat: 43.0618, lng: 141.3545),
        .init(name: "Okinawa", aliases: ["오키나와", "沖縄"], country: "Japan", lat: 26.2124, lng: 127.6792),
        .init(name: "Nagoya", aliases: ["나고야", "名古屋"], country: "Japan", lat: 35.1815, lng: 136.9066),
        .init(name: "Yufuin", aliases: ["유후인", "由布院"], country: "Japan", lat: 33.2653, lng: 131.3596),
        .init(name: "Oita", aliases: ["오이타", "大分"], country: "Japan", lat: 33.2382, lng: 131.6126),
        .init(name: "Beppu", aliases: ["벳푸", "別府"], country: "Japan", lat: 33.2797, lng: 131.5010),
        .init(name: "Hiroshima", aliases: ["히로시마", "広島"], country: "Japan", lat: 34.3853, lng: 132.4553),
        .init(name: "Seoul", aliases: ["서울"], country: "Korea, Republic of", lat: 37.5665, lng: 126.9780),
        .init(name: "Busan", aliases: ["부산"], country: "Korea, Republic of", lat: 35.1796, lng: 129.0756),
        .init(name: "Jeju", aliases: ["제주"], country: "Korea, Republic of", lat: 33.4996, lng: 126.5312),
        .init(name: "Incheon", aliases: ["인천"], country: "Korea, Republic of", lat: 37.4563, lng: 126.7052),
        .init(name: "Goyang", aliases: ["고양"], country: "Korea, Republic of", lat: 37.6584, lng: 126.8320),
        .init(name: "Bangkok", aliases: ["방콕"], country: "Thailand", lat: 13.7563, lng: 100.5018),
        .init(name: "Phuket", aliases: ["푸켓"], country: "Thailand", lat: 7.8804, lng: 98.3923),
        .init(name: "Chiang Mai", aliases: ["치앙마이"], country: "Thailand", lat: 18.7883, lng: 98.9853),
        .init(name: "Singapore", aliases: ["싱가포르"], country: "Singapore", lat: 1.3521, lng: 103.8198),
        .init(name: "Hanoi", aliases: ["하노이"], country: "Vietnam", lat: 21.0285, lng: 105.8542),
        .init(name: "Ho Chi Minh City", aliases: ["호치민", "호찌민"], country: "Vietnam", lat: 10.8231, lng: 106.6297),
        .init(name: "Da Nang", aliases: ["다낭"], country: "Vietnam", lat: 16.0544, lng: 108.2022),
        .init(name: "Bali", aliases: ["발리", "Denpasar", "덴파사르"], country: "Indonesia", lat: -8.4095, lng: 115.1889),
        .init(name: "Manila", aliases: ["마닐라"], country: "Philippines", lat: 14.5995, lng: 120.9842),
        .init(name: "Cebu", aliases: ["세부"], country: "Philippines", lat: 10.3157, lng: 123.8854),
        .init(name: "Taipei", aliases: ["타이베이", "台北"], country: "Taiwan", lat: 25.0330, lng: 121.5654),
        .init(name: "London", aliases: ["런던"], country: "United Kingdom", lat: 51.5074, lng: -0.1278),
        .init(name: "Paris", aliases: ["파리"], country: "France", lat: 48.8566, lng: 2.3522),
        .init(name: "Rome", aliases: ["로마"], country: "Italy", lat: 41.9028, lng: 12.4964),
        .init(name: "Barcelona", aliases: ["바르셀로나"], country: "Spain", lat: 41.3851, lng: 2.1734),
        .init(name: "Madrid", aliases: ["마드리드"], country: "Spain", lat: 40.4168, lng: -3.7038),
        .init(name: "Amsterdam", aliases: ["암스테르담"], country: "Netherlands", lat: 52.3676, lng: 4.9041),
        .init(name: "Berlin", aliases: ["베를린"], country: "Germany", lat: 52.5200, lng: 13.4050),
        .init(name: "New York", aliases: ["뉴욕", "NYC"], country: "United States", lat: 40.7128, lng: -74.0060),
        .init(name: "Los Angeles", aliases: ["로스앤젤레스"], country: "United States", lat: 34.0522, lng: -118.2437),
        .init(name: "Las Vegas", aliases: ["라스베이거스"], country: "United States", lat: 36.1699, lng: -115.1398),
        .init(name: "San Francisco", aliases: ["샌프란시스코"], country: "United States", lat: 37.7749, lng: -122.4194),
        .init(name: "Honolulu", aliases: ["호놀룰루"], country: "United States", lat: 21.3069, lng: -157.8583),
        .init(name: "Guam", aliases: ["괌"], country: "United States", lat: 13.4443, lng: 144.7937),
        .init(name: "Dubai", aliases: ["두바이"], country: "United Arab Emirates", lat: 25.2048, lng: 55.2708),
        .init(name: "Istanbul", aliases: ["이스탄불"], country: "Turkey", lat: 41.0082, lng: 28.9784)
    ]

    static func firstMatch(in text: String) -> KnownCity? {
        let sorted = cities.sorted { $0.name.count > $1.name.count }
        for c in sorted {
            for name in [c.name] + c.aliases where !name.isEmpty {
                if text.range(of: name, options: .caseInsensitive) != nil {
                    return c
                }
            }
        }
        return nil
    }

    static func coordinates(for name: String) -> (Double, Double)? {
        cities.first { $0.name == name }.map { ($0.lat, $0.lng) }
    }
}

// MARK: - Date extractor

enum DateExtractor {
    static func firstDate(in text: String) -> Date? {
        let patterns: [String] = [
            // 2026-06-15, 2026.06.15, 2026/06/15 [+ HH:mm]
            #"(\d{4})[-./](\d{1,2})[-./](\d{1,2})(?:[^\d]+(\d{1,2}):(\d{2}))?"#,
            // 2026년 6월 15일 [19시 30분]
            #"(\d{4})\s*년\s*(\d{1,2})\s*월\s*(\d{1,2})\s*일(?:[^\d]+(\d{1,2})\s*시(?:\s*(\d{1,2})\s*분)?)?"#,
            // 2026年6月15日
            #"(\d{4})\s*年\s*(\d{1,2})\s*月\s*(\d{1,2})\s*日"#
        ]
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Seoul")!

        for pat in patterns {
            guard let re = try? NSRegularExpression(pattern: pat) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            guard let match = re.firstMatch(in: text, range: range) else { continue }

            func captureInt(at idx: Int) -> Int? {
                guard match.numberOfRanges > idx,
                      let r = Range(match.range(at: idx), in: text) else { return nil }
                return Int(text[r].trimmingCharacters(in: .whitespaces))
            }

            guard let y = captureInt(at: 1),
                  let mo = captureInt(at: 2),
                  let d = captureInt(at: 3),
                  y >= 2020, y <= 2099,
                  mo >= 1, mo <= 12,
                  d >= 1, d <= 31
            else { continue }

            var comps = DateComponents()
            comps.year = y
            comps.month = mo
            comps.day = d
            comps.hour = captureInt(at: 4) ?? 19
            comps.minute = captureInt(at: 5) ?? 0

            if let date = cal.date(from: comps) {
                return date
            }
        }
        return nil
    }
}

// MARK: - Errors

enum TripParsingError: Error, LocalizedError {
    case imageDecoding
    case badResponse

    var errorDescription: String? {
        switch self {
        case .imageDecoding: return "Couldn't read that image."
        case .badResponse:   return "Couldn't parse the response."
        }
    }
}
