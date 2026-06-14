import Foundation
import Testing
@testable import RelatoKit

@Test func webSessionBuildsScopedCookieAndCSRFHeaders() throws {
    let future = Date().addingTimeInterval(3_600)
    let session = FeedbackWebSession(cookies: [
        FeedbackWebCookie(
            name: "SP-XSRF-TOKEN",
            value: "csrf-value",
            domain: "appleseed.apple.com",
            path: "/sp/",
            expiresAt: future
        ),
        FeedbackWebCookie(
            name: "SP-XSRF-TOKEN",
            value: "specific-csrf-value",
            domain: "appleseed.apple.com",
            path: "/sp/feedback/",
            expiresAt: future
        ),
        FeedbackWebCookie(
            name: "session",
            value: "session-value",
            domain: ".apple.com",
            expiresAt: future
        ),
        FeedbackWebCookie(
            name: "expired",
            value: "old",
            domain: "appleseed.apple.com",
            expiresAt: Date().addingTimeInterval(-60)
        ),
    ])
    let url = try #require(URL(string: "https://appleseed.apple.com/sp/feedback/form_items"))

    let header = try #require(session.cookieHeader(for: url))
    #expect(header.contains("SP-XSRF-TOKEN=csrf-value"))
    #expect(header.contains("session=session-value"))
    #expect(!header.contains("expired=old"))
    #expect(session.csrfToken(for: url) == "specific-csrf-value")

    let unrelated = try #require(URL(string: "https://example.com/sp/feedback/form_items"))
    #expect(session.cookieHeader(for: unrelated) == nil)
    #expect(session.csrfToken(for: unrelated) == nil)
    #expect(session.csrfToken(for: FeedbackWebAPI.serviceBase) == "csrf-value")

    let pathBoundary = FeedbackWebSession(cookies: [
        FeedbackWebCookie(
            name: "boundary",
            value: "secret",
            domain: "appleseed.apple.com",
            path: "/sp/form"
        )
    ])
    let sibling = try #require(URL(string: "https://appleseed.apple.com/sp/forms"))
    #expect(pathBoundary.cookieHeader(for: sibling) == nil)

    let hostOnly = FeedbackWebSession(cookies: [
        FeedbackWebCookie(
            name: "host-only",
            value: "secret",
            domain: "appleseed.apple.com"
        )
    ])
    let subdomain = try #require(URL(string: "https://child.appleseed.apple.com/sp/"))
    #expect(hostOnly.cookieHeader(for: subdomain) == nil)
}

@Test func webSessionQuotesAppleDESAuthenticationCookies() throws {
    let session = FeedbackWebSession(cookies: [
        FeedbackWebCookie(
            name: "DES5c148586dfd36821_1",
            value: "authentication-value",
            domain: ".apple.com"
        ),
        FeedbackWebCookie(
            name: "dslang",
            value: "US-EN",
            domain: ".apple.com"
        ),
    ])

    let header = try #require(
        session.appleAuthenticationCookieHeader(for: FeedbackWebAPI.loginURL)
    )
    #expect(header.contains(#"DES5c148586dfd36821_1="authentication-value""#))
    #expect(header.contains("dslang=US-EN"))
}

@Test func webSessionMergesReplacementAndExpiredCookies() throws {
    var session = FeedbackWebSession(cookies: [
        FeedbackWebCookie(
            name: "SP-XSRF-TOKEN",
            value: "old",
            domain: "appleseed.apple.com",
            path: "/sp/"
        ),
        FeedbackWebCookie(
            name: "remove-me",
            value: "old",
            domain: "appleseed.apple.com",
            path: "/sp/"
        ),
    ])
    let replacement = try #require(
        HTTPCookie(properties: [
            .name: "SP-XSRF-TOKEN",
            .value: "new",
            .domain: "appleseed.apple.com",
            .path: "/sp/",
            .secure: "TRUE",
        ])
    )
    let expired = try #require(
        HTTPCookie(properties: [
            .name: "remove-me",
            .value: "",
            .domain: "appleseed.apple.com",
            .path: "/sp/",
            .expires: Date().addingTimeInterval(-60),
        ])
    )

    session.merge([replacement, expired])

    #expect(session.cookies.count == 1)
    #expect(session.cookies[0].name == "SP-XSRF-TOKEN")
    #expect(session.cookies[0].value == "new")
}

@Test func webSessionAccountIdentifierHashIsNormalized() {
    let first = FeedbackWebSession.identifierHash(for: " User@Example.com ")
    let second = FeedbackWebSession.identifierHash(for: "user@example.com")

    #expect(first == second)
    #expect(first.count == 64)
    #expect(!first.contains("user@example.com"))
}

