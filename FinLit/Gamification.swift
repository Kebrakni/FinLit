import Foundation

// MARK: - Public models

enum MissionKind: String, Codable, CaseIterable {
    case saveAmount
    case reviewOperations
    case categoryBudget
    case noSpendDays
}

struct WeeklyMission: Codable, Identifiable, Equatable {
    let id: String
    let weekID: String
    let title: String
    let detail: String
    let kind: MissionKind
    let target: Double
    var current: Double
    let categoryCode: String?
    let xpReward: Int
    let generatedByAI: Bool
    let createdAt: Date

    var isCompleted: Bool { current >= target }
    var progress: Double { min(max(current / max(target, 1), 0), 1) }

    init(
        id: String = UUID().uuidString,
        weekID: String = GamificationManager.weekID(),
        title: String,
        detail: String,
        kind: MissionKind,
        target: Double,
        current: Double = 0,
        categoryCode: String? = nil,
        xpReward: Int = 50,
        generatedByAI: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.weekID = weekID
        self.title = title
        self.detail = detail
        self.kind = kind
        self.target = max(target, 1)
        self.current = max(current, 0)
        self.categoryCode = categoryCode
        self.xpReward = max(xpReward, 1)
        self.generatedByAI = generatedByAI
        self.createdAt = createdAt
    }
}

struct AchievementStatus: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let icon: String
    let xpReward: Int
    let unlockedAt: Date?

    var isUnlocked: Bool { unlockedAt != nil }
}

struct GamificationSnapshot {
    let levelTitle: String
    let levelIcon: String
    let level: Int
    let xp: Int
    let currentLevelXP: Int
    let nextLevelXP: Int?
    let levelProgress: Double
    let streak: Int
    let missions: [WeeklyMission]
    let achievements: [AchievementStatus]
}

// MARK: - Persisted state

private enum GamificationEventKind: String, Codable {
    case goalContribution
    case reviewedOperations
    case statementImport
}

private struct GamificationEvent: Codable {
    let id: String
    let kind: GamificationEventKind
    let date: Date
    let value: Double
}

private struct GamificationProfile: Codable {
    var xp = 0
    var activeWeekIDs: Set<String> = []
    var rewardedEventIDs: Set<String> = []
    var completedMissionIDs: Set<String> = []
    var unlockedAchievements: [String: Date] = [:]
    var weeklyMissions: [WeeklyMission] = []
    var missionWeekID: String?
    var events: [GamificationEvent] = []
    var importedStatementCount = 0
    var importedTransactionCount = 0
    var correctedTransactionCount = 0
}

private struct AchievementDefinition {
    let id: String
    let title: String
    let detail: String
    let icon: String
    let xpReward: Int
}

// MARK: - Manager

final class GamificationManager {
    static let shared = GamificationManager()
    static let updatedNotification = Notification.Name("finlit.gamification.updated")

