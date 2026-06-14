import Darwin
import Foundation
import RelatoKit

enum RelatoCLI {
    static let version = "0.2.0"
    static let webAppleIDEnvironment = "RELATO_WEB_APPLE_ID"
    static let webPasswordEnvironment = "RELATO_WEB_PASSWORD"
    static let webTwoFactorCommandEnvironment = "RELATO_WEB_2FA_CODE_COMMAND"

    static func run(_ rawArguments: [String]) async throws {
        var arguments = rawArguments
        if arguments == ["--version"] || arguments == ["-v"] {
            print(version)
            return
        }

        if arguments.isEmpty {
            printHelp()
            return
        }
        if arguments == ["--help"] || arguments == ["-h"] {
            printHelp()
            return
        }

        let command = arguments.removeFirst()
        if command == "help" {
            try printHelpTopic(arguments)
            return
        }
        if arguments.contains("--help") || arguments.contains("-h") {
            if command == "web" {
                printWebHelp()
            } else {
                printHelp(topic: command)
            }
            return
        }

        switch command {
        case "version":
            print(version)
        case "store":
            try runStore(arguments)
        case "categories":
            try runCategories(arguments)
        case "categorize":
            try runCategorize(arguments)
        case "prepare":
            try runPrepare(arguments)
        case "routes":
            runRoutes()
        case "open":
            try runOpen(arguments)
        case "open-native":
            try runOpenNative(arguments)
        case "fill":
            try runFill(arguments)
        case "submit":
            try runSubmit(arguments)
        case "web":
            try await runWeb(arguments)
        default:
            throw RelatoError.invalidArgument("Unknown command: \(command)")
        }
    }

    static func runWeb(_ rawArguments: [String]) async throws {
        var arguments = rawArguments
        guard !arguments.isEmpty else {
            printWebHelp()
            return
        }

        let subcommand = arguments.removeFirst()
        switch subcommand {
        case "auth":
            try await runWebAuth(arguments)
        case "inbox":
            try await runWebInbox(arguments)
        case "forms":
            try await runWebForms(arguments)
        case "drafts":
            try await runWebDrafts(arguments)
        default:
            throw RelatoError.invalidArgument("Unknown web subcommand: \(subcommand)")
        }
    }

