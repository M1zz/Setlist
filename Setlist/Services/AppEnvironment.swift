import Foundation

// Tiny service locator. The MRT key is read from, in order:
//   1. Bundle/Secrets.plist (auto-generated at build time from the macOS
//      Keychain by the "Generate Secrets.plist from Keychain" build phase).
//   2. ProcessInfo.processInfo.environment — useful when running with a key
//      you don't want persisted to disk (Xcode scheme env vars).
//   3. Info.plist (for xcconfig wiring).
// Missing key falls through to an empty string and MRTClient enters
// mock-data mode. The trip parser has no keys to resolve because all
// parsing runs on-device (Vision OCR + regex + local lookup tables).

enum AppEnvironment {
    static var mrtAPIKey: String {
        resolveKey(
            secretsKey: "MRTAPIKey",
            envVar: "MRT_API_KEY",
            infoKey: "MRTAPIKey"
        )
    }

    static var useMockMRT: Bool { mrtAPIKey.isEmpty }

    static let tripParser: TripParsingServiceProtocol = TripParsingService()

    static let mrtClient: MRTClientProtocol = MRTClient(
        apiKey: mrtAPIKey,
        useMockData: useMockMRT
    )

    // MARK: - Key resolution

    private static let secrets: [String: String] = loadSecretsPlist()

    private static func loadSecretsPlist() -> [String: String] {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return [:] }
        return plist.compactMapValues { $0 as? String }
    }

    private static func resolveKey(secretsKey: String, envVar: String, infoKey: String) -> String {
        if let fromSecrets = secrets[secretsKey], !fromSecrets.isEmpty {
            return fromSecrets
        }
        if let fromEnv = ProcessInfo.processInfo.environment[envVar], !fromEnv.isEmpty {
            return fromEnv
        }
        return Bundle.main.object(forInfoDictionaryKey: infoKey) as? String ?? ""
    }
}
