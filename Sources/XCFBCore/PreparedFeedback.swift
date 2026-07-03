import Foundation

public enum FeedbackKind: String, Codable, CaseIterable {
    case bug
    case suggestion

    /// The Feedback Assistant label for this kind. Single source of truth
    /// shared by the native (Accessibility) flow and the web draft flow.
    public var nativeLabel: String {
        switch self {
        case .bug:
            return "Incorrect/Unexpected Behavior"
        case .suggestion:
            return "Suggestion"
        }
    }

    /// Lenient parser for user-supplied kind values, accepting the raw kind
    /// name, common shorthands, and the full Feedback Assistant label
    /// (case-insensitively).
    public init?(userInput: String) {
        switch userInput.lowercased() {
        case FeedbackKind.bug.rawValue,
            "incorrect",
            FeedbackKind.bug.nativeLabel.lowercased():
            self = .bug
        case FeedbackKind.suggestion.rawValue,
            FeedbackKind.suggestion.nativeLabel.lowercased():
            self = .suggestion
        default:
            return nil
        }
    }
}

public struct PreparedFeedback: Codable, Equatable {
    public var title: String
    public var description: String
    public var snapshot: String?
    public var bundleID: String?
    public var platform: String?
    public var kind: FeedbackKind
    public var category: FeedbackCategory
    public var url: String

    enum CodingKeys: String, CodingKey {
        case title
        case description
        case snapshot
        case bundleID = "bundle_id"
        case platform
        case kind
        case category
        case url
    }

    public init(
        title: String,
        description: String,
        snapshot: String?,
        bundleID: String?,
        kind: FeedbackKind,
        category: FeedbackCategory,
        platform: String? = nil
    ) throws {
        self.title = title
        self.description = description
        self.snapshot = snapshot
        self.bundleID = bundleID
        self.platform = platform
        self.kind = kind
        self.category = category
        self.url = try Self.buildFeedbackURL(title: title, description: description, snapshot: snapshot, category: category).absoluteString
    }

    public static func buildFeedbackURL(title: String, description: String, snapshot: String?, category: FeedbackCategory) throws -> URL {
        var components = URLComponents(string: "\(FeedbackRoutes.webBase)/new")
        components?.queryItems = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "description", value: description),
            URLQueryItem(name: "classification", value: category.classification),
            URLQueryItem(name: "area", value: category.area)
        ]

        if let snapshot, !snapshot.isEmpty {
            components?.queryItems?.append(URLQueryItem(name: "path", value: snapshot))
        }

        guard let url = components?.url else {
            throw XCFBError.invalidArgument("Could not build prepared feedback URL")
        }
        return url
    }

    public func markdown() -> String {
        """
        # \(title)

        Category: \(category.topic)
        Area: \(category.area)
        Platform: \(platform ?? "")
        Kind: \(kind.rawValue)
        Bundle ID: \(bundleID ?? "")
        Snapshot: \(snapshot ?? "")

        ## Description

        \(description)
        """
    }
}