    static func runWebAuth(_ rawArguments: [String]) async throws {
        var arguments = rawArguments
        guard !arguments.isEmpty else {
            throw RelatoError.invalidArgument("web auth requires a subcommand: login, status, logout")
        }

        let subcommand = arguments.removeFirst()
        let store = FeedbackWebSessionStore()
        switch subcommand {
        case "login":
            let appleID = (
                try takeOption("--apple-id", from: &arguments)
                    ?? ProcessInfo.processInfo.environment[webAppleIDEnvironment]
                    ?? ""
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            let twoFactorCodeCommand = (
                try takeOption("--two-factor-code-command", from: &arguments)
                    ?? ProcessInfo.processInfo.environment[
                        webTwoFactorCommandEnvironment
                    ]
                    ?? ""
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            try ensureNoArguments(arguments)

            guard !appleID.isEmpty else {
                throw RelatoError.invalidArgument(
                    "--apple-id is required when \(webAppleIDEnvironment) is not set"
                )
            }
            let password = try resolveWebPassword()
            let existingSession = try store.load() ?? FeedbackWebSession(cookies: [])
            let authenticator = FeedbackWebAuthenticator(session: existingSession)
            let session = try await authenticator.login(
                appleID: appleID,
                password: password
            ) { challenge in
                try resolveWebTwoFactorCode(
                    challenge: challenge,
                    command: twoFactorCodeCommand
                )
            }
            try store.save(session)

            try printJSONObject([
                "authenticated": true,
                "source": "srp",
            ])
        case "status":
            try ensureNoArguments(arguments)
            guard let session = try store.load(), !session.isEmpty else {
                try printJSONObject(["authenticated": false])
                return
            }

            do {
                let client = FeedbackWebClient(session: session, sessionStore: store)
                let response = try await client.authenticate()
                _ = try decodeJSONObject(response)
                try printJSONObject([
                    "authenticated": true,
                    "source": "keychain",
                ])
            } catch FeedbackWebClientError.authenticationRequired {
                try printJSONObject(["authenticated": false, "source": "keychain"])
            }
        case "logout":
            try ensureNoArguments(arguments)
            try store.delete()
            try printJSONObject(["authenticated": false, "removed": true])
        default:
            throw RelatoError.invalidArgument("Unknown web auth subcommand: \(subcommand)")
        }
    }

    static func runWebInbox(_ rawArguments: [String]) async throws {
        var arguments = rawArguments
        guard !arguments.isEmpty else {
            throw RelatoError.invalidArgument("web inbox requires the list subcommand")
        }
        let subcommand = arguments.removeFirst()
        guard subcommand == "list" else {
            throw RelatoError.invalidArgument("Unknown web inbox subcommand: \(subcommand)")
        }

        let locale = try takeOption("--locale", from: &arguments) ?? "en"
        let teamID = try takeOption("--team-id", from: &arguments)
        let compact = takeFlag("--compact", from: &arguments)
        try ensureNoArguments(arguments)

        let client = try makeFeedbackWebClient()
        let data = try await client.contentItems(locale: locale, teamID: teamID)
        try printJSONData(data, pretty: !compact)
    }

    static func runWebForms(_ rawArguments: [String]) async throws {
        var arguments = rawArguments
        guard !arguments.isEmpty else {
            throw RelatoError.invalidArgument("web forms requires a subcommand: list, view, options")
        }

        let subcommand = arguments.removeFirst()
        let locale = try takeOption("--locale", from: &arguments) ?? "en"
        let teamID = try takeOption("--team-id", from: &arguments)
        let compact = takeFlag("--compact", from: &arguments)

        let data: Data
        switch subcommand {
        case "list":
            try ensureNoArguments(arguments)
            let client = try makeFeedbackWebClient()
            data = try await client.formItems(locale: locale, teamID: teamID)
        case "view":
            let id = try requireOption("--id", from: &arguments)
            try ensureNoArguments(arguments)
            let client = try makeFeedbackWebClient()
            data = try await client.form(id: id, locale: locale, teamID: teamID)
        case "options":
            let id = try requireOption("--id", from: &arguments)
            let tat = try takeOption("--tat", from: &arguments)
            try ensureNoArguments(arguments)
            let client = try makeFeedbackWebClient()
            data = try await client.form(id: id, locale: locale, teamID: teamID)
            let form = try decodeWebJSON(
                FeedbackWebFormSchema.self,
                from: data,
                name: "form schema"
            )
            try printJSON(form.options(tat: tat), pretty: !compact)
            return
        default:
            throw RelatoError.invalidArgument("Unknown web forms subcommand: \(subcommand)")
        }
        try printJSONData(data, pretty: !compact)
    }

    static func runWebDrafts(_ rawArguments: [String]) async throws {
        var arguments = rawArguments
        guard !arguments.isEmpty else {
            throw RelatoError.invalidArgument(
                "web drafts requires a subcommand: create, view, update, attach"
            )
        }

        let subcommand = arguments.removeFirst()
        let locale = try takeOption("--locale", from: &arguments) ?? "en"
        let compact = takeFlag("--compact", from: &arguments)

        let data: Data
        switch subcommand {
        case "create":
            let formID = try requireOption("--form-id", from: &arguments)
            let teamID = try takeOption("--team-id", from: &arguments)
            try ensureNoArguments(arguments)
            let client = try makeFeedbackWebClient()
            data = try await client.createDraft(
                formID: formID,
                locale: locale,
                teamID: teamID
            )
        case "view":
            let id = try requireOption("--id", from: &arguments)
            try ensureNoArguments(arguments)
            let client = try makeFeedbackWebClient()
            data = try await client.draft(id: id, locale: locale)
        case "update":
            let id = try requireOption("--id", from: &arguments)
            let updates = try webDraftUpdates(from: &arguments)
            try ensureNoArguments(arguments)

            let client = try makeFeedbackWebClient()
            let draftData = try await client.draft(id: id, locale: locale)
            let draft = try decodeWebJSON(
                FeedbackWebDraft.self,
                from: draftData,
                name: "draft"
            )
            let formData = try await client.form(
                id: String(draft.formID),
                locale: locale,
                teamID: draft.teamID
            )
            let form = try decodeWebJSON(
                FeedbackWebFormSchema.self,
                from: formData,
                name: "form schema"
            )
            let answers = try FeedbackWebDraftEditor.mergedAnswers(
                draft: draft,
                form: form,
                updates: updates
            )
            data = try await client.updateDraftAnswers(
                id: id,
                locale: locale,
                answers: answers
            )
        case "attach":
            let id = try requireOption("--id", from: &arguments)
            var paths = try takeOptions("--file", from: &arguments)
            if let payloadPath = try takeOption("--payload", from: &arguments) {
                let payload = try loadPayload(at: expandedPath(payloadPath))
                guard let snapshot = payload.snapshot else {
                    throw RelatoError.invalidArgument(
                        "The payload does not contain a snapshot attachment"
                    )
                }
                paths.append(snapshot)
            }
            try ensureNoArguments(arguments)
            guard !paths.isEmpty else {
                throw RelatoError.invalidArgument(
                    "web drafts attach requires --file PATH or --payload PATH"
                )
            }

            let client = try makeFeedbackWebClient()
            var seenPaths: Set<String> = []
            var receipts: [FeedbackWebAttachmentReceipt] = []
            for path in paths {
                let fileURL = URL(
                    fileURLWithPath: expandedPath(path)
                ).standardizedFileURL
                guard seenPaths.insert(fileURL.path).inserted else {
                    continue
                }
                receipts.append(
                    try await client.uploadAttachment(
                        draftID: id,
                        fileURL: fileURL,
                        locale: locale
                    )
                )
            }
            try printJSON(receipts, pretty: !compact)
            return
        default:
            throw RelatoError.invalidArgument("Unknown web drafts subcommand: \(subcommand)")
        }
        try printJSONData(data, pretty: !compact)
    }

    static func makeFeedbackWebClient() throws -> FeedbackWebClient {
        let store = FeedbackWebSessionStore()
        guard let session = try store.load(), !session.isEmpty else {
            throw FeedbackWebClientError.authenticationRequired
        }
        return FeedbackWebClient(session: session, sessionStore: store)
    }

    static func webDraftUpdates(from arguments: inout [String]) throws -> [String: [String]] {
        var updates: [String: [String]] = [:]

        func set(_ tat: String, _ value: String?) {
            guard let value else { return }
            updates[tat] = [value]
        }

        if let payloadPath = try takeOption("--payload", from: &arguments) {
            let payload = try loadPayload(at: expandedPath(payloadPath))
            set(":title", payload.title)
            set(":description", payload.description)
            set(":platform", payload.platform)
            set(":area", payload.category.area)
            set(":type_req", try webFeedbackType(payload.kind.rawValue))
        }

        set(":title", try takeOption("--title", from: &arguments))
        set(":platform", try takeOption("--platform", from: &arguments))
        set(":area", try takeOption("--technology", from: &arguments))
        if let kind = try takeOption("--kind", from: &arguments) {
            set(":type_req", try webFeedbackType(kind))
        }
        set(":description", try takeOption("--description", from: &arguments))
        set(":dev_app_name", try takeOption("--app", from: &arguments))
        set(":dev_impact", try takeOption("--impact", from: &arguments))
        if let mode = try takeOption("--foundation-models-mode", from: &arguments) {
            let value: String
            switch mode.lowercased() {
            case "feedback":
                value = "Share specific feedback"
            case "samples":
                value = "Upload model response samples"
            default:
                value = mode
            }
            set(":foundationmodels_type", value)
        }

        var customUpdates: [String: [String]] = [:]
        for assignment in try takeOptions("--answer", from: &arguments) {
            guard let separator = assignment.firstIndex(of: "=") else {
                throw RelatoError.invalidArgument(
                    "Invalid --answer value: \(assignment). Expected TAT=VALUE"
                )
            }
            let tat = String(assignment[..<separator])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(assignment[assignment.index(after: separator)...])
            guard !tat.isEmpty, !value.isEmpty else {
                throw RelatoError.invalidArgument(
                    "Invalid --answer value: \(assignment). Expected non-empty TAT=VALUE"
                )
            }
            customUpdates[tat, default: []].append(value)
        }
        for (tat, values) in customUpdates {
            updates[tat] = values
        }

        guard !updates.isEmpty else {
            throw RelatoError.invalidArgument(
                "web drafts update requires --payload, a named field option, or --answer TAT=VALUE"
            )
        }
        return updates
    }

    static func webFeedbackType(_ value: String) throws -> String {
        switch value.lowercased() {
        case "bug", "incorrect", "incorrect/unexpected behavior":
            return "Incorrect/Unexpected Behavior"
        case "suggestion":
            return "Suggestion"
        default:
            throw RelatoError.invalidArgument(
                "Invalid value for --kind: \(value). Expected bug or suggestion."
            )
        }
    }

    static func runStore(_ rawArguments: [String]) throws {
        var arguments = rawArguments
        guard !arguments.isEmpty else {
            throw RelatoError.invalidArgument("store requires a subcommand: summary, list, uploads")
        }
        let subcommand = arguments.removeFirst()
        let dbPath = try takeOption("--db", from: &arguments) ?? FeedbackStore.defaultPath
        let store = FeedbackStore(path: dbPath)

        switch subcommand {
        case "summary":
            try ensureNoArguments(arguments)
            let rows = try store.summary()
            print("store: \(NSString(string: dbPath).expandingTildeInPath)")
            printTable([["table", "rows"]] + rows.map { [$0.table, String($0.rows)] })
        case "list":
            let limit = try parseLimit(try takeOption("--limit", from: &arguments) ?? "20")
            try ensureNoArguments(arguments)
            let rows = try store.contentItems(limit: limit)
            printTable([["pk", "remote_id", "type", "updated", "title", "subtitle"]] + rows.map { [$0.pk, $0.remoteID, $0.type, $0.updated, $0.title, $0.subtitle] })
        case "uploads":
            let limit = try parseLimit(try takeOption("--limit", from: &arguments) ?? "20")
            try ensureNoArguments(arguments)
            let rows = try store.uploadTasks(limit: limit)
            printTable([["pk", "task_id", "state", "stage", "uploaded", "total"]] + rows.map { [$0.pk, $0.taskID, $0.state, $0.stage, $0.uploaded, $0.total] })
        default:
            throw RelatoError.invalidArgument("Unknown store subcommand: \(subcommand)")
        }
    }

    static func runCategories(_ rawArguments: [String]) throws {
        var arguments = rawArguments
        let dbPath = try takeOption("--db", from: &arguments) ?? FeedbackStore.defaultPath
        try ensureNoArguments(arguments)
        let store = FeedbackStore(path: dbPath)
        let rows = try store.formStubs()
        printTable([["topic", "tat", "platform", "description"]] + rows.map { [$0.topic, $0.tat, $0.platform, $0.description] })
    }

    static func runCategorize(_ rawArguments: [String]) throws {
        var arguments = rawArguments
        let title = try requireOption("--title", from: &arguments)
        let description = try takeOption("--description", from: &arguments) ?? ""
        let bundleID = try takeOption("--bundle-id", from: &arguments)
        try ensureNoArguments(arguments)
        let category = FeedbackCategoryInferer().infer(title: title, description: description, bundleID: bundleID)
        try printJSON(category)
    }

    static func runPrepare(_ rawArguments: [String]) throws {
        var arguments = rawArguments
        let title = try requireOption("--title", from: &arguments)
        let description = try requireOption("--description", from: &arguments)
        let bundleID = try takeOption("--bundle-id", from: &arguments)
        let requestedPlatform = try takeOption("--platform", from: &arguments)
        let kindValue = try takeOption("--kind", from: &arguments) ?? "bug"
        guard let kind = FeedbackKind(rawValue: kindValue) else {
            throw RelatoError.invalidArgument("Invalid value for --kind: \(kindValue). Expected bug or suggestion.")
        }
        let outputDir = expandedPath(try takeOption("--output-dir", from: &arguments) ?? FileManager.default.currentDirectoryPath)

        var snapshot = try takeOption("--snapshot", from: &arguments).map(expandedPath)
        try ensureNoArguments(arguments)
        if let snapshotPath = snapshot {
            snapshot = URL(fileURLWithPath: snapshotPath).standardizedFileURL.path
            if !FileManager.default.fileExists(atPath: snapshot!) {
                throw RelatoError.missingFile(snapshot!)
            }
        }

        let category = FeedbackCategoryInferer().infer(title: title, description: description, bundleID: bundleID)
        let platform: String?
        if let requestedPlatform {
            guard let normalized = FeedbackPlatformInferer.normalize(requestedPlatform) else {
                throw RelatoError.invalidArgument(
                    "Invalid value for --platform: \(requestedPlatform). Expected one of: \(FeedbackPlatformInferer.supportedPlatforms.joined(separator: ", "))."
                )
            }
            platform = normalized
        } else {
            platform = FeedbackPlatformInferer().infer(title: title, description: description)
        }
        let payload = try PreparedFeedback(
            title: title,
            description: description,
            snapshot: snapshot,
            bundleID: bundleID,
            kind: kind,
            category: category,
            platform: platform
        )

        try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
        let jsonURL = URL(fileURLWithPath: outputDir).appendingPathComponent("feedback-submission.json")
        let markdownURL = URL(fileURLWithPath: outputDir).appendingPathComponent("feedback-submission.md")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(payload).write(to: jsonURL)
        try (payload.markdown() + "\n").write(to: markdownURL, atomically: true, encoding: .utf8)

        print("Wrote \(jsonURL.path)")
        print("Wrote \(markdownURL.path)")
        print(payload.url)
    }

    static func runRoutes() {
        for name in FeedbackRoutes.known.keys.sorted() {
            let path = FeedbackRoutes.known[name] ?? ""
            print("\(name.padding(toLength: 15, withPad: " ", startingAt: 0)) \(FeedbackRoutes.webBase)\(path)")
        }
    }

    static func runOpen(_ rawArguments: [String]) throws {
        var arguments = rawArguments
        guard !arguments.isEmpty else {
            throw RelatoError.invalidArgument("open requires a route")
        }
        let route = arguments.removeFirst()
        let id = try takeOption("--id", from: &arguments)
        let printOnly = takeFlag("--print-only", from: &arguments)
        try ensureNoArguments(arguments)
        let url = try FeedbackRoutes.url(for: route, id: id)
        if printOnly {
            print(url.absoluteString)
        } else {
            try FeedbackAssistantApp.open(url)
        }
    }

    static func runOpenNative(_ rawArguments: [String]) throws {
        var arguments = rawArguments
        let payloadPath = expandedPath(try takeOption("--payload", from: &arguments) ?? "feedback-submission.json")
        try ensureNoArguments(arguments)
        let payload = try loadPayload(at: payloadPath)
        let url = try feedbackURL(from: payload)
        try FeedbackAssistantApp.open(url)
    }

    static func runFill(_ rawArguments: [String]) throws {
        var arguments = rawArguments
        let payloadPath = expandedPath(try takeOption("--payload", from: &arguments) ?? "feedback-submission.json")
        let selectPopups = takeFlag("--select-popups", from: &arguments)
        try ensureNoArguments(arguments)
        let payload = try loadPayload(at: payloadPath)
        let fillResult = try FeedbackAssistantApp.fill(payload: payload, selectPopups: selectPopups)
        if selectPopups {
            print("Set fields and selected requested popups through Accessibility. Review native-only fields and remember local verification is not an Apple server receipt.")
        } else {
            print("Set fields through Accessibility. Select native popups if needed: platform='\(payload.platform ?? "")', area='\(payload.category.area)', kind='\(payload.kind.rawValue)'")
        }
        printStagedAttachment(fillResult.stagedAttachment)
    }

    static func runSubmit(_ rawArguments: [String]) throws {
        var arguments = rawArguments
        let payloadPath = expandedPath(try takeOption("--payload", from: &arguments) ?? "feedback-submission.json")
        let selectPopups = takeFlag("--select-popups", from: &arguments)
        let confirmSubmit = takeFlag("--confirm", from: &arguments)
        let waitSeconds = try parseSeconds(try takeOption("--wait-seconds", from: &arguments) ?? "1.5", flag: "--wait-seconds")
        let verifyStore = takeFlag("--verify-store", from: &arguments) || confirmSubmit
        let verifyWaitSeconds = try parseSeconds(try takeOption("--verify-wait-seconds", from: &arguments) ?? "3.0", flag: "--verify-wait-seconds")
        let dryRun = takeFlag("--dry-run", from: &arguments)
        let dbPath = try takeOption("--db", from: &arguments) ?? FeedbackStore.defaultPath
        try ensureNoArguments(arguments)
        let payload = try loadPayload(at: payloadPath)
        let url = try feedbackURL(from: payload)

        if dryRun {
            printSubmitPlan(
                payloadPath: payloadPath,
                payload: payload,
                url: url,
                selectPopups: selectPopups,
                confirmSubmit: confirmSubmit,
                verifyStore: verifyStore,
                dbPath: dbPath
            )
            return
        }

        let store = FeedbackStore(path: dbPath)
        let beforeSnapshot = verifyStore ? try? store.verificationSnapshot(title: payload.title) : nil

        try FeedbackAssistantApp.open(url)
        Thread.sleep(forTimeInterval: waitSeconds)

        let fillResult = try FeedbackAssistantApp.fill(
            payload: payload,
            selectPopups: selectPopups,
            confirmSubmit: confirmSubmit,
            storePath: dbPath
        )

        if confirmSubmit {
            print("Submit press requested through the native Feedback Assistant UI.")
        } else {
            print("Opened, filled, and hid Feedback Assistant through Accessibility. Review any native-only fields or diagnostics, then re-run with --confirm to press the native Submit button.")
        }
        printStagedAttachment(fillResult.stagedAttachment)

        if verifyStore {
            Thread.sleep(forTimeInterval: verifyWaitSeconds)
            let afterSnapshot = try? store.verificationSnapshot(title: payload.title)
            printStoreVerification(before: beforeSnapshot, after: afterSnapshot, title: payload.title)
        }
    }

    static func printStagedAttachment(_ attachment: DraftAttachment?) {
        guard let attachment else { return }
        print("Staged snapshot in Feedback Assistant draft \(attachment.draftID): \(attachment.path)")
    }

    static func loadPayload(at path: String) throws -> PreparedFeedback {
        guard FileManager.default.fileExists(atPath: path) else {
            throw RelatoError.missingFile(path)
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        do {
            return try JSONDecoder().decode(PreparedFeedback.self, from: data)
        } catch {
            throw RelatoError.invalidArgument("Could not decode payload at \(path): \(friendlyDecodeError(error))")
        }
    }

    static func feedbackURL(from payload: PreparedFeedback) throws -> URL {
        guard
            let components = URLComponents(string: payload.url),
            components.scheme == "https",
            components.host == "feedbackassistant.apple.com",
            let url = components.url
        else {
            throw RelatoError.invalidArgument("Payload URL must be an https://feedbackassistant.apple.com URL")
        }
        return url
    }

    static func takeOption(_ name: String, from arguments: inout [String]) throws -> String? {
        guard let index = arguments.firstIndex(of: name) else { return nil }
        arguments.remove(at: index)
        guard index < arguments.count, !arguments[index].hasPrefix("--") else {
            throw RelatoError.missingValue(name)
        }
        return arguments.remove(at: index)
    }

    static func takeOptions(_ name: String, from arguments: inout [String]) throws -> [String] {
        var values: [String] = []
        while let index = arguments.firstIndex(of: name) {
            arguments.remove(at: index)
            guard index < arguments.count, !arguments[index].hasPrefix("--") else {
                throw RelatoError.missingValue(name)
            }
            values.append(arguments.remove(at: index))
        }
        return values
    }

    static func requireOption(_ name: String, from arguments: inout [String]) throws -> String {
        guard let value = try takeOption(name, from: &arguments), !value.isEmpty else {
            throw RelatoError.missingValue(name)
        }
        return value
    }

    static func takeFlag(_ name: String, from arguments: inout [String]) -> Bool {
        guard let index = arguments.firstIndex(of: name) else { return false }
        arguments.remove(at: index)
        return true
    }

    static func ensureNoArguments(_ arguments: [String]) throws {
        guard arguments.isEmpty else {
            throw RelatoError.invalidArgument("Unexpected argument(s): \(arguments.joined(separator: " "))")
        }
    }

    static func parseLimit(_ value: String) throws -> Int {
        guard let limit = Int(value), limit >= 0 else {
            throw RelatoError.invalidArgument("Invalid value for --limit: \(value). Expected a non-negative integer.")
        }
        return limit
    }

    static func parseSeconds(_ value: String, flag: String) throws -> Double {
        guard let seconds = Double(value), seconds >= 0 else {
            throw RelatoError.invalidArgument("Invalid value for \(flag): \(value). Expected a non-negative number.")
        }
        return seconds
    }

    static func resolveWebPassword() throws -> String {
        if let password = ProcessInfo.processInfo.environment[webPasswordEnvironment],
            !password.isEmpty
        {
            return password
        }
        guard hasInteractiveTerminal() else {
            throw RelatoError.invalidArgument(
                "Apple Account password is required; run in a terminal or set \(webPasswordEnvironment)"
            )
        }
        return try readSecret(prompt: "Apple Account password: ", trim: false)
    }

    static func resolveWebTwoFactorCode(
        challenge: FeedbackWebTwoFactorChallenge,
        command: String
    ) throws -> String {
        switch challenge.method {
        case .trustedDevice:
            writeStandardError("Enter the verification code shown on a trusted Apple device.\n")
        case .phone:
            if let destination = challenge.destination {
                writeStandardError("Verification code sent to \(destination).\n")
            } else {
                writeStandardError("Verification code sent to a trusted phone number.\n")
            }
        }

        if !command.isEmpty {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", command]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.standardError
            var environment = ProcessInfo.processInfo.environment
            environment.removeValue(forKey: webPasswordEnvironment)
            process.environment = environment
            let outputData: Data
            do {
                try process.run()
                outputData = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
            } catch {
                throw RelatoError.web("could not run the two-factor code command")
            }
            guard process.terminationStatus == 0 else {
                throw RelatoError.web("the two-factor code command failed")
            }
            let code = String(
                decoding: outputData,
                as: UTF8.self
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !code.isEmpty else {
                throw RelatoError.web("the two-factor code command returned no code")
            }
            return code
        }

        guard hasInteractiveTerminal() else {
            throw RelatoError.invalidArgument(
                "two-factor code is required; run in a terminal, pass --two-factor-code-command, or set \(webTwoFactorCommandEnvironment)"
            )
        }
        return try readSecret(prompt: "Two-factor code: ", trim: true)
    }

    static func readSecret(prompt: String, trim: Bool) throws -> String {
        let value: String? = prompt.withCString { promptPointer in
            guard let result = getpass(promptPointer) else {
                return nil
            }
            return String(cString: result)
        }
        guard let value else {
            throw RelatoError.web("could not read secure terminal input")
        }
        let resolved = trim
            ? value.trimmingCharacters(in: .whitespacesAndNewlines)
            : value
        guard !resolved.isEmpty else {
            throw RelatoError.invalidArgument("secure terminal input cannot be empty")
        }
        return resolved
    }

    static func hasInteractiveTerminal() -> Bool {
        if isatty(STDIN_FILENO) != 0 {
            return true
        }
        let descriptor = Darwin.open("/dev/tty", O_RDWR | O_NOCTTY)
        guard descriptor >= 0 else {
            return false
        }
        Darwin.close(descriptor)
        return true
    }

    static func writeStandardError(_ text: String) {
        FileHandle.standardError.write(Data(text.utf8))
    }

    static func friendlyDecodeError(_ error: Error) -> String {
        if case let DecodingError.dataCorrupted(context) = error {
            return context.debugDescription
        }
        if case let DecodingError.keyNotFound(key, _) = error {
            return "missing key '\(key.stringValue)'"
        }
        if case let DecodingError.valueNotFound(_, context) = error {
            return "missing value at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        }
        if case let DecodingError.typeMismatch(_, context) = error {
            return "type mismatch at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        }
        return error.localizedDescription
    }

    static func expandedPath(_ path: String) -> String {
        NSString(string: path).expandingTildeInPath
    }

    static func printJSON<T: Encodable>(_ value: T, pretty: Bool = true) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        let data = try encoder.encode(value)
        print(String(decoding: data, as: UTF8.self))
    }

    static func decodeWebJSON<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        name: String
    ) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw RelatoError.web(
                "could not decode Apple's \(name) response: \(friendlyDecodeError(error))"
            )
        }
    }

    static func decodeJSONObject(_ data: Data) throws -> Any {
        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            throw RelatoError.web("Apple returned malformed JSON")
        }
    }

    static func printJSONData(_ data: Data, pretty: Bool) throws {
        try printJSONObject(decodeJSONObject(data), pretty: pretty)
    }

    static func printJSONObject(_ object: Any, pretty: Bool = true) throws {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw RelatoError.web("could not encode JSON output")
        }
        let options: JSONSerialization.WritingOptions = pretty ? [.prettyPrinted, .sortedKeys] : []
        let data = try JSONSerialization.data(withJSONObject: object, options: options)
        print(String(decoding: data, as: UTF8.self))
    }