    private let profileKey = "gamification_profile_v1"
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var profile: GamificationProfile

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: profileKey),
           let value = try? decoder.decode(GamificationProfile.self, from: data) {
            profile = value
        } else {
            profile = GamificationProfile()
        }
        pruneOldData()
    }

    @discardableResult
    func markActivity(date: Date = Date()) -> Int {
        profile.activeWeekIDs.insert(Self.weekID(for: date))
        let xp = awardXP(
            5,
            eventID: "weekly-checkin:\(Self.weekID(for: date))",
            saveAfter: false
        )
        saveAndNotify()
        return xp
    }

    @discardableResult
    func recordStatementImport(
        eventID: String,
        count: Int,
        date: Date = Date()
    ) -> Int {
        let key = "statement:\(eventID)"
        guard !profile.rewardedEventIDs.contains(key) else { return 0 }
        profile.importedStatementCount += 1
        profile.importedTransactionCount += max(count, 0)
        appendEvent(id: key, kind: .statementImport, value: 1, date: date)
        profile.activeWeekIDs.insert(Self.weekID(for: date))
        let xp = awardXP(20, eventID: key, saveAfter: false)
        saveAndNotify()
        return xp
    }

    @discardableResult
    func recordGoalContribution(amount: Double, date: Date = Date()) -> Int {
        guard amount > 0 else { return 0 }
        appendEvent(
            id: "goal:\(UUID().uuidString)",
            kind: .goalContribution,
            value: amount,
            date: date
        )
        profile.activeWeekIDs.insert(Self.weekID(for: date))
        // One XP reward per day prevents farming by splitting one contribution.
        let xp = awardXP(
            10,
            eventID: "goal-day:\(Self.dayID(for: date))",
            saveAfter: false
        )
        saveAndNotify()
        return xp
    }

    @discardableResult
    func recordAIReview(correctionCount: Int, date: Date = Date()) -> Int {
        guard correctionCount > 0 else { return 0 }
        profile.correctedTransactionCount += correctionCount
        appendEvent(
            id: "ai-review:\(UUID().uuidString)",
            kind: .reviewedOperations,
            value: Double(correctionCount),
            date: date
        )
        profile.activeWeekIDs.insert(Self.weekID(for: date))
        let xp = awardXP(
            min(30, 10 + max(correctionCount - 1, 0) * 2),
            eventID: "ai-review-day:\(Self.dayID(for: date))",
            saveAfter: false
        )
        saveAndNotify()
        return xp
    }

    func installWeeklyMissions(_ missions: [WeeklyMission], date: Date = Date()) {
        let currentWeek = Self.weekID(for: date)
        let valid = missions
            .filter { $0.weekID == currentWeek && $0.target > 0 }
            .prefix(3)
        guard !valid.isEmpty else { return }
        profile.weeklyMissions = Array(valid)
        profile.missionWeekID = currentWeek
        saveAndNotify()
    }

    func needsAIMissions(date: Date = Date()) -> Bool {
        let currentWeek = Self.weekID(for: date)
        guard profile.missionWeekID == currentWeek else { return true }
        return !profile.weeklyMissions.contains { mission in
            mission.weekID == currentWeek && mission.generatedByAI
        }
    }

    @discardableResult
    func snapshot(
        transactions: [Transaction],
        goal: Goal,
        date: Date = Date()
    ) -> GamificationSnapshot {
        ensureWeeklyMissions(transactions: transactions, goal: goal, date: date)
        updateMissionProgress(transactions: transactions, date: date)
        awardCompletedMissions()
        unlockAchievements(transactions: transactions, goal: goal, date: date)
        save()

        let level = Self.level(for: profile.xp)
        let progress: Double
        if let next = level.nextXP, next > level.minimumXP {
            progress = Double(profile.xp - level.minimumXP)
                / Double(next - level.minimumXP)
        } else {
            progress = 1
        }

        return GamificationSnapshot(
            levelTitle: level.title,
            levelIcon: level.icon,
            level: level.number,
            xp: profile.xp,
            currentLevelXP: level.minimumXP,
            nextLevelXP: level.nextXP,
            levelProgress: min(max(progress, 0), 1),
            streak: weeklyStreak(asOf: date),
            missions: profile.weeklyMissions,
            achievements: Self.achievementCatalog.map { definition in
                AchievementStatus(
                    id: definition.id,
                    title: definition.title,
                    detail: definition.detail,
                    icon: definition.icon,
                    xpReward: definition.xpReward,
                    unlockedAt: profile.unlockedAchievements[definition.id]
                )
            }
        )
    }
}

// MARK: - Mission calculations

private extension GamificationManager {
    func ensureWeeklyMissions(
        transactions: [Transaction],
        goal: Goal,
        date: Date
    ) {
        let currentWeek = Self.weekID(for: date)
        guard profile.missionWeekID != currentWeek || profile.weeklyMissions.isEmpty else {
            return
        }
        profile.missionWeekID = currentWeek
        profile.weeklyMissions = makeFallbackMissions(
            weekID: currentWeek,
            transactions: transactions,
            goal: goal,
            date: date
        )
        saveAndNotify()
    }

