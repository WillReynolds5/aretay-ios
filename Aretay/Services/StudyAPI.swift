//
//  StudyAPI.swift
//  Aretay
//
//  PostgREST calls for the spaced-repetition tables. Same direct-URLSession
//  style as CourseAPI — RLS scopes every row to auth.uid(), so queries only
//  filter by course.
//

import Foundation

enum StudyAPI {
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let box = try decoder.singleValueContainer()
            let raw = try box.decode(String.self)
            guard let date = PostgRESTDate.parse(raw) else {
                throw DecodingError.dataCorruptedError(in: box, debugDescription: "Unrecognized date: \(raw)")
            }
            return date
        }
        return decoder
    }()

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(PostgRESTDate.format(date))
        }
        return encoder
    }()

    // MARK: - Cards (shared course content)

    static func fetchCards(courseId: UUID, accessToken: String) async throws -> [Card] {
        try await get(
            path: "rest/v1/cards",
            query: [
                URLQueryItem(name: "select", value: "id,course_id,segment_key,video_r2_key,captions,metadata"),
                URLQueryItem(name: "course_id", value: "eq.\(courseId.uuidString)"),
                URLQueryItem(name: "deleted_at", value: "is.null"),
            ],
            accessToken: accessToken
        )
    }

    // MARK: - Enrollment

    static func fetchEnrollment(courseId: UUID, accessToken: String) async throws -> Enrollment? {
        let rows: [Enrollment] = try await get(
            path: "rest/v1/course_enrollments",
            query: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "course_id", value: "eq.\(courseId.uuidString)"),
            ],
            accessToken: accessToken
        )
        return rows.first
    }

    /// Every enrollment for the signed-in user (RLS-scoped), most recently
    /// studied first — powers the "resume the course you were in" launch route.
    static func fetchEnrollments(accessToken: String) async throws -> [Enrollment] {
        try await get(
            path: "rest/v1/course_enrollments",
            query: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "order", value: "last_studied_at.desc.nullslast"),
            ],
            accessToken: accessToken
        )
    }

    @discardableResult
    static func upsertEnrollment(_ enrollment: Enrollment, accessToken: String) async throws -> Enrollment {
        let rows: [Enrollment] = try await write(
            path: "rest/v1/course_enrollments",
            query: [URLQueryItem(name: "on_conflict", value: "user_id,course_id")],
            body: [enrollment],
            prefer: "resolution=merge-duplicates,return=representation",
            accessToken: accessToken
        )
        guard let row = rows.first else { throw CourseAPIError.invalidResponse }
        return row
    }

    // MARK: - Card states

    static func fetchCardStates(courseId: UUID, accessToken: String) async throws -> [CardState] {
        try await get(
            path: "rest/v1/card_states",
            query: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "course_id", value: "eq.\(courseId.uuidString)"),
            ],
            accessToken: accessToken
        )
    }

    /// Upserts on (user_id, card_id) so re-introducing a segment never duplicates states.
    @discardableResult
    static func upsertCardStates(_ states: [CardState], accessToken: String) async throws -> [CardState] {
        guard !states.isEmpty else { return [] }
        return try await write(
            path: "rest/v1/card_states",
            query: [URLQueryItem(name: "on_conflict", value: "user_id,card_id")],
            body: states,
            prefer: "resolution=merge-duplicates,return=representation",
            accessToken: accessToken
        )
    }

    /// Lightweight cross-course card state row for home-screen stats.
    struct StateRow: Codable, Sendable {
        let courseId: UUID
        let due: Date
        let state: FSRSState

        enum CodingKeys: String, CodingKey {
            case courseId = "course_id"
            case due
            case state
        }
    }

    /// Every tracked card for the signed-in user (RLS-scoped), all courses.
    static func fetchStateRows(accessToken: String) async throws -> [StateRow] {
        try await get(
            path: "rest/v1/card_states",
            query: [URLQueryItem(name: "select", value: "course_id,due,state")],
            accessToken: accessToken
        )
    }

    /// Slim review-log row for streak/retention stats.
    struct LogRow: Codable, Sendable {
        let reviewedAt: Date
        let rating: Int
        let stateBefore: String

        enum CodingKeys: String, CodingKey {
            case reviewedAt = "reviewed_at"
            case rating
            case stateBefore = "state_before"
        }
    }

    /// Most recent answers, newest first — enough history for streak + retention.
    static func fetchRecentLogs(accessToken: String, limit: Int = 2000) async throws -> [LogRow] {
        try await get(
            path: "rest/v1/review_logs",
            query: [
                URLQueryItem(name: "select", value: "reviewed_at,rating,state_before"),
                URLQueryItem(name: "order", value: "reviewed_at.desc"),
                URLQueryItem(name: "limit", value: String(limit)),
            ],
            accessToken: accessToken
        )
    }

    // MARK: - Review logs

    static func insertReviewLog(_ log: ReviewLogInsert, accessToken: String) async throws {
        let _: [EmptyRow] = try await write(
            path: "rest/v1/review_logs",
            query: [],
            body: [log],
            prefer: "return=minimal",
            accessToken: accessToken
        )
    }

    private struct EmptyRow: Codable {}

    // MARK: - HTTP plumbing

    private static func get<T: Decodable>(
        path: String,
        query: [URLQueryItem],
        accessToken: String
    ) async throws -> T {
        let request = try makeRequest(path: path, query: query, method: "GET", accessToken: accessToken)
        return try await perform(request)
    }

    private static func write<Body: Encodable, T: Decodable>(
        path: String,
        query: [URLQueryItem],
        body: Body,
        prefer: String,
        accessToken: String
    ) async throws -> T {
        var request = try makeRequest(path: path, query: query, method: "POST", accessToken: accessToken)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(prefer, forHTTPHeaderField: "Prefer")
        request.httpBody = try encoder.encode(body)
        return try await perform(request)
    }

    private static func makeRequest(
        path: String,
        query: [URLQueryItem],
        method: String,
        accessToken: String
    ) throws -> URLRequest {
        guard SupabaseConfig.isConfigured else { throw CourseAPIError.notConfigured }

        var components = URLComponents(
            url: SupabaseConfig.url.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        if !query.isEmpty {
            components.queryItems = query
        }
        guard let url = components.url else { throw CourseAPIError.badURL }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = method
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private static func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CourseAPIError.invalidResponse }
        guard (200 ... 299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw CourseAPIError.http(status: http.statusCode, body: body)
        }
        if data.isEmpty, let empty = "[]".data(using: .utf8) {
            return try decoder.decode(T.self, from: empty)
        }
        return try decoder.decode(T.self, from: data)
    }
}

/// ISO8601 with and without fractional seconds — PostgREST emits both.
enum PostgRESTDate {
    static func parse(_ raw: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: raw) { return date }

        let withoutFraction = ISO8601DateFormatter()
        withoutFraction.formatOptions = [.withInternetDateTime]
        return withoutFraction.date(from: raw)
    }

    static func format(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
