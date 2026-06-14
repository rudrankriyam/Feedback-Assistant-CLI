import BigInt
import Foundation

public enum FeedbackWebTwoFactorMethod: String, Sendable {
    case trustedDevice = "trusted-device"
    case phone
}

public struct FeedbackWebTwoFactorChallenge: Equatable, Sendable {
    public let method: FeedbackWebTwoFactorMethod
    public let destination: String?
    public let codeWasRequested: Bool

    public init(
        method: FeedbackWebTwoFactorMethod,
        destination: String? = nil,
        codeWasRequested: Bool = false
    ) {
        self.method = method
        self.destination = destination
        self.codeWasRequested = codeWasRequested
    }
}

public enum FeedbackWebAuthenticationError: Error, CustomStringConvertible, Equatable {
    case invalidCredentials
    case accountActionRequired
    case malformedLoginConfiguration
    case twoFactorCodeRequired
    case noTrustedPhoneNumbers
    case invalidTwoFactorCode
    case feedbackSessionRejected
    case requestFailed(stage: String, status: Int)
    case transport(stage: String)

    public var description: String {
        switch self {
        case .invalidCredentials:
            return "incorrect Apple Account email or password"
        case .accountActionRequired:
            return "Apple requires an account action in a browser before headless login can continue"
        case .malformedLoginConfiguration:
            return "Apple returned an invalid Feedback Assistant login configuration"
        case .twoFactorCodeRequired:
            return "Apple requires a two-factor code"
        case .noTrustedPhoneNumbers:
            return "Apple requires phone verification, but no trusted phone number is available"
        case .invalidTwoFactorCode:
            return "Apple rejected the two-factor code"
        case .feedbackSessionRejected:
            return "Feedback Assistant rejected the authenticated Apple Account session"
        case .requestFailed(let stage, let status):
            return "Apple \(stage) request failed with HTTP \(status)"
        case .transport(let stage):
            return "Apple \(stage) request failed"
        }
    }
}

