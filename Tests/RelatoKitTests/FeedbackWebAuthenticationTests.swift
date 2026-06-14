import CryptoKit
import Foundation
import Testing
@testable import RelatoKit

@Test func webSRPMatchesASCCompatibleProofVector() throws {
    let secret = Data([0x03])
    let publicValue = FeedbackWebSRP.publicValue(secret: secret)
    let proof = try FeedbackWebSRP.calculateProof(
        username: "user@example.com",
        secret: secret,
        publicValue: publicValue,
        serverPublicValue: Data([0x02]),
        derivedPassword: try data(
            hex: "06263ef837edf62da9b9e5e3d69daf2df11ed1ed6f1604181658b63f16d19307"
        ),
        salt: Data([0x0A])
    )

    #expect(publicValue.serialize() == Data([0x08]))
    #expect(proof.m1 == "7nP/M1eqifu5GVm8ZAFQD04WVs3k7ih4Lf3xJkLzUuE=")
    #expect(proof.m2 == "wFjQ5ic+j0g8435QIQEm93BzZQgWw1OJZe7uqavhVZ4=")
}

@Test func webSRPDerivesBothApplePasswordProtocols() throws {
    let salt = Data([0x0A])
    let s2k = try FeedbackWebSRP.derivePassword(
        password: "example",
        protocolName: "s2k",
        salt: salt,
        iterations: 1_000
    )
    let s2kFO = try FeedbackWebSRP.derivePassword(
        password: "example",
        protocolName: "s2k_fo",
        salt: salt,
        iterations: 1_000
    )
    let expectedS2K = try data(
        hex: "a2edc9acfa1fd2f2da40f9080c158fa79d649fcaf879735d80f7fa4879fcd420"
    )
    let expectedS2KFO = try data(
        hex: "bca8f09dcbca05ce9cbebe1b8bd229393709691ecbefdb749bb82fa6d84e0d22"
    )

    #expect(s2k == expectedS2K)
    #expect(s2kFO == expectedS2KFO)
}

@Test func webSRPBuildsValidHashcash() throws {
    let hashcash = try FeedbackWebSRP.makeHashcash(
        bits: 10,
        challenge: "feedback-assistant",
        date: Date(timeIntervalSince1970: 0)
    )
    let digest = Data(Insecure.SHA1.hash(data: Data(hashcash.utf8)))

    #expect(hashcash.hasPrefix("1:10:19700101000000:feedback-assistant::"))
    #expect(FeedbackWebSRP.hasLeadingZeroBits(digest, count: 10))
}

@Test func webSRPRejectsInvalidServerValue() throws {
    #expect(throws: RelatoError.self) {
        try FeedbackWebSRP.calculateProof(
            username: "user@example.com",
            secret: Data([0x03]),
            publicValue: FeedbackWebSRP.publicValue(secret: Data([0x03])),
            serverPublicValue: Data([0x00]),
            derivedPassword: Data(repeating: 0x01, count: 32),
            salt: Data([0x0A])
        )
    }
}

@Test func webLoginConfigurationReadsDynamicWidgetKey() throws {
    let configuration = try FeedbackWebLoginConfiguration.parse(
        Data(loginHTML(widgetKey: "dynamic-widget-key").utf8)
    )

    #expect(configuration.widgetKey == "dynamic-widget-key")
}

@Test func webClientsDoNotMutateCallerSessionConfigurations() {
    let clientConfiguration = URLSessionConfiguration.ephemeral
    clientConfiguration.httpShouldSetCookies = true
    clientConfiguration.requestCachePolicy = .returnCacheDataElseLoad
    _ = FeedbackWebClient(
        session: FeedbackWebSession(cookies: []),
        configuration: clientConfiguration
    )
    #expect(clientConfiguration.httpShouldSetCookies)
    #expect(clientConfiguration.requestCachePolicy == .returnCacheDataElseLoad)

    let authenticationConfiguration = URLSessionConfiguration.ephemeral
    authenticationConfiguration.httpShouldSetCookies = true
    authenticationConfiguration.requestCachePolicy = .returnCacheDataElseLoad
    _ = FeedbackWebAuthenticator(configuration: authenticationConfiguration)
    #expect(authenticationConfiguration.httpShouldSetCookies)
    #expect(authenticationConfiguration.requestCachePolicy == .returnCacheDataElseLoad)
}

