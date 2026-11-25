//
//  HabitoAPI.swift
//  Habito
//
//  Everything the parent app says to the server, and what comes back.
//  Authenticated calls go through ParentAuth.send, which refreshes the
//  access token once when it has expired.
//

import Foundation
import KeychainSwift

// MARK: - Models

struct ParentInfo: Decodable {
    let id: String
    let email: String
    let roomCode: String
    let childName: String?
    let timezone: String
}

struct AuthResponse: Decodable {
    let parent: ParentInfo
    let access: String
    let refresh: String
}

struct MeResponse: Decodable {
    let role: String
    let parent: ParentInfo?
}

/// A task as the parent sees it. `status` is open, done, missed or upcoming.
struct TaskItem: Decodable, Identifiable, Equatable {
    let id: String
    let title: String
    /// Missing when talking to a server that predates descriptions.
    let description: String?
    let repeatKind: String
    let dueDate: String?
    let status: String
    let doneAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, title, description, repeatKind = "repeat", dueDate, status, doneAt
    }

    var isDone: Bool { status == "done" }
    var isDaily: Bool { repeatKind == "daily" }
    var descriptionText: String { description ?? "" }
}

/// GET /today: the day (in the parent's timezone) and the tasks due on it.
struct TodayList: Decodable {
    let date: String
    let tasks: [TaskItem]
}

struct HistoryTask: Decodable, Hashable {
    let title: String
    let status: String
}

struct HistoryDay: Decodable, Identifiable {
    let date: String
    let total: Int
    let done: Int
    /// Missing when talking to a server that predates task names in history.
    let tasks: [HistoryTask]?

    var id: String { date }
}

struct HistoryList: Decodable {
    let days: [HistoryDay]
}

// MARK: - Errors

struct APIError: LocalizedError {
    var status: Int
    var code: String
    var message: String
    var fields: [String: [String]] = [:]
    var retryAfter: Int?

    /// The access token expired and could not be refreshed: the parent has to log in again.
    static let signedOut = APIError(status: 401, code: "signed_out", message: "Please log in again.")

    var isSignedOut: Bool { code == "signed_out" }

    var errorDescription: String? {
        if status == 429 {
            guard let seconds = retryAfter else { return "Too many attempts. Try again later." }
            let minutes = max(1, (seconds + 59) / 60)
            return "Too many attempts. Try again in \(minutes) \(minutes == 1 ? "minute" : "minutes")."
        }
        for key in ["email", "password", "child_name", "title", "description", "non_field_errors"] {
            if let first = fields[key]?.first, !first.isEmpty { return first }
        }
        if let first = fields.values.compactMap({ $0.first }).first, !first.isEmpty { return first }
        return message.isEmpty ? "Something went wrong." : message
    }
}

/// The server's error shape: { "error": { "code", "message", "fields"?, "retry_after"? } }.
/// Decoded with a plain decoder: snake-case conversion would also rename the
/// keys inside `fields` (child_name → childName).
private struct ErrorEnvelope: Decodable {
    struct Body: Decodable {
        let code: String?
        let message: String?
        let fields: [String: [String]]?
        let retryAfter: Int?

        enum CodingKeys: String, CodingKey {
            case code, message, fields, retryAfter = "retry_after"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            code = try? container.decodeIfPresent(String.self, forKey: .code)
            message = try? container.decodeIfPresent(String.self, forKey: .message)
            // A field with an unexpected shape must not hide the rest of the error.
            fields = try? container.decodeIfPresent([String: [String]].self, forKey: .fields)
            retryAfter = try? container.decodeIfPresent(Int.self, forKey: .retryAfter)
        }
    }
    let error: Body
}

extension Error {
    /// True when a request was cancelled on purpose, for example by leaving a screen.
    var isCancellation: Bool {
        self is CancellationError || (self as? URLError)?.code == .cancelled
    }

    /// A sentence the parent can read.
    var habitoMessage: String {
        if let api = self as? APIError { return api.errorDescription ?? "Something went wrong." }
        if self is URLError { return "Can’t reach Habito. Check your connection." }
        return "Something went wrong."
    }
}

// MARK: - Decoding

extension JSONDecoder {
    static let habito: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            // The server sends microseconds ("…25.123456Z"); a whole second has none.
            return try Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
        }
        return decoder
    }()
}

// MARK: - Calls

enum HabitoAPI {
    // MARK: Plumbing

    private static func url(_ path: String, query: [URLQueryItem] = []) -> URL {
        var components = URLComponents(string: ParentAuth.baseURL + path)!
        if !query.isEmpty { components.queryItems = query }
        return components.url!
    }

    private static func failure(_ data: Data, _ http: HTTPURLResponse) -> APIError {
        if let body = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?.error {
            return APIError(
                status: http.statusCode,
                code: body.code ?? "error",
                message: body.message ?? "",
                fields: body.fields ?? [:],
                retryAfter: body.retryAfter
            )
        }
        return APIError(status: http.statusCode, code: "error", message: "The server answered with error \(http.statusCode).")
    }

    private static func json(_ body: [String: Any]?) -> Data? {
        body.flatMap { try? JSONSerialization.data(withJSONObject: $0) }
    }