    func makeFallbackMissions(
        weekID: String,
        transactions: [Transaction],
        goal: Goal,
        date: Date
    ) -> [WeeklyMission] {
        let totalExpenses = transactions
            .filter { $0.amount < 0 }
            .reduce(0.0) { $0 + abs($1.amount) }
        let monthKeys = Set(transactions.map { transaction in
            let values = Self.calendar.dateComponents([.year, .month], from: transaction.date)
            return "\(values.year ?? 0)-\(values.month ?? 0)"
        })
        let monthlyEstimate = transactions.isEmpty
            ? max(goal.targetAmount * 0.08, 20_000)
            : totalExpenses / max(Double(monthKeys.count), 1)
        let rawTarget = min(max(monthlyEstimate * 0.05, 1_000), 50_000)
        let savingTarget = max(1_000, (rawTarget / 1_000).rounded() * 1_000)
        let reviewTarget = Double(min(max(transactions.count / 20, 3), 10))

        let discretionary: Set<TxCategory> = [.cafes, .shopping, .entertainment]
        let categoryTotals = Dictionary(grouping: transactions.filter {
            $0.amount < 0 && discretionary.contains($0.category)
        }, by: \.category)
            .mapValues { rows in rows.reduce(0.0) { $0 + abs($1.amount) } }
        let topCategory = categoryTotals.max { $0.value < $1.value }

        var result = [
            WeeklyMission(
                id: "\(weekID):save",
                weekID: weekID,
                title: "Шаг к цели",
                detail: "Отложить \(Self.moneyText(savingTarget)) за неделю",
                kind: .saveAmount,
                target: savingTarget,
                xpReward: 60,
                createdAt: date
            ),
            WeeklyMission(
                id: "\(weekID):review",
                weekID: weekID,
                title: "Финансовая ревизия",
                detail: "Проверить с AI \(Int(reviewTarget)) операций",
                kind: .reviewOperations,
                target: reviewTarget,
                xpReward: 45,
                createdAt: date
            ),
        ]

        if let topCategory {
            let weeklyAverage = topCategory.value / max(Double(monthKeys.count) * 4, 1)
            let budget = max(1_000, (weeklyAverage * 0.85 / 500).rounded() * 500)
            result.append(
                WeeklyMission(
                    id: "\(weekID):category:\(topCategory.key.aiCode)",
                    weekID: weekID,
                    title: "Держим бюджет",
                    detail: "Не превысить \(Self.moneyText(budget)) в категории «\(topCategory.key.rawValue)»",
                    kind: .categoryBudget,
                    target: budget,
                    categoryCode: topCategory.key.aiCode,
                    xpReward: 55,
                    createdAt: date
                )
            )
        } else {
            result.append(
                WeeklyMission(
                    id: "\(weekID):no-spend",
                    weekID: weekID,
                    title: "Осознанная неделя",
                    detail: "Провести 2 дня без необязательных покупок",
                    kind: .noSpendDays,
                    target: 2,
                    xpReward: 55,
                    createdAt: date
                )
            )
        }
        return result
    }

    func updateMissionProgress(transactions: [Transaction], date: Date) {
        let currentWeek = Self.weekID(for: date)
        let weekTransactions = transactions.filter {
            Self.weekID(for: $0.date) == currentWeek
        }
        let elapsedWeekFraction = Self.elapsedWeekFraction(asOf: date)

        profile.weeklyMissions = profile.weeklyMissions.map { mission in
            guard mission.weekID == currentWeek else { return mission }
            var updated = mission
            switch mission.kind {
            case .saveAmount:
                updated.current = eventTotal(kind: .goalContribution, weekID: currentWeek)
            case .reviewOperations:
                updated.current = eventTotal(kind: .reviewedOperations, weekID: currentWeek)
            case .noSpendDays:
                updated.current = Double(noSpendDays(transactions: weekTransactions, date: date))
            case .categoryBudget:
                guard let code = mission.categoryCode,
                      let category = TxCategory(aiCode: code),
                      !weekTransactions.isEmpty else {
                    updated.current = 0
                    return updated
                }
                let spend = weekTransactions
                    .filter { $0.category == category && $0.amount < 0 }
                    .reduce(0.0) { $0 + abs($1.amount) }
                let allowedSoFar = mission.target * elapsedWeekFraction
                // Progress grows through the week only while spending stays on pace.
                if spend <= max(allowedSoFar, 1) {
                    updated.current = mission.target * elapsedWeekFraction
                } else {
                    let overspendRatio = (spend - allowedSoFar) / mission.target
                    updated.current = mission.target * max(elapsedWeekFraction - overspendRatio, 0)
                }
            }
            updated.current = min(max(updated.current, 0), updated.target)
            return updated
        }
    }

    func awardCompletedMissions() {
        for mission in profile.weeklyMissions
        where mission.isCompleted && !profile.completedMissionIDs.contains(mission.id) {
            profile.completedMissionIDs.insert(mission.id)
            profile.xp += mission.xpReward
        }
    }

