//
//  Categorizer.swift
//  FinLit
//

import Foundation

nonisolated final class Categorizer {

    struct Evidence: Sendable {
        let category: TxCategory
        let reason: String
    }

    /// Only strong, contextual signals belong here; unknown merchants stay open
    /// to the AI decision. A bank's "Purchases" type is not a spending category.
    static func evidence(merchant: String, details: String) -> Evidence? {
        let text = (merchant + " " + details).lowercased()
        let bankType = details.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if containsAny(text, ["foreign exchange difference", "курсовая разница"]) {
            return Evidence(category: .other, reason: "Курсовая корректировка, а не покупка")
        }
        if matches(bankType, #"^(withdrawals|снятие)\b"#) {
            return Evidence(category: .cashWithdrawals, reason: "Банк указал снятие наличных")
        }
        let atmDeposit = matches(bankType, #"^(replenishment|пополнение)\b"#)
            && containsAny(text, ["at kaspi atm", "in the kaspi terminal"])
        if atmDeposit || containsAny(text, ["kaspi deposit", "пополнение депозита", "депозит", "from my current account kaspi pay"]) {
            return Evidence(category: .internalTransfers, reason: "Перемещение денег между собственными счетами или внесение наличных")
        }
        if containsAny(text, ["kaspi red", "kaspi credit"]) {
            return Evidence(category: .loans, reason: "Платёж Kaspi Red/Credit")
        }
        if matches(bankType, #"^(transfers|replenishment|перевод|пополнение)\b"#) {
            return Evidence(category: .transfers, reason: "Банк указал перевод или пополнение")
        }
        if matches(text, #"(?:^|[^\p{L}\p{N}])(?:subcr|subscr|subscription|subscriptions|recurring)(?=$|[^\p{L}])|подписк|автопродлен"#) {
            return Evidence(category: .subscriptions, reason: "В описании есть явная пометка подписки: SUBCR/SUBSCR/subscription/recurring")
        }
        let normalized = text.replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
        if matches(normalized, #"(?:^|\s)(?:dodo\s*pizza|додо\s*пицц[аы])(?:$|\s)"#) {
            return Evidence(category: .cafes, reason: "Dodo Pizza / Додо Пицца — заказ готовой еды")
        }
        return nil
    }

    static func validatedCategory(merchant: String, details: String, aiCategory: TxCategory?, manualCategory: TxCategory? = nil) -> TxCategory? {
        manualCategory ?? evidence(merchant: merchant, details: details)?.category ?? aiCategory
    }

    static func finalCategory(for transaction: Transaction, aiCategory: TxCategory?) -> TxCategory {
        validatedCategory(
            merchant: transaction.merchant, details: transaction.details, aiCategory: aiCategory,
            manualCategory: LearnedCategoryRules.manualCategory(for: transaction.merchant)
        ) ?? categorize(merchant: transaction.merchant, details: transaction.details)
    }

    static func categorize(merchant: String, details: String) -> TxCategory {
        let text = (merchant + " " + details).lowercased()
        let detailsLow = details.lowercased()

        if let manual = LearnedCategoryRules.manualCategory(for: merchant) { return manual }
        if let evidence = evidence(merchant: merchant, details: details) { return evidence.category }

        // 2) Taxes, fines, government fees
        if containsAny(text, ["штраф", "налог", "фискал"])
            || matches(text, #"(?:^|[^\p{L}\p{N}])(?:tax|taxes|fine|fines|penalty|penalties)(?=$|[^\p{L}\p{N}])"#) {
            return .taxes
        }

        // 3) Digital subscriptions & cloud services
        if containsAny(text, [
            "google *play", "google play", "google*google services", "google services", "apple.com",
            "spotify", "netflix", "youtube premium",
            "aws emea", "aws ", "amazon web", "subscription"
        ]) {
            return .subscriptions
        }

        // 4) Transport
        if containsAny(text, [
            "avtobys", "onay", "yandex.go", "uber", "taxi", "такси",
            "проезда по qr", "пригород", "автобус"
        ]) {
            return .transport
        }

        // 5) Telecom + transfer commissions
        if containsAny(text, [
            "tele2", "beeline", "kcell", "telecom", "қазақтелеком", "казахтелеком",
            "commission for transfer of other banks", "комис"
        ]) {
            return .utilities
        }

        // 6) Water delivery, utilities supplies, self-service terminals
        if containsAny(text, [
            "аквафор", "aquafor", "novy filter", "чистая вода",
            "аппарат самообслуживания"
        ]) {
            return .utilities
        }

        // 7) Grocery / supermarkets
        if containsAny(text, [
            "magnum", "small", "my mart", "grocery", "супермаркет",
            "магазин fresh", "овощи", "фрукты"
        ]) {
            return .food
        }

        // 8) Cafes, restaurants, food delivery
        if containsAny(text, [
            "wolt", "yandex.eda", "kfc", "popeyes", "starbucks",
            "cafe", "coffee", "кофейн", "ресторан",
            "bal samsa", "бал самса", "онигири", "нори",
            "prime kitchen", "hardee", "самса", "шаурма", "pizza", "пицц"
        ]) {
            return .cafes
        }

        // 9) Electronics, tech, online retail
        if containsAny(text, [
            "cyberland", "apple city", "mobileprofi", "arduparts",
            "blisstay", "rosana", "arnatop", "smarttrade", "qpick",
            "alim store", "delta_", "star_shop", "v-com", "edera",
            "тини той", "триумф"
        ]) {
            return .shopping
        }

        // Unverified AI/legacy memories are a fallback, not a veto over evidence.
        if let hint = LearnedCategoryRules.category(for: merchant) { return hint }

        // --- Type-based fallback rules (use the leading transaction type in details) ---

        if detailsLow.hasPrefix("purchases") {
            // The bank's purchase type also includes meals, subscriptions and
            // services. Keep an opaque merchant unresolved rather than inventing goods.
            return .other
        }

        return .other
    }

    private static func containsAny(_ text: String, _ keywords: [String]) -> Bool {
        for k in keywords where text.contains(k.lowercased()) { return true }
        return false
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }
}