    /// A call that needs no login: sign up and log in.
    private static func open(_ method: String, _ path: String, body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: url(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = json(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else { throw failure(data, http) }
        return data
    }

    /// A call with the parent's access token. Throws `APIError.signedOut` when the login is no longer valid.
    @discardableResult
    private static func call(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        body: [String: Any]? = nil
    ) async throws -> Data {
        let target = url(path, query: query)
        let payload = json(body)
        let result = try await ParentAuth.send { token in
            var request = URLRequest(url: target)
            request.httpMethod = method
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if let payload {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = payload
            }
            return request
        }
        guard let (data, http) = result else { throw APIError.signedOut }
        if http.statusCode == 401 { throw APIError.signedOut }
        guard (200..<300).contains(http.statusCode) else { throw failure(data, http) }
        return data
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder.habito.decode(type, from: data)
    }

    /// The day as the server writes it: 2026-11-18, in the phone's calendar.
    static func dayString(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The other way round: a server day back to a date in the phone's calendar.
    static func date(fromDay day: String) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    // MARK: Account

    private static func saveLogin(_ response: AuthResponse) throws {
        let keychain = KeychainSwift()
        let savedAccess = keychain.set(response.access, forKey: ParentAuth.accessKey)
        let savedRefresh = keychain.set(response.refresh, forKey: ParentAuth.refreshKey)
        guard savedAccess, savedRefresh else {
            throw APIError(status: 0, code: "keychain", message: "Couldn’t save your login on this phone.")
        }
    }

    static func signUp(email: String, password: String, childName: String) async throws -> AuthResponse {
        var body: [String: Any] = [
            "email": email,
            "password": password,
            "timezone": TimeZone.current.identifier,
        ]
        let name = childName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { body["child_name"] = name }
        let response = try decode(AuthResponse.self, from: try await open("POST", "/auth/register", body: body))
        try saveLogin(response)
        return response
    }

    static func logIn(email: String, password: String) async throws -> AuthResponse {
        let body: [String: Any] = [
            "email": email,
            "password": password,
            "timezone": TimeZone.current.identifier,
        ]
        let response = try decode(AuthResponse.self, from: try await open("POST", "/auth/login", body: body))
        try saveLogin(response)
        return response
    }

    static func me() async throws -> ParentInfo {
        let response = try decode(MeResponse.self, from: try await call("GET", "/me"))
        guard let parent = response.parent else { throw APIError.signedOut }
        return parent
    }

    // MARK: Child

    static let childTokenKey = "child_token"
    /// The family code this phone joined with, kept so that leaving can ask for it again.
    static let childRoomCodeKey = "child_room_code"

    /// A call with the child's device token. Throws `APIError.signedOut` when the token is
    /// missing or no longer valid (the parent's code was used on another device).
    @discardableResult
    private static func childCall(_ method: String, _ path: String) async throws -> Data {
        guard let token = KeychainSwift().get(childTokenKey) else { throw APIError.signedOut }
        var request = URLRequest(url: url(path))
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 401 { throw APIError.signedOut }
        guard (200..<300).contains(http.statusCode) else { throw failure(data, http) }
        return data
    }

    /// The family code, from the server (for phones that joined before the app kept it).
    /// Nil from a server that does not send it.
    static func childRoomCode() async throws -> String? {
        struct Me: Decodable {
            struct Child: Decodable { let roomCode: String? }
            let child: Child?
        }
        return try decode(Me.self, from: try await childCall("GET", "/me")).child?.roomCode
    }

    /// Today's tasks, as the child's device sees them.
    static func childToday() async throws -> TodayList {
        try decode(TodayList.self, from: try await childCall("GET", "/today"))
    }

    /// Marks today's occurrence of a task done. A task that was already done counts as success.
    static func markDone(id: String) async throws {
        do {
            try await childCall("POST", "/tasks/\(id)/done")
        } catch let error as APIError where error.code == "already_done" {
            return
        }
    }

    /// The child's device joins a room with the parent's code and gets its device token.
    /// A wrong code is a 404 `invalid_code`; too many tries is a 429.
    static func join(code: String) async throws -> String {
        struct Joined: Decodable { let childToken: String }
        let data = try await open("POST", "/join", body: ["code": code])
        return try decode(Joined.self, from: data).childToken
    }

    // MARK: Tasks

    static func today() async throws -> [TaskItem] {
        try decode(TodayList.self, from: try await call("GET", "/today")).tasks
    }

    static func createTask(title: String, description: String, daily: Bool) async throws {
        try await call("POST", "/tasks", body: [
            "title": title,
            "description": description,
            "repeat": daily ? "daily" : "once",
        ])
    }

    /// Only the fields that changed.
    static func updateTask(id: String, fields: [String: Any]) async throws {
        try await call("PATCH", "/tasks/\(id)", body: fields)
    }

    static func deleteTask(id: String) async throws {
        try await call("DELETE", "/tasks/\(id)")
    }

    /// Takes back today's done mark.
    static func undo(id: String) async throws {
        try await call("DELETE", "/tasks/\(id)/done")
    }

    // MARK: History

    static func history(from: Date, to: Date) async throws -> [HistoryDay] {
        let query = [
            URLQueryItem(name: "from", value: dayString(from)),
            URLQueryItem(name: "to", value: dayString(to)),
        ]
        return try decode(HistoryList.self, from: try await call("GET", "/history", query: query)).days
    }
}
