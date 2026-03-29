//
//  Categorizer.swift
//  FinLit
//
//  Created by Arnur Inkarbek on 01.03.2026.
//


import Foundation

final class Categorizer {

    static func categorize(merchant: String, details: String) -> TxCategory {
        let type = merchant.lowercased()
        let text = (merchant + " " + details).lowercased()

        // 0) ДЕПОЗИТЫ / НАКОПЛЕНИЯ (самое важное под твой PDF)
        // примеры у тебя: "From Kaspi Deposit", "To Kaspi Deposit", "Отбасы банк. Пополнение депозита"
        if containsAny(text, [
            "kaspi deposit",
            "from kaspi deposit",
            "to kaspi deposit",
            "отбасы банк. пополнение депозита",
            "пополнение депозита",
            "deposit", "депозит", "накоп", "savings"
        ]) {
            return .internalTransfers
        }

        // 1) Комиссии (Others)
        if containsAny(text, ["commission for transfer of other banks", "комис"]) {
            return .utilities
        }

        // 2) Подписки
        if containsAny(text, ["google *play", "apple.com", "spotify", "netflix", "youtube premium", "subscription"]) {
            return .subscriptions
        }

        // 3) Транспорт
        if containsAny(text, ["avtobys", "onay", "yandex.go", "uber", "taxi", "такси"]) {
            return .transport
        }

        // 4) Связь
        if containsAny(text, ["tele2", "beeline", "kcell", "telecom", "қазақтелеком"]) {
            return .utilities
        }

        // 5) Продукты / супермаркеты
        if containsAny(text, ["magnum", "small", "my mart", "market", "grocery", "супермаркет"]) {
            return .food
        }

        // 6) Еда/доставка
        if containsAny(text, ["wolt", "yandex.eda", "kfc", "popeyes", "starbucks", "cafe", "coffee"]) {
            return .cafes
        }

        // 7) Переводы между людьми / карты
        if type == "transfers" || containsAny(text, ["to card", "p2p", "card2card", "перевод"]) {
            return .transfers
        }

        return .other
    }

    private static func containsAny(_ text: String, _ keywords: [String]) -> Bool {
        for k in keywords where text.contains(k.lowercased()) { return true }
        return false
    }
}