    static func printTable(_ rows: [[String]]) {
        guard let first = rows.first else { return }
        let widths = first.indices.map { index in
            rows.map { row in index < row.count ? row[index].count : 0 }.max() ?? 0
        }
        for row in rows {
            let line = row.indices.map { index in
                row[index].padding(toLength: widths[index], withPad: " ", startingAt: 0)
            }.joined(separator: "  ")
            print(line)
        }
    }

    static func printStoreVerification(
        before: StoreVerificationSnapshot?,
        after: StoreVerificationSnapshot?,
        title: String
    ) {
        print("")
        print("Local store verification:")

        guard let after else {
            print("  could not read Feedback Assistant store after native handoff")
            return
        }

        if let before {
            let contentDelta = after.contentItemCount - before.contentItemCount
            let uploadDelta = after.uploadTaskCount - before.uploadTaskCount
            print("  content items: \(before.contentItemCount) -> \(after.contentItemCount) (\(signed(contentDelta)))")
            print("  upload tasks:   \(before.uploadTaskCount) -> \(after.uploadTaskCount) (\(signed(uploadDelta)))")
        } else {
            print("  content items: \(after.contentItemCount)")
            print("  upload tasks:   \(after.uploadTaskCount)")
        }

        if !after.matchingItems.isEmpty {
            print("  matching local item(s) for title '\(title)':")
            for item in after.matchingItems {
                let displayTitle = item.title.isEmpty ? item.subtitle : item.title
                print("    #\(item.pk) remote_id=\(item.remoteID) type=\(item.type) updated=\(item.updated) \(displayTitle)")
            }
        } else if let newest = after.newestItem {
            let displayTitle = newest.title.isEmpty ? newest.subtitle : newest.title
            print("  no exact title match found; newest local item is #\(newest.pk) \(displayTitle)")
        } else {
            print("  no local content items found")
        }

        print("  note: this is a best-effort local check, not an Apple server receipt")
    }

