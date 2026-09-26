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
    var participants: [String]
}

enum TxCategory: String, CaseIterable, Hashable, Codable {
    case food            = "Продукты"
    case cafes           = "Кафе/еда"
    case transport       = "Транспорт"
    case entertainment   = "Развлечения"
    case health          = "Здоровье"
    case education       = "Образование"
    case utilities       = "Коммуналка/связь"
    case subscriptions   = "Подписки"
    case shopping        = "Покупки"
    case loans           = "Кредиты/долги"
    case taxes           = "Налоги/штрафы"
    case cashWithdrawals = "Снятие наличных"
    case transfers       = "Переводы"
    case internalTransfers = "Внутренние переводы"
    case other           = "Другое"

    /// Stable, language-independent value used in the AI API contract.
    /// Keep `rawValue` in Russian because it is part of the app's persisted/UI data.
    var aiCode: String {
        switch self {
        case .food:              return "food"
        case .cafes:             return "cafes"
        case .transport:         return "transport"
        case .entertainment:     return "entertainment"
        case .health:            return "health"
        case .education:         return "education"
        case .utilities:         return "utilities"
        case .subscriptions:     return "subscriptions"
        case .shopping:          return "shopping"
        case .loans:             return "loans"
        case .taxes:             return "taxes"
        case .cashWithdrawals:   return "cash_withdrawals"
        case .transfers:         return "transfers"
        case .internalTransfers: return "internal_transfers"
        case .other:             return "other"
        }
    }

    init?(aiCode: String) {
        switch aiCode.lowercased() {
        case "food":              self = .food
        case "cafes", "cafe":    self = .cafes
        case "transport":         self = .transport
        case "entertainment":     self = .entertainment
        case "health":            self = .health
        case "education":         self = .education
        case "utilities":         self = .utilities
        case "subscriptions":     self = .subscriptions
        case "shopping":          self = .shopping
        case "loans":             self = .loans
        case "taxes":             self = .taxes
        case "cash_withdrawals":  self = .cashWithdrawals
        case "transfers":         self = .transfers
        case "internal_transfers": self = .internalTransfers
        case "other":             self = .other
        default:                   return nil
        }
    }

    var icon: String {
        switch self {
        case .food:              return "cart.fill"
        case .cafes:             return "fork.knife"
        case .transport:         return "car.fill"
        case .entertainment:     return "gamecontroller.fill"
        case .health:            return "heart.fill"
        case .education:         return "book.fill"
        case .utilities:         return "bolt.fill"
        case .subscriptions:     return "arrow.clockwise.circle.fill"
        case .shopping:          return "bag.fill"
        case .loans:             return "creditcard.fill"
        case .taxes:             return "doc.text.fill"
        case .cashWithdrawals:   return "dollarsign.circle.fill"
        case .transfers:         return "arrow.left.arrow.right"
        case .internalTransfers: return "arrow.triangle.2.circlepath"
        case .other:             return "ellipsis.circle"
        }
    }

    var sortOrder: Int {
        switch self {
        case .food:              return 10
        case .cafes:             return 20
        case .transport:         return 30
        case .shopping:          return 40
        case .subscriptions:     return 50
        case .utilities:         return 60
        case .health:            return 70
        case .education:         return 80
        case .entertainment:     return 90
        case .loans:             return 95
        case .taxes:             return 96
        case .cashWithdrawals:   return 97
        case .transfers:         return 100
        case .internalTransfers: return 110
        case .other:             return 999
        }
    }
}

struct Transaction: Codable, Identifiable {
    let id: String
    let date: Date
    let amount: Double
    let merchant: String
    let details: String
    let category: TxCategory

    init(id: String = UUID().uuidString, date: Date, amount: Double,
         merchant: String, details: String, category: TxCategory) {
        self.id = id
        self.date = date
        self.amount = amount
        self.merchant = merchant
        self.details = details
        self.category = category
    }

    func withCategory(_ category: TxCategory) -> Transaction {
        Transaction(id: id, date: date, amount: amount, merchant: merchant,
                    details: details, category: category)
    }
}
