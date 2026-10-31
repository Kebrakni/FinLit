import Foundation

private final class AuditDefaults: UserDefaults, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Any] = [:]
    override func dictionary(forKey key: String) -> [String: Any]? { lock.withLock { values[key] as? [String: Any] } }
    override func data(forKey key: String) -> Data? { lock.withLock { values[key] as? Data } }
    override func object(forKey key: String) -> Any? { lock.withLock { values[key] } }
    override func stringArray(forKey key: String) -> [String]? { lock.withLock { values[key] as? [String] } }
    override func string(forKey key: String) -> String? { lock.withLock { values[key] as? String } }
    override func double(forKey key: String) -> Double { lock.withLock { (values[key] as? NSNumber)?.doubleValue ?? 0 } }
    override func set(_ value: Any?, forKey key: String) { lock.withLock { values[key] = value } }
    override func removeObject(forKey key: String) { lock.withLock { _ = values.removeValue(forKey: key) } }
}

@main
struct CoreAuditChecks {
    static func main() throws {
        let parser = KaspiPDFParser()
        let issuer = "JSC «Kaspi Bank», BIC CASPKZKA, www.kaspi.kz"
        let source = "Kaspi Gold\nBalance statement\nDate Amount Transaction Details\n\(issuer)"
        precondition(KaspiPDFParser.sourceIssue(in: source) == nil)
        precondition(KaspiPDFParser.sourceIssue(in: source.replacingOccurrences(of: "Date Amount Transaction Details", with: "Дата Сумма Операция Детали")) == .englishRequired)
        let foreignStatement = "Jusan Bank\nDate Amount Transaction Details\n20.09.2026 - 100,00 ₸ Transfers Kaspi Gold\nBIC TSESKZKA"
        precondition(KaspiPDFParser.sourceIssue(in: foreignStatement) == .unsupportedSource, "A bank mentioned as a recipient must not pass issuer verification")
        precondition(KaspiPDFParser.sourceIssue(in: "Kaspi Gold\nDate Amount Transaction Details\nTransfers to Kaspi Bank BIC CASPKZKA") == .unsupportedSource)
        precondition(KaspiPDFParser.sourceIssue(in: source.replacingOccurrences(of: "CASPKZKA", with: "OTHERBIC")) == .unsupportedSource)
        precondition(KaspiPDFParser.sourceIssue(in: "Date Amount Transaction Details") == .unsupportedSource)
        let appearanceDefaults = AuditDefaults()
        let preferences = AppearancePreferences(defaults: appearanceDefaults)
        precondition(preferences.choice == .system)
        for choice in AppearanceChoice.allCases {
            preferences.choice = choice
            precondition(AppearancePreferences(defaults: appearanceDefaults).choice == choice, "Appearance must persist across instances")
        }
        appearanceDefaults.set("invalid", forKey: "tengely.appearance")
        precondition(preferences.choice == .system)
        let duplicate = "20.09.2026 - 500,00 ₸ Purchases Dodo Pizza"
        let parsed = parser.parseExtractedPages(["\(duplicate)\n\(duplicate)"])
        precondition(parsed.errors.isEmpty && parsed.transactions.count == 2, "Two real equal payments must remain two operations")
        precondition(Set(parsed.transactions.map(\.id)).count == 2)
        precondition(parsed.transactions.allSatisfy { $0.id.count < 200 })
        precondition(parsed.transactions.map(\.id) == parser.parseExtractedPages(["\(duplicate)\n\(duplicate)"]).transactions.map(\.id))
        let wrapped = parser.parseExtractedPages(["20.09.2026 - 500,00 ₸ Purchases DODO\nPIZZA\n21.09.2026 - 100,00 ₸ Purchases SERVICE\nSUBCR"])
        precondition(wrapped.errors.isEmpty && wrapped.transactions.count == 2)
        precondition(Set(wrapped.transactions.map(\.category)) == [.cafes, .subscriptions], "Wrapped merchant/description lines must survive extraction")
        let partial = parser.parseExtractedPages(["\(duplicate)\n21.09.2026 - 100,00 ₸ UnsupportedType SERVICE"])
        precondition(!partial.errors.isEmpty, "A partially unread page must stop import instead of reserving its dates")
        let mismatch = parser.parseExtractedPages(["- 100,00 ₸\n- 200,00 ₸\nPurchases\nPurchases\nShop A\nShop B\nExtra description\n20.09.2026\n21.09.2026"])
        precondition(!mismatch.errors.isEmpty, "Mismatched columns must not invent merchant associations")
        let invalid = parser.parseExtractedPages(["31.02.2026 - 100,00 ₸ Purchases Shop"])
        precondition(!invalid.errors.isEmpty)

        let defaults = AuditDefaults()
        let storage = AppStorage(defaults: defaults)
        let one = parsed.transactions[0]
        precondition(storage.mergeTransactions([one, one]).count == 1, "Deduplicate IDs within a batch, not just against stored rows")
        precondition(storage.mergeTransactions(parsed.transactions).count == 2)
        precondition(storage.mergeTransactions(parsed.transactions).count == 2)

        let reviewDefaults = AuditDefaults()
        let reviewStore = AppStorage(defaults: reviewDefaults)
        let reviewRow = Transaction(id: "review-1", date: Date(), amount: -850.25, merchant: "Example Cafe", details: "Purchases Example Cafe", category: .shopping)
        let opaque = Transaction(id: "review-2", date: Date(), amount: -25, merchant: "Unknown Place", details: "Purchases Unknown Place", category: .other)
        reviewStore.mergeTransactions([reviewRow, opaque])
        precondition(reviewStore.categoryReviewItems().count == 1, "Opaque local fallback is actionable before AI runs")
        let proposal = CategoryAuditAssessment(snapshot: .init(reviewRow), suggestedCategory: .cafes, needsReview: true, reason: "Это кафе")
        precondition(reviewStore.saveCategoryAssessments([proposal]) == 1)
        precondition(reviewStore.loadAllTransactions().first { $0.id == reviewRow.id }?.category == .shopping, "AI proposals must never auto-apply")
        precondition(AppStorage(defaults: reviewDefaults).categoryReviewItems().count == 2, "The review inbox survives reopening")
        precondition(reviewStore.resolveCategoryReview(.init(reviewRow), category: .cafes, remember: true)?.amount == reviewRow.amount)
        precondition(reviewStore.categoryReviewItems().count == 1)
        precondition(LearnedCategoryRules.manualCategory(for: reviewRow.merchant, details: reviewRow.details, defaults: reviewDefaults) == .cafes)
        precondition(LearnedCategoryRules.manualCategory(for: reviewRow.merchant, details: "Transfers Example Cafe", defaults: reviewDefaults) == nil, "A confirmed card payment must not change transfers to that merchant")
        precondition(LearnedCategoryRules.manualCategory(for: reviewRow.merchant, details: "Purchases Example Cafe foreign exchange difference", defaults: reviewDefaults) == nil, "A purchase rule must not override a currency adjustment")
        precondition(LearnedCategoryRules.manualCategory(for: reviewRow.merchant, details: "Purchases Example Cafe SUBSCR", defaults: reviewDefaults) == nil, "A normal purchase rule must not hide an explicit subscription marker")
        precondition(reviewStore.saveCategoryAssessments([proposal]) == 0, "A late AI response cannot overwrite an accepted category")
        precondition(reviewStore.resolveCategoryReview(.init(reviewRow), category: .shopping, remember: true) == nil, "Stale cards must be rejected")
        let opaqueSnapshot = CategoryReviewSnapshot(opaque)
        precondition(reviewStore.resolveCategoryReview(opaqueSnapshot, category: .other, remember: false) != nil)
        precondition(AppStorage(defaults: reviewDefaults).categoryReviewItems().isEmpty, "Keeping the same category is a persistent explicit decision")
        precondition(reviewStore.transactionsForCategoryAudit().isEmpty)
        precondition(LearnedCategoryRules.manualCategory(for: opaque.merchant, details: opaque.details, defaults: reviewDefaults) == nil, "The remember switch can be disabled")
        precondition(reviewStore.saveCategoryAssessments([.init(snapshot: opaqueSnapshot, suggestedCategory: .food, needsReview: true, reason: "Late")]) == 0, "A late answer must not undo keeping the current category")
        _ = reviewStore.updateTransaction(opaque.withCorrections(amount: -30), learnCategory: false)
        precondition(reviewStore.transactionsForCategoryAudit().count == 1, "Edited operations invalidate old review snapshots")
        reviewStore.clearAllTransactions()
        reviewStore.mergeTransactions([opaque])
        precondition(reviewStore.categoryReviewItems().count == 1, "Reset removes obsolete per-operation decisions")
        _ = storage.applyTransactionCorrections([one.id: (amount: .nan, category: .other)])
        precondition(storage.loadAllTransactions().allSatisfy { $0.amount.isFinite })
        _ = storage.applyTransactionCorrections([one.id: (amount: 0, category: .other)])
        precondition(storage.loadAllTransactions().first { $0.id == one.id }?.amount == one.amount)
        let corrupt = Transaction(id: "bad", date: Date(), amount: .infinity, merchant: "Bad", details: "", category: .other)
        precondition(storage.mergeTransactions([corrupt]).count == 2)
        let saved = Goal(title: "Test", targetAmount: 1000, savedAmount: 100, deadline: nil)
        storage.saveGoal(saved)
        storage.saveGoal(Goal(title: "Broken", targetAmount: .nan, savedAmount: 5, deadline: nil))
        precondition(storage.loadGoal().title == "Test")
        precondition(Goal(title: "Test", targetAmount: 100, savedAmount: -10, deadline: nil).progress == 0)

        let calendar = Calendar.current
        func date(_ day: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: day))! }
        func row(_ day: Int) -> Transaction { Transaction(date: date(day), amount: -1, merchant: "Test", details: "Purchases Test", category: .other) }
        let importDefaults = AuditDefaults()
        let importStore = AppStorage(defaults: importDefaults)
        let first = importStore.prepareStatementImport([row(1), row(3)])
        importStore.markAsImported(importStore.makeFingerprint([row(1), row(3)]), plan: first)
        precondition(importStore.prepareStatementImport([row(1), row(2), row(3)]).isFullyOverlapping)
        let extended = importStore.prepareStatementImport([row(1), row(2), row(3), row(4)])
        precondition(extended.newTransactions.count == 1 && extended.newTransactions[0].date == date(4))
        importStore.clearAllTransactions()
        precondition(importStore.prepareStatementImport([row(1), row(3)]).newTransactions.count == 2)
        let interval = calendar.dateInterval(of: .month, for: date(20))!
        precondition(interval.containsTransactionDate(interval.start))
        precondition(!interval.containsTransactionDate(interval.end), "First day of the following month is excluded")

        let members: [[String: Any]] = [["uid": "a", "name": "A", "saved": 1.0], ["uid": "b", "name": "B", "saved": 2.0]]
        let afterA = BattleMembership.upsert(["uid": "a", "name": "New A", "saved": 10.0], into: members)
        let afterB = BattleMembership.upsert(["uid": "b", "name": "New B", "saved": 20.0], into: afterA)
        precondition(afterB.count == 2 && afterB.first { $0["uid"] as? String == "a" }?["saved"] as? Double == 10)
        precondition(afterB.first { $0["uid"] as? String == "b" }?["name"] as? String == "New B")
        precondition(BattleMembership.removing("a", from: afterB).count == 1)
        precondition(BattleMembership.upsert(["uid": "a"], into: members + [members[0]]).count == 2)

        let game = GamificationManager(defaults: AuditDefaults())
        let now = Date()
        _ = game.snapshot(transactions: [], goal: saved, date: now)
        game.recordAIReview(correctionCount: 0, reviewedCount: 5, date: now)
        let progress = game.snapshot(transactions: [], goal: saved, date: now)
        precondition(progress.missions.first { $0.kind == .reviewOperations }?.isCompleted == true,
                     "A successful check must count even when no corrections were necessary")
        let thursday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 12))!
        let noSpend = GamificationManager(defaults: AuditDefaults())
        let week = GamificationManager.weekID(for: thursday)
        noSpend.installWeeklyMissions([WeeklyMission(id: "test-day", weekID: week, title: "Test", detail: "Test", kind: .noSpendDays, target: 1, xpReward: 5, createdAt: thursday)], date: thursday)
        let todayOnly = [Transaction(date: thursday, amount: 100, merchant: "Income", details: "Replenishment", category: .transfers)]
        let noSpendSnapshot = noSpend.snapshot(transactions: todayOnly, goal: saved, date: thursday)
        precondition(noSpendSnapshot.missions.first?.current == 0, "Do not reward today's unfinished day or uncovered days")
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: thursday)!.start
        let sunday = calendar.date(byAdding: .day, value: 6, to: weekStart)!.addingTimeInterval(12 * 3600)
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: weekStart)!
        let weekRows = [Transaction(date: weekStart, amount: -500, merchant: "Cafe", details: "Purchases Cafe", category: .cafes),
                        Transaction(date: sunday, amount: 100, merchant: "Income", details: "Replenishment", category: .transfers)]
        let budgetGame = GamificationManager(defaults: AuditDefaults())
        budgetGame.installWeeklyMissions([WeeklyMission(id: "budget", weekID: week, title: "Budget", detail: "Test", kind: .categoryBudget, target: 1000, categoryCode: "cafes", xpReward: 50, createdAt: weekStart)], date: weekStart)
        let before = budgetGame.snapshot(transactions: weekRows, goal: saved, date: sunday)
        precondition(before.missions.first?.isCompleted == false, "Budget cannot be won before Sunday has ended")
        let after = budgetGame.snapshot(transactions: weekRows, goal: saved, date: nextWeek)
        precondition(after.xp == before.xp + 50, "Settle the previous week before replacing its missions")
        precondition(budgetGame.snapshot(transactions: weekRows, goal: saved, date: nextWeek).xp == after.xp)

        let bundled = URL(fileURLWithPath: "FinLit/gold_statement.pdf")
        if FileManager.default.fileExists(atPath: bundled.path) {
            let sample = parser.parse(pdfURL: bundled)
            precondition(sample.errors.isEmpty && sample.transactions.count == 438, "Bundled PDF regression: \(sample.errors)")
            print("Bundled PDF: \(sample.transactions.count) rows; no personal content printed")
        }
        print("PASS: statement issuer/language checks, appearance persistence, parser multiplicity/wrapping/errors, stable IDs, safe storage, overlap, boundaries, membership merge, review rewards")
    }
}
