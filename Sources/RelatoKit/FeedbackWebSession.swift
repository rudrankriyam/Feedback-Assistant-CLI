import CryptoKit
import Foundation
import Security

public struct FeedbackWebCookie: Codable, Equatable, Sendable {
    public var name: String
    public var value: String
    public var domain: String
    public var path: String
    public var expiresAt: Date?
    public var isSecure: Bool

    public init(
        name: String,
        value: String,
        domain: String,
        path: String = "/",
        expiresAt: Date? = nil,
        isSecure: Bool = true
    ) {
        self.name = name
        self.value = value
        self.domain = domain
        self.path = path
        self.expiresAt = expiresAt
        self.isSecure = isSecure
    }

    public init(_ cookie: HTTPCookie) {
        self.init(
            name: cookie.name,
            value: cookie.value,
            domain: cookie.domain,
            path: cookie.path,
            expiresAt: cookie.expiresDate,
            isSecure: cookie.isSecure
        )
    }

    public func applies(to url: URL, now: Date = Date()) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if let expiresAt, expiresAt <= now {
            return false
        }
        if isSecure, url.scheme?.lowercased() != "https" {
            return false
        }

        let normalizedDomain = domain.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if domain.hasPrefix(".") {
            guard host == normalizedDomain || host.hasSuffix(".\(normalizedDomain)") else {
                return false
            }
        } else if host != normalizedDomain {
            return false
        }

        let encodedPath = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        )?.percentEncodedPath
        let requestPath = encodedPath.flatMap { $0.isEmpty ? nil : $0 } ?? "/"
        let cookiePath = path.isEmpty ? "/" : path
        guard requestPath.hasPrefix(cookiePath) else {
            return false
        }
        if requestPath.count == cookiePath.count || cookiePath.hasSuffix("/") {
            return true
        }
        let boundary = requestPath.index(requestPath.startIndex, offsetBy: cookiePath.count)
        return requestPath[boundary] == "/"
    }
}

public struct FeedbackWebSession: Codable, Equatable, Sendable {
    public var cookies: [FeedbackWebCookie]
    public var accountIdentifierHash: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        cookies: [FeedbackWebCookie],
        accountIdentifierHash: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.cookies = Self.deduplicated(cookies)
        self.accountIdentifierHash = accountIdentifierHash
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var isEmpty: Bool {
        cookies.isEmpty
    }

    public static func identifierHash(for appleID: String) -> String {
        let normalized = appleID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return Data(SHA256.hash(data: Data(normalized.utf8)))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    public func cookieHeader(for url: URL, now: Date = Date()) -> String? {
        let applicable = cookies
            .filter { $0.applies(to: url, now: now) }
            .sorted {
                if $0.path.count == $1.path.count {
                    return $0.name < $1.name
                }
                return $0.path.count > $1.path.count
            }
        guard !applicable.isEmpty else { return nil }
        return applicable.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    public func csrfToken(for url: URL, now: Date = Date()) -> String? {
        cookies
            .filter {
                $0.name == FeedbackWebAPI.csrfCookieName && $0.applies(to: url, now: now)
            }
            .max { $0.path.count < $1.path.count }?
            .value
    }

    public mutating func merge(_ responseCookies: [HTTPCookie], now: Date = Date()) {
        var values = Dictionary(
            uniqueKeysWithValues: cookies.map { (Self.key(for: $0), $0) }
        )

        for responseCookie in responseCookies {
            let cookie = FeedbackWebCookie(responseCookie)
            let key = Self.key(for: cookie)
            if let expiresAt = cookie.expiresAt, expiresAt <= now {
                values.removeValue(forKey: key)
            } else {
                values[key] = cookie
            }
        }

        cookies = values.values.sorted {
            Self.key(for: $0) < Self.key(for: $1)
        }
        updatedAt = now
    }

    private static func deduplicated(_ cookies: [FeedbackWebCookie]) -> [FeedbackWebCookie] {
        var values: [String: FeedbackWebCookie] = [:]
        for cookie in cookies {
            values[key(for: cookie)] = cookie
        }
        return values.values.sorted {
            key(for: $0) < key(for: $1)
        }
    }

    private static func key(for cookie: FeedbackWebCookie) -> String {
        "\(cookie.domain.lowercased())\n\(cookie.path)\n\(cookie.name)"
    }
}

public struct FeedbackWebSessionStore: Sendable {
    public static let defaultService = "com.rryam.RelatoKit.feedback-web-session"

    private let service: String
    private let account: String

    public init(
        service: String = FeedbackWebSessionStore.defaultService,
        account: String = "default"
    ) {
        self.service = service
        self.account = account
    }

    public func load() throws -> FeedbackWebSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = item as? Data else {
            throw keychainError(operation: "load", status: status)
        }

        do {
            return try JSONDecoder().decode(FeedbackWebSession.self, from: data)
        } catch {
            throw RelatoError.web("could not decode the cached web session")
        }
    }

    public func save(_ session: FeedbackWebSession) throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(session)
        } catch {
            throw RelatoError.web("could not encode the web session")
        }

        var query = baseQuery
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data
        ]
        let status = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
        if status == errSecSuccess {
            return
        }
        if status != errSecItemNotFound {
            throw keychainError(operation: "update", status: status)
        }

        query.merge(updateAttributes) { _, new in new }
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw keychainError(operation: "save", status: addStatus)
        }
    }

    public func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw keychainError(operation: "delete", status: status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func keychainError(operation: String, status: OSStatus) -> RelatoError {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "status \(status)"
        return .web("could not \(operation) Keychain session: \(message)")
    }
}