    static func signed(_ value: Int) -> String {
        value >= 0 ? "+\(value)" : "\(value)"
    }

    static func printSubmitPlan(
        payloadPath: String,
        payload: PreparedFeedback,
        url: URL,
        selectPopups: Bool,
        confirmSubmit: Bool,
        verifyStore: Bool,
        dbPath: String
    ) {
        print("Submit plan:")
        print("  payload:       \(payloadPath)")
        print("  title:         \(payload.title)")
        print("  topic:         \(payload.category.topic)")
        print("  area:          \(payload.category.area)")
        print("  platform:      \(payload.platform ?? "")")
        print("  kind:          \(payload.kind.rawValue)")
        print("  bundle ID:     \(payload.bundleID ?? "")")
        print("  snapshot:      \(payload.snapshot ?? "")")
        print("  native URL:    \(url.absoluteString)")
        print("  select popups: \(selectPopups ? "yes" : "no")")
        print("  click Submit:  \(confirmSubmit ? "yes (--confirm)" : "no")")
        print("  verify store:  \(verifyStore ? "yes" : "no")")
        if verifyStore {
            print("  store:         \(NSString(string: dbPath).expandingTildeInPath)")
        }
    }

    static func printHelpTopic(_ arguments: [String]) throws {
        if arguments.isEmpty {
            printHelp()
            return
        }
        guard arguments.count == 1 else {
            throw RelatoError.invalidArgument("help accepts at most one topic")
        }
        printHelp(topic: arguments[0])
    }

