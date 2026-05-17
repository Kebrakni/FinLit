import Foundation

// MARK: - Result types

struct AIAnalysis {
    struct Categorization {
        let transactionId: String
        let suggestedCategory: String   // TxCategory.rawValue OR custom string
        let confidence: Double
        let isUncertain: Bool
        let alternatives: [String]      // shown to user when uncertain
    }
    let categorizations: [Categorization]
    let insights: String
    let advice: [String]
}

// MARK: - Service

final class AIService {
    static let shared = AIService()
    private init() {}

    private let apiKey  = "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"
    private let baseURL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    private let model   = "anthropic/claude-3.5-haiku"

    // MARK: - Public entry point

    func analyzeTransactions(_ transactions: [Transaction]) async throws -> AIAnalysis {
        guard !transactions.isEmpty else {
            throw AIError("Нет транзакций для анализа. Сначала загрузи PDF выписку в Аналитике.")
        }
        let prompt  = buildPrompt(for: transactions)
        let content = try await callAPI(prompt: prompt)
        return try parseResponse(content, transactions: transactions)
    }

    // MARK: - Prompt

    private func buildPrompt(for transactions: [Transaction]) -> String {
        let overrides  = AppStorage.shared.loadCategoryOverrides()
        let categoryNames = TxCategory.allCases.map { $0.rawValue }.joined(separator: ", ")

        // Expense summary for context
        let expenses = transactions.filter { $0.amount < 0 }
        let totalExp = expenses.reduce(0.0) { $0 + abs($1.amount) }
        let income   = transactions.filter { $0.amount > 0 }.reduce(0.0) { $0 + $1.amount }
        let grouped  = Dictionary(grouping: expenses, by: { overrides[$0.id] ?? $0.category.rawValue })
        var summaryLines = ""
        for (catName, txs) in grouped.sorted(by: { a, b in
            a.value.reduce(0.0){ $0 + abs($1.amount) } > b.value.reduce(0.0){ $0 + abs($1.amount) }
        }) {
            let total = txs.reduce(0.0) { $0 + abs($1.amount) }
            let pct   = totalExp > 0 ? Int(total / totalExp * 100) : 0
            summaryLines += "\n  \(catName): \(txs.count) транз., \(Int(total)) ₸ (\(pct)%)"
        }

        // Only send transactions without override that are categorised as .other
        let needsReview = transactions
            .filter { overrides[$0.id] == nil && $0.category == .other }
            .sorted { abs($0.amount) > abs($1.amount) }
            .prefix(60)

        var txJSON = "["
        for tx in needsReview {
            let merchant = tx.merchant
                .replacingOccurrences(of: "\"", with: "'")
                .prefix(60)
            let txType = leadingType(tx.details)
            txJSON += "\n  {\"id\":\"\(tx.id.prefix(20))\",\"merchant\":\"\(merchant)\",\"amount\":\(Int(tx.amount)),\"type\":\"\(txType)\"},"
        }
        if txJSON.last == "," { txJSON.removeLast() }
        txJSON += "\n]"

        let period = dateRange(transactions)

        return """
        Ты финансовый AI-аналитик для приложения FinLit (Казахстан, банк Kaspi).

        ПЕРИОД: \(period)
        ДОХОДЫ: \(Int(income)) ₸   РАСХОДЫ: \(Int(totalExp)) ₸
        РАСХОДЫ ПО КАТЕГОРИЯМ:\(summaryLines.isEmpty ? " нет данных" : summaryLines)

        ТРАНЗАКЦИИ ДЛЯ КАТЕГОРИЗАЦИИ (категория «Другое», нужна помощь):
        \(txJSON)

        ДОСТУПНЫЕ КАТЕГОРИИ: \(categoryNames)
        Если ни одна категория не подходит — предложи новую (например «Автосервис», «Красота», «Одежда», «Животные»).

        ЗАДАНИЕ:
        1. Для каждой транзакции из списка определи наиболее подходящую категорию.
        2. Если уверенность < 0.75 — uncertain=true и дай 2-3 альтернативы (alternatives) чтобы пользователь выбрал сам.
        3. Напиши краткий анализ расходов (insights, 2-3 предложения) на русском — с конкретными суммами.
        4. Дай 3-5 конкретных совета по экономии с цифрами (advice).

        Ответь СТРОГО в JSON без markdown-блоков:
        {
          "categorizations": [
            {"id":"...","category":"...","confidence":0.9,"uncertain":false,"alternatives":[]}
          ],
          "insights": "...",
          "advice": ["...", "...", "..."]
        }
        """
    }

