import Foundation

struct StatementImportPlan {
    let newTransactions: [Transaction]
    let statementFrom: Date?
    let statementTo: Date?
    let newDays: [Date]
    let overlappingDays: [Date]
    let skippedTransactionCount: Int

    var hasOverlap: Bool { !overlappingDays.isEmpty }
    var isFullyOverlapping: Bool { newTransactions.isEmpty && hasOverlap }
    var newFrom: Date? { newDays.first }
    var newTo: Date? { newDays.last }
    var overlapFrom: Date? { overlappingDays.first }
    var overlapTo: Date? { overlappingDays.last }
}

final class AppStorage {
    static let shared = AppStorage()
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private let goalKey             = "goal_key_v1"
    private let challengesKey       = "challenges_key_v1"
    private let battleKey           = "battle_participants_v1"
    private let allTransactionsKey  = "all_transactions_v2"
    private let fingerprintsKey     = "used_pdf_fingerprints_v1"
    private let importedDaysKey     = "imported_statement_days_v1"
    private let netSavingsKey       = "pdf_net_savings_v1"
    private let aiChatMessagesKey   = "ai_chat_messages_v1"
    private var cachedTransactions: [Transaction]?

    // MARK: - Goal

    func loadGoal() -> Goal {
        if let data = defaults.data(forKey: goalKey),
           let goal = try? JSONDecoder().decode(Goal.self, from: data) { return goal }
        return Goal(title: "New Phone", targetAmount: 350_000, savedAmount: 0, deadline: nil)
    }

    func saveGoal(_ goal: Goal) {
        guard goal.targetAmount.isFinite, goal.targetAmount > 0, goal.targetAmount <= Transaction.maximumAmount,
              goal.savedAmount.isFinite, goal.savedAmount >= 0, goal.savedAmount <= Transaction.maximumAmount,
              !goal.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if let data = try? JSONEncoder().encode(goal) {
            defaults.set(data, forKey: goalKey)
            NotificationCenter.default.post(name: .pdfNetSavingsUpdated, object: nil)
        }
    }

    /// `Goal.savedAmount` stores only money entered manually. Statement savings
    /// are derived from imported transactions so recalculation cannot add them
    /// repeatedly to the persisted goal.
    func loadCombinedSavings() -> Double {
        max(loadGoal().savedAmount, 0) + max(loadPDFNetSavings(), 0)
    }

    func loadGoalIncludingStatementSavings() -> Goal {
        var goal = loadGoal()
        goal.savedAmount = loadCombinedSavings()
        return goal
    }

    // MARK: - Challenges

    func loadChallenges() -> [Challenge] {
        if let data = defaults.data(forKey: challengesKey),
           let items = try? JSONDecoder().decode([Challenge].self, from: data) { return items }
        return [Challenge(title: "Save 10k this week", type: .weeklySaving, createdAt: Date(), participants: ["You"])]
    }

    func saveChallenges(_ challenges: [Challenge]) {
        if let data = try? JSONEncoder().encode(challenges) {
            defaults.set(data, forKey: challengesKey)
        }
    }

    // MARK: - Battle Participants

    func loadBattleParticipants() -> [BattleParticipant] {
        if let data = defaults.data(forKey: battleKey),
           let items = try? JSONDecoder().decode([BattleParticipant].self, from: data) { return items }
        return []
    }

