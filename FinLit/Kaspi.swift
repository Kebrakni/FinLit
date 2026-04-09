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

        var all: [Transaction] = []

        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i),
                  let raw = page.string,
                  !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            let cleaned = normalizePage(stripKaspiPageArtifacts(from: raw))

            // 1) Сначала пробуем обычный построчный парсинг
            let rowTx = extractRowWise(from: cleaned)
            if !rowTx.isEmpty {
                all.append(contentsOf: rowTx)
                continue
            }

            // 2) Если PDFKit отдал таблицу по колонкам — пробуем column-wise fallback
            let columnTx = extractColumnWise(from: cleaned)
            all.append(contentsOf: columnTx)
        }

        if all.isEmpty {
            return ParseResult(transactions: [], errors: ["Транзакции не найдены. Проверь формат выписки."])
        }

        var seen = Set<String>()
        let deduped = all.filter { tx in
            let key = [
                isoDay(tx.date),
                String(format: "%.2f", tx.amount),
                normalizeKey(tx.merchant),
                normalizeKey(tx.details)
            ].joined(separator: "|")
            return seen.insert(key).inserted
        }
        .sorted { $0.date > $1.date }

        return ParseResult(transactions: deduped, errors: [])
    }

    // MARK: - Row-wise

    private func extractRowWise(from text: String) -> [Transaction] {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { !isGarbageLine($0) }

        var result: [Transaction] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]
            if let parsed = parseTransactionRow(line, nextLine: i + 1 < lines.count ? lines[i + 1] : nil) {
                result.append(parsed.transaction)
                i += parsed.linesConsumed
            } else {
                i += 1
            }
        }

        return result
    }

    private func parseTransactionRow(_ line: String, nextLine: String?) -> (transaction: Transaction, linesConsumed: Int)? {
        let pattern = #"^(\d{2}\.\d{2}\.\d{2,4})\s*([+\-]\s*[\d\s]+,\d{2}\s*₸)\s+(Purchases|Transfers|Replenishment|Withdrawals|Others)\s*(.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }

        let ns = line as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard let m = regex.firstMatch(in: line, options: [], range: full) else { return nil }

        let dateStr = ns.substring(with: m.range(at: 1))
        let amountRaw = ns.substring(with: m.range(at: 2))
        let type = ns.substring(with: m.range(at: 3)).trimmingCharacters(in: .whitespacesAndNewlines)
        var detail = ns.substring(with: m.range(at: 4)).trimmingCharacters(in: .whitespacesAndNewlines)

        var consumed = 1
        if let nextLine, isCurrencyContinuationLine(nextLine) {
            consumed = 2
        }

        guard let tx = buildTransaction(dateStr: dateStr, amountRaw: amountRaw, type: type, detail: detail) else { return nil }
        if detail.isEmpty { detail = "—" }
        return (tx, consumed)
    }

    // MARK: - Column-wise fallback

    private func extractColumnWise(from text: String) -> [Transaction] {
        // PDFKit иногда отдаёт таблицу так:
        // [все суммы]\n[все типы]\n[все детали]\n[все даты]
        // или [даты][суммы][типы][детали].
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { !isGarbageLine($0) }
            .filter { !isCurrencyContinuationLine($0) }

        let joined = lines.joined(separator: "\n")

        let dates = matches(of: #"\b\d{2}\.\d{2}\.\d{2,4}\b"#, in: joined)
        let amounts = matches(of: #"[+\-]\s*[\d\s]+,\d{2}\s*₸"#, in: joined)
        let types = matches(of: #"\b(?:Purchases|Transfers|Replenishment|Withdrawals|Others)\b"#, in: joined, options: [.caseInsensitive])

        guard !dates.isEmpty, dates.count == amounts.count, amounts.count == types.count else {
            return []
        }

        // Удаляем из текста даты/суммы/типы, остаток считаем details-блоком.
        var detailsBlob = joined
        for token in (dates + amounts + types) {
            detailsBlob = detailsBlob.replacingOccurrences(of: token, with: " ")
        }

        let detailLines = detailsBlob
            .components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { !isGarbageLine($0) }

        var details = splitDetails(detailLines, expectedCount: dates.count)
        if details.count < dates.count {
            details += Array(repeating: "—", count: dates.count - details.count)
        }
        if details.count > dates.count {
            details = Array(details.prefix(dates.count))
        }

        var result: [Transaction] = []
        for idx in 0..<dates.count {
            if let tx = buildTransaction(dateStr: dates[idx], amountRaw: amounts[idx], type: types[idx], detail: details[idx]) {
                result.append(tx)
            }
        }
        return result
    }

    private func splitDetails(_ detailLines: [String], expectedCount: Int) -> [String] {
        // В лучшем случае PDFKit уже дал по одному detail на строку.
        if detailLines.count == expectedCount {
            return detailLines
        }

        // Частый кейс: одна огромная строка с деталями, разделёнными несколькими пробелами.
        let merged = detailLines.joined(separator: " ")
            .replacingOccurrences(of: "\\s{2,}", with: " | ", options: .regularExpression)
        let pipeParts = merged.split(separator: "|").map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        if pipeParts.count == expectedCount {
            return pipeParts
        }

        // Если деталей меньше, чем операций, оставляем как есть — недостающие дополним "—".
        return detailLines
    }

    // MARK: - Build transaction

    private func buildTransaction(dateStr: String, amountRaw: String, type: String, detail: String) -> Transaction? {
        guard let date = parseDate(dateStr) else { return nil }

        let sign: Double = amountRaw.trimmingCharacters(in: .whitespaces).hasPrefix("-") ? -1 : 1
        let amountDigits = amountRaw
            .replacingOccurrences(of: "+", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "₸", with: "")

        guard let absAmount = parseMoney(amountDigits) else { return nil }
        let amount = sign * absAmount

        let safeDetail = detail.isEmpty ? "—" : detail
        let safeType = type.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullDetails = "\(safeType) \(safeDetail)".trimmingCharacters(in: .whitespacesAndNewlines)
        let txId = makeStableID(dateStr: dateStr, amount: amount, type: safeType, detail: safeDetail)

        return Transaction(
            id: txId,
            date: date,
            amount: amount,
            merchant: safeDetail,
            details: fullDetails,
            category: Categorizer.categorize(merchant: safeDetail, details: fullDetails)
        )
    }

    // MARK: - Cleaning helpers

    private func stripKaspiPageArtifacts(from text: String) -> String {
        let patterns = [
            #"(?im)^\s*JSC «Kaspi Bank», BIC CASPKZKA, www\.kaspi\.kz\s*$"#,
            #"(?im)^\s*JSC \"Kaspi Bank\", BIC CASPKZKA, www\.kaspi\.kz\s*$"#,
            #"(?im)^\s*АО «Kaspi Bank», БИК CASPKZKA, www\.kaspi\.kz\s*$"#,
            #"(?im)^\s*Kaspi Bank, BIC CASPKZKA, www\.kaspi\.kz\s*$"#,
            #"(?im)^\s*www\.kaspi\.kz\s*$"#
        ]

        var cleaned = text
        for pattern in patterns {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return cleaned
    }

    private func normalizePage(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.replacingOccurrences(of: "  +", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
    }

    private func isGarbageLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        let snippets = [
            "date amount", "transaction details", "дата сумма", "күні сомасы",
            "kaspi gold", "balance statement", "account number", "card number",
            "transaction summary", "cash withdrawal limits", "card balance",
            "currency:", "opening balance", "closing balance", "period from",
            "page ", "страниц"
        ]
        if snippets.contains(where: { lower.contains($0) }) { return true }
        if line.range(of: #"^\d{1,4}$"#, options: .regularExpression) != nil { return true }
        return false
    }

    private func isCurrencyContinuationLine(_ line: String) -> Bool {
        line.range(of: #"^\(?\s*[-+]\s*\d+[\d\s]*,\d{2}\s*[A-Z]{3}\s*\)?$"#, options: .regularExpression) != nil
    }

    private func matches(of pattern: String, in text: String, options: NSRegularExpression.Options = []) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

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

    private func makeStableID(dateStr: String, amount: Double, type: String, detail: String) -> String {
        [dateStr, String(format: "%.2f", amount), normalizeKey(type), normalizeKey(detail)].joined(separator: "_")
    }

    private func normalizeKey(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: #"\s+"#, with: "_", options: .regularExpression)
            .replacingOccurrences(of: #"[^a-zа-яё0-9_қғәіңөұүһ\-*./]"#, with: "", options: .regularExpression)
    }

    private func isoDay(_ d: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = .current
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: d)
    }
}

