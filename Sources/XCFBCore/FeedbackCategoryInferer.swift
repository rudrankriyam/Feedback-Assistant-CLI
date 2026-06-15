import Foundation

public struct FeedbackCategory: Codable, Equatable {
    public var topic: String
    public var tat: String
    public var area: String
    public var classification: String
    public var reason: String

    public init(topic: String, tat: String, area: String, classification: String, reason: String) {
        self.topic = topic
        self.tat = tat
        self.area = area
        self.classification = classification
        self.reason = reason
    }
}

public struct FeedbackCategoryInferer {
    public static let defaultBundleMappingPath = "/System/Library/CoreServices/Applications/Feedback Assistant.app/Contents/Resources/bundle-mapping.json"

    private struct Rule {
        var topic: String
        var tat: String
        var area: String
        var classification: String
        var keywords: [String]
    }

    private let bundleMappingPath: String
    private let rules: [Rule]

    public init(bundleMappingPath: String = Self.defaultBundleMappingPath) {
        self.bundleMappingPath = bundleMappingPath
        self.rules = [
            Self.developerTechnology("Foundation Models Framework", "seed:foundationmodelsframework", ["foundation models", "foundationmodels", "language model", "generable", "tool calling"]),
            Self.developerTechnology("SwiftUI", "seed:swiftui", ["swiftui", "swift ui"]),
            Self.developerTechnology("SwiftData", "seed:swiftdata", ["swiftdata", "swift data"]),
            Self.developerTechnology("UIKit", "seed:uikit", ["uikit", "ui kit"]),
            Self.developerTechnology("AppKit", "seed:appkit", ["appkit", "app kit"]),
            Self.developerTechnology("StoreKit", "seed:storekit", ["storekit", "in-app purchase", "subscription"]),
            Self.developerTechnology("CloudKit", "seed:cloudkit", ["cloudkit", "icloud container"]),
            Self.developerTechnology("Core Data", "seed:coredata", ["core data", "coredata"]),
            Self.developerTechnology("Core ML", "seed:coreml", ["core ml", "coreml"]),
            Self.developerTechnology("AVFoundation", "seed:avfoundation", ["avfoundation", "av foundation", "camera capture"]),
            Self.developerTechnology("Vision Framework", "seed:vision", ["vision framework", "vision request", "ocr", "barcode"]),
            Self.developerTechnology("VisionKit", "seed:visionkit", ["visionkit", "vision kit", "document camera"]),
            Self.developerTechnology("ScreenCaptureKit", "seed:screencapturekit", ["screencapturekit", "screen capture kit", "screen recording"]),
            Self.developerTechnology("RealityKit", "seed:realitykit", ["realitykit", "reality kit"]),
            Self.developerTechnology("Metal", "seed:metal", ["metal", "metal shader"]),
            Self.developerTechnology("WebKit", "seed:webkit", ["webkit", "wkwebview"]),
            Self.developerTechnology("WidgetKit", "seed:widgetkit", ["widgetkit", "widget kit"]),
            Self.developerTechnology("ActivityKit", "seed:activitykit", ["activitykit", "activity kit", "live activities"]),
            Self.developerTechnology("App Intents Framework", "seed:appintents", ["app intents", "appintents"]),
            Self.developerTechnology("ExtensionKit", "seed:extensionkit", ["extensionkit", "extension kit"]),
            Self.developerTechnology("MapKit", "seed:mapkit", ["mapkit", "map kit"]),
            Self.developerTechnology("MusicKit", "seed:musickit", ["musickit", "music kit"]),
            Self.developerTechnology("WeatherKit", "seed:weatherkit", ["weatherkit", "weather kit"]),

            Self.developerTool("App Store Connect API", "seed:appstoreconnectAPI", ["app store connect api"]),
            Self.developerTool("App Store Connect", "seedADC:appstoreconnect", ["app store connect"]),
            Self.developerTool("TestFlight", "seedADC:testflight", ["testflight", "test flight"]),
            Self.developerTool("Simulator", "seedADC:simulator", ["simulator", "simctl"]),
            Self.developerTool("Instruments", "seed:instruments", ["instruments", "profiling", "time profiler"]),
            Self.developerTool("Swift Compiler", "seedADC:swiftcompiler", ["swift compiler", "compiler crash"]),
            Self.developerTool("Swift Testing Framework", "seed:swifttestingframework", ["swift testing", "testing framework"]),
            Self.developerTool("Xcode Cloud", "seedx:xcodecloud", ["xcode cloud"]),
            Self.developerTool("XCTest", "seedADC:XCtest", ["xctest", "ui test", "unit test"]),
            Self.developerTool("Xcode", "seedx:xcode", ["xcode", "preview", "canvas", "source editor", "build system"]),
            Self.developerTool("Feedback Assistant", "seedx:fba", ["feedback assistant", "feedbackassistant"]),
            Self.developerTool("Developer Documentation", "seedADC:devpubs", ["developer documentation", "documentation"]),
            Self.developerTool("DocC Documentation", "seedadc:documentationcompiler", ["docc", "documentation compiler"]),
            Self.developerTool("SF Symbols", "seed:sfsymbols", ["sf symbols", "sfsymbols"]),
            Self.developerTool("CreateML", "seedx:createML", ["createml", "create ml"]),
            Self.developerTool("Developer Certificates, Identifiers, and Profiles", "seedadc:certificates", ["certificate", "provisioning profile", "bundle id", "identifier"]),
            Self.developerTool("Developer Tools & Resources", "developertools.fba", ["developer tools"]),
            Self.developerTechnology("APIs and Frameworks", "dev.tech", ["framework", "api", "sdk"]),

            Self.macOSArea("Safari", "seedx:safari", ["safari"]),
            Self.macOSArea("Mail", "seedx:mail", ["mail"]),
            Self.macOSArea("Finder", "seedx:finder", ["finder"]),
            Self.macOSArea("Wi-Fi", "seedx:wifi", ["wi-fi", "wifi"]),
            Self.macOSArea("Bluetooth", "seedx:bluetooth", ["bluetooth"]),
            Self.macOSArea("Photos", "seedx:photos", ["photos"]),
            Self.macOSArea("Messages", "seedx:messages", ["messages", "imessage"]),
            Self.macOSArea("iCloud", "seedx:icloud", ["icloud"]),
            Self.macOSArea("System Settings", "seedx:systempreferences", ["system settings", "system preferences"]),
            Self.macOSArea("Apple Intelligence", "seed:appleintelligence", ["apple intelligence"]),
            Self.macOSArea("Image Playground", "seedmacos:imageplayground", ["image playground"]),
            Self.macOSArea("Feedback Assistant", "seedx:fba", ["feedback assistant", "feedbackassistant"]),
            Self.macOSArea("Something else not on this list", "public.macos", ["macos"]),

            Self.topLevel("AirPods Beta Firmware", "airpods", ["airpods", "airpod", "airpods firmware"]),
            Self.topLevel("HomePod", ":B238", ["homepod", "home pod"]),
            Self.topLevel("Enterprise & Education", "ent.edu", ["enterprise", "education", "device management", "mdm", "school manager", "business manager"]),
            Self.topLevel("MFi Technologies", "mfi", ["mfi", "made for iphone", "external accessory certification"]),
            Self.topLevel("DMA Interoperability", "interop", ["dma", "interoperability", "european union"]),

            Rule(topic: "iOS & iPadOS", tat: "public.ios", area: "Something else not on this list", classification: "public.ios", keywords: ["ios", "ipados", "iphone", "ipad"]),
            Rule(topic: "watchOS", tat: "watchos.public", area: "Something else not on this list", classification: "watchos.public", keywords: ["watchos", "apple watch", "watch"]),
            Rule(topic: "tvOS", tat: "tvos.public", area: "Something else not on this list", classification: "tvos.public", keywords: ["tvos", "apple tv"]),
            Rule(topic: "visionOS", tat: "public.visionOS", area: "Something else not on this list", classification: "public.visionOS", keywords: ["visionos", "vision pro", "visionpro"])
        ]
    }

