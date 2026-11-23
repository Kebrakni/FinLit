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
            case .unsupportedSource: return L10n.text("Эта выписка не поддерживается")
            case .englishRequired: return L10n.text("Нужна выписка на английском")
            }
        }

        var message: String {
            switch self {
            case .unsupportedSource:
                return L10n.text("Документ не соответствует поддерживаемому шаблону. Нужна оригинальная английская PDF-выписка по карте в тенге с заголовком Balance statement и колонками Date, Amount, Transaction, Details. В банковском приложении откройте «Мой Банк» → карту → «Выписка», выберите English и сохраните PDF в «Файлы». Другие шаблоны пока не поддерживаются.")
            case .englishRequired:
                return L10n.text("Выберите English / Английский при формировании выписки по карте и сохраните оригинальный PDF. В таблице должны быть колонки Date, Amount, Transaction и Details.")
            }
        }
    }

    func parse(pdfURL: URL) -> ParseResult {
        guard let doc = PDFDocument(url: pdfURL) else {
            return ParseResult(transactions: [], errors: [L10n.text("Не открыл PDF")])
        }
        guard !doc.isLocked else { return ParseResult(transactions: [], errors: [L10n.text("PDF защищён паролем. Экспортируйте выписку без пароля.")]) }

        guard let firstPage = doc.page(at: 0)?.string, !firstPage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ParseResult(transactions: [], errors: [L10n.text("Не удалось прочитать PDF. Нужен оригинальный файл с текстом, а не скан или фотография.")])
        }
        if let issue = Self.sourceIssue(in: firstPage) {
            return ParseResult(transactions: [], errors: [issue.message], issue: issue)
        }

        let pages = (0..<doc.pageCount).compactMap { index -> String? in
            guard let page = doc.page(at: index), let raw = page.string, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let visual = visualRows(on: page)
            let rawStarts = raw.components(separatedBy: .newlines).filter(isTransactionStart).count
            let visualStarts = visual.components(separatedBy: .newlines).filter(isTransactionStart).count
            return visualStarts > 0 && visualStarts >= rawStarts ? visual : raw
        }
        guard pages.count == doc.pageCount else {
            return ParseResult(transactions: [], errors: [L10n.text("Не удалось прочитать текст всех страниц. Нужен PDF с текстом, а не скан или фотография.")])
        }
        return parseExtractedPages(pages, summaryText: firstPage, requireSummary: true)
    }

    /// Identify the issuer from the document header/footer, never from a
    /// payment recipient, a filename or an isolated mention of the bank.
    static func sourceIssue(in firstPage: String) -> StatementImportIssue? {
        let text = firstPage.replacingOccurrences(of: "\u{00A0}", with: " ")
        let issuer = #"(?im)^\s*(?:(?:JSC|АО|АҚ)\s*[«“\"]?)?Kaspi\s+Bank[»”\"]?\s*[,\s]+(?:BIC|БИК)\s*:?\s*CASPKZKA\b"#
        let hasIssuer = text.range(of: issuer, options: .regularExpression) != nil
        let hasProduct = String(text.prefix(1800)).range(of: #"(?i)\bkaspi\s+gold\b"#, options: .regularExpression) != nil
        guard hasIssuer && hasProduct else { return .unsupportedSource }
        let table = text.range(of: #"(?i)\bDate\s+Amount\s+Transaction\s+Details\b"#, options: .regularExpression)
        let header = table.map { String(text[..<$0.lowerBound]) } ?? text
        if let currency = header.range(of: #"(?i)\bCurrency\s*:\s*([A-Z]{3})\b"#, options: .regularExpression) {
            let declaration = String(header[currency]).uppercased()
            guard declaration.hasSuffix("KZT") else { return .unsupportedSource }
        }
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

    func parseExtractedPages(_ pages: [String], summaryText: String? = nil, requireSummary: Bool = false) -> ParseResult {
        var all: [Transaction] = []
        var errors: [String] = []
        for (index, raw) in pages.enumerated() {
            guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                errors.append(L10n.text("Страница {0}: не удалось сопоставить даты, суммы и описания. Импорт остановлен.", String(index + 1)))
                continue
            }

            let cleaned = normalizePage(stripKaspiPageArtifacts(from: raw))

            // Count all dated rows, including malformed amounts/types. Never let
            // the valid-row regex silently hide a row it cannot understand.
            let datedLines = matches(of: #"(?m)^\d{2}\.\d{2}\.\d{2,4}(?=\s|$)"#, in: cleaned).count
            let rowStarts = cleaned.components(separatedBy: .newlines).filter(isTransactionStart).count
            let pageTransactions: [Transaction]
            if rowStarts > 0 {
                pageTransactions = extractRowWise(from: cleaned)
                if pageTransactions.count != datedLines {
                    errors.append(L10n.text("Страница {0}: часть строк не прочитана. Импорт остановлен, чтобы не потерять операции.", String(index + 1)))
                }
            } else {
                pageTransactions = extractColumnWise(from: cleaned)
                if !cleaned.isEmpty && pageTransactions.isEmpty {
                    errors.append(L10n.text("Страница {0}: не удалось сопоставить даты, суммы и описания. Импорт остановлен.", String(index + 1)))
                }
            }
            all.append(contentsOf: pageTransactions)
        }
        guard errors.isEmpty else { return ParseResult(transactions: [], errors: errors) }
        if let error = validateSummary(summaryText ?? pages.first ?? "", transactions: all, required: requireSummary) {
            return ParseResult(transactions: [], errors: [error])
        }

        if all.isEmpty {
            return ParseResult(transactions: [], errors: [L10n.text("Транзакции не найдены. Проверь формат выписки.")])
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
        // PDF extraction may place the original currency on a separate line
        // before or after the merchant. It still belongs to the amount cell.
        let currencyLines = lines.filter(isCurrencyContinuationLine)
        guard currencyLines.count <= 1 else { return nil }
        let line = lines.filter { !isCurrencyContinuationLine($0) }.joined(separator: " ")
        // The account debit is always KZT. Keep an optional original-currency
        // annotation as source text, never replace the account amount with it.
        let foreignAmount = #"(?:\s*(\(\s*[+\-−]?\s*\d[\d\s.,]*\s*(?:[A-Z]{3}|CN¥|US\$|[¥$€£₽元])\s*\)))?"#
        let pattern = #"^(\d{2}\.\d{2}\.\d{2,4})\s*([+\-−]\s*[\d ]+,\d{2}\s*₸)"#
            + foreignAmount
            + #"\s+(Purchases|Transfers|Replenishment|Withdrawals|Others)\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }

        let ns = line as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard let m = regex.firstMatch(in: line, options: [], range: full) else { return nil }

        let dateStr = ns.substring(with: m.range(at: 1))
        let amountRaw = ns.substring(with: m.range(at: 2))
        let type = ns.substring(with: m.range(at: 4)).trimmingCharacters(in: .whitespacesAndNewlines)
        var detail = ns.substring(with: m.range(at: 5)).trimmingCharacters(in: .whitespacesAndNewlines)
        var notes = currencyLines
        if m.range(at: 3).location != NSNotFound {
            guard notes.isEmpty else { return nil }
            notes.append(ns.substring(with: m.range(at: 3)))
        }
        let exchangeDifference = "foreign exchange difference"
        if detail.lowercased().hasSuffix(exchangeDifference) {
            detail = String(detail.dropLast(exchangeDifference.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            notes.append("Foreign exchange difference")
        }

        return buildTransaction(
            dateStr: dateStr,
            amountRaw: amountRaw,
            type: type,
            detail: detail,
            note: notes.isEmpty ? nil : notes.joined(separator: " ")
        )
    }

    private func isTransactionStart(_ line: String) -> Bool {
        line.range(of: #"^\d{2}\.\d{2}\.\d{2,4}\s+\S"#, options: .regularExpression) != nil
    }

    private func isTransactionContinuation(_ line: String) -> Bool {
        // Names may contain any script, numbers, punctuation or emoji.
        !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func isTableFooter(_ line: String) -> Bool {
        line.range(of: #"(?i)^(?:total|итого|всего|обороты|остаток)\s*:?\s*(?:[+\-−]?\s*[\d ]+[,\.]\d{2}\s*(?:₸|KZT))?$"#, options: .regularExpression) != nil
    }

    // MARK: - Column-wise fallback

    private func extractColumnWise(from text: String) -> [Transaction] {
        // Only whole cells can be removed from the description column. A global
        // regex replacement would corrupt names containing dates or "Transfers".
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !isGarbageLine($0) }
        var dates: [String] = [], amounts: [String] = [], types: [String] = [], details: [String] = []
        var notes: [Int: String] = [:]
        var previousWasAmount = false
        for line in lines {
            if line.range(of: #"^\d{2}\.\d{2}\.\d{2,4}$"#, options: .regularExpression) != nil {
                dates.append(line)
            } else if line.range(of: #"^[+\-−]\s*[\d ]+,\d{2}\s*₸$"#, options: .regularExpression) != nil {
                amounts.append(line); previousWasAmount = true; continue
            } else if isCurrencyContinuationLine(line) {
                guard previousWasAmount, !amounts.isEmpty, notes[amounts.count - 1] == nil else { return [] }
                notes[amounts.count - 1] = line
            } else if line.range(of: #"(?i)^(?:Purchases|Transfers|Replenishment|Withdrawals|Others)$"#, options: .regularExpression) != nil {
                types.append(line)
            } else {
                details.append(line)
            }
            previousWasAmount = false
        }
        guard !dates.isEmpty, dates.count == amounts.count, dates.count == types.count, dates.count == details.count else { return [] }
        var result: [Transaction] = []
        for idx in dates.indices {
            guard let tx = buildTransaction(dateStr: dates[idx], amountRaw: amounts[idx], type: types[idx], detail: details[idx], note: notes[idx]) else { return [] }
            result.append(tx)
        }
        return result
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

        let accountAmount = amountRaw.replacingOccurrences(of: "−", with: "-")
        let sign: Double = accountAmount.trimmingCharacters(in: .whitespaces).hasPrefix("-") ? -1 : 1
        let amountDigits = accountAmount
            .replacingOccurrences(of: "+", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "₸", with: "")

        guard let absAmount = parseMoney(amountDigits), absAmount.isFinite, absAmount > 0,
              absAmount <= Transaction.maximumAmount else { return nil }
        let amount = sign * absAmount

        guard !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let safeDetail = detail
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
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.replacingOccurrences(of: "  +", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
    }

    private func isGarbageLine(_ line: String) -> Bool {
        if isTransactionStart(line) { return false }
        // Match document metadata, not words somewhere inside a merchant name.
        let patterns = [
            #"(?i)^(?:Date\s+Amount(?:\s+Transaction\s+Details)?|Transaction\s+Details)$"#,
            #"(?i)^Page\s+\d+(?:\s*(?:of|/)\s*\d+)?$"#,
            #"(?i)^(?:Kaspi Gold|balance statement(?: for the period from .*)?|account number\s*:\s*[A-Z0-9 ]+|card number\s*:\s*[\d* ]+|transaction summary\s*:\s*(?:cash withdrawal limits with no commission:)?|cash withdrawal limits with no commission:|card balance\s+\d{2}\.\d{2}\.\d{2,4}.*|currency\s*:\s*[A-Z]{3})$"#,
        ]
        return patterns.contains { line.range(of: $0, options: .regularExpression) != nil }
    }

    private func isCurrencyContinuationLine(_ line: String) -> Bool {
        line.range(of: #"^\(\s*[-+−]?\s*\d[\d\s.,]*\s*(?:[A-Z]{3}|CN¥|US\$|[¥$€£₽元])\s*\)$"#, options: [.regularExpression, .caseInsensitive]) != nil
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
        let cleaned = s.trimmingCharacters(in: .whitespacesAndNewlines)
        // The supported document uses a decimal comma and groups of three.
        // Reject malformed grouping rather than turning "1 2,00" into 12.
        guard cleaned.range(of: #"^(?:\d+|\d{1,3}(?: \d{3})+),\d{2}$"#, options: .regularExpression) != nil,
              let decimal = Decimal(string: cleaned.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        return NSDecimalNumber(decimal: decimal).doubleValue
    }

    /// Reconcile the statement's bank transaction types, independently of any
    /// spending categories. Decimal sums keep this check exact to the cent.
    private func validateSummary(_ raw: String, transactions: [Transaction], required: Bool) -> String? {
        let text = normalizePage(raw)
        guard let start = text.range(of: "Transaction summary:", options: .caseInsensitive) else {
            return required ? L10n.text("Не удалось прочитать контрольные итоги выписки. Импорт остановлен: сохраните оригинальный PDF заново.") : nil
        }
        let tail = String(text[start.upperBound...])
        let table = tail.range(of: #"(?i)\bDate\s+Amount\s+Transaction\s+Details\b"#, options: .regularExpression)
        let header = table.map { String(tail[..<$0.lowerBound]) } ?? tail
        let expectedTypes = ["replenishment", "transfers", "purchases", "withdrawals", "others"]
        var totals: [String: Decimal] = [:]
        let pattern = #"(?im)^(Replenishment|Transfers|Purchases|Withdrawals|Others)\s*([+\-−]?\s*[\d ]+,\d{2}\s*₸)"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let source = header as NSString
        for match in regex.matches(in: header, range: NSRange(location: 0, length: source.length)) {
            let type = source.substring(with: match.range(at: 1)).lowercased()
            guard totals[type] == nil, let value = summaryAmount(source.substring(with: match.range(at: 2))) else {
                return L10n.text("Не удалось прочитать контрольные итоги выписки. Импорт остановлен: сохраните оригинальный PDF заново.")
            }
            totals[type] = value
        }
        guard expectedTypes.allSatisfy({ totals[$0] != nil }) else {
            return L10n.text("Не удалось прочитать контрольные итоги выписки. Импорт остановлен: сохраните оригинальный PDF заново.")
        }
        var actual = Dictionary(uniqueKeysWithValues: expectedTypes.map { ($0, Decimal.zero) })
        for transaction in transactions {
            let type = transaction.details.components(separatedBy: .whitespaces).first?.lowercased() ?? ""
            guard let current = actual[type], let amount = Decimal(string: String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), transaction.amount)) else {
                return L10n.text("Итоги выписки не совпали с прочитанными операциями. Импорт остановлен: проверьте файл выписки.")
            }
            actual[type] = current + amount
        }
        guard expectedTypes.allSatisfy({ totals[$0] == actual[$0] }) else {
            return L10n.text("Итоги выписки не совпали с прочитанными операциями. Импорт остановлен: проверьте файл выписки.")
        }
        let balanceRegex = try! NSRegularExpression(pattern: #"(?im)^Card balance\s+(\d{2}\.\d{2}\.\d{2,4})\s*:?\s*([+\-−]?\s*[\d ]+,\d{2}\s*₸)"#)
        let balances = balanceRegex.matches(in: header, range: NSRange(location: 0, length: source.length))
        if required || !balances.isEmpty {
            guard balances.count == 2,
                  let opening = summaryAmount(source.substring(with: balances[0].range(at: 2))),
                  let closing = summaryAmount(source.substring(with: balances[1].range(at: 2))),
                  let from = parseDate(source.substring(with: balances[0].range(at: 1))),
                  let through = parseDate(source.substring(with: balances[1].range(at: 1))), from <= through else {
                return L10n.text("Не удалось прочитать контрольные итоги выписки. Импорт остановлен: сохраните оригинальный PDF заново.")
            }
            let net = actual.values.reduce(Decimal.zero, +)
            guard opening + net == closing, transactions.allSatisfy({ $0.date >= from && $0.date <= through }) else {
                return L10n.text("Итоги выписки не совпали с прочитанными операциями. Импорт остановлен: проверьте файл выписки.")
            }
        }
        return nil
    }

    private func summaryAmount(_ text: String) -> Decimal? {
        var money = text.replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: "₸", with: "").trimmingCharacters(in: .whitespaces)
        let negative = money.hasPrefix("-")
        if money.hasPrefix("-") || money.hasPrefix("+") { money.removeFirst() }
        money = money.trimmingCharacters(in: .whitespaces)
        guard parseMoney(money) != nil else { return nil }
        return Decimal(string: (negative ? "-" : "") + money.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX"))
    }

    private func makeStableID(dateStr: String, amount: Double, type: String, detail: String) -> String {
        [dateStr, String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), amount), normalizeKey(type), normalizeKey(detail)].joined(separator: "_")
    }

    private func normalizeKey(_ s: String) -> String {
        // Removing punctuation or non-Latin characters collapses distinct
        // merchants (AB/A:B, A B/A_B, emoji, Chinese names) into the same ID.
        s.precomposedStringWithCanonicalMapping.lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isoDay(_ d: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = .current
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: d)
    }
}

