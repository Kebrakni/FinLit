import Foundation

nonisolated enum LearnedCategoryRules {
    enum Source { case manual, aiSuggestion }
    private static let legacyKey = "learned_merchant_categories_v1"
    private static let manualKey = "manual_merchant_categories_v2"
    private static let suggestionKey = "suggested_merchant_categories_v2"
    private static let contextualKey = "confirmed_merchant_categories_v3"
    private static let ignoredKeys: Set<String> = [
        "kaspi", "kaspi gold", "payment", "purchase", "покупка", "перевод", "прочее", "other"
    ]

    static func manualCategory(for merchant: String, details: String? = nil, defaults: UserDefaults = .standard) -> TxCategory? {
        if let details, canLearn(normalizedMerchant(merchant)),
           let code = (defaults.dictionary(forKey: contextualKey) as? [String: String])?[contextKey(merchant, details)],
           let category = TxCategory(aiCode: code) { return category }
        return lookup(merchant, key: manualKey, defaults: defaults)
    }

    /// An explicit decision applies to the same merchant and bank operation
    /// type. A card payment must not teach us to recategorize a transfer.
    static func confirm(merchant: String, details: String, category: TxCategory, defaults: UserDefaults = .standard) {
        guard canLearn(normalizedMerchant(merchant)) else { return }
        var rules = defaults.dictionary(forKey: contextualKey) as? [String: String] ?? [:]
        rules[contextKey(merchant, details)] = category.aiCode
        defaults.set(rules, forKey: contextualKey)
    }

    private static func contextKey(_ merchant: String, _ details: String) -> String {
        let type = details.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var group = ["purchases", "transfers", "replenishment", "withdrawals", "others"].first { type.hasPrefix($0) } ?? "unknown"
        if type.contains("foreign exchange difference") || type.contains("курсовая разница") {
            group += ":exchange-adjustment"
        } else if group == "purchases", type.range(of: #"(?:^|[^\p{L}\p{N}])(?:subcr|subscr|subscription|subscriptions|recurring)(?=$|[^\p{L}])|подписк|автопродлен"#, options: .regularExpression) != nil {
            group += ":subscription"
        }
        return normalizedMerchant(merchant) + "|" + group
    }

    /// Older entries have no provenance: use them as a first-pass hint only.
    /// They must never veto fresh evidence or an AI reassessment.
    static func category(for merchant: String, defaults: UserDefaults = .standard) -> TxCategory? {
        manualCategory(for: merchant, defaults: defaults)
            ?? lookup(merchant, key: suggestionKey, defaults: defaults)
            ?? lookup(merchant, key: legacyKey, defaults: defaults)
    }

    static func learn(merchant: String, category: TxCategory, source: Source = .manual, defaults: UserDefaults = .standard) {
        let merchantKey = normalizedMerchant(merchant)
        guard canLearn(merchantKey) else { return }
        let key = source == .manual ? manualKey : suggestionKey
        var rules = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        rules[merchantKey] = category.aiCode
        defaults.set(rules, forKey: key)
    }

    private static func lookup(_ merchant: String, key: String, defaults: UserDefaults) -> TxCategory? {
        let merchantKey = normalizedMerchant(merchant)
        guard canLearn(merchantKey), let code = (defaults.dictionary(forKey: key) as? [String: String])?[merchantKey] else { return nil }
        return TxCategory(aiCode: code)
    }

    private static func canLearn(_ value: String) -> Bool { value.count >= 3 && !ignoredKeys.contains(value) }

    private static func normalizedMerchant(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ru_RU"))
            .lowercased()
            .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