public actor FeedbackWebAuthenticator {
    public typealias TwoFactorCodeProvider =
        @Sendable (FeedbackWebTwoFactorChallenge) async throws -> String

    private var session: FeedbackWebSession
    private let urlSession: URLSession

    public init(
        session: FeedbackWebSession = FeedbackWebSession(cookies: []),
        configuration: URLSessionConfiguration = .ephemeral
    ) {
        self.session = session
        self.urlSession = FeedbackWebHTTP.makeSession(configuration: configuration)
    }

    public func login(
        appleID: String,
        password: String,
        twoFactorCodeProvider: TwoFactorCodeProvider? = nil
    ) async throws -> FeedbackWebSession {
        let appleID = appleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !appleID.isEmpty else {
            throw RelatoError.invalidArgument("Apple Account email is required")
        }
        guard !password.isEmpty else {
            throw RelatoError.invalidArgument("Apple Account password is required")
        }
        let accountIdentifierHash = FeedbackWebSession.identifierHash(for: appleID)
        session = FeedbackWebSession(
            cookies: [],
            accountIdentifierHash: accountIdentifierHash
        )

        let configuration = try await fetchLoginConfiguration()
        if let pending = try await performSRPLogin(
            appleID: appleID,
            password: password,
            widgetKey: configuration.widgetKey
        ) {
            guard let twoFactorCodeProvider else {
                throw FeedbackWebAuthenticationError.twoFactorCodeRequired
            }
            try await completeTwoFactor(
                pending,
                codeProvider: twoFactorCodeProvider
            )
        }

        try await bootstrapFeedbackSession()
        session.accountIdentifierHash = accountIdentifierHash
        session.updatedAt = Date()
        return session
    }

    public func currentSession() -> FeedbackWebSession {
        session
    }

    private func fetchLoginConfiguration() async throws -> FeedbackWebLoginConfiguration {
        let response = try await send(
            stage: "login configuration",
            method: "GET",
            url: FeedbackWebAPI.loginURL,
            headers: [
                "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
            ]
        )
        guard response.http.statusCode == 200 else {
            throw FeedbackWebAuthenticationError.requestFailed(
                stage: "login configuration",
                status: response.http.statusCode
            )
        }
        return try FeedbackWebLoginConfiguration.parse(response.data)
    }

    private func performSRPLogin(
        appleID: String,
        password: String,
        widgetKey: String
    ) async throws -> PendingTwoFactor? {
        let secret = try FeedbackWebSRP.randomSecret()
        let publicValue = FeedbackWebSRP.publicValue(secret: secret)
        let initResponse = try await signinInit(
            appleID: appleID,
            publicValue: publicValue,
            widgetKey: widgetKey
        )

        guard
            let salt = Data(base64Encoded: initResponse.salt),
            !salt.isEmpty,
            let serverPublicValue = Data(base64Encoded: initResponse.serverPublicValue),
            !serverPublicValue.isEmpty,
            !initResponse.challenge.isNull
        else {
            throw FeedbackWebAuthenticationError.malformedLoginConfiguration
        }
        let derivedPassword = try FeedbackWebSRP.derivePassword(
            password: password,
            protocolName: initResponse.protocolName,
            salt: salt,
            iterations: initResponse.iteration
        )
        let proof = try FeedbackWebSRP.calculateProof(
            username: appleID,
            secret: secret,
            publicValue: publicValue,
            serverPublicValue: serverPublicValue,
            derivedPassword: derivedPassword,
            salt: salt
        )
        let hashcash = try await fetchHashcash(widgetKey: widgetKey)
        return try await signinComplete(
            appleID: appleID,
            proof: proof,
            challenge: initResponse.challenge,
            widgetKey: widgetKey,
            hashcash: hashcash
        )
    }

    private func signinInit(
        appleID: String,
        publicValue: BigUInt,
        widgetKey: String
    ) async throws -> SigninInitResponse {
        let payload = SigninInitRequest(
            accountName: appleID,
            protocols: ["s2k", "s2k_fo"],
            publicValue: publicValue.serialize().base64EncodedString()
        )
        let response = try await sendJSON(
            stage: "sign-in initialization",
            method: "POST",
            url: FeedbackWebAPI.authServiceURL.appendingPathComponent("signin/init"),
            headers: appleWidgetHeaders(widgetKey: widgetKey),
            payload: payload
        )
        guard response.http.statusCode == 200 else {
            throw FeedbackWebAuthenticationError.requestFailed(
                stage: "sign-in initialization",
                status: response.http.statusCode
            )
        }
        do {
            return try JSONDecoder().decode(SigninInitResponse.self, from: response.data)
        } catch {
            throw FeedbackWebAuthenticationError.malformedLoginConfiguration
        }
    }

    private func fetchHashcash(widgetKey: String) async throws -> String? {
        var components = URLComponents(
            url: FeedbackWebAPI.authServiceURL.appendingPathComponent("signin"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "widgetKey", value: widgetKey)]
        guard let url = components?.url else {
            throw FeedbackWebAuthenticationError.malformedLoginConfiguration
        }

        let response = try await send(
            stage: "hashcash",
            method: "GET",
            url: url,
            headers: [
                "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
            ]
        )
        guard response.http.statusCode == 200 else {
            throw FeedbackWebAuthenticationError.requestFailed(
                stage: "hashcash",
                status: response.http.statusCode
            )
        }
        guard
            let bitsValue = response.http.value(forHTTPHeaderField: "X-Apple-HC-Bits"),
            let bits = Int(bitsValue),
            let challenge = response.http.value(forHTTPHeaderField: "X-Apple-HC-Challenge"),
            !challenge.isEmpty
        else {
            return nil
        }
        return try FeedbackWebSRP.makeHashcash(bits: bits, challenge: challenge)
    }

    private func signinComplete(
        appleID: String,
        proof: FeedbackWebSRPProof,
        challenge: FeedbackJSONValue,
        widgetKey: String,
        hashcash: String?
    ) async throws -> PendingTwoFactor? {
        var components = URLComponents(
            url: FeedbackWebAPI.authServiceURL.appendingPathComponent("signin/complete"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "isRememberMeEnabled", value: "false")
        ]
        guard let url = components?.url else {
            throw FeedbackWebAuthenticationError.malformedLoginConfiguration
        }

        var headers = appleWidgetHeaders(widgetKey: widgetKey)
        if let hashcash, !hashcash.isEmpty {
            headers["X-Apple-HC"] = hashcash
        }
        let response = try await sendJSON(
            stage: "sign-in completion",
            method: "POST",
            url: url,
            headers: headers,
            payload: SigninCompleteRequest(
                accountName: appleID,
                rememberMe: false,
                m1: proof.m1,
                m2: proof.m2,
                challenge: challenge
            )
        )

        switch response.http.statusCode {
        case 200:
            return nil
        case 409:
            guard
                let appleIDSessionID = response.http.value(
                    forHTTPHeaderField: "X-Apple-ID-Session-Id"
                ),
                let scnt = response.http.value(forHTTPHeaderField: "scnt"),
                !appleIDSessionID.isEmpty,
                !scnt.isEmpty
            else {
                throw FeedbackWebAuthenticationError.malformedLoginConfiguration
            }
            return PendingTwoFactor(
                widgetKey: widgetKey,
                appleIDSessionID: appleIDSessionID,
                scnt: scnt
            )
        case 401 where serviceErrorCodes(response.data).contains("-20101"):
            throw FeedbackWebAuthenticationError.invalidCredentials
        case 412 where accountActionRequired(response.data):
            throw FeedbackWebAuthenticationError.accountActionRequired
        default:
            throw FeedbackWebAuthenticationError.requestFailed(
                stage: "sign-in completion",
                status: response.http.statusCode
            )
        }
    }

    private func completeTwoFactor(
        _ initialPending: PendingTwoFactor,
        codeProvider: TwoFactorCodeProvider
    ) async throws {
        var pending = initialPending
        let optionsStep = try await authOptions(pending)
        let options = optionsStep.options
        pending = optionsStep.pending
        let phone = options.trustedPhoneNumbers.first

        if options.noTrustedDevices {
            guard let phone else {
                throw FeedbackWebAuthenticationError.noTrustedPhoneNumbers
            }
            pending = try await requestPhoneCode(phone, pending: pending)
            let code = try await resolveCode(
                from: codeProvider,
                challenge: FeedbackWebTwoFactorChallenge(
                    method: .phone,
                    destination: phone.numberWithDialCode.nilIfEmpty,
                    codeWasRequested: true
                )
            )
            pending = try await submitPhoneCode(code, phone: phone, pending: pending)
            try await finalizeTwoFactor(pending)
            return
        }

        let trustedDeviceCode = try await resolveCode(
            from: codeProvider,
            challenge: FeedbackWebTwoFactorChallenge(
                method: .trustedDevice,
                destination: phone?.numberWithDialCode.nilIfEmpty
            )
        )
        let trustedDeviceStep = try await submitTrustedDeviceCode(
            trustedDeviceCode,
            pending: pending
        )
        pending = trustedDeviceStep.pending
        if trustedDeviceStep.accepted {
            try await finalizeTwoFactor(pending)
            return
        }

        guard let phone else {
            throw FeedbackWebAuthenticationError.invalidTwoFactorCode
        }
        pending = try await requestPhoneCode(phone, pending: pending)
        let phoneCode = try await resolveCode(
            from: codeProvider,
            challenge: FeedbackWebTwoFactorChallenge(
                method: .phone,
                destination: phone.numberWithDialCode.nilIfEmpty,
                codeWasRequested: true
            )
        )
        pending = try await submitPhoneCode(phoneCode, phone: phone, pending: pending)
        try await finalizeTwoFactor(pending)
    }

    private func resolveCode(
        from provider: TwoFactorCodeProvider,
        challenge: FeedbackWebTwoFactorChallenge
    ) async throws -> String {
        let code = try await provider(challenge)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            throw FeedbackWebAuthenticationError.twoFactorCodeRequired
        }
        return code
    }

    private func authOptions(
        _ pending: PendingTwoFactor
    ) async throws -> (options: AuthOptionsResponse, pending: PendingTwoFactor) {
        let response = try await send(
            stage: "two-factor options",
            method: "GET",
            url: FeedbackWebAPI.authServiceURL,
            headers: appleSessionHeaders(pending)
        )
        let refreshedPending = pending.refreshing(from: response.http)
        guard (200..<300).contains(response.http.statusCode) else {
            throw FeedbackWebAuthenticationError.requestFailed(
                stage: "two-factor options",
                status: response.http.statusCode
            )
        }
        do {
            return (
                try JSONDecoder().decode(AuthOptionsResponse.self, from: response.data),
                refreshedPending
            )
        } catch {
            throw FeedbackWebAuthenticationError.malformedLoginConfiguration
        }
    }

    private func requestPhoneCode(
        _ phone: TrustedPhoneNumber,
        pending: PendingTwoFactor
    ) async throws -> PendingTwoFactor {
        let response = try await sendJSON(
            stage: "phone code delivery",
            method: "PUT",
            url: FeedbackWebAPI.authServiceURL.appendingPathComponent("verify/phone"),
            headers: appleSessionHeaders(pending),
            payload: PhoneCodeRequest(
                phoneNumber: PhoneNumberID(id: phone.id),
                mode: phone.mode
            )
        )
        let refreshedPending = pending.refreshing(from: response.http)
        guard (200..<300).contains(response.http.statusCode) else {
            throw FeedbackWebAuthenticationError.requestFailed(
                stage: "phone code delivery",
                status: response.http.statusCode
            )
        }
        return refreshedPending
    }

    private func submitTrustedDeviceCode(
        _ code: String,
        pending: PendingTwoFactor
    ) async throws -> (accepted: Bool, pending: PendingTwoFactor) {
        let response = try await sendJSON(
            stage: "trusted-device verification",
            method: "POST",
            url: FeedbackWebAPI.authServiceURL.appendingPathComponent(
                "verify/trusteddevice/securitycode"
            ),
            headers: appleSessionHeaders(pending),
            payload: SecurityCodeRequest(securityCode: SecurityCode(code: code))
        )
        let refreshedPending = pending.refreshing(from: response.http)
        if (200..<300).contains(response.http.statusCode) {
            return (true, refreshedPending)
        }
        if response.http.statusCode == 400 {
            return (false, refreshedPending)
        }
        throw FeedbackWebAuthenticationError.requestFailed(
            stage: "trusted-device verification",
            status: response.http.statusCode
        )
    }

    private func submitPhoneCode(
        _ code: String,
        phone: TrustedPhoneNumber,
        pending: PendingTwoFactor
    ) async throws -> PendingTwoFactor {
        let response = try await sendJSON(
            stage: "phone verification",
            method: "POST",
            url: FeedbackWebAPI.authServiceURL.appendingPathComponent(
                "verify/phone/securitycode"
            ),
            headers: appleSessionHeaders(pending),
            payload: PhoneSecurityCodeRequest(
                securityCode: SecurityCode(code: code),
                phoneNumber: PhoneNumberID(id: phone.id),
                mode: phone.mode
            )
        )
        let refreshedPending = pending.refreshing(from: response.http)
        if response.http.statusCode == 400 {
            throw FeedbackWebAuthenticationError.invalidTwoFactorCode
        }
        guard (200..<300).contains(response.http.statusCode) else {
            throw FeedbackWebAuthenticationError.requestFailed(
                stage: "phone verification",
                status: response.http.statusCode
            )
        }
        return refreshedPending
    }

    private func finalizeTwoFactor(_ pending: PendingTwoFactor) async throws {
        let response = try await send(
            stage: "two-factor trust",
            method: "GET",
            url: FeedbackWebAPI.authServiceURL.appendingPathComponent("2sv/trust"),
            headers: appleSessionHeaders(pending)
        )
        guard (200..<300).contains(response.http.statusCode) else {
            throw FeedbackWebAuthenticationError.requestFailed(
                stage: "two-factor trust",
                status: response.http.statusCode
            )
        }
    }

    private func bootstrapFeedbackSession() async throws {
        let url = FeedbackWebAPI.serviceBase.appendingPathComponent("login/with_ds")
        var headers = [
            "Accept": "application/json",
            "X-SP-API": FeedbackWebAPI.apiVersion,
            "locale": "en",
            "Origin": FeedbackWebAPI.webBase.absoluteString,
            "Referer": FeedbackWebAPI.webBase.absoluteString + "/",
        ]
        if let csrfToken = session.csrfToken(for: url) {
            headers["X-CSRF-TOKEN"] = csrfToken
        }
        let response = try await send(
            stage: "Feedback Assistant session",
            method: "POST",
            url: url,
            headers: headers
        )
        guard (200..<300).contains(response.http.statusCode) else {
            if response.http.statusCode == 401 || response.http.statusCode == 403 {
                throw FeedbackWebAuthenticationError.feedbackSessionRejected
            }
            throw FeedbackWebAuthenticationError.requestFailed(
                stage: "Feedback Assistant session",
                status: response.http.statusCode
            )
        }
        guard
            (try? JSONSerialization.jsonObject(with: response.data)) != nil,
            session.csrfToken(for: url) != nil
        else {
            throw FeedbackWebAuthenticationError.feedbackSessionRejected
        }
    }

    private func appleWidgetHeaders(widgetKey: String) -> [String: String] {
        [
            "Accept": "application/json, text/javascript",
            "X-Apple-Widget-Key": widgetKey,
            "X-Requested-With": "XMLHttpRequest",
        ]
    }

    private func appleSessionHeaders(_ pending: PendingTwoFactor) -> [String: String] {
        [
            "Accept": "application/json",
            "X-Apple-ID-Session-Id": pending.appleIDSessionID,
            "X-Apple-Widget-Key": pending.widgetKey,
            "scnt": pending.scnt,
        ]
    }

    private func sendJSON<Payload: Encodable>(
        stage: String,
        method: String,
        url: URL,
        headers: [String: String],
        payload: Payload
    ) async throws -> WebResponse {
        let body: Data
        do {
            body = try JSONEncoder().encode(payload)
        } catch {
            throw RelatoError.web("could not encode Apple \(stage) request")
        }
        var headers = headers
        headers["Content-Type"] = "application/json"
        return try await send(
            stage: stage,
            method: method,
            url: url,
            headers: headers,
            body: body
        )
    }

    private func send(
        stage: String,
        method: String,
        url: URL,
        headers: [String: String] = [:],
        body: Data? = nil
    ) async throws -> WebResponse {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 60
        request.setValue(FeedbackWebHTTP.userAgent, forHTTPHeaderField: "User-Agent")
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        if let cookieHeader = session.appleAuthenticationCookieHeader(for: url) {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw FeedbackWebAuthenticationError.transport(stage: stage)
        }
        guard let http = response as? HTTPURLResponse else {
            throw FeedbackWebAuthenticationError.transport(stage: stage)
        }

        let responseCookies = HTTPCookie.cookies(
            withResponseHeaderFields: FeedbackWebHTTP.responseHeaderFields(http),
            for: url
        )
        if !responseCookies.isEmpty {
            session.merge(responseCookies)
        }
        return WebResponse(data: data, http: http)
    }

    private func serviceErrorCodes(_ data: Data) -> [String] {
        (try? JSONDecoder().decode(ServiceErrorsResponse.self, from: data))?
            .serviceErrors
            .map(\.code) ?? []
    }

    private func accountActionRequired(_ data: Data) -> Bool {
        guard
            let response = try? JSONDecoder().decode(AuthTypeResponse.self, from: data)
        else {
            return false
        }
        return ["sa", "hsa", "non-sa", "hsa2"].contains(response.authType)
    }
}

