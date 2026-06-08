//
//  CourseAPI.swift
//  Aretay
//
//  Direct PostgREST fetch with URLSession timeouts — avoids Supabase SDK hangs.
//

import Foundation

enum CourseAPI {
    private static let courseColumns =
        "id,owner_id,title,description,cover_image_url,visibility,curriculum,created_at"

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { container in
            let box = try container.singleValueContainer()
            let raw = try box.decode(String.self)
            guard let date = parseDate(raw) else {
                throw DecodingError.dataCorruptedError(
                    in: box,
                    debugDescription: "Unrecognized date: \(raw)"
                )
            }
            return date
        }
        return decoder
    }()

    private static func parseDate(_ raw: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: raw) { return date }

        let withoutFraction = ISO8601DateFormatter()
        withoutFraction.formatOptions = [.withInternetDateTime]
        return withoutFraction.date(from: raw)
    }

    static func fetchPublicCourses() async throws -> [Course] {
        guard SupabaseConfig.isConfigured else {
            throw CourseAPIError.notConfigured
        }

        var components = URLComponents(
            url: SupabaseConfig.url.appendingPathComponent("rest/v1/courses"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "select", value: courseColumns),
            URLQueryItem(name: "deleted_at", value: "is.null"),
            URLQueryItem(name: "order", value: "created_at.desc"),
        ]

        guard let url = components.url else {
            throw CourseAPIError.badURL
        }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw CourseAPIError.invalidResponse
        }

        guard (200 ... 299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw CourseAPIError.http(status: http.statusCode, body: body)
        }

        return try decoder.decode([Course].self, from: data)
    }
}

enum CourseAPIError: LocalizedError {
    case notConfigured
    case badURL
    case invalidResponse
    case http(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Supabase is not configured. Check Config/Secrets.xcconfig."
        case .badURL:
            return "Could not build the courses request URL."
        case .invalidResponse:
            return "Invalid response from server."
        case .http(let status, let body):
            return "Server error (\(status)): \(body)"
        }
    }
}
