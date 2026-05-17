//
//  Categorizer.swift
//  FinLit
//
//  Hybrid categorizer:
//  1. Rule-based fast path (Kaspi type prefix + keywords) — синхронный, без сети
//  2. Gemini AI fallback — асинхронный, для неясных "Purchases"
//

import Foundation

// MARK: - Gemini Categorizer
 
final class GeminiCategorizer {
 
    static let shared = GeminiCategorizer()
    private init() {}
 
    private let apiKey = "AIzaSyDzJJAzThlGYF837fGCZc-Qa08S7ShSOz8"
    private let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-lite:generateContent"
 
    private var cache: [String: TxCategory] = [:]
 
    /// Одиночная классификация (не используется в основном флоу, но пусть будет)
    func classify(merchant: String, details: String, completion: @escaping (TxCategory) -> Void) {
        let cacheKey = "\(merchant)|\(details)"
        if let cached = cache[cacheKey] {
            DispatchQueue.main.async { completion(cached) }
            return
        }
 
        let categories = TxCategory.allCases.map { $0.rawValue }.joined(separator: ", ")
        let prompt = """
        Ты помощник по категоризации банковских транзакций для казахстанского пользователя.
        Транзакция:
        - Мерчант: \(merchant)
        - Детали: \(details)
        Доступные категории: \(categories)
        Ответь ТОЛЬКО одним словом/фразой — точным названием категории из списка выше.
        Никаких объяснений, никакого дополнительного текста.
        """
 
        let body: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": ["temperature": 0, "maxOutputTokens": 20]
        ]
 
        guard let url = URL(string: "\(endpoint)?key=\(apiKey)"),
              let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            DispatchQueue.main.async { completion(.other) }
            return
        }
 
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        request.timeoutInterval = 8
 
        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self, let data, error == nil else {
                DispatchQueue.main.async { completion(.other) }
                return
            }
            let category = self.parseGeminiResponse(data: data)
            self.cache[cacheKey] = category
            DispatchQueue.main.async { completion(category) }
        }.resume()
    }
 
    /// Пакетная классификация — все транзакции одним запросом
    func classifyBatch(
        transactions: [(merchant: String, details: String)],
        completion: @escaping ([TxCategory]) -> Void
    ) {
        print("📤 classifyBatch вызван, транзакций: \(transactions.count)")
        guard !transactions.isEmpty else {
            DispatchQueue.main.async { completion([]) }
            return
        }
 
        let categoryList = TxCategory.allCases.map { $0.rawValue }.joined(separator: ", ")
 
        let txLines = transactions.enumerated().map { idx, tx in
            "\(idx + 1). Мерчант: \(tx.merchant) | Детали: \(tx.details)"
        }.joined(separator: "\n")
 
        let prompt = "Ты помощник по категоризации банковских транзакций для казахстанского пользователя.\n\nДоступные категории: \(categoryList)\n\nКлассифицируй каждую транзакцию. Ответь ТОЛЬКО в формате JSON-массива строк, где каждый элемент — точное название категории из списка выше. Количество элементов должно строго совпадать с количеством транзакций. Пример ответа: [\"Продукты\", \"Транспорт\", \"Переводы\"]\n\nТранзакции:\n\(txLines)"
        let body: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": ["temperature": 0, "maxOutputTokens": 1000]
        ]
 
        guard let url = URL(string: "\(endpoint)?key=\(apiKey)"),
              let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            let fallback = Array(repeating: TxCategory.other, count: transactions.count)
            DispatchQueue.main.async { completion(fallback) }
            return
        }
 
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        request.timeoutInterval = 15
 
        let count = transactions.count
 
        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            print("📥 Ответ от Gemini: error=\(String(describing: error)), data=\(data?.count ?? 0) bytes")
            if let data, let raw = String(data: data, encoding: .utf8) {
                print("📥 Raw JSON: \(raw)")
            }
            guard let self, let data, error == nil else {
                let fallback = Array(repeating: TxCategory.other, count: count)
                DispatchQueue.main.async { completion(fallback) }
                return
            }
            let categories = self.parseGeminiBatchResponse(data: data, expectedCount: count)
            DispatchQueue.main.async { completion(categories) }
        }.resume()
    }
 
    // MARK: - Response parsing
 
    private func parseGeminiResponse(data: Data) -> TxCategory {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            return .other
        }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return TxCategory.allCases.first { $0.rawValue == cleaned } ?? .other
    }
 
    private func parseGeminiBatchResponse(data: Data, expectedCount: Int) -> [TxCategory] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            print("❌ Не удалось распарсить ответ Gemini")
            return Array(repeating: .other, count: expectedCount)
        }
 
        print("🤖 Gemini raw response: \(text)")
        print("📋 Available categories: \(TxCategory.allCases.map { $0.rawValue })")
 
        let cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
 
        guard let arrayData = cleaned.data(using: .utf8),
              let rawArray = try? JSONSerialization.jsonObject(with: arrayData) as? [String] else {
            print("❌ Не удалось распарсить JSON массив из ответа: \(cleaned)")
            return Array(repeating: .other, count: expectedCount)
        }
 
        print("✅ Gemini вернул \(rawArray.count) категорий: \(rawArray)")
 
        var result = rawArray.map { str -> TxCategory in
            TxCategory.allCases.first { $0.rawValue == str } ?? .other
        }
 
        if result.count < expectedCount {
            result += Array(repeating: .other, count: expectedCount - result.count)
        }
        return Array(result.prefix(expectedCount))
    }
}
 