@Test func webSessionDecodesCachesWithoutAccountIdentifierHash() throws {
    let cached = FeedbackWebSession(cookies: [
        FeedbackWebCookie(
            name: "session",
            value: "value",
            domain: ".apple.com"
        )
    ])
    let decoded = try JSONDecoder().decode(
        FeedbackWebSession.self,
        from: JSONEncoder().encode(cached)
    )

    #expect(decoded.accountIdentifierHash == nil)
    #expect(decoded.cookies == cached.cookies)
}

@Test func webFileSessionStoreUsesOwnerOnlyPermissions() throws {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("relato-web-session-\(UUID().uuidString)")
    let store = FeedbackWebSessionStore(
        backend: .file,
        directoryURL: directoryURL
    )
    defer { try? FileManager.default.removeItem(at: directoryURL) }
    let session = FeedbackWebSession(cookies: [
        FeedbackWebCookie(
            name: "session",
            value: "value",
            domain: ".apple.com"
        )
    ])

    try store.save(session)

    #expect(try store.load() == session)
    let directoryAttributes = try FileManager.default.attributesOfItem(
        atPath: directoryURL.path
    )
    #expect(
        (directoryAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700
    )
    let sessionURL = directoryURL.appendingPathComponent("session.json")
    let fileAttributes = try FileManager.default.attributesOfItem(atPath: sessionURL.path)
    #expect((fileAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
}

@Test func webFileSessionStoreHandlesConcurrentSaves() async throws {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("relato-web-session-\(UUID().uuidString)")
    let store = FeedbackWebSessionStore(
        backend: .file,
        directoryURL: directoryURL
    )
    defer { try? FileManager.default.removeItem(at: directoryURL) }

    try await withThrowingTaskGroup(of: Void.self) { group in
        for index in 0..<16 {
            group.addTask {
                try store.save(
                    FeedbackWebSession(cookies: [
                        FeedbackWebCookie(
                            name: "session",
                            value: "\(index)",
                            domain: ".apple.com"
                        )
                    ])
                )
            }
        }
        try await group.waitForAll()
    }

    let loaded = try store.load()
    let saved = try #require(loaded)
    #expect(saved.cookies.count == 1)
}

@Test func webFileSessionStoreMergesCookiesFromStaleSessions() throws {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("relato-web-session-\(UUID().uuidString)")
    let store = FeedbackWebSessionStore(
        backend: .file,
        directoryURL: directoryURL
    )
    defer { try? FileManager.default.removeItem(at: directoryURL) }
    let original = FeedbackWebSession(cookies: [
        FeedbackWebCookie(
            name: "session",
            value: "original",
            domain: ".apple.com"
        )
    ])
    try store.save(original)

    let firstCookie = try #require(
        HTTPCookie(properties: [
            .name: "first",
            .value: "one",
            .domain: "appleseed.apple.com",
            .path: "/sp/",
        ])
    )
    let secondCookie = try #require(
        HTTPCookie(properties: [
            .name: "second",
            .value: "two",
            .domain: "appleseed.apple.com",
            .path: "/sp/",
        ])
    )

    _ = try store.mergeResponseCookies([firstCookie], into: original)
    _ = try store.mergeResponseCookies([secondCookie], into: original)

    let saved = try #require(try store.load())
    #expect(saved.cookies.contains(where: { $0.name == "session" }))
    #expect(saved.cookies.contains(where: { $0.name == "first" }))
    #expect(saved.cookies.contains(where: { $0.name == "second" }))
}

@Test func webFileSessionStoreRejectsBroadDirectoryWithoutChangingIt() throws {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("relato-web-session-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
        at: directoryURL,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o755]
    )
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: directoryURL.path
    )
    defer { try? FileManager.default.removeItem(at: directoryURL) }
    let store = FeedbackWebSessionStore(
        backend: .file,
        directoryURL: directoryURL
    )

    #expect(throws: RelatoError.self) {
        try store.save(FeedbackWebSession(cookies: []))
    }
    let attributes = try FileManager.default.attributesOfItem(atPath: directoryURL.path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o755)
}

@Test func webKeychainSessionStoreHandlesConcurrentInitialSaves() async throws {
    let store = FeedbackWebSessionStore(
        service: "com.rryam.RelatoKit.tests.\(UUID().uuidString)",
        backend: .keychain
    )
    defer { try? store.delete() }

    try await withThrowingTaskGroup(of: Void.self) { group in
        for index in 0..<16 {
            group.addTask {
                try store.save(
                    FeedbackWebSession(cookies: [
                        FeedbackWebCookie(
                            name: "session",
                            value: "\(index)",
                            domain: ".apple.com"
                        )
                    ])
                )
            }
        }
        try await group.waitForAll()
    }

    let loaded = try store.load()
    let saved = try #require(loaded)
    #expect(saved.cookies.count == 1)
}

