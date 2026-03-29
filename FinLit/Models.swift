import Foundation

struct Goal: Codable {
    var title: String
    var targetAmount: Double
    var savedAmount: Double
    var deadline: Date?

    var progress: Double {
        guard targetAmount > 0 else { return 0 }
        return min(savedAmount / targetAmount, 1.0)
    }
}

enum ChallengeType: String, Codable, CaseIterable {
    case weeklySaving = "Weekly Saving"
    case fastestToGoal = "Fastest to Goal"
    case noSpendWeekend = "No-Spend Weekend"
}

struct Challenge: Codable, Identifiable {
    var id: String = UUID().uuidString
    var title: String
    var type: ChallengeType
    var createdAt: Date
    var participants: [String] // пока просто имена/ники
}


enum TxCategory: String, CaseIterable, Hashable,Codable {
    case food = "Продукты"
    case cafes = "Кафе/еда"
    case transport = "Транспорт"
    case entertainment = "Развлечения"
    case health = "Здоровье"
    case education = "Образование"
    case utilities = "Коммуналка/связь"
    case subscriptions = "Подписки"
    case shopping = "Покупки"
    case transfers = "Переводы"
    case internalTransfers = "Внутренние переводы"
    case other = "Другое"

    // чтобы был стабильный порядок в списке
    var sortOrder: Int {
        switch self {
        case .food: return 10
        case .cafes: return 20
        case .transport: return 30
        case .shopping: return 40
        case .subscriptions: return 50
        case .utilities: return 60
        case .health: return 70
        case .education: return 80
        case .entertainment: return 90
        case .transfers: return 100
        case .internalTransfers: return 110
        case .other: return 999
        }
    }
}


struct Transaction: Codable, Identifiable {
    let id: String
    let date: Date
    let amount: Double    // расход обычно отрицательный, доход положительный
    let merchant: String
    let details: String
    let category: TxCategory

    init(id: String = UUID().uuidString, date: Date, amount: Double, merchant: String, details: String, category: TxCategory) {
        self.id = id
        self.date = date
        self.amount = amount
        self.merchant = merchant
        self.details = details
        self.category = category
    }
}