struct FeedbackWebLoginConfiguration: Equatable, Sendable {
    let widgetKey: String

    static func parse(_ data: Data) throws -> FeedbackWebLoginConfiguration {
        guard let html = String(data: data, encoding: .utf8) else {
            throw FeedbackWebAuthenticationError.malformedLoginConfiguration
        }
        let marker = #"id="embed_login_boot_args""#
        guard
            let markerRange = html.range(of: marker),
            let tagEnd = html[markerRange.upperBound...].firstIndex(of: ">"),
            let scriptEnd = html[tagEnd...].range(of: "</script>")?.lowerBound
        else {
            throw FeedbackWebAuthenticationError.malformedLoginConfiguration
        }

        let json = html[html.index(after: tagEnd)..<scriptEnd]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let jsonData = json.data(using: .utf8) else {
            throw FeedbackWebAuthenticationError.malformedLoginConfiguration
        }
        let boot: LoginBootPayload
        do {
            boot = try JSONDecoder().decode(LoginBootPayload.self, from: jsonData)
        } catch {
            throw FeedbackWebAuthenticationError.malformedLoginConfiguration
        }
        let widgetKey = boot.direct.authWidgetConfig.widgetKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !widgetKey.isEmpty,
            boot.direct.app.appIDKey == FeedbackWebAPI.appIDKey
        else {
            throw FeedbackWebAuthenticationError.malformedLoginConfiguration
        }
        return FeedbackWebLoginConfiguration(widgetKey: widgetKey)
    }
}

