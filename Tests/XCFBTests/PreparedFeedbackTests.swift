import Foundation
import Testing
@testable import XCFBCore

@Test func preparedFeedbackBuildsFeedbackAssistantURL() throws {
    let category = FeedbackCategory(
        topic: "Developer Tools & Resources",
        tat: "developertools.fba",
        area: "Xcode",
        classification: "seedx:xcode",
        reason: "test"
    )

    let payload = try PreparedFeedback(
        title: "Canvas fails after rename",
        description: "Steps, expected result, actual result.",
        snapshot: "/tmp/snapshot.png",
        bundleID: "com.apple.dt.Xcode",
        kind: .bug,
        category: category,
        platform: "macOS"
    )

    let components = try #require(URLComponents(string: payload.url))
    #expect(components.scheme == "https")
    #expect(components.host == "feedbackassistant.apple.com")
    #expect(components.path == "/new")

    let queryItems = Dictionary(
        uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }
    )
    #expect(queryItems["title"] == "Canvas fails after rename")
    #expect(queryItems["description"] == "Steps, expected result, actual result.")
    #expect(queryItems["classification"] == "seedx:xcode")
    #expect(queryItems["area"] == "Xcode")
    #expect(queryItems["path"] == "/tmp/snapshot.png")
    #expect(payload.platform == "macOS")
}

@Test func routeWithIDReplacesPlaceholder() throws {
    let url = try FeedbackRoutes.url(for: "feedback", id: "123456")
    #expect(url.absoluteString == "https://feedbackassistant.apple.com/feedback/123456")
}

@Test func platformInfererRecognizesApplePlatformNames() {
    let inferer = FeedbackPlatformInferer()

    #expect(inferer.infer(title: "Backport this picker to iOS 18") == "iOS")
    #expect(inferer.infer(title: "Fix this on iPadOS") == "iPadOS")
    #expect(inferer.infer(title: "Mac Catalyst presentation issue") == "Mac Catalyst")
    #expect(FeedbackPlatformInferer.normalize("ios") == "iOS")
    #expect(FeedbackPlatformInferer.normalize("Windows") == nil)
}

@Test func preparedFeedbackDecodesPayloadsWithoutPlatform() throws {
    let category = FeedbackCategory(
        topic: "Developer Technologies & SDKs",
        tat: "dev.tech",
        area: "MusicKit",
        classification: "seed:musickit",
        reason: "test"
    )
    let payload = try PreparedFeedback(
        title: "Music picker",
        description: "Backport to iOS 18.",
        snapshot: nil,
        bundleID: nil,
        kind: .suggestion,
        category: category,
        platform: "iOS"
    )
    let encoded = try JSONEncoder().encode(payload)
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object.removeValue(forKey: "platform")

    let legacyData = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(PreparedFeedback.self, from: legacyData)

    #expect(decoded.platform == nil)
    #expect(decoded.category.area == "MusicKit")
}

@Test func routeWithMissingIDThrows() {
    #expect(throws: XCFBError.self) {
        try FeedbackRoutes.url(for: "feedback")
    }
}
