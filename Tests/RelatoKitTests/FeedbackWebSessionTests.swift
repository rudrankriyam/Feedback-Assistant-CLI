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

@Suite(.serialized)
struct FeedbackWebClientTests {
    @Test func usesAppleseedHeadersAndRefreshesSession() async throws {
        defer {
            FeedbackWebMockURLProtocol.handler = nil
            FeedbackWebMockURLProtocol.lastRequest = nil
            FeedbackWebMockURLProtocol.lastRequestBody = nil
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FeedbackWebMockURLProtocol.self]
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
        defer {
            FeedbackWebMockURLProtocol.handler = nil
            FeedbackWebMockURLProtocol.lastRequest = nil
            FeedbackWebMockURLProtocol.lastRequestBody = nil
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FeedbackWebMockURLProtocol.self]
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

    @Test func createsServerBackedDraftForForm() async throws {
        defer {
            FeedbackWebMockURLProtocol.handler = nil
            FeedbackWebMockURLProtocol.lastRequest = nil
            FeedbackWebMockURLProtocol.lastRequestBody = nil
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FeedbackWebMockURLProtocol.self]
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
        defer {
            FeedbackWebMockURLProtocol.handler = nil
            FeedbackWebMockURLProtocol.lastRequest = nil
            FeedbackWebMockURLProtocol.lastRequestBody = nil
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FeedbackWebMockURLProtocol.self]
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

    @Test func updatesCompleteDraftAnswerSet() async throws {
        defer {
            FeedbackWebMockURLProtocol.handler = nil
            FeedbackWebMockURLProtocol.lastRequest = nil
            FeedbackWebMockURLProtocol.lastRequestBody = nil
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FeedbackWebMockURLProtocol.self]
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
}

private final class FeedbackWebMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler:
        ((URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastRequestBody: Data?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lastRequest = request
        Self.lastRequestBody = Self.bodyData(from: request)
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
