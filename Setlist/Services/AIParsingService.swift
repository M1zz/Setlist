import Foundation
import UIKit

// Parses user inputs (pasted URLs, uploaded ticket images) into structured
// trip intents via Claude. For production, proxy this through your own
// backend rather than embedding the Anthropic key in the iOS binary.

protocol AIParsingServiceProtocol {
    func parseContentLink(_ url: URL) async throws -> ContentSource
    func parseConcertTicket(image: UIImage) async throws -> ConcertSource
    func parseConcertTicket(rawText: String) async throws -> ConcertSource
}

struct AIParsingService: AIParsingServiceProtocol {
    let anthropicAPIKey: String
    let mcpServerURL: URL?
    let useMockData: Bool

    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let model = "claude-sonnet-4-6"

    init(
        anthropicAPIKey: String,
        mcpServerURL: URL? = nil,
        useMockData: Bool = true
    ) {
        self.anthropicAPIKey = anthropicAPIKey
        self.mcpServerURL = mcpServerURL
        self.useMockData = useMockData
    }

    // MARK: - Public API

    func parseContentLink(_ url: URL) async throws -> ContentSource {
        if useMockData {
            return ContentSource(
                originalURL: url,
                detectedPlaceName: "Yufuin Onsen Ryokan",
                detectedCity: "Yufuin",
                detectedCountry: "Japan",
                detectedLatitude: 33.2653,
                detectedLongitude: 131.3596,
                caption: "Hidden ryokan in Oita prefecture"
            )
        }
        let prompt = """
        A user pasted this URL from Instagram, TikTok, or YouTube: \(url.absoluteString)

        Fetch the page and extract a JSON object with these keys exactly:
        - detectedPlaceName (string or null): specific venue, hotel, or landmark if mentioned
        - detectedCity (string): city name
        - detectedCountry (string): country name
        - detectedLatitude (number or null): best coordinate estimate
        - detectedLongitude (number or null)
        - caption (string or null): original caption if visible

        Respond with ONLY the JSON object. No markdown, no prose.
        """
        let raw = try await callClaude(prompt: prompt, useWebFetch: true)
        let data = Data(raw.utf8)
        let partial = try JSONDecoder.setlist.decode(PartialContentSource.self, from: data)
        return ContentSource(
            originalURL: url,
            detectedPlaceName: partial.detectedPlaceName,
            detectedCity: partial.detectedCity,
            detectedCountry: partial.detectedCountry,
            detectedLatitude: partial.detectedLatitude,
            detectedLongitude: partial.detectedLongitude,
            caption: partial.caption
        )
    }

    func parseConcertTicket(image: UIImage) async throws -> ConcertSource {
        if useMockData {
            return sampleConcert()
        }
        guard let jpeg = image.jpegData(compressionQuality: 0.85) else {
            throw AIParsingError.imageEncoding
        }
        let prompt = """
        This is a concert or live event ticket. Extract a JSON object:
        {
          "artist": string,
          "venueName": string,
          "venueLatitude": number,
          "venueLongitude": number,
          "city": string,
          "country": string,
          "showDate": ISO-8601 string with timezone
        }

        Use your knowledge to fill venue coordinates. Respond with ONLY the JSON.
        """
        let raw = try await callClaudeVision(
            prompt: prompt,
            imageBase64: jpeg.base64EncodedString()
        )
        return try decodeConcert(from: raw)
    }

    func parseConcertTicket(rawText: String) async throws -> ConcertSource {
        if useMockData {
            return sampleConcert()
        }
        let prompt = """
        Extract concert info from this text and respond with ONLY a JSON object
        matching keys artist, venueName, venueLatitude, venueLongitude, city,
        country, showDate (ISO-8601 with timezone). Use your knowledge for
        venue coordinates.

        TEXT:
        \(rawText)
        """
        let raw = try await callClaude(prompt: prompt, useWebFetch: false)
        return try decodeConcert(from: raw)
    }

    // MARK: - Internals

    private func sampleConcert() -> ConcertSource {
        ConcertSource(
            artist: "BTS",
            venueName: "Tokyo Dome",
            venueLatitude: 35.7056,
            venueLongitude: 139.7519,
            city: "Tokyo",
            country: "Japan",
            showDate: Date().addingTimeInterval(86400 * 45)
        )
    }

    private func decodeConcert(from json: String) throws -> ConcertSource {
        guard let data = json.data(using: .utf8) else { throw AIParsingError.badResponse }
        return try JSONDecoder.setlist.decode(ConcertSource.self, from: data)
    }

    private func callClaude(prompt: String, useWebFetch: Bool) async throws -> String {
        var body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "messages": [["role": "user", "content": prompt]]
        ]
        if useWebFetch {
            body["tools"] = [["type": "web_search_20250305", "name": "web_search"]]
        }
        return try await performAnthropicCall(body: body)
    }

    private func callClaudeVision(prompt: String, imageBase64: String) async throws -> String {
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "image",
                     "source": ["type": "base64", "media_type": "image/jpeg", "data": imageBase64]],
                    ["type": "text", "text": prompt]
                ]
            ]]
        ]
        return try await performAnthropicCall(body: body)
    }

    private func performAnthropicCall(body: [String: Any]) async throws -> String {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue(anthropicAPIKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: req)
        let decoded = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        let text = decoded.content
            .compactMap { $0.text }
            .joined(separator: "\n")
        return text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum AIParsingError: Error {
    case imageEncoding
    case badResponse
}

private struct AnthropicResponse: Decodable {
    let content: [Block]
    struct Block: Decodable {
        let type: String
        let text: String?
    }
}

private struct PartialContentSource: Decodable {
    let detectedPlaceName: String?
    let detectedCity: String
    let detectedCountry: String
    let detectedLatitude: Double?
    let detectedLongitude: Double?
    let caption: String?
}
