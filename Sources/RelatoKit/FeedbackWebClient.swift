import Foundation

public enum FeedbackWebAPI {
    public static let appIDKey =
        "4b98a8e6a3a3ce265b93c90207c442b53c45a1afa9ff1dc9bde8bb6928078d3b"
    public static let webBase = URL(string: "https://feedbackassistant.apple.com")!
    public static let serviceBase = URL(string: "https://appleseed.apple.com/sp/")!
    public static let authServiceURL = URL(
        string: "https://idmsa.apple.com/appleauth/auth"
    )!
    public static let loginURL = URL(
        string:
            "https://idmsa.apple.com/IDMSWebAuth/signin?appIdKey=\(appIDKey)&sslEnabled=true&rv=4&path=/"
    )!
    public static let apiVersion = "4.2"
    public static let csrfCookieName = "SP-XSRF-TOKEN"
}

public enum FeedbackWebClientError: Error, CustomStringConvertible, Equatable {
    case authenticationRequired
    case invalidResponse
    case requestFailed(status: Int, path: String)

    public var description: String {
        switch self {
        case .authenticationRequired:
            return "web authentication is required; run `relato web auth login`"
        case .invalidResponse:
            return "Apple returned an invalid web response"
        case .requestFailed(let status, let path):
            return "Apple returned HTTP \(status) for \(path)"
        }
    }
}

final class FeedbackWebRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

