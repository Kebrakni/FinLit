import Foundation

nonisolated struct CategoryReviewSnapshot: Codable, Equatable, Sendable {
    let id: String
    let date: Date
    let amount: Double
    let merchant: String
    let details: String
    let category: TxCategory

    init(_ transaction: Transaction) {
        id = transaction.id; date = transaction.date; amount = transaction.amount
        merchant = transaction.merchant; details = transaction.details; category = transaction.category
    }

    func matches(_ transaction: Transaction) -> Bool { self == Self(transaction) }
}

nonisolated struct CategoryAuditAssessment: Sendable {
    let snapshot: CategoryReviewSnapshot
    let suggestedCategory: TxCategory
    let needsReview: Bool
    let reason: String
}

nonisolated struct CategoryReviewRecord: Codable {
    let snapshot: CategoryReviewSnapshot
    let suggestedCategory: TxCategory
    let needsReview: Bool
    let reason: String
    let decidedByUser: Bool
    let date: Date
}

nonisolated struct CategoryReviewItem: Identifiable {
    let transaction: Transaction
    let suggestedCategory: TxCategory?
    let reason: String
    let fromAI: Bool
    var id: String { transaction.id }
    var snapshot: CategoryReviewSnapshot { .init(transaction) }
}