@Suite(.serialized)
struct FeedbackWebAuthenticationFlowTests {
    @Test func performsHeadlessSRPAndBootstrapsAppleseed() async throws {
        defer { FeedbackWebAuthenticationMockURLProtocol.reset() }
        var requests: [URLRequest] = []
        FeedbackWebAuthenticationMockURLProtocol.handler = { request in
            requests.append(request)
            let index = requests.count
            switch index {
            case 1:
                return response(
                    request,
                    status: 200,
                    headers: [
                        "Content-Type": "text/html",
                        "Set-Cookie": "dslang=US-EN; Domain=apple.com; Path=/; Secure",
                    ],
                    body: loginHTML(widgetKey: "widget-key")
                )
            case 2:
                return response(
                    request,
                    status: 200,
                    body:
                        #"{"iteration":1,"salt":"Cg==","protocol":"s2k","b":"Ag==","c":"challenge"}"#
                )
            case 3:
                return response(request, status: 200, body: "")
            case 4:
                return response(
                    request,
                    status: 200,
                    headers: [
                        "Set-Cookie":
                            "myacinfo=account-session; Domain=.apple.com; Path=/; Secure; HttpOnly"
                    ],
                    body: "{}"
                )
            case 5:
                return response(
                    request,
                    status: 200,
                    headers: [
                        "Set-Cookie":
                            "SP-XSRF-TOKEN=csrf-token; Domain=appleseed.apple.com; Path=/sp/; Secure, _seedportal_session=feedback-session; Domain=.apple.com; Path=/; Secure; HttpOnly"
                    ],
                    body: #"{"participant":{"id":"1"}}"#
                )
            default:
                throw RelatoError.web("unexpected request \(index)")
            }
        }

        let authenticator = FeedbackWebAuthenticator(
            configuration: FeedbackWebAuthenticationMockURLProtocol.configuration()
        )
        let session = try await authenticator.login(
            appleID: "user@example.com",
            password: "example"
        )

        #expect(requests.count == 5)
        #expect(requests[0].url == FeedbackWebAPI.loginURL)
        #expect(requests[1].url?.path == "/appleauth/auth/signin/init")
        #expect(requests[1].value(forHTTPHeaderField: "X-Apple-Widget-Key") == "widget-key")
        #expect(requests[1].value(forHTTPHeaderField: "Cookie")?.contains("dslang=US-EN") == true)
        #expect(requests[3].url?.path == "/appleauth/auth/signin/complete")
        #expect(requests[4].url?.path == "/sp/login/with_ds")
        #expect(
            requests[4].value(forHTTPHeaderField: "Cookie")?
                .contains("myacinfo=account-session") == true
        )
        #expect(
            session.cookies.first(where: { $0.name == "SP-XSRF-TOKEN" })?.value
                == "csrf-token"
        )
        #expect(
            session.accountIdentifierHash
                == FeedbackWebSession.identifierHash(for: "user@example.com")
        )
    }

    @Test func discardsCachedCookiesBeforeReauthentication() async throws {
        defer { FeedbackWebAuthenticationMockURLProtocol.reset() }
        var requests: [URLRequest] = []
        FeedbackWebAuthenticationMockURLProtocol.handler = { request in
            requests.append(request)
            switch requests.count {
            case 1:
                #expect(
                    request.value(forHTTPHeaderField: "Cookie")?.contains("old-session")
                        != true
                )
                return response(
                    request,
                    status: 200,
                    body: loginHTML(widgetKey: "widget-key")
                )
            case 2:
                return response(
                    request,
                    status: 200,
                    body:
                        #"{"iteration":1,"salt":"Cg==","protocol":"s2k","b":"Ag==","c":"challenge"}"#
                )
            case 3, 4:
                return response(request, status: 200, body: "{}")
            case 5:
                return response(
                    request,
                    status: 200,
                    headers: [
                        "Set-Cookie":
                            "SP-XSRF-TOKEN=csrf-token; Domain=appleseed.apple.com; Path=/sp/; Secure"
                    ],
                    body: #"{"participant":{"id":"1"}}"#
                )
            default:
                throw RelatoError.web("unexpected request \(requests.count)")
            }
        }

        let cached = FeedbackWebSession(
            cookies: [
                FeedbackWebCookie(
                    name: "myacinfo",
                    value: "old-session",
                    domain: ".apple.com"
                )
            ],
            accountIdentifierHash: FeedbackWebSession.identifierHash(
                for: "user@example.com"
            )
        )
        let authenticator = FeedbackWebAuthenticator(
            session: cached,
            configuration: FeedbackWebAuthenticationMockURLProtocol.configuration()
        )
        let session = try await authenticator.login(
            appleID: "user@example.com",
            password: "example"
        )

        #expect(requests.count == 5)
        #expect(session.cookies.contains(where: { $0.value == "old-session" }) == false)
    }

    @Test func completesPhoneTwoFactorBeforeAppleseedBootstrap() async throws {
        defer { FeedbackWebAuthenticationMockURLProtocol.reset() }
        var requests: [URLRequest] = []
        FeedbackWebAuthenticationMockURLProtocol.handler = { request in
            requests.append(request)
            let index = requests.count
            switch index {
            case 1:
                return response(
                    request,
                    status: 200,
                    body: loginHTML(widgetKey: "widget-key")
                )
            case 2:
                return response(
                    request,
                    status: 200,
                    body:
                        #"{"iteration":1,"salt":"Cg==","protocol":"s2k_fo","b":"Ag==","c":{"token":"challenge"}}"#
                )
            case 3:
                return response(request, status: 200, body: "")
            case 4:
                return response(
                    request,
                    status: 409,
                    headers: [
                        "X-Apple-ID-Session-Id": "apple-session-id",
                        "scnt": "scnt-token",
                    ],
                    body: "{}"
                )
            case 5:
                return response(
                    request,
                    status: 200,
                    body:
                        #"{"noTrustedDevices":true,"trustedPhoneNumbers":[{"id":42,"pushMode":"sms","numberWithDialCode":"••• ••67"}]}"#
                )
            case 6, 7:
                return response(request, status: 200, body: "{}")
            case 8:
                return response(
                    request,
                    status: 200,
                    headers: [
                        "Set-Cookie":
                            "myacinfo=two-factor-session; Domain=.apple.com; Path=/; Secure; HttpOnly"
                    ],
                    body: "{}"
                )
            case 9:
                return response(
                    request,
                    status: 200,
                    headers: [
                        "Set-Cookie":
                            "SP-XSRF-TOKEN=csrf-token; Domain=appleseed.apple.com; Path=/sp/; Secure"
                    ],
                    body: #"{"participant":{"id":"1"}}"#
                )
            default:
                throw RelatoError.web("unexpected request \(index)")
            }
        }

        let recorder = ChallengeRecorder()
        let authenticator = FeedbackWebAuthenticator(
            configuration: FeedbackWebAuthenticationMockURLProtocol.configuration()
        )
        let session = try await authenticator.login(
            appleID: "user@example.com",
            password: "example"
        ) { challenge in
            await recorder.record(challenge)
            return "123456"
        }

        #expect(requests.count == 9)
        #expect(requests[4].url?.path == "/appleauth/auth")
        #expect(requests[5].url?.path == "/appleauth/auth/verify/phone")
        #expect(requests[6].url?.path == "/appleauth/auth/verify/phone/securitycode")
        #expect(requests[7].url?.path == "/appleauth/auth/2sv/trust")
        for request in requests[4...7] {
            #expect(
                request.value(forHTTPHeaderField: "X-Apple-ID-Session-Id")
                    == "apple-session-id"
            )
            #expect(request.value(forHTTPHeaderField: "scnt") == "scnt-token")
        }
        let challenges = await recorder.challenges
        #expect(
            challenges
                == [
                    FeedbackWebTwoFactorChallenge(
                        method: .phone,
                        destination: "••• ••67",
                        codeWasRequested: true
                    )
                ]
        )
        #expect(
            session.cookies.first(where: { $0.name == "SP-XSRF-TOKEN" })?.value
                == "csrf-token"
        )
    }

    @Test func completesTrustedDeviceTwoFactorBeforeAppleseedBootstrap() async throws {
        defer { FeedbackWebAuthenticationMockURLProtocol.reset() }
        var requests: [URLRequest] = []
        FeedbackWebAuthenticationMockURLProtocol.handler = { request in
            requests.append(request)
            switch requests.count {
            case 1:
                return response(
                    request,
                    status: 200,
                    body: loginHTML(widgetKey: "widget-key")
                )
            case 2:
                return response(
                    request,
                    status: 200,
                    body:
                        #"{"iteration":1,"salt":"Cg==","protocol":"s2k","b":"Ag==","c":"challenge"}"#
                )
            case 3:
                return response(request, status: 200, body: "")
            case 4:
                return response(
                    request,
                    status: 409,
                    headers: [
                        "X-Apple-ID-Session-Id": "apple-session-id",
                        "scnt": "scnt-token",
                    ],
                    body: "{}"
                )
            case 5:
                return response(
                    request,
                    status: 200,
                    body:
                        #"{"noTrustedDevices":false,"trustedPhoneNumbers":[{"id":42,"pushMode":"sms","numberWithDialCode":"••• ••67"}]}"#
                )
            case 6:
                return response(request, status: 200, body: "{}")
            case 7:
                return response(
                    request,
                    status: 200,
                    headers: [
                        "Set-Cookie":
                            "myacinfo=trusted-device-session; Domain=.apple.com; Path=/; Secure; HttpOnly"
                    ],
                    body: "{}"
                )
            case 8:
                return response(
                    request,
                    status: 200,
                    headers: [
                        "Set-Cookie":
                            "SP-XSRF-TOKEN=csrf-token; Domain=appleseed.apple.com; Path=/sp/; Secure"
                    ],
                    body: #"{"participant":{"id":"1"}}"#
                )
            default:
                throw RelatoError.web("unexpected request \(requests.count)")
            }
        }

        let recorder = ChallengeRecorder()
        let authenticator = FeedbackWebAuthenticator(
            configuration: FeedbackWebAuthenticationMockURLProtocol.configuration()
        )
        let session = try await authenticator.login(
            appleID: "user@example.com",
            password: "example"
        ) { challenge in
            await recorder.record(challenge)
            return "123456"
        }

        #expect(requests.count == 8)
        #expect(requests[5].url?.path == "/appleauth/auth/verify/trusteddevice/securitycode")
        #expect(requests[6].url?.path == "/appleauth/auth/2sv/trust")
        #expect(
            await recorder.challenges
                == [
                    FeedbackWebTwoFactorChallenge(
                        method: .trustedDevice,
                        destination: "••• ••67"
                    )
                ]
        )
        #expect(
            session.cookies.first(where: { $0.name == "SP-XSRF-TOKEN" })?.value
                == "csrf-token"
        )
    }

    @Test func rotatesContinuationHeadersDuringTrustedDeviceFallback() async throws {
        defer { FeedbackWebAuthenticationMockURLProtocol.reset() }
        var requests: [URLRequest] = []
        FeedbackWebAuthenticationMockURLProtocol.handler = { request in
            requests.append(request)
            switch requests.count {
            case 1:
                return response(
                    request,
                    status: 200,
                    body: loginHTML(widgetKey: "widget-key")
                )
            case 2:
                return response(
                    request,
                    status: 200,
                    body:
                        #"{"iteration":1,"salt":"Cg==","protocol":"s2k","b":"Ag==","c":"challenge"}"#
                )
            case 3:
                return response(request, status: 200, body: "")
            case 4:
                return response(
                    request,
                    status: 409,
                    headers: [
                        "X-Apple-ID-Session-Id": "session-initial",
                        "scnt": "scnt-initial",
                    ],
                    body: "{}"
                )
            case 5:
                #expect(
                    request.value(forHTTPHeaderField: "X-Apple-ID-Session-Id")
                        == "session-initial"
                )
                #expect(request.value(forHTTPHeaderField: "scnt") == "scnt-initial")
                return response(
                    request,
                    status: 200,
                    headers: [
                        "X-Apple-ID-Session-Id": "session-options",
                        "scnt": "scnt-options",
                    ],
                    body:
                        #"{"noTrustedDevices":false,"trustedPhoneNumbers":[{"id":42,"pushMode":"sms","numberWithDialCode":"••• ••67"}]}"#
                )
            case 6:
                #expect(
                    request.value(forHTTPHeaderField: "X-Apple-ID-Session-Id")
                        == "session-options"
                )
                #expect(request.value(forHTTPHeaderField: "scnt") == "scnt-options")
                return response(
                    request,
                    status: 400,
                    headers: [
                        "X-Apple-ID-Session-Id": "session-trusted",
                        "scnt": "scnt-trusted",
                    ],
                    body: #"{"serviceErrors":[{"code":"-21669"}]}"#
                )
            case 7:
                #expect(request.url?.path == "/appleauth/auth/verify/phone")
                #expect(
                    request.value(forHTTPHeaderField: "X-Apple-ID-Session-Id")
                        == "session-trusted"
                )
                #expect(request.value(forHTTPHeaderField: "scnt") == "scnt-trusted")
                return response(
                    request,
                    status: 200,
                    headers: [
                        "X-Apple-ID-Session-Id": "session-delivery",
                        "scnt": "scnt-delivery",
                    ],
                    body: "{}"
                )
            case 8:
                #expect(request.url?.path == "/appleauth/auth/verify/phone/securitycode")
                #expect(
                    request.value(forHTTPHeaderField: "X-Apple-ID-Session-Id")
                        == "session-delivery"
                )
                #expect(request.value(forHTTPHeaderField: "scnt") == "scnt-delivery")
                return response(
                    request,
                    status: 200,
                    headers: [
                        "X-Apple-ID-Session-Id": "session-phone",
                        "scnt": "scnt-phone",
                    ],
                    body: "{}"
                )
            case 9:
                #expect(request.url?.path == "/appleauth/auth/2sv/trust")
                #expect(
                    request.value(forHTTPHeaderField: "X-Apple-ID-Session-Id")
                        == "session-phone"
                )
                #expect(request.value(forHTTPHeaderField: "scnt") == "scnt-phone")
                return response(
                    request,
                    status: 200,
                    headers: [
                        "Set-Cookie":
                            "myacinfo=fallback-session; Domain=.apple.com; Path=/; Secure; HttpOnly"
                    ],
                    body: "{}"
                )
            case 10:
                return response(
                    request,
                    status: 200,
                    headers: [
                        "Set-Cookie":
                            "SP-XSRF-TOKEN=csrf-token; Domain=appleseed.apple.com; Path=/sp/; Secure"
                    ],
                    body: #"{"participant":{"id":"1"}}"#
                )
            default:
                throw RelatoError.web("unexpected request \(requests.count)")
            }
        }

        let recorder = ChallengeRecorder()
        let authenticator = FeedbackWebAuthenticator(
            configuration: FeedbackWebAuthenticationMockURLProtocol.configuration()
        )
        let session = try await authenticator.login(
            appleID: "user@example.com",
            password: "example"
        ) { challenge in
            await recorder.record(challenge)
            return "123456"
        }

        #expect(requests.count == 10)
        #expect(
            await recorder.challenges
                == [
                    FeedbackWebTwoFactorChallenge(
                        method: .trustedDevice,
                        destination: "••• ••67"
                    ),
                    FeedbackWebTwoFactorChallenge(
                        method: .phone,
                        destination: "••• ••67",
                        codeWasRequested: true
                    ),
                ]
        )
        #expect(
            session.cookies.first(where: { $0.name == "SP-XSRF-TOKEN" })?.value
                == "csrf-token"
        )
    }

    @Test func trustedDeviceServerErrorDoesNotTriggerPhoneFallback() async throws {
        defer { FeedbackWebAuthenticationMockURLProtocol.reset() }
        var requests: [URLRequest] = []
        FeedbackWebAuthenticationMockURLProtocol.handler = { request in
            requests.append(request)
            switch requests.count {
            case 1:
                return response(
                    request,
                    status: 200,
                    body: loginHTML(widgetKey: "widget-key")
                )
            case 2:
                return response(
                    request,
                    status: 200,
                    body:
                        #"{"iteration":1,"salt":"Cg==","protocol":"s2k","b":"Ag==","c":"challenge"}"#
                )
            case 3:
                return response(request, status: 200, body: "")
            case 4:
                return response(
                    request,
                    status: 409,
                    headers: [
                        "X-Apple-ID-Session-Id": "apple-session-id",
                        "scnt": "scnt-token",
                    ],
                    body: "{}"
                )
            case 5:
                return response(
                    request,
                    status: 200,
                    body:
                        #"{"noTrustedDevices":false,"trustedPhoneNumbers":[{"id":42,"pushMode":"sms","numberWithDialCode":"••• ••67"}]}"#
                )
            case 6:
                return response(request, status: 500, body: "{}")
            default:
                throw RelatoError.web("unexpected fallback request \(requests.count)")
            }
        }

        let authenticator = FeedbackWebAuthenticator(
            configuration: FeedbackWebAuthenticationMockURLProtocol.configuration()
        )
        await #expect(
            throws: FeedbackWebAuthenticationError.requestFailed(
                stage: "trusted-device verification",
                status: 500
            )
        ) {
            try await authenticator.login(
                appleID: "user@example.com",
                password: "example"
            ) { _ in
                "123456"
            }
        }
        #expect(requests.count == 6)
        #expect(
            requests.last?.url?.path
                == "/appleauth/auth/verify/trusteddevice/securitycode"
        )
    }

    @Test func phoneRateLimitIsReportedAsARequestFailure() async throws {
        defer { FeedbackWebAuthenticationMockURLProtocol.reset() }
        var requests: [URLRequest] = []
        FeedbackWebAuthenticationMockURLProtocol.handler = { request in
            requests.append(request)
            switch requests.count {
            case 1:
                return response(
                    request,
                    status: 200,
                    body: loginHTML(widgetKey: "widget-key")
                )
            case 2:
                return response(
                    request,
                    status: 200,
                    body:
                        #"{"iteration":1,"salt":"Cg==","protocol":"s2k","b":"Ag==","c":"challenge"}"#
                )
            case 3:
                return response(request, status: 200, body: "")
            case 4:
                return response(
                    request,
                    status: 409,
                    headers: [
                        "X-Apple-ID-Session-Id": "apple-session-id",
                        "scnt": "scnt-token",
                    ],
                    body: "{}"
                )
            case 5:
                return response(
                    request,
                    status: 200,
                    body:
                        #"{"noTrustedDevices":true,"trustedPhoneNumbers":[{"id":42,"pushMode":"sms","numberWithDialCode":"••• ••67"}]}"#
                )
            case 6:
                return response(request, status: 200, body: "{}")
            case 7:
                return response(request, status: 429, body: "{}")
            default:
                throw RelatoError.web("unexpected phone request \(requests.count)")
            }
        }

        let authenticator = FeedbackWebAuthenticator(
            configuration: FeedbackWebAuthenticationMockURLProtocol.configuration()
        )
        await #expect(
            throws: FeedbackWebAuthenticationError.requestFailed(
                stage: "phone verification",
                status: 429
            )
        ) {
            try await authenticator.login(
                appleID: "user@example.com",
                password: "example"
            ) { _ in
                "123456"
            }
        }
        #expect(requests.count == 7)
        #expect(
            requests.last?.url?.path
                == "/appleauth/auth/verify/phone/securitycode"
        )
    }
}