    static func printHelp(topic: String) {
        switch topic {
        case "payload", "prepare":
            printPrepareHelp()
        case "submit":
            printSubmitHelp()
        case "fill":
            printFillHelp()
        case "store":
            printStoreHelp()
        case "web":
            printWebHelp()
        default:
            printHelp()
        }
    }

    static func printHelp() {
        print(
            """
            relato: agent-first tooling for Apple Feedback Assistant workflows

            RelatoKit is designed for coding agents preparing useful Feedback Assistant
            reports. Its stable workflow uses Apple's native macOS app. The experimental
            `web` command family provides headless access to Apple's undocumented
            Feedback Assistant web service after an explicit Apple Account login.

            Agent workflow:
              1. Research the issue and write any supporting evidence to a local file.
              2. Run `relato prepare` to create the payload pair:
                   feedback-submission.json  machine-readable contract for relato
                   feedback-submission.md    human-readable report for review/logs
              3. Inspect the Markdown and JSON before touching the native app.
              4. Run `relato submit --dry-run --select-popups --payload feedback-submission.json`.
              5. Run `relato submit --select-popups --payload feedback-submission.json`
                 to open, fill, and select known native popups without submitting.
              6. Inspect Feedback Assistant for native-only fields, diagnostics, and files.
              7. Only after explicit user confirmation, run with `--confirm`.
              8. Use `relato store list` and `relato store uploads` as local evidence.

            Commands:
              relato version
              relato store summary [--db PATH]
              relato store list [--limit N] [--db PATH]
              relato store uploads [--limit N] [--db PATH]
              relato categories [--db PATH]
              relato categorize --title TEXT [--description TEXT] [--bundle-id ID]
              relato prepare --title TEXT --description TEXT [--snapshot PATH] [--bundle-id ID] [--platform PLATFORM] [--kind bug|suggestion] [--output-dir DIR]
              relato routes
              relato open ROUTE [--id ID] [--print-only]
              relato open-native [--payload PATH]
              relato fill [--payload PATH] [--select-popups]
              relato submit [--payload PATH] [--select-popups] [--wait-seconds N] [--verify-wait-seconds N] [--db PATH] [--confirm] [--verify-store] [--dry-run]
              relato web auth login --apple-id EMAIL [--two-factor-code-command COMMAND]
              relato web auth status
              relato web auth logout
              relato web inbox list [--locale LOCALE] [--team-id ID] [--compact]
              relato web forms list [--locale LOCALE] [--team-id ID] [--compact]
              relato web forms view --id ID [--locale LOCALE] [--team-id ID] [--compact]
              relato web forms options --id ID [--tat TAT] [--locale LOCALE] [--team-id ID] [--compact]
              relato web drafts create --form-id ID [--locale LOCALE] [--team-id ID] [--compact]
              relato web drafts view --id ID [--locale LOCALE] [--compact]
              relato web drafts update --id ID [--payload PATH] [field options] [--answer TAT=VALUE]... [--locale LOCALE] [--compact]
              relato web drafts attach --id ID [--file PATH]... [--payload PATH] [--locale LOCALE] [--compact]

            Help topics:
              relato help payload
              relato help prepare
              relato help submit
              relato help fill
              relato help store
              relato help web

            Safety:
              `--confirm` presses the native Submit button through Accessibility. It is not headless
              submission and local store verification is not an Apple server receipt.
              Native form automation uses an Objective-C Accessibility engine with passive
              AX value writes for fields and AX menu actions for requested popup selection.
              Feedback Assistant is opened without activation. `--select-popups` briefly
              activates it for menu selection, and the app is hidden after launch/fill.
              Snapshot attachments are staged into the local Feedback Assistant draft
              folder in the background after the native draft exists.

              `relato web` is unofficial and isolated from the stable native workflow.
              Its endpoints may change without notice. Draft creation, inspection, and
              schema-validated answer updates are supported. Attachment upload uses
              Apple's file-promise protocol and verifies the result from the draft.
              Final web submission is not yet exposed.
            """
        )
    }

