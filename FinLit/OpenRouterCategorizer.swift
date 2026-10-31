import Foundation

/// Sends parsed statement rows to the app's backend proxy.
/// The OpenRouter key must never be shipped inside the iOS app.
final class OpenRouterCategorizer {
    static let shared = OpenRouterCategorizer()

    private struct Request: Encodable {
        let transactions: [InputTransaction]
    }

    private struct ReviewRequest: Encodable {
        let message: String
        let history: [String]
        let analyticsContext: String
        let transactions: [InputTransaction]
    }

    private struct MissionRequest: Encodable {
        struct GoalPayload: Encodable {
            let title: String
            let targetAmount: Double
            let savedAmount: Double
        }

        let goal: GoalPayload
        let transactions: [InputTransaction]
    }

    private struct InputTransaction: Encodable {
        let id: String
        let date: String
        let amount: Double
        let merchant: String
        let details: String
        let currentCategory: String

        init(_ transaction: Transaction) {
            self.id = transaction.id
            self.date = ISO8601DateFormatter().string(from: transaction.date)
            self.amount = transaction.amount
            self.merchant = transaction.merchant
            self.details = transaction.details
            self.currentCategory = transaction.category.aiCode
        }
    }

    private struct Response: Decodable {
        let categories: [Category]
    }

    private struct Category: Decodable {
        let id: String
        let category: String
    }

    struct ReviewChange {
        let id: String
        let category: TxCategory
        let amount: Double
        let reason: String
    }

    struct ReviewResult {
        let reply: String
        let changes: [ReviewChange]
    }

    struct MissionSuggestion: Decodable {
        let kind: String
        let title: String
        let detail: String
        let target: Double
        let category: String
    }

    private struct MissionResponse: Decodable {
        let missions: [MissionSuggestion]
    }

    private struct ReviewResponse: Decodable {
        struct Change: Decodable {
            let id: String
            let category: String
            let amount: Double
            let reason: String
        }

        let reply: String
        let changes: [Change]
    }

    private let session: URLSession
    private let decoder = JSONDecoder()

    private init(session: URLSession = .shared) {
        self.session = session
    }

    /// Sends every locally categorized row to AI for a second-pass review.
    /// Missing or invalid assignments stay with the local category at the call site.
    func categorize(
        _ transactions: [Transaction],
        progress: ((Int, Int) -> Void)? = nil
    ) async throws -> [String: TxCategory] {
        guard !transactions.isEmpty else { return [:] }

        // Keep requests small enough for the free endpoint and for long merchant names.
        let chunkSize = 80
        var result: [String: TxCategory] = [:]
        var lastError: Error?
        var start = 0
        while start < transactions.count {
            let end = min(start + chunkSize, transactions.count)
            let batch = Array(transactions[start..<end])
            do {
                let categories = try await categorizeBatch(batch)
                result.merge(categories) { _, new in new }
            } catch {
                // A long annual statement should keep successful batches even if
                // one free-model request is temporarily rate-limited.
                lastError = error
            }
            start = end
            progress?(start, transactions.count)
        }
        if result.isEmpty, let lastError { throw lastError }
        return result
    }

    func review(
        message: String,
        history: [AIChatMessage],
        transactions: [Transaction]
    ) async throws -> ReviewResult {
        if Self.isCapabilitiesQuestion(message) {
            return ReviewResult(
                reply: Self.capabilitiesReply,
                changes: []
            )
        }
        let candidates = Self.reviewCandidates(
            for: message,
            history: history,
            in: transactions
        )
        guard !candidates.isEmpty else {
            return ReviewResult(
                reply: "Сначала загрузите выписку — тогда я смогу найти и проверить операцию.",
                changes: []
            )
        }

        let endpoint = try configuredEndpoint(path: "/api/chat")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            ReviewRequest(
                message: message,
                history: history.suffix(16).map { item in
                    "\(item.role == .user ? "Пользователь" : "AI"): \(item.text)"
                },
                analyticsContext: Self.analyticsContext(
                    for: message,
                    in: transactions
                ),
                transactions: candidates.map(InputTransaction.init)
            )
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let serverMessage = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw APIError.server(serverMessage)
        }