private struct WebResponse: Sendable {
    let data: Data
    let http: HTTPURLResponse
}

private struct PendingTwoFactor: Sendable {
    let widgetKey: String
    let appleIDSessionID: String
    let scnt: String

    func refreshing(from response: HTTPURLResponse) -> PendingTwoFactor {
        let appleIDSessionID =
            response.value(forHTTPHeaderField: "X-Apple-ID-Session-Id")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? self.appleIDSessionID
        let scnt =
            response.value(forHTTPHeaderField: "scnt")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? self.scnt
        return PendingTwoFactor(
            widgetKey: widgetKey,
            appleIDSessionID: appleIDSessionID,
            scnt: scnt
        )
    }
}

private struct LoginBootPayload: Decodable {
    let direct: Direct

    struct Direct: Decodable {
        let authWidgetConfig: AuthWidgetConfig
        let app: App
    }

    struct AuthWidgetConfig: Decodable {
        let widgetKey: String
    }

    struct App: Decodable {
        let appIDKey: String

        enum CodingKeys: String, CodingKey {
            case appIDKey = "appIdKey"
        }
    }
}

private struct SigninInitRequest: Encodable {
    let accountName: String
    let protocols: [String]
    let publicValue: String

    enum CodingKeys: String, CodingKey {
        case accountName
        case protocols
        case publicValue = "a"
    }
}