    static func printPrepareHelp() {
        print(
            """
            relato prepare: create the payload pair agents should review and reuse

            Usage:
              relato prepare --title TEXT --description TEXT [--snapshot PATH] [--bundle-id ID] [--platform PLATFORM] [--kind bug|suggestion] [--output-dir DIR]

            Outputs:
              feedback-submission.json
                Machine-readable payload consumed by `open-native`, `fill`, and `submit`.
                Keep this file as the source of truth for the native handoff.

              feedback-submission.md
                Human-readable review artifact. Use it in agent logs, PR notes, or as an
                attachment when useful.

            Options:
              --title TEXT          Feedback title.
              --description TEXT    Full report body. Preserve real newlines.
              --snapshot PATH       Local evidence attachment. This can be a screenshot,
                                    Markdown note, log, sysdiagnose pointer, or sample file.
              --bundle-id ID        App bundle ID when relevant.
              --platform VALUE      Native platform label. Inferred from the title and
                                    description when omitted.
                                    Values: iOS, iPadOS, Mac Catalyst, macOS, tvOS,
                                    visionOS, watchOS, or Web & Services.
              --kind VALUE          bug or suggestion. Defaults to bug.
              --output-dir DIR      Where to write the JSON and Markdown files.

            Agent pattern:
              relato prepare \\
                --title "Foundation Models framework: add first-class video input support" \\
                --description "$REPORT_BODY" \\
                --snapshot ./evidence.md \\
                --kind suggestion \\
                --output-dir /tmp/relato-report

              sed -n '1,220p' /tmp/relato-report/feedback-submission.md
              relato submit --payload /tmp/relato-report/feedback-submission.json --dry-run
            """
        )
    }