// MARK: - Categorizer (rule-based, синхронный)

final class Categorizer {

    // KaspiPDFParser always builds fullDetails as "KaspiType MerchantName"
    // e.g. "Transfers Дархан Е.", "Replenishment From Kaspi Deposit", "Purchases Magnum"

    /// Синхронная классификация по правилам.
    /// Используй этот метод везде где раньше был Categorizer.categorize(...)
    /// Для явных типов (Transfers, Replenishment, Others, Withdrawals) — ответ мгновенный.
    /// Для "Purchases" с известным мерчантом — тоже мгновенный.
    /// Для "Purchases" с неизвестным мерчантом — возвращает .other,
    /// и нужно дополнительно вызвать GeminiCategorizer.shared.classify(...)
    static func categorize(merchant: String, details: String) -> TxCategory {
        let text       = (merchant + " " + details).lowercased()
        let detailsLow = details.lowercased()

        // -- Kaspi type prefix --
        let kaspiType: String
        if      detailsLow.hasPrefix("purchases")    { kaspiType = "purchases"    }
        else if detailsLow.hasPrefix("transfers")    { kaspiType = "transfers"    }
        else if detailsLow.hasPrefix("replenishment"){ kaspiType = "replenishment"}
        else if detailsLow.hasPrefix("withdrawals")  { kaspiType = "withdrawals"  }
        else if detailsLow.hasPrefix("others")       { kaspiType = "others"       }
        else                                         { kaspiType = ""             }

        // 0) Депозиты / внутренние переводы — наивысший приоритет
        if containsAny(text, [
            "deposit", "депозит", "накоп", "savings", "saving",
            "отбасы", "otbasy", "kopilka", "копилка", "вклад",
            "piggy", "safe", "fixed deposit", "term deposit"
        ]) { return .internalTransfers }

        // 1) Переводы
        if kaspiType == "transfers"     { return .transfers }
        if kaspiType == "replenishment" { return .transfers }

        // 2) Банковские сборы
        if kaspiType == "others" || containsAny(text, [
            "commission", "комис", "service fee", "annual fee",
            "monthly fee", "bank fee", "bank charge", "processing fee",
            "штраф", "пеня", "late fee"
        ]) { return .utilities }

        // 3) Подписки / digital
        if containsAny(text, [
            "apple.com", "itunes", "google *play", "play store",
            "spotify", "netflix", "youtube", "subscription", "bill", "membership",
            "quillbot", "classno", "kino", "steam", "steamgames", "cybershoke",
            "chatgpt", "openai", "notion", "icloud", "discord", "twitch", "patreon",
            "yandex plus", "ivi", "okko", "megogo"
        ]) { return .subscriptions }

        // 4) Транспорт
        if containsAny(text, [
            "metro", "метро", "subway", "bus", "автобус", "tram",
            "rides", "fare", "ticket rail", "railway", "поезд", "avtobys", "onay",
            "yandex.go", "uber", "bolt", "taxi", "такси", "indriver",
            "sharing", "carsharing", "fuel", "petrol", "бензин", "азс", "заправка",
            "parking", "парковка", "airport", "авиабилет", "air astana", "flyarystan"
        ]) { return .transport }

        // 5) Коммуналка / связь
        if containsAny(text, [
            "tele2", "beeline", "kcell", "activ", "altel",
            "telecom", "қазақтелеком", "kazakhtelecom",
            "internet", "wifi", "mobile plan", "utility", "коммун", "жкх",
            "electricity", "свет", "water", "вода", "газ", "отопление", "rent", "аренда"
        ]) { return .utilities }

        // 6) Продукты
        if containsAny(text, [
            "market", "магазин", "супермаркет", "shop", "store",
            "grocery", "superma", "hypermarket",
            "magnum", "small", "galmart", "spar",
            "береке", "фэмэли", "вкусмарт", "choco",
            "bakery", "хлеб", "мясо", "рыба", "продукты"
        ]) { return .food }

        // 7) Кафе / рестораны / доставка
        if containsAny(text, [
            "cafe", "coffee", "coffeeshop", "restaurant", "ресторан",
            "bar", "pub", "lounge", "pizza", "dodo", "dominos",
            "burger", "kfc", "mcdonalds", "hardees", "popeyes", "bbq", "grill",
            "wolt", "glovo", "yandex.eda", "доставка", "delivery",
            "starbucks", "costa", "sushi", "roll",
            "doner", "shawarma", "шаурма", "tandir", "тандыр",
            "бауырсак", "cake", "dessert", "candy", "sweet",
            "чайхана", "столовая", "fast food", "canteen"
        ]) { return .cafes }

        // 8) Здоровье
        if containsAny(text, [
            "аптека", "pharmacy", "apteka", "дəріхана",
            "dental", "dent", "clinic", "hospital", "медицин", "doctor", "врач", "лечени"
        ]) { return .health }

        // 9) Образование
        if containsAny(text, [
            "ниш", "nis", "школа", "school", "university",
            "курс", "course", "coursera", "udemy", "duolingo", "образован", "учеб"
        ]) { return .education }

        // 10) Развлечения
        if containsAny(text, [
            "kino", "cinema", "кино", "театр", "concert",
            "игр", "game", "билет", "ticket", "event"
        ]) { return .entertainment }

        // 11) Шопинг
        if containsAny(text, [
            "technodom", "dns", "спортмастер", "meloman",
            "sulpak", "alser", "samsung", "apple store",
            "mega", "silk", "одежда", "clothes", "fashion"
        ]) { return .shopping }

        // Не распознано — кандидат для Gemini
        return .other
    }

    /// Нужно ли отправлять транзакцию в Gemini?
    /// Только "Purchases" которые не распознаны правилами.
    static func needsAIClassification(merchant: String, details: String) -> Bool {
        let detailsLow = details.lowercased()
        let isPurchase = detailsLow.hasPrefix("purchases") || detailsLow.isEmpty
        return isPurchase && categorize(merchant: merchant, details: details) == .other
    }

    private static func containsAny(_ text: String, _ keywords: [String]) -> Bool {
        keywords.contains { text.contains($0.lowercased()) }
    }
}

