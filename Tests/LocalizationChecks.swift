import Foundation

@main struct LocalizationChecks {
    static func main() throws {
        let suite = "tengely.localization.checks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = LanguagePreferences(defaults: defaults)
        precondition(preferences.language == .russian)
        preferences.language = .english
        precondition(LanguagePreferences(defaults: defaults).language == .english)
        defaults.set("unknown", forKey: "tengely.language")
        precondition(preferences.language == .russian)
        let previous = UserDefaults.standard.object(forKey: "tengely.language")
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: "tengely.language") }
            else { UserDefaults.standard.removeObject(forKey: "tengely.language") }
        }
        var dictionaries: [[String: String]] = []
        for language in AppLanguage.allCases {
            let data = try Data(contentsOf: URL(fileURLWithPath: "FinLit/\(language.rawValue).lproj/Localizable.strings"))
            dictionaries.append(try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: String])
        }
        precondition(Set(dictionaries[0].keys) == Set(dictionaries[1].keys))
        let tokens = try NSRegularExpression(pattern: #"\{\d+\}"#)
        func placeholders(_ value: String) -> [String] {
            tokens.matches(in: value, range: NSRange(value.startIndex..., in: value)).map { (value as NSString).substring(with: $0.range) }.sorted()
        }
        for (key, translation) in dictionaries[1] {
            precondition(placeholders(key) == placeholders(translation), "Missing interpolation: \(key)")
            precondition(!translation.isEmpty)
        }
        precondition(L10n.format("{1}, {0}!", arguments: ["{1}", "Hello"]) == "Hello, {1}!")
        LanguagePreferences().language = .english
        precondition(TxCategory.cafes.displayName == "Dining")
        precondition(TxCategory.cafes.rawValue == "Кафе/еда")
        let encoded = try JSONEncoder().encode(TxCategory.subscriptions)
        let decoded = try JSONDecoder().decode(TxCategory.self, from: encoded)
        precondition(decoded == .subscriptions)
        precondition(L10n.privacyURL("https://example.com/privacy") == "https://example.com/privacy")
        precondition(L10n.text("До этапа «{0}» осталось {1}", "Halfway", "500 ₸") == "500 ₸ to go until “Halfway”")
        let mission = WeeklyMission(title: "test", detail: "test", kind: .saveAmount, target: 1000)
        let manager = GamificationManager(defaults: defaults)
        let goal = Goal(title: "Test", targetAmount: 1000, savedAmount: 0, deadline: nil)
        precondition(mission.localizedTitle == "Step toward your goal")
        precondition(manager.snapshot(transactions: [], goal: goal).achievements.first?.title == "First statement")
        LanguagePreferences().language = .russian
        precondition(TxCategory.cafes.displayName == "Кафе/еда")
        precondition(mission.localizedTitle == "Шаг к цели")
        precondition(manager.snapshot(transactions: [], goal: goal).achievements.first?.title == "Первая выписка")
        precondition(L10n.privacyURL("https://example.com/privacy") == "https://example.com/privacy/ru")
        print("PASS: language persistence, resource coverage, placeholders, live RU/EN switching, stable saved categories and missions")
    }
}