private actor ChallengeRecorder {
    private(set) var challenges: [FeedbackWebTwoFactorChallenge] = []

    func record(_ challenge: FeedbackWebTwoFactorChallenge) {
        challenges.append(challenge)
    }
}

private final class FeedbackWebAuthenticationMockURLProtocol:
    URLProtocol,
    @unchecked Sendable
{
    nonisolated(unsafe) static var handler:
        ((URLRequest) throws -> (HTTPURLResponse, Data))?

    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Self.self]
        return configuration
    }

    static func reset() {
        handler = nil
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            guard let handler = Self.handler else {
                throw RelatoError.web("missing authentication mock handler")
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
}

private func response(
    _ request: URLRequest,
    status: Int,
    headers: [String: String] = [:],
    body: String
) -> (HTTPURLResponse, Data) {
    let response = HTTPURLResponse(
        url: request.url!,
        statusCode: status,
        httpVersion: nil,
        headerFields: headers
    )!
    return (response, Data(body.utf8))
}

private func loginHTML(widgetKey: String) -> String {
    """
    <html>
      <script type="application/json" id="embed_login_boot_args">
        {
          "direct": {
            "authWidgetConfig": {"widgetKey": "\(widgetKey)"},
            "app": {"appIdKey": "\(FeedbackWebAPI.appIDKey)"}
          }
        }
      </script>
    </html>
    """
}

private func data(hex: String) throws -> Data {
    guard hex.count.isMultiple(of: 2) else {
        throw RelatoError.web("invalid test hex")
    }
    var output = Data()
    output.reserveCapacity(hex.count / 2)
    var index = hex.startIndex
    while index < hex.endIndex {
        let next = hex.index(index, offsetBy: 2)
        guard let byte = UInt8(hex[index..<next], radix: 16) else {
            throw RelatoError.web("invalid test hex")
        }
        output.append(byte)
        index = next
    }
    return output
}