    private func leadingType(_ details: String) -> String {
        let d = details.lowercased()
        for t in ["purchases","transfers","replenishment","withdrawals","others"] {
            if d.hasPrefix(t) { return t.capitalized }
        }
        return "—"
    }

    private func dateRange(_ txs: [Transaction]) -> String {
        let df = DateFormatter(); df.dateFormat = "dd.MM.yyyy"
        let sorted = txs.sorted { $0.date < $1.date }
        guard let f = sorted.first, let l = sorted.last else { return "—" }
        return "\(df.string(from: f.date)) – \(df.string(from: l.date))"
    }

    // MARK: - Network

    private func callAPI(prompt: String) async throws -> String {
        var req = URLRequest(url: baseURL)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)",    forHTTPHeaderField: "Authorization")
        req.setValue("application/json",    forHTTPHeaderField: "Content-Type")
        req.setValue("https://finlit.app",  forHTTPHeaderField: "HTTP-Referer")
        req.setValue("FinLit",              forHTTPHeaderField: "X-Title")
        req.timeoutInterval = 90

        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": prompt]],
            "max_tokens": 4096,
            "temperature": 0.2
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw AIError("Нет ответа от сервера")
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AIError("Ошибка API \(http.statusCode): \(body.prefix(300))")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let msg = choices.first?["message"] as? [String: Any],
              let content = msg["content"] as? String else {
            throw AIError("Неверный формат ответа от API")
        }
        return content
    }

    // MARK: - Parse

    private func parseResponse(_ raw: String, transactions: [Transaction]) throws -> AIAnalysis {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["```json","```"] { if s.hasPrefix(prefix) { s = String(s.dropFirst(prefix.count)) } }
        if s.hasSuffix("```") { s = String(s.dropLast(3)) }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = s.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError("Не удалось разобрать ответ AI. Попробуй снова.")
        }

        // Short-id → full-id lookup (we sent prefix(20) to save tokens)
        var idMap = [String: String]()
        for tx in transactions { idMap[String(tx.id.prefix(20))] = tx.id }

        var categorizations: [AIAnalysis.Categorization] = []
        if let arr = json["categorizations"] as? [[String: Any]] {
            for item in arr {
                guard let shortId  = item["id"] as? String,
                      let category = item["category"] as? String else { continue }
                let fullId       = idMap[shortId] ?? shortId
                let confidence   = item["confidence"]  as? Double ?? 0.8
                let uncertain    = item["uncertain"]   as? Bool ?? (confidence < 0.75)
                let alternatives = item["alternatives"] as? [String] ?? []
                categorizations.append(.init(
                    transactionId: fullId,
                    suggestedCategory: category,
                    confidence: confidence,
                    isUncertain: uncertain,
                    alternatives: alternatives
                ))
            }
        }

        let insights = json["insights"] as? String ?? "Анализ завершён."
        let advice   = json["advice"]   as? [String] ?? []
        return AIAnalysis(categorizations: categorizations, insights: insights, advice: advice)
    }
}

// MARK: - Error helper

private func AIError(_ msg: String) -> NSError {
    NSError(domain: "AIService", code: 0, userInfo: [NSLocalizedDescriptionKey: msg])
}