@Suite(.serialized)
struct FeedbackWebClientTests {
    @Test func usesAppleseedHeadersAndRefreshesSession() async throws {
        defer { FeedbackWebMockURLProtocol.reset() }

        let configuration = FeedbackWebMockURLProtocol.configuration()
        FeedbackWebMockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: [
                    "Content-Type": "application/json",
                    "Set-Cookie":
                        "SP-XSRF-TOKEN=refreshed; Domain=appleseed.apple.com; Path=/sp/; Secure",
                ]
            )!
            return (response, Data(#"{"items":[]}"#.utf8))
        }

        let session = FeedbackWebSession(cookies: [
            FeedbackWebCookie(
                name: "SP-XSRF-TOKEN",
                value: "original",
                domain: "appleseed.apple.com",
                path: "/sp/"
            ),
            FeedbackWebCookie(
                name: "session",
                value: "secret",
                domain: ".apple.com"
            ),
        ])
        let client = FeedbackWebClient(session: session, configuration: configuration)

        let data = try await client.contentItems(locale: "en", teamID: "team 42")
        #expect(String(decoding: data, as: UTF8.self) == #"{"items":[]}"#)

        let request = try #require(FeedbackWebMockURLProtocol.lastRequest)
        #expect(request.httpMethod == "GET")
        #expect(
            request.url?.absoluteString
                == "https://appleseed.apple.com/sp/en/feedback/content_items?team_id=team%2042"
        )
        #expect(request.value(forHTTPHeaderField: "X-SP-API") == "4.2")
        #expect(request.value(forHTTPHeaderField: "X-CSRF-TOKEN") == "original")
        #expect(request.value(forHTTPHeaderField: "Cookie")?.contains("session=secret") == true)

