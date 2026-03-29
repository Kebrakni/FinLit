import Foundation

final class AppStorage {
    static let shared = AppStorage()
    private init() {}

    private let goalKey             = "goal_key_v1"
    private let challengesKey       = "challenges_key_v1"
    private let battleKey           = "battle_participants_v1"
    private let allTransactionsKey  = "all_transactions_v2"
    private let fingerprintsKey     = "used_pdf_fingerprints_v1"
    private let netSavingsKey       = "pdf_net_savings_v1"

    // MARK: - Goal

    func loadGoal() -> Goal {
        if let data = UserDefaults.standard.data(forKey: goalKey),
           let goal = try? JSONDecoder().decode(Goal.self, from: data) { return goal }
        return Goal(title: "New Phone", targetAmount: 350_000, savedAmount: 0, deadline: nil)
    }

    func saveGoal(_ goal: Goal) {
        if let data = try? JSONEncoder().encode(goal) {
            UserDefaults.standard.set(data, forKey: goalKey)
        }
    }

    // MARK: - Challenges

    func loadChallenges() -> [Challenge] {
        if let data = UserDefaults.standard.data(forKey: challengesKey),
           let items = try? JSONDecoder().decode([Challenge].self, from: data) { return items }
        return [Challenge(title: "Save 10k this week", type: .weeklySaving, createdAt: Date(), participants: ["You"])]
    }

    func saveChallenges(_ challenges: [Challenge]) {
        if let data = try? JSONEncoder().encode(challenges) {
            UserDefaults.standard.set(data, forKey: challengesKey)
        }
    }

    // MARK: - Battle Participants

    func loadBattleParticipants() -> [BattleParticipant] {
        if let data = UserDefaults.standard.data(forKey: battleKey),
           let items = try? JSONDecoder().decode([BattleParticipant].self, from: data) { return items }
        return []
    }

    func saveBattleParticipants(_ items: [BattleParticipant]) {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: battleKey)
        }
    }

    // MARK: - Accumulated Transactions

    func loadAllTransactions() -> [Transaction] {
        guard let data = UserDefaults.standard.data(forKey: allTransactionsKey),
              let items = try? JSONDecoder().decode([Transaction].self, from: data) else { return [] }
        return items
    }

    /// Добавляет новые транзакции к накопленным (дедупликация по id)
    /// Возвращает весь накопленный список
    @discardableResult
    func mergeTransactions(_ newTxs: [Transaction]) -> [Transaction] {
        var existing = loadAllTransactions()
        let existingIDs = Set(existing.map { $0.id })
        let toAdd = newTxs.filter { !existingIDs.contains($0.id) }
        existing.append(contentsOf: toAdd)
        existing.sort { $0.date > $1.date }
        if let data = try? JSONEncoder().encode(existing) {
            UserDefaults.standard.set(data, forKey: allTransactionsKey)
        }
        return existing
    }

    /// Сброс всех данных
    func clearAllTransactions() {
        UserDefaults.standard.removeObject(forKey: allTransactionsKey)
        UserDefaults.standard.removeObject(forKey: fingerprintsKey)
        UserDefaults.standard.set(0.0, forKey: netSavingsKey)
        var participants = loadBattleParticipants()
        if let idx = participants.firstIndex(where: { $0.id == "me_local" }) {
            participants[idx].savedAmount = 0
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

    func markAsImported(_ fingerprint: String) {
        var set = loadFingerprints()
        set.insert(fingerprint)
        UserDefaults.standard.set(Array(set), forKey: fingerprintsKey)
    }

    private func loadFingerprints() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: fingerprintsKey) ?? [])
    }

    // MARK: - Net Savings

    /// Пересчитывает net по ВСЕМ накопленным транзакциям и сохраняет
    func recalculateAndSaveNet() {
        let all = loadAllTransactions()
        let income  = all.filter { $0.amount > 0 }.reduce(0.0) { $0 + $1.amount }
        let expense = all.filter { $0.amount < 0 }.reduce(0.0) { $0 + (-$1.amount) }
        let net = income - expense

        UserDefaults.standard.set(net, forKey: netSavingsKey)

        // Обновляем Battle
        var participants = loadBattleParticipants()
        let myId = "me_local"
        if let idx = participants.firstIndex(where: { $0.id == myId }) {
            participants[idx].savedAmount = net
        } else {
            let goal = loadGoal()
            participants.insert(
                BattleParticipant(id: myId, name: "Я", savedAmount: net,
                                  targetAmount: goal.targetAmount, joinedAt: Date()),
                at: 0
            )
        }
        saveBattleParticipants(participants)
        NotificationCenter.default.post(name: .pdfNetSavingsUpdated, object: nil)
    }

    func loadPDFNetSavings() -> Double {
        UserDefaults.standard.double(forKey: netSavingsKey)
    }
}

// MARK: - Notification

extension Notification.Name {
    static let pdfNetSavingsUpdated = Notification.Name("pdfNetSavingsUpdated")
}
