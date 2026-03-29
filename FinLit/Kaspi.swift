import Foundation
import PDFKit

final class KaspiPDFParser {

    struct ParseResult {
        let transactions: [Transaction]
        let errors: [String]
    }

    func parse(pdfURL: URL) -> ParseResult {
        guard let doc = PDFDocument(url: pdfURL) else {
            return ParseResult(transactions: [], errors: ["Не открыл PDF"])
        }

        var text = ""
        for i in 0..<doc.pageCount {
            if let page = doc.page(at: i), let s = page.string {
                text += "\n" + s
            }
        }

        text = normalize(text)

        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ParseResult(transactions: [], errors: ["PDF без текста (похоже на скан)"])
        }

        // Kaspi может иметь разные заголовки таблицы в зависимости от типа/периода выписки
        let tableMarkers = [
            "Date Amount Transaction Details",
            "Дата Сумма Транзакция Детали",
            "Дата Сумма Тип транзакции Детали",
            "Date Amount Type Details",
            "Date Amount Transaction type Details",
            "Күні Сомасы Транзакция Мәліметтер",   // казахский
        ]

        var tableText: String? = nil
        for marker in tableMarkers {
            if let range = text.range(of: marker, options: .caseInsensitive) {
                tableText = String(text[range.upperBound...])
                break
            }
        }

        // Если заголовок не найден — пробуем найти первую транзакцию напрямую
        // (годовые выписки иногда не имеют чёткого заголовка)
        if tableText == nil {
            if let firstTxRange = findFirstTransactionRange(in: text) {
                tableText = String(text[firstTxRange...])
            }
        }

        guard let body = tableText else {
            return ParseResult(transactions: [], errors: ["Не нашёл таблицу транзакций. Возможно, нестандартный формат выписки."])
        }

        let txs = extractTransactions(from: body)

        if txs.isEmpty {
            return ParseResult(transactions: [],
                               errors: ["Транзакции не найдены. Проверь формат выписки."])
        }

        return ParseResult(transactions: txs, errors: [])
    }

    // MARK: - Find first transaction when header is missing

    /// Ищет позицию первой строки вида "01.01.24 + 1 000,00 ₸ ..."
    private func findFirstTransactionRange(in text: String) -> String.Index? {
        let pattern = #"\d{2}\.\d{2}\.\d{2,4}\s*[+\-]\s*[\d\s]+,\d{2}\s*₸"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return nil }
        return range.lowerBound
    }

    // MARK: - Core extraction

    private func extractTransactions(from text: String) -> [Transaction] {
        let safeText = text + " "

        // Поддерживаем даты формата dd.MM.yy И dd.MM.yyyy (годовая выписка может использовать 4-значный год)
        let pattern =
            #"(\d{2}\.\d{2}\.\d{2,4})\s*([+\-])\s*([\d\s]+,\d{2})\s*₸\s*([A-Za-zА-Яа-яЁёҚқҮүҰұҒғҺһӘәІі]+)\s+(.+?)(?=\d{2}\.\d{2}\.\d{2,4}\s*[+\-]\s*[\d\s]+,\d{2}\s*₸|$)"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }

        let ns = safeText as NSString
        let matches = regex.matches(in: safeText, range: NSRange(location: 0, length: ns.length))

        var results: [Transaction] = []

        for m in matches {
            let dateStr   = ns.substring(with: m.range(at: 1))
            let signStr   = ns.substring(with: m.range(at: 2))
            let amountStr = ns.substring(with: m.range(at: 3))
            let typeStr   = ns.substring(with: m.range(at: 4))
            var details   = ns.substring(with: m.range(at: 5))

            details = sanitizeDetails(details)

            // Поддержка и dd.MM.yy и dd.MM.yyyy
            guard let date = parseDate(dateStr),
                  let absAmount = parseMoney(amountStr) else { continue }

            let sign: Double = (signStr == "+") ? 1 : -1
            let amount = sign * absAmount

            let fullTitle = "\(typeStr) \(details)".trimmingCharacters(in: .whitespacesAndNewlines)

            // Детерминированный id = дата + сумма + merchant (защита от дублей внутри одного PDF)
            let txId = "\(dateStr)_\(amountStr.filter { !$0.isWhitespace })_\(fullTitle.prefix(30))"
                .replacingOccurrences(of: " ", with: "_")

            results.append(Transaction(
                id: txId,
                date: date,
                amount: amount,
                merchant: fullTitle,
                details: fullTitle,
                category: Categorizer.categorize(merchant: fullTitle, details: fullTitle)
            ))
        }

        // Убираем дубли внутри одного PDF (одинаковый id)
        var seen = Set<String>()
        results = results.filter { seen.insert($0.id).inserted }

        results.sort { $0.date > $1.date }
        return results
    }

    // MARK: - Cleaning

    private let typeWords: Set<String> = [
        "purchases", "transfers", "replenishment", "withdrawals", "others",
        "salary", "deposit", "from", "to"
    ]

    private func sanitizeDetails(_ details: String) -> String {
        let collapsed = details
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if collapsed.isEmpty { return "" }

        let tokens = collapsed.split(separator: " ").map { String($0) }
        var idx = 0
        while idx < tokens.count {
            if typeWords.contains(tokens[idx].lowercased()) { idx += 1 } else { break }
        }

        let cleaned = tokens[idx...].joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? collapsed : cleaned
    }

    // MARK: - Helpers

    /// Поддержка dd.MM.yy и dd.MM.yyyy
    private func parseDate(_ s: String) -> Date? {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ru_RU")
        df.timeZone = .current

        // Определяем формат по длине года
        let parts = s.split(separator: ".")
        if parts.count == 3, let yearPart = parts.last {
            df.dateFormat = yearPart.count == 4 ? "dd.MM.yyyy" : "dd.MM.yy"
        } else {
            df.dateFormat = "dd.MM.yy"
        }
        return df.date(from: s)
    }

    private func parseMoney(_ s: String) -> Double? {
        let cleaned = s
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return Double(cleaned)
    }

    private func normalize(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
    }
}
