import Foundation
import PDFKit
import CryptoKit

nonisolated final class KaspiPDFParser {

    struct ParseResult {
        let transactions: [Transaction]
        let errors: [String]
        var issue: StatementImportIssue? = nil
    }

    enum StatementImportIssue: Equatable {
        case unsupportedSource, englishRequired

        var title: String {
            switch self {
            case .unsupportedSource: return "Эта выписка не поддерживается"
            case .englishRequired: return "Нужна выписка на английском"
            }
        }

        var message: String {
            switch self {
            case .unsupportedSource:
                return "Сейчас Tengely поддерживает только оригинальную PDF-выписку по карте Kaspi Gold на английском языке. Выписки других банков пока не поддерживаются. Откройте карту → «Выписка», выберите English и сохраните PDF в «Файлы»."
            case .englishRequired:
                return "Выберите English / Английский при формировании выписки по карте и сохраните оригинальный PDF. В таблице должны быть колонки Date, Amount, Transaction и Details."
            }
        }
    }

    func parse(pdfURL: URL) -> ParseResult {
        guard let doc = PDFDocument(url: pdfURL) else {
            return ParseResult(transactions: [], errors: ["Не открыл PDF"])
        }
        guard !doc.isLocked else { return ParseResult(transactions: [], errors: ["PDF защищён паролем. Экспортируйте выписку без пароля."]) }

        guard let firstPage = doc.page(at: 0)?.string, !firstPage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ParseResult(transactions: [], errors: ["Не удалось прочитать PDF. Нужен оригинальный файл с текстом, а не скан или фотография."])
        }
        if let issue = Self.sourceIssue(in: firstPage) {
            return ParseResult(transactions: [], errors: [issue.message], issue: issue)
        }

        let pages = (0..<doc.pageCount).compactMap { index -> String? in
            guard let page = doc.page(at: index), let raw = page.string else { return nil }
            let visual = visualRows(on: page)
            let rawStarts = raw.components(separatedBy: .newlines).filter(isTransactionStart).count
            let visualStarts = visual.components(separatedBy: .newlines).filter(isTransactionStart).count
            return visualStarts > rawStarts ? visual : raw
        }
        guard pages.count == doc.pageCount else {
            return ParseResult(transactions: [], errors: ["Не удалось прочитать текст всех страниц. Нужен PDF с текстом, а не скан или фотография."])
        }
        return parseExtractedPages(pages)
    }

    /// Identify the issuer from the document header/footer, never from a
    /// payment recipient, a filename or an isolated mention of the bank.
    static func sourceIssue(in firstPage: String) -> StatementImportIssue? {
        let text = firstPage.replacingOccurrences(of: "\u{00A0}", with: " ")
        let issuer = #"(?im)^\s*(?:(?:JSC|АО|АҚ)\s*[«“\"]?)?Kaspi\s+Bank[»”\"]?\s*[,\s]+(?:BIC|БИК)\s*:?\s*CASPKZKA\b"#
        let hasIssuer = text.range(of: issuer, options: .regularExpression) != nil
        let hasProduct = String(text.prefix(1800)).range(of: #"(?i)\bkaspi\s+gold\b"#, options: .regularExpression) != nil
        guard hasIssuer && hasProduct else { return .unsupportedSource }
        let hasEnglishTable = ["date", "amount", "transaction", "details"].allSatisfy { word in
            text.range(of: "(?i)\\b" + word + "\\b", options: .regularExpression) != nil
        }
        return hasEnglishTable ? nil : .englishRequired
    }

    /// Some Kaspi PDFs expose an entire date/amount/type column as one string.
    /// Reconstruct visual rows by PDF coordinates rather than guessing which
    /// of several description lines belongs to which amount.
    private func visualRows(on page: PDFPage) -> String {
        let selections = page.selection(for: page.bounds(for: .mediaBox))?.selectionsByLine() ?? []
        let fragments: [(text: String, bounds: CGRect)] = selections.compactMap { selection in
            guard let text = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            return (text, selection.bounds(for: page))
        }.sorted { $0.bounds.midY > $1.bounds.midY }
        var groups: [[(text: String, bounds: CGRect)]] = []
        for fragment in fragments {
            if let last = groups.last, let anchor = last.first, abs(anchor.bounds.midY - fragment.bounds.midY) < 3 {
                groups[groups.count - 1].append(fragment)
            } else { groups.append([fragment]) }
        }
        return groups.map { group in
            group.sorted { $0.bounds.minX < $1.bounds.minX }.map(\.text).joined(separator: " ")
        }.joined(separator: "\n")
    }

    func parseExtractedPages(_ pages: [String]) -> ParseResult {
        var all: [Transaction] = []
        var errors: [String] = []
        for (index, raw) in pages.enumerated() {
            guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            let cleaned = normalizePage(stripKaspiPageArtifacts(from: raw))

            // 1) Сначала пробуем обычный построчный парсинг
            let rowTx = extractRowWise(from: cleaned)
            if !rowTx.isEmpty {
                let expected = matches(of: #"(?m)^\d{2}\.\d{2}\.\d{2,4}\s*[+\-]\s*[\d\s]+,\d{2}\s*₸"#, in: cleaned).count
                if rowTx.count < expected { errors.append("Страница \(index + 1): часть строк не прочитана. Импорт остановлен, чтобы не потерять операции.") }
                all.append(contentsOf: rowTx)
                continue
            }

            // 2) Если PDFKit отдал таблицу по колонкам — пробуем column-wise fallback
            let columnTx = extractColumnWise(from: cleaned)
            if columnTx.isEmpty, cleaned.range(of: #"(?i)\b(purchases|transfers|replenishment|withdrawals|others)\b"#, options: .regularExpression) != nil,
               cleaned.range(of: #"[+\-]\s*[\d\s]+,\d{2}\s*₸"#, options: .regularExpression) != nil {
                errors.append("Страница \(index + 1): не удалось сопоставить даты, суммы и описания. Импорт остановлен.")
            }
            all.append(contentsOf: columnTx)
        }

        if all.isEmpty {
            return ParseResult(transactions: [], errors: ["Транзакции не найдены. Проверь формат выписки."])
        }

        // Equal amounts at the same merchant on the same day can be separate
        // real payments. Preserve their multiplicity with stable occurrence IDs.
        var occurrences: [String: Int] = [:]
        var identified: [Transaction] = []
        for tx in all {
            let ordinal = occurrences[tx.id, default: 0] + 1
            occurrences[tx.id] = ordinal
            let bytes = SHA256.hash(data: Data(tx.id.utf8))
            let digest = bytes.map { String(format: "%02x", $0) }.joined()
            let transaction = Transaction(id: "\(digest)-\(ordinal)", date: tx.date, amount: tx.amount,
                                          merchant: tx.merchant, details: tx.details, category: tx.category)
            identified.append(transaction)
        }
        identified.sort { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
        return ParseResult(transactions: identified, errors: errors)
    }

    // MARK: - Row-wise

    private func extractRowWise(from text: String) -> [Transaction] {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { !isGarbageLine($0) }

        var result: [Transaction] = []
        var currentBlock: [String] = []

        func finishCurrentBlock() {
            guard !currentBlock.isEmpty else { return }
            if let transaction = parseTransactionBlock(currentBlock) {
                result.append(transaction)
            }
            currentBlock.removeAll(keepingCapacity: true)
        }

        for line in lines {
            if isTransactionStart(line) {
                finishCurrentBlock()
                currentBlock = [line]
            } else if isTableFooter(line) {
                finishCurrentBlock()
            } else if !currentBlock.isEmpty, isTransactionContinuation(line) {
                currentBlock.append(line)
            }
        }
        finishCurrentBlock()

        return result
    }

    private func parseTransactionBlock(_ lines: [String]) -> Transaction? {
        let line = lines.joined(separator: " ")
        let foreignAmount = #"(?:\s*\(\s*[+\-]\s*[\d\s]+,\d{2}\s*[A-Z]{3}\s*\))?"#
        let pattern = #"^(\d{2}\.\d{2}\.\d{2,4})\s*([+\-]\s*[\d\s]+,\d{2}\s*₸)"#
            + foreignAmount
            + #"\s+(Purchases|Transfers|Replenishment|Withdrawals|Others)\s*(.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }

        let ns = line as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard let m = regex.firstMatch(in: line, options: [], range: full) else { return nil }

        let dateStr = ns.substring(with: m.range(at: 1))
        let amountRaw = ns.substring(with: m.range(at: 2))
        let type = ns.substring(with: m.range(at: 3)).trimmingCharacters(in: .whitespacesAndNewlines)
        var detail = ns.substring(with: m.range(at: 4)).trimmingCharacters(in: .whitespacesAndNewlines)
        var note: String?
        let exchangeDifference = "foreign exchange difference"
        if detail.lowercased().hasSuffix(exchangeDifference) {
            detail = String(detail.dropLast(exchangeDifference.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            note = "Foreign exchange difference"
        }

        return buildTransaction(
            dateStr: dateStr,
            amountRaw: amountRaw,
            type: type,
            detail: detail,
            note: note
        )
    }

    private func isTransactionStart(_ line: String) -> Bool {
        line.range(
            of: #"^\d{2}\.\d{2}\.\d{2,4}\s*[+\-]\s*[\d\s]+,\d{2}\s*₸"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private func isTransactionContinuation(_ line: String) -> Bool {
        let lower = line.lowercased()
        let beginsWithType = lower.range(
            of: #"^(purchases|transfers|replenishment|withdrawals|others)\b"#,
            options: .regularExpression
        ) != nil

        return beginsWithType
            || isCurrencyContinuationLine(line)
            || lower == "foreign exchange difference"
            || line.range(of: #"\p{L}"#, options: .regularExpression) != nil
    }

    private func isTableFooter(_ line: String) -> Bool {
        line.range(of: #"(?i)^(?:total|итого|всего|обороты|остаток)\b"#, options: .regularExpression) != nil
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

        let details = splitDetails(detailLines, expectedCount: dates.count)
        guard details.count == dates.count else { return [] }

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

    private func buildTransaction(
        dateStr: String,
        amountRaw: String,
        type: String,
        detail: String,
        note: String? = nil
    ) -> Transaction? {
        guard let date = parseDate(dateStr) else { return nil }

        let sign: Double = amountRaw.trimmingCharacters(in: .whitespaces).hasPrefix("-") ? -1 : 1
        let amountDigits = amountRaw
            .replacingOccurrences(of: "+", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "₸", with: "")

        guard let absAmount = parseMoney(amountDigits), absAmount.isFinite, absAmount > 0,
              absAmount <= Transaction.maximumAmount else { return nil }
        let amount = sign * absAmount

        let safeDetail = detail.isEmpty ? "—" : detail
        let safeType = type.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullDetails = [safeType, safeDetail, note]
            .compactMap { $0 }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let txId = makeStableID(dateStr: dateStr, amount: amount, type: safeType, detail: safeDetail)
        let isPositivePurchase = amount > 0 && safeType.lowercased() == "purchases"

        return Transaction(
            id: txId,
            date: date,
            amount: amount,
            merchant: safeDetail,
            details: fullDetails,
            category: isPositivePurchase
                ? .other
                : Categorizer.categorize(merchant: safeDetail, details: fullDetails)
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
        if isTransactionStart(line) { return false }
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
        df.calendar = Calendar(identifier: .gregorian)
        df.isLenient = false
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

