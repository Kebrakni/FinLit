import Foundation

/// Sends parsed statement rows to the app's backend proxy.
/// The OpenRouter key must never be shipped inside the iOS app.
final class OpenRouterCategorizer {
    static let shared = OpenRouterCategorizer()

    private struct Request: Encodable {
        let transactions: [InputTransaction]
    }

    private struct InputTransaction: Encodable {
        let id: String
        let date: String
        let amount: Double
        let merchant: String
        let details: String

        init(_ transaction: Transaction) {
            self.id = transaction.id
            self.date = ISO8601DateFormatter().string(from: transaction.date)
            self.amount = transaction.amount
            self.merchant = transaction.merchant
            self.details = transaction.details
        }
    }

    private struct Response: Decodable {
        let categories: [Category]
    }

    private struct Category: Decodable {
        let id: String
        let category: String
    }

    private let session: URLSession
    private let decoder = JSONDecoder()

    private init(session: URLSession = .shared) {
        self.session = session
    }

    /// Returns only valid AI assignments. Missing or invalid rows intentionally
    /// stay with the local rule-based category.
    func categorize(_ transactions: [Transaction]) async throws -> [String: TxCategory] {
        guard !transactions.isEmpty else { return [:] }

        // Keep requests small enough for the free endpoint and for long merchant names.
        let chunkSize = 80
        var result: [String: TxCategory] = [:]
        var start = 0
        while start < transactions.count {
            let end = min(start + chunkSize, transactions.count)
            let batch = Array(transactions[start..<end])
            let categories = try await categorizeBatch(batch)
            result.merge(categories) { _, new in new }
            start = end
        }
        return result
    }

    private func categorizeBatch(_ transactions: [Transaction]) async throws -> [String: TxCategory] {
        guard !transactions.isEmpty else { return [:] }

        let endpoint = try configuredEndpoint()
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            Request(transactions: transactions.map(InputTransaction.init))
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let serverMessage = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw APIError.server(serverMessage)
        }

        let result = try decoder.decode(Response.self, from: data)
        return result.categories.reduce(into: [:]) { output, item in
            if let category = TxCategory(aiCode: item.category) {
                output[item.id] = category
            }
        }
    }

    private func configuredEndpoint() throws -> URL {
        let raw = Bundle.main.object(forInfoDictionaryKey: "AI_API_BASE_URL") as? String
        let baseURL = (raw?.isEmpty == false && raw != "$(AI_API_BASE_URL)")
            ? raw!
            : "http://127.0.0.1:8787"
        let normalized = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        guard let url = URL(string: normalized + "/api/categorize") else {
            throw APIError.invalidURL
        }
        return url
    }

    enum APIError: LocalizedError {
        case invalidURL
        case invalidResponse
        case server(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Неверный адрес AI-сервера"
            case .invalidResponse:
                return "AI-сервер вернул неверный ответ"
            case .server(let message):
                return message
            }
        }
    }
}
