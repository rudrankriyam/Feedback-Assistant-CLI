import Foundation

public struct FeedbackPlatformInferer {
    public static let supportedPlatforms = [
        "iOS",
        "iPadOS",
        "Mac Catalyst",
        "macOS",
        "tvOS",
        "visionOS",
        "watchOS",
        "Web & Services"
    ]

    public init() {}

    public func infer(title: String, description: String = "") -> String? {
        let haystack = "\(title)\n\(description)".lowercased()
        let rules: [(platform: String, keywords: [String])] = [
            ("Mac Catalyst", ["mac catalyst", "maccatalyst"]),
            ("iPadOS", ["ipados", "ipad"]),
            ("iOS", ["ios", "iphone"]),
            ("visionOS", ["visionos", "vision pro", "visionpro"]),
            ("watchOS", ["watchos", "apple watch"]),
            ("tvOS", ["tvos", "apple tv"]),
            ("macOS", ["macos"]),
            ("Web & Services", ["web & services", "web service"])
        ]

        return rules.first { rule in
            rule.keywords.contains { haystack.contains($0) }
        }?.platform
    }

    public static func normalize(_ value: String) -> String? {
        supportedPlatforms.first {
            $0.caseInsensitiveCompare(value.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
        }
    }
}