private struct SigninInitResponse: Decodable {
    let iteration: Int
    let salt: String
    let protocolName: String
    let serverPublicValue: String
    let challenge: FeedbackJSONValue

    enum CodingKeys: String, CodingKey {
        case iteration
        case salt
        case protocolName = "protocol"
        case serverPublicValue = "b"
        case challenge = "c"
    }
}

private struct SigninCompleteRequest: Encodable {
    let accountName: String
    let rememberMe: Bool
    let m1: String
    let m2: String
    let challenge: FeedbackJSONValue

    enum CodingKeys: String, CodingKey {
        case accountName
        case rememberMe
        case m1
        case m2
        case challenge = "c"
    }
}

private struct AuthOptionsResponse: Decodable {
    let noTrustedDevices: Bool
    let trustedPhoneNumbers: [TrustedPhoneNumber]

    enum CodingKeys: String, CodingKey {
        case noTrustedDevices
        case trustedPhoneNumbers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        noTrustedDevices = try container.decodeIfPresent(
            Bool.self,
            forKey: .noTrustedDevices
        ) ?? false
        trustedPhoneNumbers = try container.decodeIfPresent(
            [TrustedPhoneNumber].self,
            forKey: .trustedPhoneNumbers
        ) ?? []
    }
}

private struct TrustedPhoneNumber: Decodable, Sendable {
    let id: Int
    let pushMode: String
    let numberWithDialCode: String

