import Foundation

// Search the public Openverse API for commercially-usable images. No API key
// required. Aggregates Wikimedia Commons, Flickr (CC), and other open-license
// sources. We restrict to cc0, by, and by-sa — all permit commercial use.

struct OpenverseImage: Hashable, Sendable {
    let url: URL              // Full-resolution image
    let thumbnailURL: URL     // Cached smaller version served by Openverse
    let width: Int
    let height: Int
    let title: String
    let creator: String?
    let licenseLabel: String  // "CC BY 3.0" etc.
    let licenseURL: URL?
    let attribution: String   // Full attribution string Openverse generates
    let foreignLandingURL: URL?
}

actor OpenverseClient {
    static let shared = OpenverseClient()

    private let baseURL = URL(string: "https://api.openverse.org/v1")!
    private let session: URLSession
    private var cache: [String: OpenverseImage] = [:]
    private var inFlight: [String: Task<OpenverseImage?, Never>] = [:]
    private var failed: Set<String> = []

    init(session: URLSession = .shared) {
        self.session = session
    }

    func image(forTopic topic: String) async -> OpenverseImage? {
        let key = topic.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if key.isEmpty { return nil }
        if let cached = cache[key] { return cached }
        if failed.contains(key) { return nil }
        if let existing = inFlight[key] { return await existing.value }

        let task = Task<OpenverseImage?, Never> { [topic = key] in
            do {
                return try await self.search(query: topic)
            } catch {
                return nil
            }
        }
        inFlight[key] = task
        let result = await task.value
        inFlight.removeValue(forKey: key)
        if let r = result {
            cache[key] = r
        } else {
            failed.insert(key)
        }
        return result
    }

    private func search(query: String) async throws -> OpenverseImage? {
        var comps = URLComponents(url: baseURL.appendingPathComponent("images/"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "page_size", value: "5"),
            URLQueryItem(name: "license", value: "cc0,by,by-sa"),
            URLQueryItem(name: "filter_dead", value: "true"),
            URLQueryItem(name: "mature", value: "false")
        ]
        guard let url = comps.url else { return nil }

        var req = URLRequest(url: url)
        req.timeoutInterval = 6
        req.setValue("Setlist/1.0 (com.devkoan.setlist)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil
        }
        let decoded = try JSONDecoder().decode(OpenverseSearchResponse.self, from: data)

        // Pick the first landscape-ish result so the framing fits hero areas.
        let preferred = decoded.results.first { ($0.width ?? 0) >= ($0.height ?? 1) }
            ?? decoded.results.first
        guard let raw = preferred,
              let imageURL = URL(string: raw.url),
              let thumbURL = URL(string: raw.thumbnail ?? raw.url)
        else { return nil }

        return OpenverseImage(
            url: imageURL,
            thumbnailURL: thumbURL,
            width: raw.width ?? 0,
            height: raw.height ?? 0,
            title: raw.title ?? "",
            creator: raw.creator,
            licenseLabel: licenseLabel(code: raw.license, version: raw.licenseVersion),
            licenseURL: raw.licenseUrl.flatMap(URL.init(string:)),
            attribution: raw.attribution ?? "",
            foreignLandingURL: raw.foreignLandingUrl.flatMap(URL.init(string:))
        )
    }

    private func licenseLabel(code: String?, version: String?) -> String {
        guard let code = code, !code.isEmpty else { return "" }
        let prefix = code.uppercased() == "CC0" ? "CC0" : "CC \(code.uppercased())"
        if let v = version, !v.isEmpty { return "\(prefix) \(v)" }
        return prefix
    }
}

private struct OpenverseSearchResponse: Decodable {
    let resultCount: Int?
    let results: [Result]

    enum CodingKeys: String, CodingKey {
        case resultCount = "result_count"
        case results
    }

    struct Result: Decodable {
        let id: String
        let title: String?
        let url: String
        let thumbnail: String?
        let width: Int?
        let height: Int?
        let creator: String?
        let creatorUrl: String?
        let license: String?
        let licenseVersion: String?
        let licenseUrl: String?
        let attribution: String?
        let foreignLandingUrl: String?

        enum CodingKeys: String, CodingKey {
            case id, title, url, thumbnail, width, height, creator, license, attribution
            case creatorUrl = "creator_url"
            case licenseVersion = "license_version"
            case licenseUrl = "license_url"
            case foreignLandingUrl = "foreign_landing_url"
        }
    }
}
