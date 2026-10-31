//
//  Categorizer.swift
//  FinLit
//

import Foundation

nonisolated final class Categorizer {

    static func categorize(merchant: String, details: String) -> TxCategory {
        let text = (merchant + " " + details).lowercased()
        let detailsLow = details.lowercased()

        // A confirmed manual/AI correction has priority over generic keyword
        // rules. Rules are stored only for sufficiently specific merchant names.
        if let learned = LearnedCategoryRules.category(for: merchant) {
            return learned
        }

        // 0) Internal transfers: Kaspi Deposit, ATM deposits, Kaspi Pay internal
        if containsAny(text, [
            "kaspi deposit", "пополнение депозита", "депозит",
            "from my current account kaspi pay",
            "at kaspi atm", "in the kaspi terminal"
        ]) {
            return .internalTransfers
        }

        // 1) Loan / credit payments (Kaspi Red, Kaspi Credit)
        if containsAny(text, [
            "pay for kaspi red", "pay for kaspi credit",
            "kaspi red", "kaspi credit"
        ]) {
            return .loans
        }

        // A positive correction created by card currency conversion is not a purchase.
        if containsAny(text, ["foreign exchange difference", "курсовая разница"]) {
            return .other
        }

        // The operation type comes from the bank statement and is more reliable
        // than a merchant-like word in the description. Never let a recipient
        // name turn a transfer into a purchase.
        if detailsLow.hasPrefix("withdrawals") {
            return .cashWithdrawals
        }

        if detailsLow.hasPrefix("transfers") || detailsLow.hasPrefix("replenishment") {
            return .transfers
        }

        // 2) Taxes, fines, government fees
        if containsAny(text, [
            "штраф", "налог", "tax", "fine", "penalty", "фискал"
        ]) {
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
            "prime kitchen", "hardee", "самса", "шаурма"
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

        // --- Type-based fallback rules (use the leading transaction type in details) ---

        if detailsLow.hasPrefix("purchases") {
            // Unknown purchase merchant → shopping
            return .shopping
        }

        return .other
    }

    private static func containsAny(_ text: String, _ keywords: [String]) -> Bool {
        for k in keywords where text.contains(k.lowercased()) { return true }
        return false
    }
}
