import Foundation

enum FeedbackWebHTTP {
    static let userAgent = "RelatoKit/experimental-web"

    static func makeSession(
        configuration: URLSessionConfiguration
    ) -> URLSession {
        let isolatedConfiguration = configuration.copy() as! URLSessionConfiguration
        isolatedConfiguration.httpShouldSetCookies = false
        isolatedConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(
            configuration: isolatedConfiguration,
            delegate: FeedbackWebRedirectDelegate(),
            delegateQueue: nil
        )
    }

    static func responseHeaderFields(
        _ response: HTTPURLResponse
    ) -> [String: String] {
        response.allHeaderFields.reduce(into: [:]) { result, pair in
            result[String(describing: pair.key)] = String(describing: pair.value)
        }
    }
}

private final class FeedbackWebRedirectDelegate:
    NSObject,
    URLSessionTaskDelegate,
    @unchecked Sendable
{
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