    func noSpendDays(transactions: [Transaction], date: Date) -> Int {
        guard !transactions.isEmpty,
              let interval = Self.calendar.dateInterval(of: .weekOfYear, for: date) else {
            return 0
        }
        let discretionary: Set<TxCategory> = [.cafes, .shopping, .entertainment]
        let spendingDays = Set(transactions.compactMap { transaction -> Date? in
            guard transaction.amount < 0,
                  discretionary.contains(transaction.category) else { return nil }
            return Self.calendar.startOfDay(for: transaction.date)
        })
        let elapsed = min(
            7,
            max(Self.calendar.dateComponents([.day], from: interval.start, to: date).day ?? 0, 0) + 1
        )
        return (0..<elapsed).reduce(0) { result, offset in
            guard let day = Self.calendar.date(byAdding: .day, value: offset, to: interval.start) else {
                return result
            }
            return result + (spendingDays.contains(Self.calendar.startOfDay(for: day)) ? 0 : 1)
        }
    }

    func eventTotal(kind: GamificationEventKind, weekID: String) -> Double {
        profile.events
            .filter { $0.kind == kind && Self.weekID(for: $0.date) == weekID }
            .reduce(0) { $0 + $1.value }
    }
}

// MARK: - Achievements and levels

private extension GamificationManager {
    struct LevelDefinition {
        let number: Int
        let title: String
        let icon: String
        let minimumXP: Int
        let nextXP: Int?
    }

    static let achievementCatalog: [AchievementDefinition] = [
        AchievementDefinition(
            id: "first_statement",
            title: "Первая выписка",
            detail: "Загрузить первую банковскую выписку",
            icon: "doc.text.fill",
            xpReward: 25
        ),
        AchievementDefinition(
            id: "hundred_operations",
            title: "Под контролем",
            detail: "Проанализировать 100 операций",
            icon: "checklist",
            xpReward: 50
        ),
        AchievementDefinition(
            id: "positive_balance",
            title: "В плюсе",
            detail: "Получить положительный баланс по выпискам",
            icon: "chart.line.uptrend.xyaxis",
            xpReward: 40
        ),
        AchievementDefinition(
            id: "goal_25",
            title: "Первый рубеж",
            detail: "Накопить 25% финансовой цели",
            icon: "flag.fill",
            xpReward: 35
        ),
        AchievementDefinition(
            id: "goal_50",
            title: "Половина пути",
            detail: "Накопить 50% финансовой цели",
            icon: "mountain.2.fill",
            xpReward: 60
        ),
        AchievementDefinition(
            id: "goal_100",
            title: "Цель достигнута",
            detail: "Полностью закрыть финансовую цель",
            icon: "trophy.fill",
            xpReward: 120
        ),
        AchievementDefinition(
            id: "streak_4",
            title: "Месяц дисциплины",
            detail: "Поддерживать активность четыре недели подряд",
            icon: "flame.fill",
            xpReward: 80
        ),
        AchievementDefinition(
            id: "corrections_10",
            title: "AI-аудитор",
            detail: "Исправить 10 операций вместе с AI",
            icon: "sparkles",
            xpReward: 60
        ),
        AchievementDefinition(
            id: "saved_100k",
            title: "Первые 100 000 ₸",
            detail: "Отложить 100 000 ₸ на цель",
            icon: "banknote.fill",
            xpReward: 100
        ),
    ]

    static func level(for xp: Int) -> LevelDefinition {
        let catalog: [(Int, String, String)] = [
            (0, "Новичок", "leaf.fill"),
            (150, "Планировщик", "list.bullet.clipboard.fill"),
            (400, "Накопитель", "banknote.fill"),
            (800, "Стратег", "scope"),
            (1_400, "Инвестор привычек", "chart.line.uptrend.xyaxis"),
            (2_200, "Финансовый мастер", "crown.fill"),
            (3_200, "Легенда FinLit", "sparkles"),
        ]
        let safeXP = max(xp, 0)
        let index = catalog.lastIndex { safeXP >= $0.0 } ?? 0
        let item = catalog[index]
        return LevelDefinition(
            number: index + 1,
            title: item.1,
            icon: item.2,
            minimumXP: item.0,
            nextXP: index + 1 < catalog.count ? catalog[index + 1].0 : nil
        )
    }