    var mode: String {
        pushMode.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "sms"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case pushMode
        case numberWithDialCode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        pushMode = try container.decodeIfPresent(String.self, forKey: .pushMode) ?? ""
        numberWithDialCode = try container.decodeIfPresent(
            String.self,
            forKey: .numberWithDialCode
        ) ?? ""
    }
}

private struct PhoneNumberID: Encodable {
    let id: Int
}

private struct SecurityCode: Encodable {
    let code: String
}

private struct PhoneCodeRequest: Encodable {
    let phoneNumber: PhoneNumberID
    let mode: String
}

private struct SecurityCodeRequest: Encodable {
    let securityCode: SecurityCode
}

private struct PhoneSecurityCodeRequest: Encodable {
    let securityCode: SecurityCode
    let phoneNumber: PhoneNumberID
    let mode: String
}

private struct ServiceErrorsResponse: Decodable {
    let serviceErrors: [ServiceError]

    struct ServiceError: Decodable {
        let code: String
    }
}

private struct AuthTypeResponse: Decodable {
    let authType: String
}

private enum FeedbackJSONValue: Codable, Sendable {
    case object([String: FeedbackJSONValue])
    case array([FeedbackJSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    var isNull: Bool {
        if case .null = self {
            return true
        }
        return false
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([FeedbackJSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: FeedbackJSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
