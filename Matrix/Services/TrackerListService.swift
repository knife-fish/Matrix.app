import Foundation

enum TrackerListError: LocalizedError {
    case invalidURL
    case invalidResponse
    case emptyList

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return L10n.text("tracker_error_invalid_url", language: .system)
        case .invalidResponse:
            return L10n.text("tracker_error_invalid_response", language: .system)
        case .emptyList:
            return L10n.text("tracker_error_empty", language: .system)
        }
    }
}

actor TrackerListService {
    static let shared = TrackerListService()

    private let session = URLSession.shared

    func fetchTrackerList(from urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else {
            throw TrackerListError.invalidURL
        }

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw TrackerListError.invalidResponse
        }

        let rawText = String(decoding: data, as: UTF8.self)
        let trackers = sanitizeTrackerList(rawText)
        guard !trackers.isEmpty else {
            throw TrackerListError.emptyList
        }

        return trackers.joined(separator: "\n")
    }

    nonisolated func sanitizeTrackerList(_ rawText: String) -> [String] {
        var seen = Set<String>()

        return rawText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { tracker in
                guard !tracker.isEmpty, !tracker.hasPrefix("#") else { return false }
                guard !seen.contains(tracker) else { return false }
                seen.insert(tracker)
                return true
            }
    }
}