    static func printSubmitHelp() {
        print(
            """
            relato submit: open/fill Feedback Assistant and optionally click native Submit

            Usage:
              relato submit [--payload PATH] [--select-popups] [--wait-seconds N] [--verify-wait-seconds N] [--db PATH] [--confirm] [--verify-store] [--dry-run]

            Default behavior:
              Without `--confirm`, this fills the native form from the JSON payload, hides
              the app, and stops before Submit. Without `--select-popups`, Feedback Assistant
              is opened without activation. Popup selection briefly activates the app.

            Confirmation:
              --confirm             Presses the native Submit button through
                                    Accessibility automation. Use only after explicit
                                    user confirmation at action time.

            Verification:
              --verify-store        Reads the local Feedback Assistant store before/after
                                    the handoff and prints local deltas.
              --db PATH             Override the local Feedback Assistant SQLite path.
              --dry-run             Print the planned native handoff without opening,
                                    filling, attaching, or submitting.

            Native form reality:
              Apple can add topic-specific required fields, popups, diagnostics, or log
              gathering. Agents should inspect the native app before `--confirm`; the
              local store check is useful evidence but not a server-side receipt.
              RelatoKit uses an Objective-C Accessibility engine for native UI automation.
              Text fields are set through passive AX value writes. With `--select-popups`,
              native platform, area, and type menus are selected through AX actions.
              Snapshot attachments are staged into the local Feedback Assistant draft folder after the native draft
              exists, avoiding the Add Attachment picker. Popup selection briefly activates
              Feedback Assistant and fails closed if the requested native option is absent.

            Agent pattern:
              relato submit --payload feedback-submission.json --select-popups --dry-run
              relato submit --payload feedback-submission.json --select-popups
              # inspect native UI and satisfy any remaining Apple-only fields
              relato submit --payload feedback-submission.json --select-popups --confirm --verify-store
              relato store list --limit 10
              relato store uploads --limit 10
            """
        )
    }