    public func infer(title: String, description: String = "", bundleID: String? = nil) -> FeedbackCategory {
        let haystack = "\(title)\n\(description)".lowercased()
        let mapping = loadBundleMapping()

        if let bundleID, let mapped = mapping[bundleID] {
            if let mappedRule = rules.first(where: { $0.classification.caseInsensitiveCompare(mapped) == .orderedSame }) {
                return category(from: mappedRule, reason: "bundle mapping \(bundleID) -> \(mapped)")
            }
        }

        var bestRule: Rule?
        var bestScore = 0
        for rule in rules {
            let score = rule.keywords.reduce(0) { count, keyword in
                haystack.contains(keyword) ? count + 1 : count
            }
            if score > bestScore {
                bestScore = score
                bestRule = rule
            }
        }

        if let bestRule {
            return category(from: bestRule, reason: "matched \(bestScore) keyword(s)")
        }

        return FeedbackCategory(
            topic: "macOS",
            tat: "public.macos",
            area: "Something else not on this list",
            classification: "public.macos",
            reason: "fallback"
        )
    }

    private func loadBundleMapping() -> [String: String] {
        guard
            let data = FileManager.default.contents(atPath: bundleMappingPath),
            let mapping = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return [:]
        }
        return mapping
    }

    private func category(from rule: Rule, reason: String) -> FeedbackCategory {
        FeedbackCategory(
            topic: rule.topic,
            tat: rule.tat,
            area: rule.area,
            classification: rule.classification,
            reason: reason
        )
    }

    private static func developerTechnology(_ area: String, _ classification: String, _ keywords: [String]) -> Rule {
        Rule(
            topic: "Developer Technologies & SDKs",
            tat: "dev.tech",
            area: area,
            classification: classification,
            keywords: keywords
        )
    }

    private static func developerTool(_ area: String, _ classification: String, _ keywords: [String]) -> Rule {
        Rule(
            topic: "Developer Tools & Resources",
            tat: "developertools.fba",
            area: area,
            classification: classification,
            keywords: keywords
        )
    }

    private static func macOSArea(_ area: String, _ classification: String, _ keywords: [String]) -> Rule {
        Rule(
            topic: "macOS",
            tat: "public.macos",
            area: area,
            classification: classification,
            keywords: keywords
        )
    }

    private static func topLevel(_ topic: String, _ tat: String, _ keywords: [String]) -> Rule {
        Rule(
            topic: topic,
            tat: tat,
            area: "Something else not on this list",
            classification: tat,
            keywords: keywords
        )
    }
}