    func saveBattleParticipants(_ items: [BattleParticipant]) {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: battleKey)
        }
    }

    // MARK: - AI Chat

    func loadAIChatMessages() -> [AIChatMessage] {
        guard let data = defaults.data(forKey: aiChatMessagesKey),
              let messages = try? JSONDecoder().decode([AIChatMessage].self, from: data) else {
            return []
        }
        return messages
    }

    func saveAIChatMessages(_ messages: [AIChatMessage]) {
        // Bound local history so it cannot grow indefinitely.
        let recent = Array(messages.suffix(200))
        if let data = try? JSONEncoder().encode(recent) {
            defaults.set(data, forKey: aiChatMessagesKey)
        }
    }

    func clearAIChatMessages() {
        defaults.removeObject(forKey: aiChatMessagesKey)
    }

    // MARK: - Accumulated Transactions

    func loadAllTransactions() -> [Transaction] {
        if let cachedTransactions { return cachedTransactions }
        guard let data = defaults.data(forKey: allTransactionsKey),
              let items = try? JSONDecoder().decode([Transaction].self, from: data) else { return [] }

        // Categories are final after the AI review and must survive relaunches.
        cachedTransactions = items
        return items
    }

    /// Добавляет новые транзакции к накопленным (дедупликация по id)
    /// Возвращает весь накопленный список
    @discardableResult
    func mergeTransactions(_ newTxs: [Transaction]) -> [Transaction] {
        var existing = loadAllTransactions()
        var existingIDs = Set(existing.map { $0.id })
        let toAdd = newTxs.filter { $0.isValid && existingIDs.insert($0.id).inserted }
        existing.append(contentsOf: toAdd)
        existing.sort { $0.date > $1.date }
        cachedTransactions = existing
        if let data = try? JSONEncoder().encode(existing) {
            defaults.set(data, forKey: allTransactionsKey)
        }
        return existing
    }

    /// Replaces one persisted operation without changing its stable id.
    /// Manual category changes become merchant rules for future imports.
    @discardableResult
    func updateTransaction(
        _ updatedTransaction: Transaction,
        learnCategory: Bool = true
    ) -> [Transaction] {
        var transactions = loadAllTransactions()
        guard updatedTransaction.isValid else { return transactions }
        guard let index = transactions.firstIndex(where: { $0.id == updatedTransaction.id }) else {
            return transactions
        }
        let original = transactions[index]
        transactions[index] = updatedTransaction
        transactions.sort { $0.date > $1.date }
        cachedTransactions = transactions
        if let data = try? JSONEncoder().encode(transactions) {
            defaults.set(data, forKey: allTransactionsKey)
        }
        if learnCategory,
           original.category != updatedTransaction.category
            || original.merchant != updatedTransaction.merchant {
            LearnedCategoryRules.learn(
                merchant: updatedTransaction.merchant,
                category: updatedTransaction.category,
                defaults: defaults
            )
        }
        recalculateAndSaveNet()
        NotificationCenter.default.post(name: .transactionsUpdated, object: updatedTransaction.id)
        return transactions
    }

    @discardableResult
    func applyTransactionCorrections(_ corrections: [String: (amount: Double, category: TxCategory)]) -> [Transaction] {
        let updated = loadAllTransactions().map { transaction in
            guard let correction = corrections[transaction.id], correction.amount.isFinite,
                  correction.amount != 0, abs(correction.amount) <= Transaction.maximumAmount else { return transaction }
            if correction.category != transaction.category {
                LearnedCategoryRules.learn(
                    merchant: transaction.merchant,
                    category: correction.category,
                    source: .aiSuggestion,
                    defaults: defaults
                )
            }
            return transaction.withCorrections(
                amount: correction.amount,
                category: correction.category
            )
        }.sorted { $0.date > $1.date }

        cachedTransactions = updated
        if let data = try? JSONEncoder().encode(updated) {
            defaults.set(data, forKey: allTransactionsKey)
        }
        recalculateAndSaveNet()
        NotificationCenter.default.post(name: .transactionsUpdated, object: nil)
        return updated
    }

    /// Сброс всех данных
    func clearAllTransactions() {
        cachedTransactions = []
        defaults.removeObject(forKey: allTransactionsKey)
        defaults.removeObject(forKey: fingerprintsKey)
        defaults.removeObject(forKey: importedDaysKey)
        defaults.set(0.0, forKey: netSavingsKey)
        var participants = loadBattleParticipants()
        if let idx = participants.firstIndex(where: { $0.id == "me_local" }) {
            let goal = loadGoal()
            participants[idx].savedAmount = max(goal.savedAmount, 0)
            participants[idx].targetAmount = goal.targetAmount
            saveBattleParticipants(participants)
        }
        NotificationCenter.default.post(name: .pdfNetSavingsUpdated, object: nil)
    }

    // MARK: - Duplicate Detection

    /// Fingerprint = "minDate|maxDate|count"
    func makeFingerprint(_ transactions: [Transaction]) -> String {
        guard !transactions.isEmpty else { return "empty" }
        let sorted = transactions.sorted { $0.date < $1.date }
        let df = DateFormatter(); df.dateFormat = "dd.MM.yyyy"
        return "\(df.string(from: sorted.first!.date))|\(df.string(from: sorted.last!.date))|\(transactions.count)"
    }

    func isAlreadyImported(_ fingerprint: String) -> Bool {
        return loadFingerprints().contains(fingerprint)
    }

    /// Returns the first and last already imported day shared with the new
    /// statement. Every day between the earliest and latest transaction is
    /// treated as covered, including days without operations.
    func importedDateOverlap(
        for transactions: [Transaction]
    ) -> (from: Date, to: Date)? {
        let plan = prepareStatementImport(transactions)
        guard let first = plan.overlapFrom,
              let last = plan.overlapTo else { return nil }
        return (first, last)
    }

    /// Splits a statement by calendar coverage. Transactions from days already
    /// imported are removed, while transactions from genuinely new days remain.
    /// The returned `newDays` also includes covered days without transactions so
    /// they can be remembered when the plan is committed.
    func prepareStatementImport(_ transactions: [Transaction]) -> StatementImportPlan {
        guard let range = statementDateRange(for: transactions) else {
            return StatementImportPlan(
                newTransactions: [],
                statementFrom: nil,
                statementTo: nil,
                newDays: [],
                overlappingDays: [],
                skippedTransactionCount: 0
            )
        }

        let previouslyImported = loadImportedDayIDsIncludingLegacyFingerprints()
        let statementDays = dates(in: range)
        let overlappingDays = statementDays.filter {
            previouslyImported.contains(dayID(for: $0))
        }
        let newDays = statementDays.filter {
            !previouslyImported.contains(dayID(for: $0))
        }
        let newDayIDs = Set(newDays.map(dayID(for:)))
        let accepted = transactions.filter {
            newDayIDs.contains(dayID(for: $0.date))
        }

        return StatementImportPlan(
            newTransactions: accepted,
            statementFrom: range.lowerBound,
            statementTo: range.upperBound,
            newDays: newDays,
            overlappingDays: overlappingDays,
            skippedTransactionCount: transactions.count - accepted.count
        )
    }

    func markAsImported(_ fingerprint: String, transactions: [Transaction]) {
        var set = loadFingerprints()
        set.insert(fingerprint)
        defaults.set(Array(set), forKey: fingerprintsKey)

        guard let range = statementDateRange(for: transactions) else { return }
        var importedDays = loadImportedDayIDsIncludingLegacyFingerprints()
        importedDays.formUnion(dates(in: range).map(dayID(for:)))
        defaults.set(Array(importedDays).sorted(), forKey: importedDaysKey)
    }

    /// Commits the exact set of new calendar days from a previously prepared
    /// plan. Use this overload for partially overlapping statements.
    func markAsImported(_ fingerprint: String, plan: StatementImportPlan) {
        var fingerprints = loadFingerprints()
        fingerprints.insert(fingerprint)
        defaults.set(Array(fingerprints), forKey: fingerprintsKey)

        var importedDays = loadImportedDayIDsIncludingLegacyFingerprints()
        importedDays.formUnion(plan.newDays.map(dayID(for:)))
        defaults.set(Array(importedDays).sorted(), forKey: importedDaysKey)
    }

    private func loadFingerprints() -> Set<String> {
        Set(defaults.stringArray(forKey: fingerprintsKey) ?? [])
    }

    private func loadImportedDayIDsIncludingLegacyFingerprints() -> Set<String> {
        var importedDays = Set(
            defaults.stringArray(forKey: importedDaysKey) ?? []
        )
        let legacyFormatter = DateFormatter()
        legacyFormatter.calendar = statementCalendar
        legacyFormatter.locale = Locale(identifier: "en_US_POSIX")
        legacyFormatter.dateFormat = "dd.MM.yyyy"

        for fingerprint in loadFingerprints() {
            let parts = fingerprint.split(separator: "|", omittingEmptySubsequences: false)
            guard parts.count >= 2,
                  let from = legacyFormatter.date(from: String(parts[0])),
                  let to = legacyFormatter.date(from: String(parts[1])) else { continue }
            let start = statementCalendar.startOfDay(for: min(from, to))
            let end = statementCalendar.startOfDay(for: max(from, to))
            importedDays.formUnion(dates(in: start...end).map(dayID(for:)))
        }
        return importedDays
    }

    private var statementCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    private func statementDateRange(
        for transactions: [Transaction]
    ) -> ClosedRange<Date>? {
        guard let minimum = transactions.map(\.date).min(),
              let maximum = transactions.map(\.date).max() else { return nil }
        let start = statementCalendar.startOfDay(for: minimum)
        let end = statementCalendar.startOfDay(for: maximum)
        return start...end
    }

    private func dates(in range: ClosedRange<Date>) -> [Date] {
        var result: [Date] = []
        var date = range.lowerBound
        // The cap protects local storage from a malformed date far in the past.
        while date <= range.upperBound, result.count < 5_000 {
            result.append(date)
            guard let next = statementCalendar.date(byAdding: .day, value: 1, to: date) else {
                break
            }
            date = next
        }
        return result
    }

    private func dayID(for date: Date) -> String {
        let values = statementCalendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            values.year ?? 0,
            values.month ?? 0,
            values.day ?? 0
        )
    }

    // MARK: - Net Savings

    /// Пересчитывает net по ВСЕМ накопленным транзакциям и сохраняет
    func recalculateAndSaveNet() {
        let all = loadAllTransactions()
        let income  = all.filter { $0.amount > 0 }.reduce(0.0) { $0 + $1.amount }
        let expense = all.filter { $0.amount < 0 }.reduce(0.0) { $0 + (-$1.amount) }
        let net = income - expense

        defaults.set(net, forKey: netSavingsKey)

        // Battle counts both sources: positive statement balance and money
        // entered manually (for example cash kept outside the bank statement).
        var participants = loadBattleParticipants()
        let myId = "me_local"
        let goal = loadGoal()
        let combinedSavings = max(net, 0) + max(goal.savedAmount, 0)
        if let idx = participants.firstIndex(where: { $0.id == myId }) {
            participants[idx].savedAmount = combinedSavings
            participants[idx].targetAmount = goal.targetAmount
        } else {
            participants.insert(
                BattleParticipant(id: myId, name: "Я", savedAmount: combinedSavings,
                                  targetAmount: goal.targetAmount, joinedAt: Date()),
                at: 0
            )
        }
        saveBattleParticipants(participants)
        NotificationCenter.default.post(name: .pdfNetSavingsUpdated, object: nil)
    }

    func loadPDFNetSavings() -> Double {
        defaults.double(forKey: netSavingsKey)
    }
}

// MARK: - Notification

extension Notification.Name {
    static let pdfNetSavingsUpdated = Notification.Name("pdfNetSavingsUpdated")
    static let transactionsUpdated = Notification.Name("finlit.transactions.updated")
}
