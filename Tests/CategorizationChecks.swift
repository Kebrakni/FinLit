import Foundation

private final class MemoryDefaults: UserDefaults, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Any] = [:]
    override func dictionary(forKey key: String) -> [String: Any]? { lock.withLock { values[key] as? [String: Any] } }
    override func set(_ value: Any?, forKey key: String) { lock.withLock { values[key] = value } }
}

@main
struct CategorizationChecks {
    struct Fixture: Decodable {
        let name: String
        let merchant: String
        let details: String
        let aiCategory: String?
        let manualCategory: String?
        let expected: String
    }

    static func main() throws {
        let path = CommandLine.arguments.dropFirst().first ?? "Tests/categorization-cases.json"
        let cases = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        for fixture in cases {
            let result = Categorizer.validatedCategory(
                merchant: fixture.merchant, details: fixture.details,
                aiCategory: fixture.aiCategory.flatMap(TxCategory.init(aiCode:)),
                manualCategory: fixture.manualCategory.flatMap(TxCategory.init(aiCode:))
            ) ?? Categorizer.categorize(merchant: fixture.merchant, details: fixture.details)
            precondition(result.aiCode == fixture.expected, "\(fixture.name): got \(result.aiCode), expected \(fixture.expected)")
        }
        precondition(Categorizer.categorize(merchant: "UNKNOWN 12345", details: "Purchases UNKNOWN 12345") == .other)
        precondition(Categorizer.categorize(merchant: "DODOPIZZA.KZ", details: "Purchases DODOPIZZA.KZ") == .cafes)
        precondition(Categorizer.categorize(merchant: "Example SUBCR", details: "Purchases Example SUBCR") == .subscriptions)

        let defaults = MemoryDefaults()
        LearnedCategoryRules.learn(merchant: "Dodo Pizza", category: .shopping, source: .aiSuggestion, defaults: defaults)
        precondition(LearnedCategoryRules.category(for: "Dodo Pizza", defaults: defaults) == .shopping)
        precondition(LearnedCategoryRules.manualCategory(for: "Dodo Pizza", defaults: defaults) == nil,
                     "An AI suggestion must not acquire the priority of a manual choice")
        precondition(Categorizer.validatedCategory(merchant: "Dodo Pizza", details: "Purchases Dodo Pizza", aiCategory: .shopping,
                                                   manualCategory: LearnedCategoryRules.manualCategory(for: "Dodo Pizza", defaults: defaults)) == .cafes)
        LearnedCategoryRules.learn(merchant: "Dodo Pizza", category: .education, defaults: defaults)
        precondition(LearnedCategoryRules.manualCategory(for: "DODO-PIZZA", defaults: defaults) == .education)
        precondition(LearnedCategoryRules.category(for: "Dodo Pizza", defaults: defaults) == .education)
        defaults.set(["legacy merchant": "shopping"], forKey: "learned_merchant_categories_v1")
        precondition(LearnedCategoryRules.category(for: "Legacy Merchant", defaults: defaults) == .shopping)
        precondition(LearnedCategoryRules.manualCategory(for: "Legacy Merchant", defaults: defaults) == nil)
        print("PASS: \(cases.count) shared categorization cases, local fallbacks, manual/AI provenance, legacy hints")
    }
}