        let updatedSession = await client.currentSession()
        #expect(
            updatedSession.cookies.first(where: { $0.name == "SP-XSRF-TOKEN" })?.value
                == "refreshed"
        )
    }

    @Test func treatsLoginRedirectAsExpiredSession() async throws {
        defer { FeedbackWebMockURLProtocol.reset() }

        let configuration = FeedbackWebMockURLProtocol.configuration()
        FeedbackWebMockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 302,
                httpVersion: nil,
                headerFields: [
                    "Location": FeedbackWebAPI.loginURL.absoluteString
                ]
            )!
            return (response, Data())
        }

        let client = FeedbackWebClient(
            session: FeedbackWebSession(cookies: []),
            configuration: configuration
        )

        await #expect(throws: FeedbackWebClientError.authenticationRequired) {
            try await client.authenticate()
        }
    }

    @Test func rejectedResponsesDoNotOverwriteCachedSessionCookies() async throws {
        defer { FeedbackWebMockURLProtocol.reset() }

        let configuration = FeedbackWebMockURLProtocol.configuration()
        FeedbackWebMockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 401,
                httpVersion: nil,
                headerFields: [
                    "Set-Cookie":
                        "SP-XSRF-TOKEN=poisoned; Domain=appleseed.apple.com; Path=/sp/; Secure"
                ]
            )!
            return (response, Data())
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FeedbackWebSessionStore(
            backend: .file,
            directoryURL: directory
        )
        let original = FeedbackWebSession(cookies: [
            FeedbackWebCookie(
                name: "SP-XSRF-TOKEN",
                value: "original",
                domain: "appleseed.apple.com",
                path: "/sp/"
            )
        ])
        try store.save(original)
        let client = FeedbackWebClient(
            session: original,
            sessionStore: store,
            configuration: configuration
        )

        await #expect(throws: FeedbackWebClientError.authenticationRequired) {
            try await client.authenticate()
        }
        let current = await client.currentSession()
        #expect(
            current.cookies.first(where: { $0.name == "SP-XSRF-TOKEN" })?.value
                == "original"
        )
        let loaded = try store.load()
        let cached = try #require(loaded)
        #expect(
            cached.cookies.first(where: { $0.name == "SP-XSRF-TOKEN" })?.value
                == "original"
        )
    }

    @Test func responseCookieSavePreservesParallelSessionUpdates() async throws {
        defer { FeedbackWebMockURLProtocol.reset() }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FeedbackWebSessionStore(
            backend: .file,
            directoryURL: directory
        )
        let original = FeedbackWebSession(cookies: [
            FeedbackWebCookie(
                name: "session",
                value: "original",
                domain: ".apple.com"
            )
        ])
        try store.save(original)

        let configuration = FeedbackWebMockURLProtocol.configuration()
        FeedbackWebMockURLProtocol.handler = { request in
            let parallelSession = FeedbackWebSession(cookies: original.cookies + [
                FeedbackWebCookie(
                    name: "parallel",
                    value: "preserved",
                    domain: "appleseed.apple.com",
                    path: "/sp/"
                )
            ])
            try store.save(parallelSession)
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: [
                    "Content-Type": "application/json",
                    "Set-Cookie":
                        "SP-XSRF-TOKEN=refreshed; Domain=appleseed.apple.com; Path=/sp/; Secure",
                ]
            )!
            return (response, Data(#"{"items":[]}"#.utf8))
        }

        let client = FeedbackWebClient(
            session: original,
            sessionStore: store,
            configuration: configuration
        )
        _ = try await client.authenticate()

        let saved = try #require(try store.load())
        #expect(
            saved.cookies.first(where: { $0.name == "parallel" })?.value
                == "preserved"
        )
        #expect(
            saved.cookies.first(where: { $0.name == "SP-XSRF-TOKEN" })?.value
                == "refreshed"
        )
        let current = await client.currentSession()
        #expect(current == saved)
    }

    @Test func createsServerBackedDraftForForm() async throws {
        defer { FeedbackWebMockURLProtocol.reset() }

        let configuration = FeedbackWebMockURLProtocol.configuration()
        FeedbackWebMockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 201,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(#"{"form_response":{"id":104688952}}"#.utf8))
        }

        let client = FeedbackWebClient(
            session: FeedbackWebSession(cookies: []),
            configuration: configuration
        )
        let data = try await client.createDraft(
            formID: "4167",
            locale: "en",
            teamID: " team 42 "
        )

        #expect(
            String(decoding: data, as: UTF8.self)
                == #"{"form_response":{"id":104688952}}"#
        )
        let request = try #require(FeedbackWebMockURLProtocol.lastRequest)
        #expect(request.httpMethod == "POST")
        #expect(
            request.url?.absoluteString
                == "https://appleseed.apple.com/sp/en/feedback/forms/4167/form_responses/start.json"
        )
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try #require(FeedbackWebMockURLProtocol.lastRequestBody)
        let object = try #require(
            JSONSerialization.jsonObject(with: body) as? [String: String]
        )
        #expect(object == ["team_id": "team 42"])
    }

    @Test func readsServerBackedDraft() async throws {
        defer { FeedbackWebMockURLProtocol.reset() }

        let configuration = FeedbackWebMockURLProtocol.configuration()
        FeedbackWebMockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (
                response,
                Data(#"{"id":104688952,"form_id":4167,"answers":[]}"#.utf8)
            )
        }

        let client = FeedbackWebClient(
            session: FeedbackWebSession(cookies: []),
            configuration: configuration
        )
        let data = try await client.draft(id: "104688952", locale: "en")

        #expect(
            String(decoding: data, as: UTF8.self)
                == #"{"id":104688952,"form_id":4167,"answers":[]}"#
        )
        let request = try #require(FeedbackWebMockURLProtocol.lastRequest)
        #expect(request.httpMethod == "GET")
        #expect(
            request.url?.absoluteString
                == "https://appleseed.apple.com/sp/en/feedback/form_responses/104688952"
        )
        #expect(FeedbackWebMockURLProtocol.lastRequestBody == nil)
    }

    @Test func readsSubmittedFeedbackDetails() async throws {
        defer { FeedbackWebMockURLProtocol.reset() }

        let configuration = FeedbackWebMockURLProtocol.configuration()
        FeedbackWebMockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (
                response,
                Data(
                    #"{"id":23049003,"form_response_id":103969139,"items":{"upsert":[{"id":23049003,"type":"FEEDBACK"}]}}"#
                        .utf8
                )
            )
        }

        let client = FeedbackWebClient(
            session: FeedbackWebSession(cookies: []),
            configuration: configuration
        )
        let data = try await client.feedback(id: "23049003", locale: "en")

        #expect(
            String(decoding: data, as: UTF8.self)
                == #"{"id":23049003,"form_response_id":103969139,"items":{"upsert":[{"id":23049003,"type":"FEEDBACK"}]}}"#
        )
        let request = try #require(FeedbackWebMockURLProtocol.lastRequest)
        #expect(request.httpMethod == "GET")
        #expect(
            request.url?.absoluteString
                == "https://appleseed.apple.com/sp/feedback/feedback_details/feedback/23049003"
        )
        #expect(FeedbackWebMockURLProtocol.lastRequestBody == nil)
    }

    @Test func readsSubmittedFeedbackStatus() async throws {
        defer { FeedbackWebMockURLProtocol.reset() }

        let configuration = FeedbackWebMockURLProtocol.configuration()
        FeedbackWebMockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (
                response,
                Data(
                    #"{"id":23049003,"status":[{"key":"Recent Similar Reports","value":"None"}]}"#
                        .utf8
                )
            )
        }

        let client = FeedbackWebClient(
            session: FeedbackWebSession(cookies: []),
            configuration: configuration
        )
        let data = try await client.feedbackStatus(id: "23049003", locale: "en")

        #expect(
            String(decoding: data, as: UTF8.self)
                == #"{"id":23049003,"status":[{"key":"Recent Similar Reports","value":"None"}]}"#
        )
        let request = try #require(FeedbackWebMockURLProtocol.lastRequest)
        #expect(request.httpMethod == "GET")
        #expect(
            request.url?.absoluteString
                == "https://appleseed.apple.com/sp/feedback/23049003/status"
        )
        #expect(FeedbackWebMockURLProtocol.lastRequestBody == nil)
    }

    @Test func updatesCompleteDraftAnswerSet() async throws {
        defer { FeedbackWebMockURLProtocol.reset() }

        let configuration = FeedbackWebMockURLProtocol.configuration()
        FeedbackWebMockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(#"{"answers":[],"items":{"upsert":[],"delete":[]}}"#.utf8))
        }

        let client = FeedbackWebClient(
            session: FeedbackWebSession(cookies: []),
            configuration: configuration
        )
        let data = try await client.updateDraftAnswers(
            id: "104688952",
            locale: "en",
            answers: [
                FeedbackWebAnswerMutation(questionID: 366028, values: ["Video input"]),
                FeedbackWebAnswerMutation(questionID: 364164, ignoreRequired: true),
            ]
        )

        #expect(
            String(decoding: data, as: UTF8.self)
                == #"{"answers":[],"items":{"upsert":[],"delete":[]}}"#
        )
        let request = try #require(FeedbackWebMockURLProtocol.lastRequest)
        #expect(request.httpMethod == "PUT")
        #expect(
            request.url?.absoluteString
                == "https://appleseed.apple.com/sp/en/feedback/form_responses/104688952/answers.json"
        )
        let body = try #require(FeedbackWebMockURLProtocol.lastRequestBody)
        let object = try #require(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        let answers = try #require(object["answers"] as? [[String: Any]])
        #expect(answers.count == 2)
        #expect(answers[0]["question_id"] as? Int == 366028)
        #expect(answers[0]["values"] as? [String] == ["Video input"])
        #expect(answers[0]["ignore_required"] == nil)
        #expect(answers[1]["question_id"] as? Int == 364164)
        #expect(answers[1]["values"] == nil)
        #expect(answers[1]["ignore_required"] as? Bool == true)
    }

    @Test func uploadsAndVerifiesDraftAttachment() async throws {
        defer { FeedbackWebMockURLProtocol.reset() }

        FeedbackWebMockURLProtocol.reset()
        let configuration = FeedbackWebMockURLProtocol.configuration()
        FeedbackWebMockURLProtocol.handler = { request in
            let url = try #require(request.url)
            let responseBody: Data
            let status: Int

            switch (request.httpMethod, url.host, url.path) {
            case ("POST"?, "appleseed.apple.com", "/sp/feedback/file_promise/new"):
                status = 201
                responseBody = Data(#"{"uuid":"BE25C106-A40B-4C79-B94E-B9BC8BD46640"}"#.utf8)
            case ("PUT"?, "appleseed.apple.com", let path)
                where path == "/sp/feedback/file_promise/BE25C106-A40B-4C79-B94E-B9BC8BD46640":
                status = 200
                responseBody = Data(#"{"ok":true}"#.utf8)
            case ("GET"?, "appleseed.apple.com", let path)
                where path == "/sp/feedback/file_promise/BE25C106-A40B-4C79-B94E-B9BC8BD46640/upload_link":
                status = 200
                responseBody = Data(
                    #"{"presigned_url":"https://uploads.example.test/object"}"#.utf8
                )
            case ("PUT"?, "uploads.example.test", "/object"):
                status = 200
                responseBody = Data()
            case ("GET"?, "appleseed.apple.com", "/sp/en/feedback/form_responses/104688952"):
                status = 200
                responseBody = Data(
                    #"""
                    {
                      "id": 104688952,
                      "form_id": 4167,
                      "answers": [],
                      "file_promises": [
                        {
                          "id": 60604757,
                          "uuid": "BE25C106-A40B-4C79-B94E-B9BC8BD46640",
                          "name": "evidence.md",
                          "size": 17,
                          "status_enum": 40
                        }
                      ]
                    }
                    """#.utf8
                )
            default:
                throw RelatoError.web(
                    "unexpected mock attachment request: \(request.httpMethod ?? "") \(url)"
                )
            }

            let response = HTTPURLResponse(
                url: url,
                statusCode: status,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, responseBody)
        }

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("evidence.md")
        try Data("attachment bytes\n".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let client = FeedbackWebClient(
            session: FeedbackWebSession(cookies: [
                FeedbackWebCookie(
                    name: "SP-XSRF-TOKEN",
                    value: "csrf",
                    domain: "appleseed.apple.com",
                    path: "/sp/"
                ),
                FeedbackWebCookie(
                    name: "session",
                    value: "secret",
                    domain: ".apple.com"
                ),
            ]),
            configuration: configuration
        )
        let receipt = try await client.uploadAttachment(
            draftID: "104688952",
            fileURL: fileURL
        )

        #expect(receipt.draftID == 104688952)
        #expect(receipt.id == 60604757)
        #expect(receipt.name == "evidence.md")
        #expect(receipt.size == 17)
        #expect(receipt.status == 40)
        #expect(receipt.verified)

        let requests = FeedbackWebMockURLProtocol.requests
        #expect(requests.map(\.httpMethod) == ["POST", "PUT", "GET", "PUT", "PUT", "GET"])
        #expect(requests[0].url?.path == "/sp/feedback/file_promise/new")
        #expect(requests[2].url?.path.hasSuffix("/upload_link") == true)
        #expect(requests[3].url?.host == "uploads.example.test")
        #expect(requests[5].url?.path == "/sp/en/feedback/form_responses/104688952")
        #expect(requests[3].value(forHTTPHeaderField: "Cookie") == nil)
        #expect(requests[3].value(forHTTPHeaderField: "X-CSRF-TOKEN") == nil)
        #expect(requests[3].value(forHTTPHeaderField: "X-SP-API") == nil)
        #expect(
            requests[3].value(forHTTPHeaderField: "Content-Type")
                == "application/x-www-form-urlencoded"
        )

        let statusBodies = [1, 4].compactMap {
            FeedbackWebMockURLProtocol.requestBodies[$0]
        }.compactMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        }
        #expect(statusBodies.compactMap { $0["status"] as? String } == ["uploading", "uploaded"])
    }

    @Test func marksFilePromiseErroredWhenObjectUploadFails() async throws {
        defer { FeedbackWebMockURLProtocol.reset() }

        FeedbackWebMockURLProtocol.reset()
        let configuration = FeedbackWebMockURLProtocol.configuration()
        FeedbackWebMockURLProtocol.handler = { request in
            let url = try #require(request.url)
            let status: Int
            let responseBody: Data

            switch (request.httpMethod, url.host, url.path) {
            case ("POST"?, "appleseed.apple.com", "/sp/feedback/file_promise/new"):
                status = 201
                responseBody = Data(#"{"uuid":"FAILED-UPLOAD"}"#.utf8)
            case ("PUT"?, "appleseed.apple.com", "/sp/feedback/file_promise/FAILED-UPLOAD"):
                status = 200
                responseBody = Data(#"{"ok":true}"#.utf8)
            case ("GET"?, "appleseed.apple.com", "/sp/feedback/file_promise/FAILED-UPLOAD/upload_link"):
                status = 200
                responseBody = Data(
                    #"{"presigned_url":"https://uploads.example.test/failure"}"#.utf8
                )
            case ("PUT"?, "uploads.example.test", "/failure"):
                status = 500
                responseBody = Data()
            default:
                throw RelatoError.web(
                    "unexpected mock failed-upload request: \(request.httpMethod ?? "") \(url)"
                )
            }

            let response = HTTPURLResponse(
                url: url,
                statusCode: status,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, responseBody)
        }

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("failed-upload.txt")
        try Data("test".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let client = FeedbackWebClient(
            session: FeedbackWebSession(cookies: []),
            configuration: configuration
        )
        await #expect(
            throws: FeedbackWebClientError.requestFailed(
                status: 500,
                path: "attachment object upload"
            )
        ) {
            try await client.uploadAttachment(
                draftID: "104688952",
                fileURL: fileURL
            )
        }

        let statusBodies: [[String: Any]] =
            FeedbackWebMockURLProtocol.requestBodies.compactMap { body in
                guard
                    let body,
                    let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                    object["status"] != nil
                else {
                    return nil
                }
                return object
            }
        #expect(
            statusBodies.compactMap { $0["status"] as? String }
                == ["uploading", "upload_error"]
        )
    }

    @Test func submitsDraftAndVerifiesServerReceipt() async throws {
        defer { FeedbackWebMockURLProtocol.reset() }

        FeedbackWebMockURLProtocol.reset()
        let configuration = FeedbackWebMockURLProtocol.configuration()
        FeedbackWebMockURLProtocol.handler = { request in
            let url = try #require(request.url)
            let responseBody: Data

            switch (request.httpMethod, url.path) {
            case ("GET"?, "/sp/en/feedback/form_responses/104688952"):
                responseBody = Data(
                    #"""
                    {
                      "id": 104688952,
                      "form_id": 4167,
                      "answers": [
                        {"question_id": 366028, "values": ["Video input"]},
                        {"question_id": 366031, "values": ["Suggestion"]}
                      ],
                      "file_promises": [
                        {
                          "id": 60604757,
                          "uuid": "BE25C106-A40B-4C79-B94E-B9BC8BD46640",
                          "name": "evidence.md",
                          "size": 823,
                          "status_enum": 40
                        }
                      ]
                    }
                    """#.utf8
                )
            case ("GET"?, "/sp/en/feedback/forms/4167"):
                responseBody = Data(
                    #"""
                    {
                      "id": 4167,
                      "name": "Developer Technologies & SDKs",
                      "question_groups": [
                        {
                          "title": "Basic Information",
                          "questions": [
                            {
                              "id": 366028,
                              "tat": ":title",
                              "text": "Title",
                              "answer_widget": "Text Field",
                              "is_required": true,
                              "is_visible_in_form": true
                            },
                            {
                              "id": 366031,
                              "tat": ":type_req",
                              "text": "Feedback type",
                              "answer_widget": "Popup",
                              "is_required": true,
                              "is_visible_in_form": true
                            },
                            {
                              "id": 364164,
                              "tat": ":required_file_zone",
                              "text": "Attach evidence",
                              "answer_widget": "Required File Zone",
                              "is_required": true,
                              "is_visible_in_form": true,
                              "conditions": "[[\":type_req\",\":==\",\"Suggestion\"]]"
                            }
                          ]
                        }
                      ]
                    }
                    """#.utf8
                )
            case ("PUT"?, "/sp/en/feedback/form_responses/104688952/answers.json"):
                responseBody = Data(#"{"answers":[],"items":{"upsert":[]}}"#.utf8)
            case ("PUT"?, "/sp/en/feedback/forms/4167/form_responses/104688952"):
                responseBody = Data(
                    #"{"items":{"upsert":[{"id":60604757,"type":"FILE_PROMISE"},{"id":23050000,"type":"FEEDBACK"}]}}"#
                        .utf8
                )
            case ("GET"?, "/sp/feedback/feedback_details/feedback/23050000"):
                responseBody = Data(
                    #"{"id":23050000,"form_response_id":104688952,"items":{"upsert":[{"id":23050000,"type":"FEEDBACK"}]}}"#
                        .utf8
                )
            default:
                throw RelatoError.web(
                    "unexpected mock submission request: \(request.httpMethod ?? "") \(url)"
                )
            }

            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, responseBody)
        }

        let client = FeedbackWebClient(
            session: FeedbackWebSession(cookies: []),
            configuration: configuration
        )
        let receipt = try await client.submitDraft(id: "104688952")

        #expect(receipt.draftID == 104688952)
        #expect(receipt.formID == 4167)
        #expect(receipt.feedbackID == 23050000)
        #expect(receipt.feedbackNumber == "FB23050000")
        #expect(receipt.webURL == "https://feedbackassistant.apple.com/feedback/23050000")
        #expect(receipt.verified)

        let requests = FeedbackWebMockURLProtocol.requests
        #expect(requests.map(\.httpMethod) == ["GET", "GET", "PUT", "PUT", "GET"])
        #expect(requests[2].url?.path.hasSuffix("/answers.json") == true)
        #expect(
            requests[3].url?.path
                == "/sp/en/feedback/forms/4167/form_responses/104688952"
        )
        #expect(
            requests[4].url?.path
                == "/sp/feedback/feedback_details/feedback/23050000"
        )

        let answerBody = try #require(FeedbackWebMockURLProtocol.requestBodies[2])
        let answerObject = try #require(
            JSONSerialization.jsonObject(with: answerBody) as? [String: Any]
        )
        let answers = try #require(answerObject["answers"] as? [[String: Any]])
        let fileAnswer = try #require(
            answers.first(where: { $0["question_id"] as? Int == 364164 })
        )
        #expect(fileAnswer["values"] as? Bool == false)
        #expect(fileAnswer["ignore_required"] as? Bool == true)

        let submitBody = try #require(FeedbackWebMockURLProtocol.requestBodies[3])
        let submitObject = try #require(
            JSONSerialization.jsonObject(with: submitBody) as? [String: Any]
        )
        let formResponse = try #require(
            submitObject["form_response"] as? [String: Bool]
        )
        #expect(
            formResponse
                == ["used_filer": true, "answers_complete": true]
        )
    }

    @Test func refusesSubmissionBeforeMutationWhenRequiredFieldsAreMissing() async throws {
        defer { FeedbackWebMockURLProtocol.reset() }

        FeedbackWebMockURLProtocol.reset()
        let configuration = FeedbackWebMockURLProtocol.configuration()
        FeedbackWebMockURLProtocol.handler = { request in
            let url = try #require(request.url)
            let responseBody: Data

            switch (request.httpMethod, url.path) {
            case ("GET"?, "/sp/en/feedback/form_responses/104688952"):
                responseBody = Data(
                    #"{"id":104688952,"form_id":4167,"answers":[],"file_promises":[]}"#
                        .utf8
                )
            case ("GET"?, "/sp/en/feedback/forms/4167"):
                responseBody = Data(
                    #"""
                    {
                      "id": 4167,
                      "name": "Developer Technologies & SDKs",
                      "form_role": "Issue",
                      "question_groups": [
                        {
                          "title": "Basic Information",
                          "questions": [
                            {
                              "id": 366028,
                              "tat": ":title",
                              "text": "Title",
                              "answer_widget": "Text Field",
                              "is_required": true,
                              "is_visible_in_form": true
                            }
                          ]
                        }
                      ]
                    }
                    """#.utf8
                )
            default:
                throw RelatoError.web(
                    "unexpected mock preflight request: \(request.httpMethod ?? "") \(url)"
                )
            }

            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, responseBody)
        }

        let client = FeedbackWebClient(
            session: FeedbackWebSession(cookies: []),
            configuration: configuration
        )
        await #expect(throws: RelatoError.self) {
            try await client.submitDraft(id: "104688952")
        }
        #expect(FeedbackWebMockURLProtocol.requests.map(\.httpMethod) == ["GET", "GET"])
    }

    @Test func refusesSurveySubmissionBeforeMutation() async throws {
        defer { FeedbackWebMockURLProtocol.reset() }

        FeedbackWebMockURLProtocol.reset()
        let configuration = FeedbackWebMockURLProtocol.configuration()
        FeedbackWebMockURLProtocol.handler = { request in
            let url = try #require(request.url)
            let responseBody: Data

            switch (request.httpMethod, url.path) {
            case ("GET"?, "/sp/en/feedback/form_responses/104688952"):
                responseBody = Data(
                    #"{"id":104688952,"form_id":4167,"answers":[],"file_promises":[]}"#
                        .utf8
                )
            case ("GET"?, "/sp/en/feedback/forms/4167"):
                responseBody = Data(
                    #"""
                    {
                      "id": 4167,
                      "name": "Developer Survey",
                      "form_role": "Survey",
                      "question_groups": []
                    }
                    """#.utf8
                )
            default:
                throw RelatoError.web(
                    "unexpected mock survey request: \(request.httpMethod ?? "") \(url)"
                )
            }

            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, responseBody)
        }

        let client = FeedbackWebClient(
            session: FeedbackWebSession(cookies: []),
            configuration: configuration
        )
        await #expect(throws: RelatoError.self) {
            try await client.submitDraft(id: "104688952")
        }
        #expect(FeedbackWebMockURLProtocol.requests.map(\.httpMethod) == ["GET", "GET"])
    }
}

private final class FeedbackWebMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler:
        ((URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastRequestBody: Data?
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var requestBodies: [Data?] = []

    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Self.self]
        return configuration
    }

    static func reset() {
        handler = nil
        lastRequest = nil
        lastRequestBody = nil
        requests = []
        requestBodies = []
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lastRequest = request
        Self.lastRequestBody = Self.bodyData(from: request)
        Self.requests.append(request)
        Self.requestBodies.append(Self.lastRequestBody)
        do {
            guard let handler = Self.handler else {
                throw RelatoError.web("missing mock URL handler")
            }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else {
                break
            }
            data.append(buffer, count: count)
        }
        return data
    }
}
