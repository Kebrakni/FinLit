import Foundation

@main struct StatementParserChecks {
    static func main() {
        let parser = KaspiPDFParser()
        var checks = 0
        func valid(_ pages: [String], count: Int) -> [Transaction] {
            let result = parser.parseExtractedPages(pages)
            precondition(result.errors.isEmpty && result.transactions.count == count, "Unexpected parser refusal: \(result.errors)")
            checks += 1
            return result.transactions
        }
        func refused(_ pages: [String]) {
            let result = parser.parseExtractedPages(pages)
            precondition(!result.errors.isEmpty && result.transactions.isEmpty, "A suspect statement must not return a partial import")
            checks += 1
        }
        let row = "20.09.2026 - 7 200,50 ₸ Purchases Shop"
        for annotation in ["(-100,00 CNY)", "(100.00 CNY)", "(-1,234.56 USD)", "(100 JPY)", "(100,00 ¥)", "(100,00 元)", "(100.00 EUR)"] {
            let text = row.replacingOccurrences(of: "₸ Purchases", with: "₸ \(annotation) Purchases")
            let parsed = valid([text], count: 1)[0]
            precondition(parsed.amount == -7200.5 && parsed.merchant == "Shop" && parsed.details.contains(annotation))
            let wrapped = valid([text.replacingOccurrences(of: " \(annotation) Purchases", with: "\n\(annotation)\nPurchases")], count: 1)[0]
            precondition(wrapped.amount == parsed.amount && wrapped.details == parsed.details && wrapped.id == parsed.id)
            let belowMerchant = valid([row + "\n" + annotation], count: 1)[0]
            precondition(belowMerchant.merchant == "Shop" && belowMerchant.details == parsed.details)
        }
        for merchant in ["商店甲", "商店乙", "متجر", "12345", "😀", "😃", "Page Studio", "Card Balance Studio", "Transaction Summary Studio", "Purchases Transfers 24.09.2026"] {
            let text = "20.09.2026 - 1,00 ₸ Purchases \(merchant)"
            precondition(valid([text], count: 1)[0].merchant == merchant)
        }
        let numeric = valid(["20.09.2026 - 1,00 ₸ Purchases Shop\n12345\n😀"], count: 1)[0]
        precondition(numeric.merchant == "Shop 12345 😀")
        let names = ["商店甲", "商店乙", "😀", "😃", "AB", "A:B", "A B", "A_B"]
        let originals = names.map { "20.09.2026 - 1,00 ₸ Purchases \($0)" }
        let first = valid([originals.joined(separator: "\n")], count: names.count)
        let reversed = valid([originals.reversed().joined(separator: "\n")], count: names.count)
        precondition(Dictionary(uniqueKeysWithValues: first.map { ($0.merchant, $0.id) }) == Dictionary(uniqueKeysWithValues: reversed.map { ($0.merchant, $0.id) }), "Unicode names must not collapse to the same identity")
        let normalSpaces = valid([row], count: 1)[0]
        let narrowSpaces = valid([row.replacingOccurrences(of: "7 200", with: "7\u{202F}200").replacingOccurrences(of: "-", with: "−")], count: 1)[0]
        precondition(normalSpaces.id == narrowSpaces.id && narrowSpaces.amount == -7200.5)
        let good = "20.09.2026 - 100,00 ₸ Purchases Shop"
        for malformed in [
            "21.09.2026 - 10,00 CNY Purchases Shop", // account currency is not KZT
            "21.09.2026 - 1 2,00 ₸ Purchases Shop", // corrupt grouping
            "21.09.2026 - 100,0 ₸ Purchases Shop", // incomplete amount
            "21.09.2026 - 100,00 ₸ Unknown Shop", // unsupported bank type
            "21.09.2026 - 100,00 ₸ Purchases", // no description
            "31.02.2026 - 100,00 ₸ Purchases Shop", // invalid date
            "21.09.2026 - 0,00 ₸ Purchases Shop",
            "21.09.2026\n- 100,00 ₸ Purchases Shop", // mixed column/row text
        ] { refused([good + "\n" + malformed]) }
        // A bad page must invalidate the whole statement, not just that page.
        refused([good, "21.09.2026 - 100,00 ₸ Unknown Shop"])
        refused([good, ""])
        refused([good + "\n(-1,00 USD)\n(-2,00 CNY)"])
        let originalMinusName = valid(["20.09.2026 − 100,00 ₸ Purchases Shop − 123"], count: 1)[0]
        precondition(originalMinusName.amount == -100 && originalMinusName.merchant == "Shop − 123")
        let columns = "- 100,00 ₸\n(-10,00 CNY)\n- 200,00 ₸\nPurchases\nTransfers\nShop Transfers\n商店甲\n20.09.2026\n21.09.2026"
        let columnRows = valid([columns], count: 2)
        precondition(columnRows.first { $0.amount == -100 }?.merchant == "Shop Transfers")
        precondition(columnRows.first { $0.amount == -100 }?.details.contains("CNY") == true)
        refused([columns.replacingOccurrences(of: "21.09.2026", with: "31.02.2026")])
        refused([columns + "\nextra description"])
        refused([columns + "\n(-5,00 CNY)"])

        let summary = """
        Transaction summary:
        Card balance 01.09.2026 + 100,00 ₸
        Replenishment + 200,00 ₸
        Transfers - 0,00 ₸
        Purchases - 100,00 ₸
        Withdrawals 0,00 ₸
        Others 0,00 ₸
        Card balance 30.09.2026 + 200,00 ₸
        Date Amount Transaction Details
        """
        let body = "20.09.2026 + 200,00 ₸ Replenishment Person\n\(good)"
        _ = valid([summary + "\n" + body], count: 2)
        // Missing or repeated rows and wrong signs/types cannot silently import.
        refused([summary + "\n" + good])
        refused([summary + "\n" + body + "\n" + good])
        refused([summary + "\n" + body.replacingOccurrences(of: "Purchases Shop", with: "Transfers Shop")])
        refused([summary.replacingOccurrences(of: "30.09.2026 + 200,00", with: "30.09.2026 + 200,01") + "\n" + body])
        refused([summary + "\n" + body.replacingOccurrences(of: "20.09.2026", with: "20.08.2026")])
        refused([summary.replacingOccurrences(of: "Others 0,00 ₸", with: "") + "\n" + body])
        let required = parser.parseExtractedPages([good], requireSummary: true)
        precondition(!required.errors.isEmpty && required.transactions.isEmpty)
        let issuer = "Kaspi Gold\nBalance statement\nCurrency: USD\nDate Amount Transaction Details\nJSC «Kaspi Bank», BIC CASPKZKA"
        precondition(KaspiPDFParser.sourceIssue(in: issuer) == .unsupportedSource)
        let namedCurrency = issuer.replacingOccurrences(of: "Currency: USD", with: "Currency: KZT") + "\n20.09.2026 - 100,00 ₸ Purchases Currency: USD"
        precondition(KaspiPDFParser.sourceIssue(in: namedCurrency) == nil, "Merchant text must not change account currency detection")
        print("PASS: \(checks) parser cases for foreign annotations, Unicode names, column alignment, exact totals, balances, dates and atomic refusal")
    }
}
