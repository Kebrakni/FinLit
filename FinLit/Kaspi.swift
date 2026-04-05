// Kaspi.swift
// Исправлен парсер: теперь корректно читает месячные и годовые выписки (многостраничные PDF)

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

        // ИСПРАВЛЕНИЕ 1: Собираем текст постранично с явным разделителем
        // Раньше \n заменялись пробелами — из-за этого транзакции с разных строк
        // склеивались и regex не мог их разобрать
        var pages: [String] = []
        for i in 0..<doc.pageCount {
            if let page = doc.page(at: i), let s = page.string {
                pages.append(s)
            }
        }

        if pages.isEmpty {
            return ParseResult(transactions: [], errors: ["PDF без текста (похоже на скан)"])
        }

        // Нормализуем каждую страницу отдельно (убираем только лишние пробелы,
        // но НЕ трогаем переносы строк — они нужны для парсинга)
        let fullText = pages
            .map { normalizePage($0) }
            .joined(separator: "\n")

        // Ищем начало таблицы транзакций
        let tableMarkers = [
            "Date Amount Transaction Details",
            "Дата Сумма Транзакция Детали",
            "Дата Сумма Тип транзакции Детали",
            "Date Amount Type Details",
            "Date Amount Transaction type Details",
            "Күні Сомасы Транзакция Мәліметтер",
        ]

        var tableText: String? = nil
        for marker in tableMarkers {
            if let range = fullText.range(of: marker, options: .caseInsensitive) {
                tableText = String(fullText[range.upperBound...])
                break
            }
        }

        // Если заголовок не найден — ищем первую транзакцию напрямую
        if tableText == nil {
            if let firstTxRange = findFirstTransactionRange(in: fullText) {
                tableText = String(fullText[firstTxRange...])
            }
        }

        guard let body = tableText else {
            return ParseResult(
                transactions: [],
                errors: ["Не нашёл таблицу транзакций. Возможно, нестандартный формат выписки."]
            )
        }

        let txs = extractTransactions(from: body)

        if txs.isEmpty {
            return ParseResult(
                transactions: [],
                errors: ["Транзакции не найдены. Проверь формат выписки."]
            )
        }

        return ParseResult(transactions: txs, errors: [])
    }

    // MARK: - Find first transaction when header is missing

    private func findFirstTransactionRange(in text: String) -> String.Index? {
        let pattern = #"\d{2}\.\d{2}\.\d{2,4}\s*[+\-]\s*[\d\s]+,\d{2}\s*₸"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return nil }
        return range.lowerBound
    }

    // MARK: - Core extraction

    private func extractTransactions(from text: String) -> [Transaction] {
        // ИСПРАВЛЕНИЕ 2: Новая стратегия — ищем строки-заголовки транзакций
        // Формат Kaspi: дата стоит в начале строки, потом знак и сумма
        // Многостраничный PDF: между транзакциями могут быть переносы страниц,
        // повторяющиеся заголовки таблицы, номера страниц — всё это фильтруем

        // Шаг 1: разбиваем текст на строки
        let lines = text.components(separatedBy: "\n")

        // Шаг 2: "склеиваем" строки обратно в плоский текст с сохранением структуры
        // но убирая мусорные строки (пустые, заголовки таблиц, номера страниц)
        let cleaned = cleanLines(lines)

        // Шаг 3: применяем основной regex
        // Паттерн: дата [+/-] сумма ₸ ТИП детали
        // Используем lookahead на следующую транзакцию как разделитель
        let datePattern = #"\d{2}\.\d{2}\.\d{2,4}"#
        let amountPattern = #"[+\-]\s*[\d\s]+,\d{2}\s*₸"#
        let txStartPattern = "(\(datePattern))\\s*(\(amountPattern))"

        guard let startRegex = try? NSRegularExpression(pattern: txStartPattern) else { return [] }

        let ns = cleaned as NSString
        let matches = startRegex.matches(in: cleaned, range: NSRange(location: 0, length: ns.length))

        var results: [Transaction] = []

        for (i, match) in matches.enumerated() {
            let matchStart = match.range.location
            let matchEnd   = match.range.location + match.range.length

            // Получаем "хвост" до следующей транзакции или конец текста
            let nextStart = i + 1 < matches.count ? matches[i + 1].range.location : ns.length
            let tailRange = NSRange(location: matchEnd, length: nextStart - matchEnd)
            let tail = ns.substring(with: tailRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // Дата
            let dateStr = ns.substring(with: match.range(at: 1))
            guard let date = parseDate(dateStr) else { continue }

            // Знак и сумма
            let amountRaw = ns.substring(with: match.range(at: 2))
            let sign: Double = amountRaw.hasPrefix("-") ? -1 : 1
            let amountDigits = amountRaw
                .replacingOccurrences(of: "+", with: "")
                .replacingOccurrences(of: "-", with: "")
                .replacingOccurrences(of: "₸", with: "")
            guard let absAmount = parseMoney(amountDigits) else { continue }
            let amount = sign * absAmount

            // Тип транзакции + детали из хвоста
            let merchantAndDetails = sanitizeTail(tail)

            // Детерминированный id
            let txId = "\(dateStr)_\(Int(absAmount))_\(merchantAndDetails.prefix(30))"
                .replacingOccurrences(of: " ", with: "_")

            results.append(Transaction(
                id: txId,
                date: date,
                amount: amount,
                merchant: merchantAndDetails,
                details: merchantAndDetails,
                category: Categorizer.categorize(merchant: merchantAndDetails, details: merchantAndDetails)
            ))
        }

        // Дедупликация по id
        var seen = Set<String>()
        results = results.filter { seen.insert($0.id).inserted }
        results.sort { $0.date > $1.date }
        return results
    }

    // MARK: - Line cleaning

    // Убирает мусорные строки: заголовки таблиц, номера страниц, пустые строки
    private func cleanLines(_ lines: [String]) -> String {
        let headerKeywords = [
            "date amount", "дата сумма", "transaction details",
            "транзакция детали", "тип транзакции", "page ", "страниц",
            "күні сомасы", "выписка по", "account statement",
            "kaspi bank", "каспи банк", "period:", "период:",
            "opening balance", "closing balance", "начальный остаток", "конечный остаток"
        ]

        var cleaned: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let lower = trimmed.lowercased()
            let isHeader = headerKeywords.contains { lower.contains($0) }
            // Строка из одного числа — номер страницы
            let isPageNumber = trimmed.range(of: #"^\d{1,4}$"#, options: .regularExpression) != nil

            if !isHeader && !isPageNumber {
                cleaned.append(trimmed)
            }
        }

        // Возвращаем как единую строку — транзакции на одной строке или через пробел
        return cleaned.joined(separator: " ")
    }

    // MARK: - Tail sanitization

    private let typeWords: Set<String> = [
        "purchases", "transfers", "replenishment", "withdrawals", "others",
        "salary", "deposit", "from", "to"
    ]

    private func sanitizeTail(_ tail: String) -> String {
        let collapsed = tail
            .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !collapsed.isEmpty else { return "—" }

        // Убираем ведущие технические слова (Purchases, Transfers и т.п.)
        let tokens = collapsed.split(separator: " ").map { String($0) }
        var idx = 0
        while idx < tokens.count && typeWords.contains(tokens[idx].lowercased()) {
            idx += 1
        }

        let result = tokens[idx...].joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? collapsed : result
    }

    // MARK: - Helpers

    private func parseDate(_ s: String) -> Date? {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ru_RU")
        df.timeZone = .current
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
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(cleaned)
    }

    // ИСПРАВЛЕНИЕ 3: normalizePage НЕ убивает переносы строк
    // Только убирает неразрывные пробелы и лишние пробелы внутри строки
    private func normalizePage(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            // Убираем множественные пробелы внутри строки, но не трогаем \n
            .components(separatedBy: "\n")
            .map { line in
                line.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
            }
            .joined(separator: "\n")
    }
}
