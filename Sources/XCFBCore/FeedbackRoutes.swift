import Foundation

public enum FeedbackRoutes {
    public static let appBundleIdentifier = "com.apple.appleseed.FeedbackAssistant"
    public static let webBase = "https://feedbackassistant.apple.com"

    public static let known: [String: String] = [
        "inbox": "/",
        "new": "/new",
        "welcome": "/welcome",
        "feedback": "/feedback/{id}",
        "draft": "/draft/{id}",
        "survey": "/survey/{id}",
        "announcement": "/announcement/{id}",
        "form-response": "/form-response/{id}",
        "survey-feedback": "/survey-feedback/{id}"
    ]

    public static func url(for route: String, id: String? = nil) throws -> URL {
        guard var path = known[route] else {
            throw XCFBError.invalidArgument("Unknown route: \(route)")
        }
        if path.contains("{id}") {
            guard let id, !id.isEmpty else {
                throw XCFBError.invalidArgument("\(route) requires --id")
            }
            path = path.replacingOccurrences(of: "{id}", with: id)
        }
        guard let url = URL(string: webBase + path) else {
            throw XCFBError.invalidArgument("Could not build Feedback Assistant URL")
        }
        return url
    }
}