    static func printFillHelp() {
        print(
            """
            relato fill: fill the currently open Feedback Assistant draft

            Usage:
              relato fill [--payload PATH] [--select-popups]

            Notes:
              This does not open a new route and does not submit. It is useful when an
              agent has already navigated the native app, manually selected a topic, or
              needs to retry form fill after changing native-only fields.

              --select-popups asks the AX driver to select known platform, area, and type
              popups. Feedback Assistant is briefly activated for menu selection, then hidden.
            """
        )
    }

    static func printStoreHelp() {
        print(
            """
            relato store: inspect the local Feedback Assistant store

            Usage:
              relato store summary [--db PATH]
              relato store list [--limit N] [--db PATH]
              relato store uploads [--limit N] [--db PATH]

            Agent pattern:
              relato store summary
              relato store list --limit 10
              relato store uploads --limit 10

            Notes:
              Store reads are local evidence only. They can show drafts, recent items,
              and upload tasks, but they are not Apple server receipts.
            """
        )
    }

    static func printWebHelp() {
        print(
            """
            relato web: experimental Feedback Assistant web access

            Status:
              EXPERIMENTAL / UNOFFICIAL

            This command family uses Apple's undocumented Appleseed web service. It is
            separate from the public App Store Connect API and from ASC's private Iris API.
            Endpoints and response schemas can change without notice.

            Authentication:
              relato web auth login --apple-id EMAIL [--two-factor-code-command COMMAND]
                Performs Apple Account SRP authentication directly from Swift. The password
                is read from a secure terminal prompt by default and is never stored.
                Trusted-device and trusted-phone two-factor challenges are supported.
                RelatoKit stores the resulting cookies and a one-way account hash in Keychain.

              relato web auth status
                Validates the cached session against Feedback Assistant.

              relato web auth logout
                Deletes the local Keychain session. It does not revoke Apple sessions.

            Login options and environment:
              --apple-id EMAIL
                Apple Account email. Defaults to RELATO_WEB_APPLE_ID.

              --two-factor-code-command COMMAND
                Runs COMMAND for each requested verification code and reads the code from
                stdout. Defaults to RELATO_WEB_2FA_CODE_COMMAND. Without a command, an
                interactive terminal prompt is used.

              RELATO_WEB_PASSWORD
                Supplies the password non-interactively. A secure terminal prompt is safer
                for human use because environment variables may be exposed to child
                processes or shell tooling.

            Headless boundary:
              Password-based Apple Accounts, including trusted-device and trusted-phone 2FA,
              can authenticate without WebKit, Chrome, or the ASC binary. Passkey-only
              accounts and Apple Account actions that require a browser are not supported.

            Inspection commands:
              relato web inbox list [--locale LOCALE] [--team-id ID] [--compact]
              relato web forms list [--locale LOCALE] [--team-id ID] [--compact]
              relato web forms view --id ID [--locale LOCALE] [--team-id ID] [--compact]
              relato web forms options --id ID [--tat TAT] [--locale LOCALE] [--team-id ID] [--compact]
                Emits normalized question metadata and label/value pairs. Use --tat to
                inspect one semantic field, such as :platform or :area.

            Draft commands:
              relato web drafts create --form-id ID [--locale LOCALE] [--team-id ID] [--compact]
                Creates a server-backed draft for a form returned by `web forms list`.
                The Apple response, including the new form response ID, is emitted as JSON.

              relato web drafts view --id ID [--locale LOCALE] [--compact]
                Reads a server-backed draft, including its form ID, saved answers, and
                attachment records.

              relato web drafts update --id ID [--payload PATH] [field options] [--answer TAT=VALUE]... [--locale LOCALE] [--compact]
                Fetches the current draft and form schema, preserves untouched answers,
                resolves choice labels to Apple's values, validates text limits, and saves
                the complete answer set.

                Named field options:
                  --title TEXT
                  --platform VALUE
                  --technology LABEL_OR_VALUE
                  --kind bug|suggestion
                  --description TEXT
                  --app TEXT
                  --impact TEXT
                  --foundation-models-mode feedback|samples|APPLE_VALUE

                --payload imports title, description, platform, category area, and kind
                from a `relato prepare` JSON payload. Explicit named options override it.
                Repeat --answer TAT=VALUE for conditional or form-specific questions.
                Repeating the same TAT supplies multiple checkbox values.

              relato web drafts attach --id ID [--file PATH]... [--payload PATH] [--locale LOCALE] [--compact]
                Uploads one or more local files through Apple's file-promise sequence:
                create, mark uploading, obtain a presigned object URL, upload raw bytes,
                mark uploaded, and verify the persisted file promise from the draft.

                Repeat --file to attach multiple files. --payload attaches the snapshot
                path from a `relato prepare` JSON payload. Duplicate paths are uploaded once.
                The command emits verified attachment receipts and never prints presigned URLs.

            Output:
              JSON is pretty-printed by default for agent inspection.
              --compact emits compact JSON.

            Boundaries:
              This experiment creates, reads, edits, and attaches files to drafts. It does
              not yet submit feedback. The stable native workflow is unchanged.
            """
        )
    }
}

do {
    try await RelatoCLI.run(Array(CommandLine.arguments.dropFirst()))
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    Foundation.exit(1)
}
