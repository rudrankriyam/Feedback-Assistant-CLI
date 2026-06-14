import CryptoKit
import Darwin
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

public enum FeedbackWebSessionBackend: String, Sendable {
    case file
    case keychain
}

public struct FeedbackWebSessionStore: Sendable {
    public static let defaultService = "com.rryam.RelatoKit.feedback-web-session"
    public static let backendEnvironment = "RELATO_WEB_SESSION_BACKEND"
    public static let directoryEnvironment = "RELATO_WEB_SESSION_DIR"

    private let service: String
    private let account: String
    private let directoryURL: URL
    public let backend: FeedbackWebSessionBackend

    public init(
        service: String = FeedbackWebSessionStore.defaultService,
        account: String = "default",
        backend: FeedbackWebSessionBackend? = nil,
        directoryURL: URL? = nil
    ) {
        self.service = service
        self.account = account
        self.backend = backend ?? Self.defaultBackend
        self.directoryURL = directoryURL ?? Self.defaultDirectoryURL
    }

    public var source: String {
        backend.rawValue
    }

    public func load() throws -> FeedbackWebSession? {
        switch backend {
        case .file:
            return try loadFile()
        case .keychain:
            return try loadKeychain()
        }
    }

    public func save(_ session: FeedbackWebSession) throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(session)
        } catch {
            throw RelatoError.web("could not encode the web session")
        }

        switch backend {
        case .file:
            try saveFile(data)
        case .keychain:
            try saveKeychain(data)
        }
    }

    public func delete() throws {
        switch backend {
        case .file:
            try deleteFile()
        case .keychain:
            try deleteKeychain()
        }
    }

    private static var defaultBackend: FeedbackWebSessionBackend {
        let value = ProcessInfo.processInfo.environment[backendEnvironment]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return value == FeedbackWebSessionBackend.keychain.rawValue ? .keychain : .file
    }

    private static var defaultDirectoryURL: URL {
        if let value = ProcessInfo.processInfo.environment[directoryEnvironment]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        {
            return URL(
                fileURLWithPath: (value as NSString).expandingTildeInPath,
                isDirectory: true
            )
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".relato", isDirectory: true)
            .appendingPathComponent("web", isDirectory: true)
    }

    private func loadFile() throws -> FeedbackWebSession? {
        try withStoreLock {
            guard FileManager.default.fileExists(atPath: sessionFileURL.path) else {
                return nil
            }
            try validateSessionDirectory()
            try validateSessionFile()
            let data: Data
            do {
                data = try Data(contentsOf: sessionFileURL)
            } catch {
                throw RelatoError.web("could not read the cached web session")
            }
            return try decodeSession(data)
        }
    }

    private func saveFile(_ data: Data) throws {
        try withStoreLock {
            try prepareSessionDirectory()
            let temporaryURL = directoryURL.appendingPathComponent(
                ".session-\(UUID().uuidString).tmp",
                isDirectory: false
            )
            guard FileManager.default.createFile(
                atPath: temporaryURL.path,
                contents: data,
                attributes: [.posixPermissions: 0o600]
            ) else {
                throw RelatoError.web("could not write the cached web session")
            }
            defer { try? FileManager.default.removeItem(at: temporaryURL) }

            do {
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o600],
                    ofItemAtPath: temporaryURL.path
                )
            } catch {
                throw RelatoError.web("could not secure the cached web session")
            }
            guard Darwin.rename(temporaryURL.path, sessionFileURL.path) == 0 else {
                throw fileError(operation: "finalize")
            }
        }
    }

    private func deleteFile() throws {
        try withStoreLock {
            do {
                try FileManager.default.removeItem(at: sessionFileURL)
            } catch CocoaError.fileNoSuchFile {
                return
            } catch {
                throw RelatoError.web("could not delete the cached web session")
            }
        }
    }

    private func loadKeychain() throws -> FeedbackWebSession? {
        try withStoreLock {
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
            return try decodeSession(data)
        }
    }

    private func saveKeychain(_ data: Data) throws {
        try withStoreLock {
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
            if addStatus == errSecSuccess {
                return
            }
            if addStatus == errSecDuplicateItem {
                let retryStatus = SecItemUpdate(
                    baseQuery as CFDictionary,
                    updateAttributes as CFDictionary
                )
                guard retryStatus == errSecSuccess else {
                    throw keychainError(operation: "update", status: retryStatus)
                }
                return
            }
            throw keychainError(operation: "save", status: addStatus)
        }
    }

    private func deleteKeychain() throws {
        try withStoreLock {
            let status = SecItemDelete(baseQuery as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw keychainError(operation: "delete", status: status)
            }
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private var sessionFileURL: URL {
        directoryURL.appendingPathComponent("session.json", isDirectory: false)
    }

    private var lockURL: URL {
        let identifier = Data(
            SHA256.hash(
                data: Data(
                    "\(backend.rawValue)\n\(service)\n\(account)\n\(directoryURL.path)".utf8
                )
            )
        )
            .map { String(format: "%02x", $0) }
            .joined()
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("relato-feedback-web-session-\(identifier).lock")
    }

    private func withStoreLock<T>(_ operation: () throws -> T) throws -> T {
        let descriptor = Darwin.open(
            lockURL.path,
            O_CREAT | O_RDWR,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else {
            throw lockError(operation: "open")
        }
        defer {
            _ = Darwin.lockf(descriptor, F_ULOCK, 0)
            _ = Darwin.close(descriptor)
        }

        while Darwin.lockf(descriptor, F_LOCK, 0) != 0 {
            if errno == EINTR {
                continue
            }
            throw lockError(operation: "acquire")
        }
        return try operation()
    }

    private func prepareSessionDirectory() throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: directoryURL.path) {
            try validateSessionDirectory()
            return
        } else {
            do {
                try fileManager.createDirectory(
                    at: directoryURL,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
            } catch {
                throw RelatoError.web("could not create the web session cache directory")
            }
        }
    }

    private func validateSessionDirectory() throws {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: directoryURL.path)
        } catch {
            throw RelatoError.web("could not inspect the web session cache directory")
        }
        guard attributes[.type] as? FileAttributeType == .typeDirectory else {
            throw RelatoError.web(
                "web session cache path is not a directory: \(directoryURL.path)"
            )
        }
        if let ownerID = attributes[.ownerAccountID] as? NSNumber,
            ownerID.uint32Value != Darwin.getuid()
        {
            throw RelatoError.web("web session cache directory is owned by another user")
        }
        if let permissions = attributes[.posixPermissions] as? NSNumber,
            permissions.intValue & 0o077 != 0
        {
            throw RelatoError.web(
                "web session cache directory permissions are too broad; use a private directory with mode 700"
            )
        }
    }

    private func validateSessionFile() throws {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: sessionFileURL.path)
        } catch {
            throw RelatoError.web("could not inspect the cached web session")
        }
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw RelatoError.web("cached web session is not a regular file")
        }
        if let ownerID = attributes[.ownerAccountID] as? NSNumber,
            ownerID.uint32Value != Darwin.getuid()
        {
            throw RelatoError.web("cached web session is owned by another user")
        }
        if let permissions = attributes[.posixPermissions] as? NSNumber,
            permissions.intValue & 0o077 != 0
        {
            throw RelatoError.web(
                "cached web session permissions are too broad; run `chmod 600 \(sessionFileURL.path)`"
            )
        }
    }

    private func decodeSession(_ data: Data) throws -> FeedbackWebSession {
        do {
            return try JSONDecoder().decode(FeedbackWebSession.self, from: data)
        } catch {
            throw RelatoError.web("could not decode the cached web session")
        }
    }

    private func keychainError(operation: String, status: OSStatus) -> RelatoError {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "status \(status)"
        return .web("could not \(operation) Keychain session: \(message)")
    }

    private func lockError(operation: String) -> RelatoError {
        let message = String(cString: strerror(errno))
        return .web("could not \(operation) web session lock: \(message)")
    }

    private func fileError(operation: String) -> RelatoError {
        let message = String(cString: strerror(errno))
        return .web("could not \(operation) cached web session: \(message)")
    }
}
