import Foundation
import Testing
@testable import XCFBCore

private struct CategoryExpectation {
    var title: String
    var description: String
    var topic: String
    var tat: String
    var area: String
    var classification: String
}

@Test func xcodeBundleMapsToDeveloperTools() {
    let inferer = FeedbackCategoryInferer(bundleMappingPath: "/missing")
    let category = inferer.infer(
        title: "Xcode preview does not update",
        description: "Simulator and XCTest are involved.",
        bundleID: nil
    )

    #expect(category.topic == "Developer Tools & Resources")
    #expect(category.area == "Xcode")
    #expect(category.classification == "seedx:xcode")
}

@Test func bundleMappingUsesCuratedAreaNames() throws {
    let mapping = """
    {
      "com.apple.Safari": "seedx:safari",
      "com.apple.dt.Xcode": "seedx:xcode"
    }
    """
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("json")
    try mapping.write(to: url, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: url) }

    let inferer = FeedbackCategoryInferer(bundleMappingPath: url.path)
    let safari = inferer.infer(title: "Generic crash", bundleID: "com.apple.Safari")
    let xcode = inferer.infer(title: "Generic crash", bundleID: "com.apple.dt.Xcode")

    #expect(safari.topic == "macOS")
    #expect(safari.area == "Safari")
    #expect(safari.classification == "seedx:safari")
    #expect(xcode.topic == "Developer Tools & Resources")
    #expect(xcode.area == "Xcode")
    #expect(xcode.classification == "seedx:xcode")
}

@Test func fallbackIsMacOS() {
    let inferer = FeedbackCategoryInferer(bundleMappingPath: "/missing")
    let category = inferer.infer(title: "Something weird", description: "No known words here.")

    #expect(category.topic == "macOS")
    #expect(category.classification == "public.macos")
}

@Test func foundationModelsMapsToSpecificFrameworkArea() {
    let inferer = FeedbackCategoryInferer(bundleMappingPath: "/missing")
    let category = inferer.infer(
        title: "Foundation Models framework should accept video input",
        description: "LanguageModel and tool calling should support temporal media."
    )

    #expect(category.topic == "Developer Technologies & SDKs")
    #expect(category.tat == "dev.tech")
    #expect(category.area == "Foundation Models Framework")
    #expect(category.classification == "seed:foundationmodelsframework")
}

@Test func appStoreConnectMapsToDeveloperToolsArea() {
    let inferer = FeedbackCategoryInferer(bundleMappingPath: "/missing")
    let category = inferer.infer(
        title: "App Store Connect API returns an unexpected relationship error",
        description: "The App Store Connect API response is missing expected build data."
    )

    #expect(category.topic == "Developer Tools & Resources")
    #expect(category.tat == "developertools.fba")
    #expect(category.area == "App Store Connect API")
    #expect(category.classification == "seed:appstoreconnectAPI")
}

@Test func swiftUIMapsToDeveloperTechnologyArea() {
    let inferer = FeedbackCategoryInferer(bundleMappingPath: "/missing")
    let category = inferer.infer(
        title: "SwiftUI sheet dismisses immediately",
        description: "A SwiftUI presentation regression occurs on macOS."
    )

    #expect(category.topic == "Developer Technologies & SDKs")
    #expect(category.area == "SwiftUI")
    #expect(category.classification == "seed:swiftui")
}

@Test func safariMapsToMacOSArea() {
    let inferer = FeedbackCategoryInferer(bundleMappingPath: "/missing")
    let category = inferer.infer(
        title: "Safari tab groups disappear after relaunch",
        description: "The issue reproduces on macOS."
    )

    #expect(category.topic == "macOS")
    #expect(category.tat == "public.macos")
    #expect(category.area == "Safari")
    #expect(category.classification == "seedx:safari")
}

