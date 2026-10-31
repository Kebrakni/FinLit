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
        let categoryEvidence: String?
        let manualCategory: String?

        init(_ transaction: Transaction, formatter: ISO8601DateFormatter) {
            self.id = transaction.id
            self.date = formatter.string(from: transaction.date)
            self.amount = transaction.amount
            self.merchant = transaction.merchant
            self.details = transaction.details
            let manual = LearnedCategoryRules.manualCategory(for: transaction.merchant)
            let evidence = Categorizer.evidence(merchant: transaction.merchant, details: transaction.details)
            // Keep the actual stored category: chat review must be able to see
            // that an old shopping assignment still needs correction.
            self.currentCategory = transaction.category.aiCode
            self.categoryEvidence = evidence?.reason
            self.manualCategory = manual?.aiCode
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
        let insight: AIChatInsight?

        init(reply: String, changes: [ReviewChange], insight: AIChatInsight? = nil) {
            self.reply = reply
            self.changes = changes
            self.insight = insight
        }
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

    init(session: URLSession = .shared) {
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
            try Task.checkCancellation()
            let end = min(start + chunkSize, transactions.count)
            let batch = Array(transactions[start..<end])
            do {
                let categories = try await categorizeBatch(batch)
                result.merge(categories) { _, new in new }
            } catch {
                if Task.isCancelled { throw CancellationError() }
                // A long annual statement should keep successful batches even if
                // one free-model request is temporarily rate-limited.
                lastError = error
                if case APIError.server(let status, _) = error, [401, 403, 429].contains(status) || status >= 500 { break }
                if error is DecodingError { break }
                if let network = error as? URLError,
                   [.notConnectedToInternet, .timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost].contains(network.code) { break }
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
        if let result = Self.quickAnswer(message: message, transactions: transactions) { return result }
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
                history: history.suffix(8).map { item in
                    "\(item.role == .user ? "Пользователь" : "AI"): \(item.text)"
                },
                analyticsContext: Self.analyticsContext(
                    for: message,
                    in: transactions
                ),
                transactions: Self.inputTransactions(candidates)
            )
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw Self.serverError(data, status: httpResponse.statusCode)
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
                transactions: Self.inputTransactions(Array(candidates))
            )
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw Self.serverError(data, status: httpResponse.statusCode)
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

    private static let capabilitiesReply = "Кнопки под чатом помогут без ожидания посмотреть переводы человеку, расходы по категории и обзор за месяц. Нажмите «Проверить», чтобы найти ошибки в категориях с AI или исправить операцию вручную. Любое предложенное исправление можно проверить перед применением. Можно и просто написать: «Сколько я перевёл Даниялу за сентябрь?»"

    private static func quickAnswer(message: String, transactions: [Transaction]) -> ReviewResult? {
        let lower = message.lowercased().replacingOccurrences(of: "ё", with: "е")
        guard !["исправ", "помен", "проверь", "правильн", "неверн", "сравн", "почему", "тестер"].contains(where: lower.contains),
              ["сколько", "потрат", "расход", "перевел", "скинул", "перевод", "обзор", "баланс"].contains(where: lower.contains) else { return nil }
        // Leave non-calendar or incomplete date expressions to clarification in the free-form chat.
        if ["недел", "сегодня", "вчера", "дней", "дня", "дней", "числа"].contains(where: lower.contains)
            || lower.range(of: #"\d{1,2}[./]\d{1,2}"#, options: .regularExpression) != nil { return nil }
        let numbers = lower.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
        if numbers.contains(where: { $0.count != 4 || !$0.hasPrefix("20") }) { return nil }
        let periodRows = transactionsInRequestedPeriod(message, transactions: transactions)
        let incoming = ["мне", "получ", "кто", " от "].contains(where: lower.contains)
        let outgoing = ["я перев", "я скин", "я отпра", "мои перев", "кому"].contains(where: lower.contains)
        let direction: AssistantAnalytics.Direction = incoming ? .incoming : .outgoing
        let queryStems = meaningfulStems(in: message)
        let transferIntent = ["перев", "скин", "отправ"].contains(where: lower.contains) || lower.contains("получ") && lower.contains("от ")
        let unresolvedReply = "Не удалось однозначно выбрать человека или магазин. Нажмите «Переводы» или «Расходы» под чатом и выберите нужный вариант. Общую сумму вместо нужной операции я не подставляю."
        if transferIntent, lower.range(of: #"(?:перевел|скинул|отправил)\s+(?!мне\b|кому\b|куда\b|всем\b|всего\b|за\b|на\b)[\p{L}]{2,3}\b"#, options: .regularExpression) != nil {
            return ReviewResult(reply: unresolvedReply, changes: [])
        }
        let residual = queryStems.filter { Int($0) == nil }
        if transferIntent && !incoming && !outgoing {
            return ReviewResult(reply: "Посмотреть ваши исходящие переводы или поступления от другого человека? Выберите направление кнопкой «Переводы» под чатом.", changes: [])
        }
        let merchantMatches = Dictionary(grouping: transactions.filter { $0.amount < 0 }, by: { AssistantAnalytics.merchantKey($0.merchant) })
            .compactMap { key, rows -> (String, String)? in
                guard let name = rows.first?.merchant, !allStems(in: name).intersection(queryStems).isEmpty else { return nil }
                return (key, name)
            }
        let people = AssistantAnalytics.people(in: transactions, direction: direction)
        let matches = people.filter { !allStems(in: $0.name).intersection(queryStems).isEmpty }
        let query: AssistantAnalytics.Query
        if transferIntent, matches.count == 1, let person = matches.first {
            query = .person(key: person.key, name: person.name, direction: direction)
        } else if transferIntent, matches.count > 1 {
            return ReviewResult(reply: "В выписках несколько подходящих людей: \(matches.prefix(6).map(\.name).joined(separator: ", ")). Нажмите «Переводы» под чатом и выберите нужного человека.", changes: [])
        } else if let category = requestedCategory(in: message), category != .transfers {
            query = .category(category)
        } else if !transferIntent && merchantMatches.count == 1, let merchant = merchantMatches.first {
            query = .merchant(key: merchant.0, name: merchant.1)
        } else if !residual.isEmpty {
            return ReviewResult(reply: unresolvedReply, changes: [])
        } else if transferIntent && (lower.contains("всего") || lower.contains("кому") || lower.contains("кто")) {
            query = .transfers(direction)
        } else if ["обзор", "баланс", "на что", "больше всего"].contains(where: lower.contains) {
            query = .overview
        } else if !transferIntent && ["потрат", "расход"].contains(where: lower.contains) {
            query = .expenses
        } else if !transferIntent && ["получ", "доход", "поступ"].contains(where: lower.contains) {
            query = .income
        } else {
            // Unknown names need clarification from the AI instead of returning a total for everybody.
            return nil
        }
        let result = AssistantAnalytics.answer(query: query, period: .all, transactions: periodRows)
        let date = DateFormatter()
        date.locale = Locale(identifier: "ru_RU")
        date.dateFormat = "dd.MM.yyyy"
        let period = [periodRows.map(\.date).min(), periodRows.map(\.date).max()].compactMap { $0 }.map(date.string).joined(separator: "–")
        let insight = AIChatInsight(title: result.insight.title, amount: result.insight.amount,
                                    subtitle: "\(period.isEmpty ? "За выбранный период" : period) · по загруженным операциям", lines: result.insight.lines)
        return ReviewResult(reply: "\(insight.title). \(insight.subtitle): \(AssistantAnalytics.money(insight.amount)).\n\(insight.lines.joined(separator: "\n"))", changes: [], insight: insight)
    }

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
        let explicitYear = lower.range(of: #"\b20\d{2}\b"#, options: .regularExpression)
            .flatMap { Int(lower[$0]) }
        if lower.contains("прошл") && lower.contains("месяц"),
           let previous = calendar.date(byAdding: .month, value: -1, to: now),
           let interval = calendar.dateInterval(of: .month, for: previous) {
            return transactions.filter { interval.containsTransactionDate($0.date) }
        }
        if (lower.contains("этот месяц") || lower.contains("текущ") && lower.contains("месяц")),
           let interval = calendar.dateInterval(of: .month, for: now) {
            return transactions.filter { interval.containsTransactionDate($0.date) }
        }

        let months: [(String, Int)] = [
            ("январ", 1), ("феврал", 2), ("март", 3), ("апрел", 4),
            ("мая", 5), ("май", 5), ("июн", 6), ("июл", 7),
            ("август", 8), ("сентябр", 9), ("октябр", 10),
            ("ноябр", 11), ("декабр", 12),
        ]
        guard let month = months.first(where: { lower.contains($0.0) })?.1 else {
            if let explicitYear {
                return transactions.filter { calendar.component(.year, from: $0.date) == explicitYear }
            }
            if lower.contains("год") && (lower.contains("прошл") || lower.contains("текущ") || lower.contains("этот")) {
                let year = calendar.component(.year, from: now) - (lower.contains("прошл") ? 1 : 0)
                return transactions.filter { calendar.component(.year, from: $0.date) == year }
            }
            return transactions
        }
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
            "март", "время", "вообщ", "расхо", "доход", "поступ", "итого", "посмо", "моих", "общая", "трачу", "траты", "денег", "больш",
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
            Request(transactions: Self.inputTransactions(transactions))
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw Self.serverError(data, status: httpResponse.statusCode)
        }

        let result = try decoder.decode(Response.self, from: data)
        let decisions = result.categories.reduce(into: [String: TxCategory]()) { output, item in
            if let category = TxCategory(aiCode: item.category) { output[item.id] = category }
        }
        return transactions.reduce(into: [:]) { output, transaction in
            output[transaction.id] = Categorizer.finalCategory(for: transaction, aiCategory: decisions[transaction.id])
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

    private static func inputTransactions(_ transactions: [Transaction]) -> [InputTransaction] {
        let formatter = ISO8601DateFormatter()
        return transactions.map { InputTransaction($0, formatter: formatter) }
    }

    enum APIError: LocalizedError {
        case invalidURL
        case invalidResponse
        case server(Int, String)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Неверный адрес AI-сервера"
            case .invalidResponse:
                return "AI-сервер вернул неверный ответ"
            case .server(_, let message):
                return message
            }
        }
    }

    private static func serverError(_ data: Data, status: Int) -> APIError {
        struct Envelope: Decodable { let error: String?; let message: String? }
        let envelope = try? JSONDecoder().decode(Envelope.self, from: data)
        return .server(status, envelope?.error ?? envelope?.message ?? "AI-сервер вернул ошибку HTTP \(status)")
    }
}