public actor FeedbackWebClient {
    private var session: FeedbackWebSession
    private let sessionStore: FeedbackWebSessionStore?
    private let urlSession: URLSession

    public init(
        session: FeedbackWebSession,
        sessionStore: FeedbackWebSessionStore? = nil,
        configuration: URLSessionConfiguration = .ephemeral
    ) {
        let configuration = configuration
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = session
        self.sessionStore = sessionStore
        self.urlSession = URLSession(
            configuration: configuration,
            delegate: FeedbackWebRedirectDelegate(),
            delegateQueue: nil
        )
    }

    public func authenticate(locale: String = "en") async throws -> Data {
        try await request(method: "POST", path: "login/with_ds", locale: locale)
    }

    public func contentItems(
        locale: String = "en",
        teamID: String? = nil
    ) async throws -> Data {
        let path = try path(
            "\(validatedLocale(locale))/feedback/content_items",
            queryName: "team_id",
            queryValue: teamID
        )
        return try await request(method: "GET", path: path, locale: locale)
    }

    public func feedback(
        id: String,
        locale: String = "en"
    ) async throws -> Data {
        let feedbackID = try pathSegment(id, name: "feedback id")
        return try await request(
            method: "GET",
            path: "feedback/feedback_details/feedback/\(feedbackID)",
            locale: locale
        )
    }

    public func feedbackStatus(
        id: String,
        locale: String = "en"
    ) async throws -> Data {
        let feedbackID = try pathSegment(id, name: "feedback id")
        return try await request(
            method: "GET",
            path: "feedback/\(feedbackID)/status",
            locale: locale
        )
    }

    public func formItems(
        locale: String = "en",
        teamID: String? = nil
    ) async throws -> Data {
        let path = try path(
            "feedback/form_items",
            queryName: "team_id",
            queryValue: teamID
        )
        return try await request(method: "GET", path: path, locale: locale)
    }

    public func form(
        id: String,
        locale: String = "en",
        teamID: String? = nil
    ) async throws -> Data {
        let formID = try pathSegment(id, name: "form id")
        let path = try path(
            "\(validatedLocale(locale))/feedback/forms/\(formID)",
            queryName: "team_id",
            queryValue: teamID
        )
        return try await request(method: "GET", path: path, locale: locale)
    }

    public func createDraft(
        formID: String,
        locale: String = "en",
        teamID: String? = nil
    ) async throws -> Data {
        let formID = try pathSegment(formID, name: "form id")
        var payload: [String: String] = [:]
        if let teamID {
            let value = teamID.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                payload["team_id"] = value
            }
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        return try await request(
            method: "POST",
            path:
                "\(validatedLocale(locale))/feedback/forms/\(formID)/form_responses/start.json",
            locale: locale,
            body: body
        )
    }

    public func draft(
        id: String,
        locale: String = "en"
    ) async throws -> Data {
        let draftID = try pathSegment(id, name: "draft id")
        return try await request(
            method: "GET",
            path: "\(validatedLocale(locale))/feedback/form_responses/\(draftID)",
            locale: locale
        )
    }

    public func submissionPreflight(
        id: String,
        locale: String = "en"
    ) async throws -> FeedbackWebSubmissionPreflight {
        let draftData = try await draft(id: id, locale: locale)
        let draft = try decodeWebResponse(
            FeedbackWebDraft.self,
            from: draftData,
            name: "draft"
        )
        let formData = try await form(
            id: String(draft.formID),
            locale: locale,
            teamID: draft.teamID
        )
        let form = try decodeWebResponse(
            FeedbackWebFormSchema.self,
            from: formData,
            name: "form schema"
        )
        return try FeedbackWebSubmissionValidator.preflight(
            draft: draft,
            form: form
        )
    }

    public func updateDraftAnswers(
        id: String,
        locale: String = "en",
        answers: [FeedbackWebAnswerMutation]
    ) async throws -> Data {
        let draftID = try pathSegment(id, name: "draft id")
        let body = try JSONEncoder().encode(FeedbackWebAnswersPayload(answers: answers))
        return try await request(
            method: "PUT",
            path: "\(validatedLocale(locale))/feedback/form_responses/\(draftID)/answers.json",
            locale: locale,
            body: body
        )
    }

    public func uploadAttachment(
        draftID: String,
        fileURL: URL,
        locale: String = "en"
    ) async throws -> FeedbackWebAttachmentReceipt {
        let draftIDValue = try numericID(draftID, name: "draft id")
        let fileURL = fileURL.standardizedFileURL
        let resourceValues = try fileURL.resourceValues(
            forKeys: [.fileSizeKey, .isRegularFileKey]
        )
        guard resourceValues.isRegularFile == true else {
            throw RelatoError.missingFile(fileURL.path)
        }
        guard let fileSize = resourceValues.fileSize, fileSize > 0 else {
            throw RelatoError.invalidArgument("Attachment must be a non-empty regular file")
        }
        let fileName = fileURL.lastPathComponent
        guard !fileName.isEmpty else {
            throw RelatoError.invalidArgument("Attachment filename cannot be empty")
        }

        var promiseUUID: String?
        do {
            let createBody = try JSONEncoder().encode(
                FeedbackWebCreateFilePromisePayload(
                    parentType: "FormResponse",
                    parentID: draftIDValue
                )
            )
            let createData = try await request(
                method: "POST",
                path: "feedback/file_promise/new",
                locale: locale,
                body: createBody
            )
            let created = try decodeWebResponse(
                FeedbackWebCreateFilePromiseResponse.self,
                from: createData,
                name: "file promise"
            )
            guard !created.uuid.isEmpty else {
                throw RelatoError.web("Apple returned an empty file promise UUID")
            }
            promiseUUID = created.uuid

            try await updateFilePromise(
                uuid: created.uuid,
                status: "uploading",
                name: fileName,
                size: fileSize,
                locale: locale
            )
            let linkData = try await request(
                method: "GET",
                path:
                    "feedback/file_promise/\(try pathSegment(created.uuid, name: "file promise UUID"))/upload_link",
                locale: locale
            )
            let link = try decodeWebResponse(
                FeedbackWebUploadLinkResponse.self,
                from: linkData,
                name: "attachment upload link"
            )
            let uploadURL = try validatedUploadURL(link.presignedURL)
            try await uploadFile(at: fileURL, to: uploadURL)
            try await updateFilePromise(
                uuid: created.uuid,
                status: "uploaded",
                name: fileName,
                size: fileSize,
                locale: locale
            )
        } catch {
            if let promiseUUID {
                try? await updateFilePromise(
                    uuid: promiseUUID,
                    status: "upload_error",
                    name: fileName,
                    size: fileSize,
                    locale: locale
                )
            }
            throw error
        }

        guard let uuid = promiseUUID else {
            throw RelatoError.web("Apple did not create a file promise")
        }
        let promise = try await verifyAttachment(
            draftID: draftID,
            uuid: uuid,
            locale: locale
        )
        return FeedbackWebAttachmentReceipt(
            draftID: draftIDValue,
            id: promise.id,
            uuid: promise.uuid,
            name: promise.name,
            size: promise.size,
            status: promise.status,
            verified: true
        )
    }

    public func currentSession() -> FeedbackWebSession {
        session
    }

    private func request(
        method: String,
        path: String,
        locale: String,
        body: Data? = nil
    ) async throws -> Data {
        guard
            !path.hasPrefix("/"),
            !path.contains("://"),
            let url = URL(string: path, relativeTo: FeedbackWebAPI.serviceBase)?.absoluteURL
        else {
            throw RelatoError.web("invalid Appleseed API path")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.setValue(FeedbackWebAPI.apiVersion, forHTTPHeaderField: "X-SP-API")
        request.setValue(try validatedLocale(locale), forHTTPHeaderField: "locale")
        request.setValue(FeedbackWebAPI.webBase.absoluteString, forHTTPHeaderField: "Origin")
        request.setValue(
            FeedbackWebAPI.webBase.absoluteString + "/",
            forHTTPHeaderField: "Referer"
        )
        request.setValue("RelatoKit/experimental-web", forHTTPHeaderField: "User-Agent")
        if let cookieHeader = session.cookieHeader(for: url) {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }
        if let csrfToken = session.csrfToken(for: url) {
            request.setValue(csrfToken, forHTTPHeaderField: "X-CSRF-TOKEN")
        }

        let (data, response) = try await urlSession.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw FeedbackWebClientError.invalidResponse
        }

        let responseCookies = HTTPCookie.cookies(
            withResponseHeaderFields: responseHeaderFields(response),
            for: url
        )
        if !responseCookies.isEmpty {
            session.merge(responseCookies)
            try sessionStore?.save(session)
        }

        let responseHost = response.url?.host?.lowercased()
        if response.statusCode == 401
            || response.statusCode == 403
            || (300..<400).contains(response.statusCode)
            || responseHost == "idmsa.apple.com"
        {
            throw FeedbackWebClientError.authenticationRequired
        }
        guard (200..<300).contains(response.statusCode) else {
            throw FeedbackWebClientError.requestFailed(status: response.statusCode, path: path)
        }
        return data
    }

    private func responseHeaderFields(_ response: HTTPURLResponse) -> [String: String] {
        response.allHeaderFields.reduce(into: [:]) { result, pair in
            guard let key = pair.key as? String, let value = pair.value as? String else {
                return
            }
            result[key] = value
        }
    }

    private func updateFilePromise(
        uuid: String,
        status: String,
        name: String,
        size: Int,
        locale: String
    ) async throws {
        let uuid = try pathSegment(uuid, name: "file promise UUID")
        let body = try JSONEncoder().encode(
            FeedbackWebFilePromiseStatusPayload(
                status: status,
                options: FeedbackWebFilePromiseOptions(name: name, size: size)
            )
        )
        _ = try await request(
            method: "PUT",
            path: "feedback/file_promise/\(uuid)",
            locale: locale,
            body: body
        )
    }

    private func uploadFile(at fileURL: URL, to uploadURL: URL) async throws {
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.timeoutInterval = 30 * 60
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )

        let (_, response) = try await urlSession.upload(for: request, fromFile: fileURL)
        guard let response = response as? HTTPURLResponse else {
            throw FeedbackWebClientError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw FeedbackWebClientError.requestFailed(
                status: response.statusCode,
                path: "attachment object upload"
            )
        }
    }

    private func verifyAttachment(
        draftID: String,
        uuid: String,
        locale: String
    ) async throws -> FeedbackWebFilePromise {
        for attempt in 0..<5 {
            if attempt > 0 {
                try await Task.sleep(nanoseconds: 250_000_000)
            }
            let data = try await draft(id: draftID, locale: locale)
            let draft = try decodeWebResponse(
                FeedbackWebDraft.self,
                from: data,
                name: "draft attachment verification"
            )
            if let promise = draft.filePromises.first(where: {
                $0.uuid.caseInsensitiveCompare(uuid) == .orderedSame
                    && $0.status == 40
            }) {
                return promise
            }
        }
        throw RelatoError.web(
            "attachment upload completed, but Apple did not return an uploaded file promise"
        )
    }

    private func validatedUploadURL(_ value: String) throws -> URL {
        guard
            let components = URLComponents(string: value),
            components.scheme?.lowercased() == "https",
            components.host != nil,
            components.user == nil,
            components.password == nil,
            let url = components.url
        else {
            throw RelatoError.web("Apple returned an invalid attachment upload URL")
        }
        return url
    }

    private func decodeWebResponse<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        name: String
    ) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw RelatoError.web("Apple returned a malformed \(name) response")
        }
    }

    private func path(
        _ basePath: String,
        queryName: String,
        queryValue: String?
    ) throws -> String {
        guard let queryValue, !queryValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return basePath
        }
        let value = queryValue.trimmingCharacters(in: .whitespacesAndNewlines)
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: queryName, value: value)]
        guard let query = components.percentEncodedQuery else {
            throw RelatoError.web("could not encode \(queryName)")
        }
        return "\(basePath)?\(query)"
    }

    private func pathSegment(_ value: String, name: String) throws -> String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            throw RelatoError.invalidArgument("\(name) is required")
        }
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        guard let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) else {
            throw RelatoError.web("could not encode \(name)")
        }
        return encoded
    }

    private func numericID(_ value: String, name: String) throws -> Int {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let id = Int(value), id > 0 else {
            throw RelatoError.invalidArgument("\(name) must be a positive integer")
        }
        return id
    }

    private func validatedLocale(_ locale: String) throws -> String {
        let locale = locale.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !locale.isEmpty,
            locale.unicodeScalars.allSatisfy({
                CharacterSet.letters.contains($0) || $0 == "-"
            })
        else {
            throw RelatoError.invalidArgument("Invalid locale: \(locale)")
        }
        return locale
    }
}

private struct FeedbackWebAnswersPayload: Encodable {
    let answers: [FeedbackWebAnswerMutation]
}

private struct FeedbackWebCreateFilePromisePayload: Encodable {
    let parentType: String
    let parentID: Int

    enum CodingKeys: String, CodingKey {
        case parentType = "parent_type"
        case parentID = "parent_id"
    }
}

private struct FeedbackWebCreateFilePromiseResponse: Decodable {
    let uuid: String
}

private struct FeedbackWebFilePromiseOptions: Encodable {
    let name: String
    let size: Int
}

private struct FeedbackWebFilePromiseStatusPayload: Encodable {
    let status: String
    let options: FeedbackWebFilePromiseOptions
}

private struct FeedbackWebUploadLinkResponse: Decodable {
    let presignedURL: String

    enum CodingKeys: String, CodingKey {
        case presignedURL = "presigned_url"
    }
}