    func unlockAchievements(transactions: [Transaction], goal: Goal, date: Date) {
        var earned: Set<String> = []
        if profile.importedStatementCount > 0 || !transactions.isEmpty {
            earned.insert("first_statement")
        }
        if max(profile.importedTransactionCount, transactions.count) >= 100 {
            earned.insert("hundred_operations")
        }
        if transactions.reduce(0.0, { $0 + $1.amount }) > 0 {
            earned.insert("positive_balance")
        }
        if goal.progress >= 0.25 { earned.insert("goal_25") }
        if goal.progress >= 0.50 { earned.insert("goal_50") }
        if goal.progress >= 1.00 { earned.insert("goal_100") }
        if weeklyStreak(asOf: date) >= 4 { earned.insert("streak_4") }
        if profile.correctedTransactionCount >= 10 { earned.insert("corrections_10") }
        if goal.savedAmount >= 100_000 { earned.insert("saved_100k") }

        for definition in Self.achievementCatalog
        where earned.contains(definition.id)
            && profile.unlockedAchievements[definition.id] == nil {
            profile.unlockedAchievements[definition.id] = date
            profile.xp += definition.xpReward
        }
    }

    func weeklyStreak(asOf date: Date) -> Int {
        guard !profile.activeWeekIDs.isEmpty,
              var cursor = Self.calendar.dateInterval(of: .weekOfYear, for: date)?.start else {
            return 0
        }
        if !profile.activeWeekIDs.contains(Self.weekID(for: cursor)) {
            guard let previous = Self.calendar.date(
                byAdding: .weekOfYear,
                value: -1,
                to: cursor
            ), profile.activeWeekIDs.contains(Self.weekID(for: previous)) else {
                return 0
            }
            cursor = previous
        }

        var count = 0
        while profile.activeWeekIDs.contains(Self.weekID(for: cursor)) {
            count += 1
            guard count < 104,
                  let previous = Self.calendar.date(
                    byAdding: .weekOfYear,
                    value: -1,
                    to: cursor
                  ) else { break }
            cursor = previous
        }
        return count
    }
}

// MARK: - Persistence helpers

private extension GamificationManager {
    func appendEvent(id: String, kind: GamificationEventKind, value: Double, date: Date) {
        guard !profile.events.contains(where: { $0.id == id }) else { return }
        profile.events.append(
            GamificationEvent(id: id, kind: kind, date: date, value: value)
        )
    }

    @discardableResult
    func awardXP(
        _ amount: Int,
        eventID: String,
        saveAfter: Bool = true
    ) -> Int {
        guard amount > 0,
              !profile.rewardedEventIDs.contains(eventID) else { return 0 }
        profile.rewardedEventIDs.insert(eventID)
        profile.xp += amount
        if saveAfter { saveAndNotify() }
        return amount
    }

    func pruneOldData(date: Date = Date()) {
        let cutoff = Self.calendar.date(byAdding: .year, value: -2, to: date) ?? .distantPast
        profile.events.removeAll { $0.date < cutoff }
        if profile.events.count > 500 {
            profile.events = Array(profile.events.sorted { $0.date < $1.date }.suffix(500))
        }
        if profile.activeWeekIDs.count > 104 {
            profile.activeWeekIDs = Set(profile.activeWeekIDs.sorted().suffix(104))
        }
        save()
    }

    func saveAndNotify() {
        save()
        NotificationCenter.default.post(name: Self.updatedNotification, object: nil)
    }

    func save() {
        guard let data = try? encoder.encode(profile) else { return }
        defaults.set(data, forKey: profileKey)
    }
}

// MARK: - Date and formatting helpers

extension GamificationManager {
    fileprivate static let calendar: Calendar = {
        var value = Calendar(identifier: .iso8601)
        value.firstWeekday = 2
        value.minimumDaysInFirstWeek = 4
        return value
    }()

    static func weekID(for date: Date = Date()) -> String {
        let values = calendar.dateComponents(
            [.yearForWeekOfYear, .weekOfYear],
            from: date
        )
        return String(
            format: "%04d-W%02d",
            values.yearForWeekOfYear ?? 0,
            values.weekOfYear ?? 0
        )
    }

    static func weekID() -> String { weekID(for: Date()) }

    fileprivate static func dayID(for date: Date) -> String {
        let values = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            values.year ?? 0,
            values.month ?? 0,
            values.day ?? 0
        )
    }

    fileprivate static func elapsedWeekFraction(asOf date: Date) -> Double {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else {
            return 0
        }
        let elapsedDays = min(
            7,
            max(calendar.dateComponents([.day], from: interval.start, to: date).day ?? 0, 0) + 1
        )
        return Double(elapsedDays) / 7
    }

    fileprivate static func moneyText(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return "\(formatter.string(from: NSNumber(value: amount)) ?? String(Int(amount))) ₸"
    }
}
