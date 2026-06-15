import AppKit
import Foundation
import XCFBNativeAutomation

public enum FeedbackAssistantApp {
    public struct FillResult: Equatable {
        public var stagedAttachment: DraftAttachment?
    }

    public static func open(_ url: URL) throws {
        try run("/usr/bin/open", arguments: ["-g", "-j", "-b", FeedbackRoutes.appBundleIdentifier, url.absoluteString])
        hideIfRunning()
    }

    @discardableResult
    public static func fill(
        payload: PreparedFeedback,
        selectPopups: Bool = false,
        confirmSubmit: Bool = false,
        attachmentDraftID: String? = nil,
        storePath: String = FeedbackStore.defaultPath
    ) throws -> FillResult {
        let shouldStageAttachment = payload.snapshot?.isEmpty == false
        if shouldStageAttachment && confirmSubmit {
            try runNativeFill(payload: payload, snapshot: "", selectPopups: selectPopups, confirmSubmit: false)
            let attachment = try FeedbackDraftAttachmentStager.stage(
                snapshotPath: payload.snapshot!,
                draftID: attachmentDraftID,
                storePath: storePath
            )
            try runNativeFill(payload: payload, snapshot: "", selectPopups: selectPopups, confirmSubmit: true)
            hideIfRunning()
            return FillResult(stagedAttachment: attachment)
        }

        let nativeSnapshot = shouldStageAttachment ? "" : (payload.snapshot ?? "")
        try runNativeFill(payload: payload, snapshot: nativeSnapshot, selectPopups: selectPopups, confirmSubmit: confirmSubmit)
        let attachment = try shouldStageAttachment ? FeedbackDraftAttachmentStager.stage(
            snapshotPath: payload.snapshot!,
            draftID: attachmentDraftID,
            storePath: storePath
        ) : nil
        hideIfRunning()
        return FillResult(stagedAttachment: attachment)
    }

    private static func hideIfRunning() {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: FeedbackRoutes.appBundleIdentifier)
            .forEach { _ = $0.hide() }
    }

    private static func runNativeFill(
        payload: PreparedFeedback,
        snapshot: String,
        selectPopups: Bool,
        confirmSubmit: Bool
    ) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let status = XCFBFeedbackAssistantFill(
            payload.title,
            payload.description,
            payload.category.topic,
            payload.platform ?? "",
            payload.category.area,
            payload.kind.nativeLabel,
            snapshot,
            payload.bundleID ?? "",
            selectPopups,
            confirmSubmit,
            &errorMessage
        )
        defer {
            if let errorMessage {
                XCFBFeedbackAssistantFree(errorMessage)
            }
        }
        guard status == 0 else {
            throw XCFBError.invalidArgument(errorMessage.map { String(cString: $0) } ?? "Feedback Assistant automation failed")
        }
    }

    private static func run(_ launchPath: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw XCFBError.processFailed((launchPath as NSString).lastPathComponent, process.terminationStatus)
        }
    }
}