        let result = try decoder.decode(ReviewResponse.self, from: data)
        let changes = result.changes.compactMap { change -> ReviewChange? in
            guard let category = TxCategory(aiCode: change.category) else { return nil }
            return ReviewChange(
                id: change.id,
                category: category,
                amount: change.amount,
                reason: change.reason
            )
        }
        return ReviewResult(reply: result.reply, changes: changes)
    }

    func generateWeeklyMissions(
        transactions: [Transaction],
        goal: Goal
    ) async throws -> [MissionSuggestion] {
        guard !transactions.isEmpty else { return [] }

        // A representative recent window keeps the prompt small while retaining
        // enough category and income context for realistic weekly targets.
        let candidates = transactions
            .sorted { $0.date > $1.date }
            .prefix(100)
        let endpoint = try configuredEndpoint(path: "/api/missions")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            MissionRequest(
                goal: .init(
                    title: goal.title,
                    targetAmount: goal.targetAmount,
                    savedAmount: goal.savedAmount
                ),
                transactions: candidates.map(InputTransaction.init)
            )
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let serverMessage = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw APIError.server(serverMessage)
        }
        return try decoder.decode(MissionResponse.self, from: data).missions
    }

    private static func reviewCandidates(
        for message: String,
        history: [AIChatMessage],
        in transactions: [Transaction]
    ) -> [Transaction] {
        guard transactions.count > 120 else { return transactions }
        // Short follow-ups such as "да, исправь её" need names and amounts from
        // the recent conversation to keep the referenced row in the AI request.
        let searchContext = ([message] + history.suffix(6).map(\.text))
            .joined(separator: " ")
        let queryStems = meaningfulStems(in: searchContext)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd MM yyyy"
        let ranked = transactions.map { transaction -> (Transaction, Int) in
            let haystack = "\(transaction.merchant) \(transaction.details) \(transaction.amount) \(dateFormatter.string(from: transaction.date))"
            let stems = allStems(in: haystack)
            let score = queryStems.reduce(0) { $0 + (stems.contains($1) ? 1 : 0) }
            return (transaction, score)
        }
        let matches = ranked.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.map(\.0)
        var selected = Array(matches.prefix(120))
        let selectedIDs = Set(selected.map(\.id))
        selected.append(contentsOf: transactions
            .filter { !selectedIDs.contains($0.id) }
            .sorted { $0.date > $1.date }
            .prefix(120 - selected.count))
        return selected
    }

    private static let capabilitiesReply = "Я умею искать операции по имени, магазину, категории, сумме и периоду; точно считать, сколько вы перевели человеку или потратили за месяц; сравнивать расходы; находить регулярные платежи; объяснять категории и предлагать исправления суммы или категории. Например: «Сколько я перевёл Даниялу?», «Покажи траты на еду за сентябрь» или «Найди мои подписки»."

    private static func isCapabilitiesQuestion(_ message: String) -> Bool {
        let value = message.lowercased()
        return value.contains("что ты умеешь")
            || value.contains("что умеешь")
            || value.contains("твои возможности")
            || value.contains("как ты можешь помочь")
    }

    /// Produces authoritative totals locally. The language model only explains
    /// these facts and never has to add hundreds of statement rows itself.
    private static func analyticsContext(
        for message: String,
        in transactions: [Transaction]
    ) -> String {
        let periodRows = transactionsInRequestedPeriod(message, transactions: transactions)
        let queryStems = meaningfulStems(in: message)
        let category = requestedCategory(in: message)

        let stemMatches: [(stem: String, rows: [Transaction])] = queryStems.compactMap { stem in
            let rows = periodRows.filter { transaction in
                allStems(in: "\(transaction.merchant) \(transaction.details)").contains(stem)
            }
            return rows.isEmpty ? nil : (stem, rows)
        }
        let entityMatch = stemMatches.min { lhs, rhs in lhs.rows.count < rhs.rows.count }

        var focused = entityMatch?.rows ?? periodRows
        if let category {
            focused = focused.filter { $0.category == category }
        }
        let outgoing = focused.filter { $0.amount < 0 }.reduce(0.0) { $0 + abs($1.amount) }
        let incoming = focused.filter { $0.amount > 0 }.reduce(0.0) { $0 + $1.amount }
        let periodOutgoing = periodRows.filter { $0.amount < 0 }.reduce(0.0) { $0 + abs($1.amount) }
        let periodIncoming = periodRows.filter { $0.amount > 0 }.reduce(0.0) { $0 + $1.amount }
        let categories = Dictionary(grouping: periodRows.filter { $0.amount < 0 }, by: \.category)
            .mapValues { rows in rows.reduce(0.0) { $0 + abs($1.amount) } }
            .sorted { $0.value > $1.value }
            .map { "\($0.key.rawValue)=\(moneyNumber($0.value))" }
            .joined(separator: ", ")
        let monthlySummary = monthlyTotals(in: transactions)
        let recurringSummary = recurringPaymentFacts(in: transactions)
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "ru_RU")
        dateFormatter.dateFormat = "dd.MM.yyyy"
        let sortedDates = periodRows.map(\.date).sorted()
        let periodText: String
        if let first = sortedDates.first, let last = sortedDates.last {
            periodText = "\(dateFormatter.string(from: first))–\(dateFormatter.string(from: last))"
        } else {
            periodText = "нет подходящих дат"
        }
        let focusName = entityMatch?.rows.first?.merchant
            ?? category?.rawValue
            ?? "все подходящие операции"
        return [
            "ЛОКАЛЬНО РАССЧИТАННЫЕ ТОЧНЫЕ ФАКТЫ (считать заново не нужно):",
            "Период: \(periodText). Операций в периоде: \(periodRows.count).",
            "За период: исходящие \(moneyNumber(periodOutgoing)) ₸, входящие \(moneyNumber(periodIncoming)) ₸, чистый результат \(moneyNumber(periodIncoming - periodOutgoing)) ₸.",
            "Фокус запроса: \(focusName). Найдено операций: \(focused.count). Исходящие: \(moneyNumber(outgoing)) ₸. Входящие: \(moneyNumber(incoming)) ₸.",
            "Расходы по категориям: \(categories.isEmpty ? "нет" : categories).",
            "Месячные итоги: \(monthlySummary.isEmpty ? "нет" : monthlySummary).",
            "Вероятные регулярные платежи: \(recurringSummary.isEmpty ? "не найдены" : recurringSummary).",
        ].joined(separator: "\n")
    }

    private static func monthlyTotals(in transactions: [Transaction]) -> String {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: transactions) { transaction -> String in
            let values = calendar.dateComponents([.year, .month], from: transaction.date)
            return String(format: "%04d-%02d", values.year ?? 0, values.month ?? 0)
        }
        return grouped.map { key, rows -> (String, String) in
            let outgoing = rows.filter { $0.amount < 0 }.reduce(0.0) { $0 + abs($1.amount) }
            let incoming = rows.filter { $0.amount > 0 }.reduce(0.0) { $0 + $1.amount }
            return (key, "\(key): доходы \(moneyNumber(incoming)) ₸, расходы \(moneyNumber(outgoing)) ₸, баланс \(moneyNumber(incoming - outgoing)) ₸")
        }
        .sorted { $0.0 > $1.0 }
        .prefix(12)
        .map(\.1)
        .joined(separator: "; ")
    }

    private static func recurringPaymentFacts(in transactions: [Transaction]) -> String {
        let ignored: Set<TxCategory> = [.transfers, .internalTransfers, .cashWithdrawals]
        let expenses = transactions.filter { $0.amount < 0 && !ignored.contains($0.category) }
        let grouped = Dictionary(grouping: expenses) { transaction in
            transaction.merchant.lowercased()
                .folding(options: [.diacriticInsensitive], locale: Locale(identifier: "ru_RU"))
                .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let calendar = Calendar.current
        return grouped.compactMap { _, rows -> (Double, String)? in
            guard rows.count >= 2, let sample = rows.first else { return nil }
            let months = Set(rows.map {
                let values = calendar.dateComponents([.year, .month], from: $0.date)
                return "\(values.year ?? 0)-\(values.month ?? 0)"
            })
            guard months.count >= 2 else { return nil }
            let amounts = rows.map { abs($0.amount) }
            let average = amounts.reduce(0, +) / Double(amounts.count)
            let spread = (amounts.max() ?? average) - (amounts.min() ?? average)
            guard spread <= max(average * 0.25, 1_000) else { return nil }
            return (
                average * Double(rows.count),
                "\(sample.merchant): \(rows.count) платежа, обычно \(moneyNumber(average)) ₸, категория \(sample.category.rawValue)"
            )
        }
        .sorted { $0.0 > $1.0 }
        .prefix(8)
        .map(\.1)
        .joined(separator: "; ")
    }

    private static func transactionsInRequestedPeriod(
        _ message: String,
        transactions: [Transaction]
    ) -> [Transaction] {
        let lower = message.lowercased()
        let calendar = Calendar.current
        let now = Date()
        if lower.contains("прошл") && lower.contains("месяц"),
           let previous = calendar.date(byAdding: .month, value: -1, to: now),
           let interval = calendar.dateInterval(of: .month, for: previous) {
            return transactions.filter { interval.contains($0.date) }
        }
        if (lower.contains("этот месяц") || lower.contains("текущ") && lower.contains("месяц")),
           let interval = calendar.dateInterval(of: .month, for: now) {
            return transactions.filter { interval.contains($0.date) }
        }

        let months: [(String, Int)] = [
            ("январ", 1), ("феврал", 2), ("март", 3), ("апрел", 4),
            ("мая", 5), ("май", 5), ("июн", 6), ("июл", 7),
            ("август", 8), ("сентябр", 9), ("октябр", 10),
            ("ноябр", 11), ("декабр", 12),
        ]
        guard let month = months.first(where: { lower.contains($0.0) })?.1 else {
            return transactions
        }
        let explicitYear = lower.range(of: #"\b20\d{2}\b"#, options: .regularExpression)
            .flatMap { Int(lower[$0]) }
        let year = explicitYear ?? transactions
            .filter { calendar.component(.month, from: $0.date) == month }
            .map { calendar.component(.year, from: $0.date) }
            .max()
        guard let year else { return [] }
        return transactions.filter {
            calendar.component(.month, from: $0.date) == month
                && calendar.component(.year, from: $0.date) == year
        }
    }

    private static func requestedCategory(in message: String) -> TxCategory? {
        let lower = message.lowercased()
        let mappings: [(TxCategory, [String])] = [
            (.food, ["продукт", "супермаркет"]),
            (.cafes, ["кафе", "ресторан", "доставк", "еду", "еда"]),
            (.transport, ["такси", "транспорт", "автобус"]),
            (.entertainment, ["развлеч", "кино", "игр"]),
            (.health, ["здоров", "аптек", "врач"]),
            (.education, ["образован", "обучен", "курс"]),
            (.utilities, ["коммун", "интернет", "связь"]),
            (.subscriptions, ["подписк"]),
            (.shopping, ["покупк", "магазин"]),
            (.loans, ["кредит", "займ", "долг"]),
            (.taxes, ["налог", "штраф"]),
            (.cashWithdrawals, ["снял", "снятие", "наличн"]),
            (.transfers, ["перевел", "перевёл", "перевод"]),
        ]
        return mappings.first { item in item.1.contains { lower.contains($0) } }?.0
    }

    private static func meaningfulStems(in text: String) -> Set<String> {
        let ignored: Set<String> = [
            "сколь", "всего", "пере", "перев", "отпра", "потра", "запла",
            "получ", "трат", "опера", "деньг", "сумм", "тенге", "месяц",
            "недел", "покаж", "найди", "какие", "какой", "было", "этому",
            "этого", "куда", "когда", "катег", "через", "между", "прошл",
            "текущ", "напри", "пожал", "можеш", "сентя", "октяб", "ноябр",
            "декаб", "январ", "февра", "апрел", "авгус",
        ]
        return Set(allStems(in: text).filter { !ignored.contains($0) })
    }

    private static func allStems(in text: String) -> Set<String> {
        Set(text.lowercased()
            .folding(options: [.diacriticInsensitive], locale: Locale(identifier: "ru_RU"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 4 }
            .map { String($0.prefix(5)) })
    }

    private static func moneyNumber(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func categorizeBatch(_ transactions: [Transaction]) async throws -> [String: TxCategory] {
        guard !transactions.isEmpty else { return [:] }

        let endpoint = try configuredEndpoint(path: "/api/categorize")
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

    private func configuredEndpoint(path: String) throws -> URL {
        let raw = Bundle.main.object(forInfoDictionaryKey: "AI_API_BASE_URL") as? String
        let baseURL = (raw?.isEmpty == false && raw != "$(AI_API_BASE_URL)")
            ? raw!
            : "http://127.0.0.1:8787"
        let normalized = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        guard let url = URL(string: normalized + path) else {
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
