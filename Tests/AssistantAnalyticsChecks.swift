import Foundation

/// Run directly with swiftc alongside Models, AssistantAnalytics and OpenRouterCategorizer.
@main
struct AssistantAnalyticsChecks {
    static func main() async throws {
        let calendar = Calendar.current
        func row(_ merchant: String, _ amount: Double, _ month: Int = 9, _ category: TxCategory = .transfers, year: Int = 2026) -> Transaction {
            Transaction(date: calendar.date(from: DateComponents(year: year, month: month, day: 20, hour: 12))!,
                        amount: amount, merchant: merchant, details: "", category: category)
        }
        let rows = [
            row("Даниял Ж.", -3400), row("ДАНИЯЛ  Ж", -950), row("Даниял Ж.", -800),
            row("Даниял Ж.", 123), row("Даниял Ж.", -50, 10),
            row("Дархан Е.", 25000), row("Дархан Е.", 5000), row("Дархан Е.", 10000),
            row("Даниял Ж.", -500, 9, .internalTransfers),
            row("Магазин", -2500, 9, .shopping), row("Даниял Ж.", -700, 9, .shopping),
            row("Даниял Ж.", -999, 9, .transfers, year: 2025)
        ]
        let september = AssistantAnalytics.Period(year: 2026, month: 9)
        let daniyal = AssistantAnalytics.Query.person(key: AssistantAnalytics.merchantKey("Даниял Ж."), name: "Даниял Ж.", direction: .outgoing)
        let answer = AssistantAnalytics.answer(query: daniyal, period: september, transactions: rows)
        precondition(answer.insight.amount == 5150, "Outgoing total must exclude income, internal transfers, purchases and other periods")
        precondition(AssistantAnalytics.rows(for: daniyal, period: september, in: rows).count == 3)
        let received = AssistantAnalytics.answer(query: .person(key: AssistantAnalytics.merchantKey("Дархан Е."), name: "Дархан Е.", direction: .incoming), period: september, transactions: rows)
        precondition(received.insight.amount == 40000)
        precondition(AssistantAnalytics.people(in: rows, direction: .outgoing).filter { $0.key == AssistantAnalytics.merchantKey("Даниял Ж.") }.count == 1, "Whitespace, punctuation and case must not duplicate a person")
        precondition(AssistantAnalytics.answer(query: .category(.shopping), period: september, transactions: rows).insight.amount == 3200)
        precondition(AssistantAnalytics.answer(query: .expenses, period: september, transactions: rows).insight.amount == 8850)
        precondition(AssistantAnalytics.answer(query: .income, period: september, transactions: rows).insight.amount == 40123)
        precondition(AssistantAnalytics.answer(query: .overview, period: september, transactions: rows).insight.amount == 31273)
        precondition(AssistantAnalytics.total([row("A", -0.1), row("B", -0.2)]) == 0.3)
        precondition(AssistantAnalytics.total([row("A", .infinity), row("B", -.nan)]) == 0)
        let periods = AssistantAnalytics.periods(in: rows)
        precondition(periods.first == .all && periods[1] == .init(year: 2026, month: 10))

        // Legacy chat histories do not contain the new optional rich-card field.
        let legacy = Data(#"[{"id":"old","date":0,"text":"Привет","role":"assistant"}]"#.utf8)
        let decoded = try JSONDecoder().decode([AIChatMessage].self, from: legacy)
        precondition(decoded.count == 1 && decoded[0].insight == nil)
        let message = AIChatMessage(text: answer.text, role: .assistant, insight: answer.insight)
        let restored = try JSONDecoder().decode(AIChatMessage.self, from: JSONEncoder().encode(message))
        precondition(restored.insight?.amount == 5150)

        // These queries must complete locally; no configured backend is needed.
        let outgoing = try await OpenRouterCategorizer.shared.review(message: "Сколько я перевёл Даниялу за сентябрь 2026?", history: [], transactions: rows)
        precondition(outgoing.insight?.amount == 5150)
        let incoming = try await OpenRouterCategorizer.shared.review(message: "Сколько денег мне скинул Дархан за сентябрь 2026?", history: [], transactions: rows)
        precondition(incoming.insight?.amount == 40000)
        let expenses = try await OpenRouterCategorizer.shared.review(message: "Сколько я потратил всего за сентябрь 2026?", history: [], transactions: rows)
        precondition(expenses.insight?.amount == 8850, "Expenses must not accidentally return the transfer-only total")
        let year = try await OpenRouterCategorizer.shared.review(message: "Сколько я перевёл Даниялу за 2025 год?", history: [], transactions: rows)
        precondition(year.insight?.amount == 999)
        let ambiguous = try await OpenRouterCategorizer.shared.review(message: "Сколько я перевёл Даниялу?", history: [], transactions: rows + [row("Даниял К.", -100)])
        precondition(ambiguous.insight == nil && ambiguous.reply.contains("несколько"))
        let capability = try await OpenRouterCategorizer.shared.review(message: "Что ты умеешь?", history: [], transactions: [])
        precondition(capability.reply.contains("Кнопки"))

        let start = Date()
        let annual = (0..<5000).map { index in row("Человек \(index % 30)", -Double(index % 100 + 1), index % 12 + 1) }
        _ = AssistantAnalytics.people(in: annual, direction: .outgoing)
        _ = AssistantAnalytics.answer(query: .overview, period: .all, transactions: annual)
        print("PASS: exact totals, directions, periods, normalized names, history migration, local chat replies. 5000-row analytics: \(String(format: "%.3f", Date().timeIntervalSince(start))) s")
    }
}
