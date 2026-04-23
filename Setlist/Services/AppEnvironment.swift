import Foundation

// Tiny service locator. Keys come from, in order:
//   1. Bundle/Secrets.plist (auto-generated at build time from the macOS
//      Keychain by the "Generate Secrets.plist from Keychain" build phase).
//   2. ProcessInfo.processInfo.environment (Xcode scheme env vars — useful
//      when running the app with a key you don't want persisted to disk).
//   3. Info.plist (for anyone who wants to wire up xcconfig by hand).
// Missing keys fall through to empty strings, which keeps each service in
// mock-data mode. That's why the UI flow works end-to-end with zero setup.

enum AppEnvironment {
    static var anthropicAPIKey: String {
        resolveKey(
            secretsKey: "AnthropicAPIKey",
            envVar: "ANTHROPIC_API_KEY",
            infoKey: "AnthropicAPIKey"
        )
    }
    static var mrtAPIKey: String {
        resolveKey(
            secretsKey: "MRTAPIKey",
            envVar: "MRT_API_KEY",
            infoKey: "MRTAPIKey"
        )
    }

    static var useMockAI: Bool { anthropicAPIKey.isEmpty }
    static var useMockMRT: Bool { mrtAPIKey.isEmpty }

    static let aiParser: AIParsingServiceProtocol = AIParsingService(
        anthropicAPIKey: anthropicAPIKey,
        mcpServerURL: URL(string: "https://mcp-servers.myrealtrip.com/mcp"),
        useMockData: useMockAI
    )

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