@Test func topLevelPlatformFormsMapToTheirTats() {
    let cases = [
        CategoryExpectation(
            title: "iPhone notification summary is wrong",
            description: "This reproduces on iOS 26.",
            topic: "iOS & iPadOS",
            tat: "public.ios",
            area: "Something else not on this list",
            classification: "public.ios"
        ),
        CategoryExpectation(
            title: "Apple Watch complication does not refresh",
            description: "The issue appears on watchOS.",
            topic: "watchOS",
            tat: "watchos.public",
            area: "Something else not on this list",
            classification: "watchos.public"
        ),
        CategoryExpectation(
            title: "Apple TV app layout clips focus rings",
            description: "The issue reproduces on tvOS.",
            topic: "tvOS",
            tat: "tvos.public",
            area: "Something else not on this list",
            classification: "tvos.public"
        ),
        CategoryExpectation(
            title: "Vision Pro window ornaments flicker",
            description: "The issue reproduces on visionOS.",
            topic: "visionOS",
            tat: "public.visionOS",
            area: "Something else not on this list",
            classification: "public.visionOS"
        )
    ]

    assertCategories(cases)
}

@Test func topLevelSpecialFormsMapToTheirTats() {
    let cases = [
        CategoryExpectation(
            title: "AirPods firmware audio drops during calls",
            description: "The issue reproduces on AirPods beta firmware.",
            topic: "AirPods Beta Firmware",
            tat: "airpods",
            area: "Something else not on this list",
            classification: "airpods"
        ),
        CategoryExpectation(
            title: "HomePod stereo pair loses sync",
            description: "HomePod audio briefly desynchronizes.",
            topic: "HomePod",
            tat: ":B238",
            area: "Something else not on this list",
            classification: ":B238"
        ),
        CategoryExpectation(
            title: "MDM payload fails for managed devices",
            description: "Device management configuration is rejected.",
            topic: "Enterprise & Education",
            tat: "ent.edu",
            area: "Something else not on this list",
            classification: "ent.edu"
        ),
        CategoryExpectation(
            title: "MFi accessory certification tool rejects valid metadata",
            description: "The external accessory certification flow fails.",
            topic: "MFi Technologies",
            tat: "mfi",
            area: "Something else not on this list",
            classification: "mfi"
        ),
        CategoryExpectation(
            title: "DMA interoperability request for EU distribution",
            description: "The app needs interoperability in the European Union.",
            topic: "DMA Interoperability",
            tat: "interop",
            area: "Something else not on this list",
            classification: "interop"
        )
    ]

    assertCategories(cases)
}

@Test func specificRoutesBeatGenericPlatformWords() {
    let cases = [
        CategoryExpectation(
            title: "App Store Connect API fails on macOS",
            description: "The API returns an unexpected payload.",
            topic: "Developer Tools & Resources",
            tat: "developertools.fba",
            area: "App Store Connect API",
            classification: "seed:appstoreconnectAPI"
        ),
        CategoryExpectation(
            title: "ScreenCaptureKit recording drops frames on macOS",
            description: "The framework regression appears on desktop.",
            topic: "Developer Technologies & SDKs",
            tat: "dev.tech",
            area: "ScreenCaptureKit",
            classification: "seed:screencapturekit"
        ),
        CategoryExpectation(
            title: "WKWebView crashes while loading a WebKit test page",
            description: "This is a WebKit integration issue in an app.",
            topic: "Developer Technologies & SDKs",
            tat: "dev.tech",
            area: "WebKit",
            classification: "seed:webkit"
        )
    ]

    assertCategories(cases)
}

private func assertCategories(_ cases: [CategoryExpectation]) {
    let inferer = FeedbackCategoryInferer(bundleMappingPath: "/missing")

    for expected in cases {
        let category = inferer.infer(title: expected.title, description: expected.description)
        #expect(category.topic == expected.topic)
        #expect(category.tat == expected.tat)
        #expect(category.area == expected.area)
        #expect(category.classification == expected.classification)
    }
}
