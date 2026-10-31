import Foundation

/// Exact statement queries used by the chat buttons. No network or model arithmetic.
nonisolated enum AssistantAnalytics {
    enum Direction: String, Sendable {
        case outgoing, incoming
        var title: String { self == .outgoing ? "Кому я переводил" : "Кто переводил мне" }
        func includes(_ row: Transaction) -> Bool { self == .outgoing ? row.amount < 0 : row.amount > 0 }
    }

    enum Query: Sendable {
        case person(key: String, name: String, direction: Direction)
        case transfers(Direction)
        case category(TxCategory)
        case merchant(key: String, name: String)
        case expenses
        case income
        case overview
        case review(TxCategory?)

        var title: String {
            switch self {
            case let .person(_, name, direction): return "\(direction == .outgoing ? "Переводы →" : "Переводы от") \(name)"
            case let .transfers(direction): return direction.title
            case let .category(category): return "Расходы · \(category.rawValue)"
            case let .merchant(_, name): return "Расходы · \(name)"
            case .expenses: return "Все расходы"
            case .income: return "Все поступления"
            case .overview: return "Обзор финансов"
            case let .review(category): return category.map { "Проверить · \($0.rawValue)" } ?? "Проверить распределение"
            }
        }
    }

    struct Period: Hashable, Sendable {
        let year: Int
        let month: Int
        static let all = Period(year: 0, month: 0)
        var title: String {
            guard year > 0 else { return "За всё время" }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "ru_RU")
            formatter.dateFormat = "LLLL yyyy"
            let date = Calendar.current.date(from: DateComponents(year: year, month: month)) ?? .distantPast
            return formatter.string(from: date).capitalized
        }
        func includes(_ date: Date) -> Bool {
            guard year > 0 else { return true }
            let parts = Calendar.current.dateComponents([.year, .month], from: date)
            return parts.year == year && parts.month == month
        }
    }

    struct Person: Sendable {
        let key: String
        let name: String
        let count: Int
        let total: Double
    }

    struct Answer: Sendable {
        let text: String
        let insight: AIChatInsight
    }

    static func merchantKey(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ru_RU"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func people(in transactions: [Transaction], direction: Direction) -> [Person] {
        let transfers = transactions.filter { $0.category == .transfers && direction.includes($0) }
        return Dictionary(grouping: transfers, by: { merchantKey($0.merchant) }).compactMap { key, rows in
            guard !key.isEmpty, let first = rows.first else { return nil }
            return Person(key: key, name: first.merchant, count: rows.count, total: total(rows))
        }.sorted { $0.total == $1.total ? $0.name < $1.name : $0.total > $1.total }
    }

    static func rows(for query: Query, period: Period = .all, in transactions: [Transaction]) -> [Transaction] {
        transactions.filter { row in
            guard period.includes(row.date) else { return false }
            switch query {
            case let .person(key, _, direction):
                return row.category == .transfers && direction.includes(row) && merchantKey(row.merchant) == key
            case let .transfers(direction): return row.category == .transfers && direction.includes(row)
            case let .category(category): return row.category == category && row.amount < 0
            case let .merchant(key, _): return row.amount < 0 && merchantKey(row.merchant) == key
            case .expenses: return row.amount < 0
            case .income: return row.amount > 0
            case .overview: return true
            case let .review(category): return category == nil || row.category == category
            }
        }.sorted { $0.date > $1.date }
    }

    static func periods(in rows: [Transaction]) -> [Period] {
        let calendar = Calendar.current
        let months = Set(rows.map { row in
            let parts = calendar.dateComponents([.year, .month], from: row.date)
            return Period(year: parts.year ?? 0, month: parts.month ?? 0)
        })
        return [.all] + months.sorted { ($0.year, $0.month) > ($1.year, $1.month) }
    }

    static func total(_ rows: [Transaction]) -> Double {
        // Sum currency at kopeck precision rather than accumulating binary fractions.
        let amount = rows.reduce(Decimal.zero) { result, row in
            guard row.amount.isFinite else { return result }
            return result + (Decimal(string: String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), abs(row.amount))) ?? .zero)
        }
        return NSDecimalNumber(decimal: amount).doubleValue
    }

    static func money(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "ru_KZ")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return "\(formatter.string(from: NSNumber(value: amount)) ?? "0") ₸"
    }

    static func answer(query: Query, period: Period, transactions: [Transaction]) -> Answer {
        let selected = rows(for: query, period: period, in: transactions)
        let date = DateFormatter()
        date.locale = Locale(identifier: "ru_RU")
        date.dateFormat = "dd.MM.yyyy"
        let summary: String
        let amount: Double
        var lines: [String]
        switch query {
        case .expenses, .income:
            amount = total(selected)
            summary = "\(selected.count) операций в загруженных выписках"
            lines = Dictionary(grouping: selected, by: \.category)
                .map { ($0.key, total($0.value)) }.sorted { $0.1 > $1.1 }
                .prefix(8).map { "\($0.0.rawValue): \(money($0.1))" }
        case let .transfers(direction):
            amount = total(selected)
            summary = "\(selected.count) переводов в загруженных выписках"
            lines = people(in: selected, direction: direction).prefix(8).map { "\($0.name): \(money($0.total)) · \($0.count) операций" }
        case .overview:
            let incoming = total(selected.filter { $0.amount > 0 })
            let outgoing = total(selected.filter { $0.amount < 0 })
            amount = incoming - outgoing
            summary = "Баланс за выбранный период"
            let categories = Dictionary(grouping: selected.filter { $0.amount < 0 }, by: \.category)
                .map { ($0.key, total($0.value)) }.sorted { $0.1 > $1.1 }
            lines = ["Доходы: \(money(incoming))", "Расходы: \(money(outgoing))"]
            lines += categories.prefix(5).map { "\($0.0.rawValue): \(money($0.1))" }
        default:
            amount = total(selected)
            summary = selected.isEmpty ? "В загруженных выписках нет таких операций" : "\(selected.count) операций в загруженных выписках"
            lines = selected.prefix(6).map { "\(date.string(from: $0.date)) · \($0.merchant) · \(money(abs($0.amount)))" }
            if selected.count > 6 { lines.append("И ещё \(selected.count - 6) операций, учтённых в общей сумме") }
        }
        let insight = AIChatInsight(title: query.title, amount: amount, subtitle: "\(period.title) · \(summary)", lines: lines)
        return Answer(text: "\(query.title). \(period.title): \(money(amount)). \(summary).\n\(lines.joined(separator: "\n"))", insight: insight)
    }
}
