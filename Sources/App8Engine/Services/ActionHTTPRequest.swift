//
//  ActionHTTPRequest.swift
//  App8Engine
//
//  The `request` action: one HTTP call made with URLSession. The engine knows
//  nothing about auth; the host adds credentials or reroutes the call in
//  `App8DataSource.prepareRequest(_:)`.
//

import Foundation

@MainActor
enum ActionHTTPRequest {

    static let timeout: TimeInterval = 30
    static let allowedMethods: Set<String> = ["GET", "POST", "PUT", "PATCH", "DELETE"]

    /// What `onSuccess` / `onError` and `resultVariable` see as `response`.
    struct Response {
        /// HTTP status; 0 when the request never got a response.
        let status: Int
        /// Parsed JSON, else the body as a string; NSNull when empty or when
        /// there was no response.
        let body: Any
        /// Names lowercased.
        let headers: [String: String]

        var isSuccess: Bool { (200..<300).contains(status) }

        var dictionary: [String: Any] {
            ["status": status, "body": body, "headers": headers]
        }
    }

    /// Builds the request. An unparsable URL yields `nil` (reported as a
    /// status-0 error when performed).
    static func make(method: String?, url: String, headers: [String: String], body: Any?) -> URLRequest? {
        guard let parsed = URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = parsed.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }
        var request = URLRequest(url: parsed, timeoutInterval: timeout)
        let upper = (method ?? "GET").uppercased()
        request.httpMethod = allowedMethods.contains(upper) ? upper : "GET"
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        // GET sends no body.
        if request.httpMethod != "GET", let body, !(body is NSNull) {
            let safe = VariablePersistence.jsonSafe(body)
            if let data = try? JSONSerialization.data(withJSONObject: safe, options: [.fragmentsAllowed]) {
                request.httpBody = data
                if request.value(forHTTPHeaderField: "Content-Type") == nil {
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                }
            }
        }
        return request
    }

    /// Runs `prepare` (the host hook), then the request. Never throws: a
    /// rejected or failed request comes back with status 0.
    static func perform(
        _ request: URLRequest?,
        session: URLSession,
        prepare: (URLRequest) async throws -> URLRequest
    ) async -> Response {
        guard let request else {
            return Response(status: 0, body: NSNull(), headers: [:])
        }
        do {
            let prepared = try await prepare(request)
            let (data, urlResponse) = try await session.data(for: prepared)
            let http = urlResponse as? HTTPURLResponse
            var headers: [String: String] = [:]
            for (key, value) in http?.allHeaderFields ?? [:] {
                headers["\(key)".lowercased()] = "\(value)"
            }
            return Response(status: http?.statusCode ?? 0, body: parseBody(data), headers: headers)
        } catch {
            return Response(status: 0, body: NSNull(), headers: [:])
        }
    }

    /// JSON when the bytes parse as JSON, else a UTF-8 string (NSNull when empty).
    static func parseBody(_ data: Data) -> Any {
        guard !data.isEmpty else { return NSNull() }
        if let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
            return VariablePersistence.native(json)
        }
        return String(decoding: data, as: UTF8.self)
    }
}
