import Foundation

private final class AIProtocol: URLProtocol, @unchecked Sendable {
    static var handler: ((URLRequest, Int) throws -> (Int, Data))!
    static var calls = 0
    private static let lock = NSLock()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let result = try Self.lock.withLock { () throws -> (Int, Data) in
                Self.calls += 1
                return try Self.handler(request, Self.calls)
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: result.0, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: result.1)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@main
struct AIClientChecks {
    static func main() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AIProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let client = OpenRouterCategorizer(session: session, chatTokenProvider: { "test-token" }, consentProvider: { true })
        let rows = (0..<250).map { index in
            Transaction(id: String(index), date: Date(), amount: -100, merchant: "Opaque", details: "Purchases Opaque", category: .other)
        }
        var identityCalls = 0
        let localOnly = OpenRouterCategorizer(session: session, chatTokenProvider: { identityCalls += 1; return "must-not-be-used" }, consentProvider: { false })
        AIProtocol.calls = 0
        AIProtocol.handler = { _, _ in preconditionFailure("No financial HTTP request without explicit consent") }
        func denied(_ work: () async throws -> Void) async {
            do { try await work(); preconditionFailure("Expected consent refusal") }
            catch { guard case OpenRouterCategorizer.APIError.aiConsentRequired = error else { preconditionFailure("Wrong refusal error") } }
        }
        await denied { _ = try await localOnly.categorize([rows[0]]) }
        await denied { _ = try await localOnly.auditCategories([rows[0]], onBatch: { _ in preconditionFailure() }) }
        await denied { _ = try await localOnly.generateWeeklyMissions(transactions: [rows[0]], goal: Goal(title: "Test", targetAmount: 1000, savedAmount: 0, deadline: nil)) }
        await denied { _ = try await localOnly.review(message: "Проверь категорию этой операции", history: [], transactions: [rows[0]]) }
        await denied { _ = try await localOnly.chatUsage() }
        let localHelp = try await localOnly.review(message: "Что ты умеешь", history: [], transactions: [])
        precondition(!localHelp.reply.isEmpty && AIProtocol.calls == 0 && identityCalls == 0)
        AIProtocol.handler = { _, _ in (429, Data(#"{"error":"Временный лимит"}"#.utf8)) }
        do { _ = try await client.categorize(rows); preconditionFailure("Expected 429") }
        catch { precondition(error.localizedDescription == "Временный лимит") }
        precondition(AIProtocol.calls == 1, "Do not send every annual-statement batch after rate limiting")
        for status in [401, 403, 502, 503, 504] {
            AIProtocol.calls = 0
            AIProtocol.handler = { _, _ in (status, Data(#"{"error":"Unavailable"}"#.utf8)) }
            do { _ = try await client.categorize(rows); preconditionFailure("Expected upstream error") } catch {}
            precondition(AIProtocol.calls == 1, "Do not repeat all batches after authentication or provider failure")
        }

        AIProtocol.calls = 0
        AIProtocol.handler = { request, count in
            if count == 2 { return (429, Data(#"{"error":"Limit"}"#.utf8)) }
            var data = request.httpBody ?? Data()
            if let stream = request.httpBodyStream, data.isEmpty {
                stream.open()
                defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while true {
                    let read = stream.read(&buffer, maxLength: buffer.count)
                    if read <= 0 { break }
                    data.append(contentsOf: buffer.prefix(read))
                }
            }
            let body = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            let input = body["transactions"] as! [[String: Any]]
            let categories = input.map { ["id": $0["id"] as! String, "category": "food"] }
            return (200, try JSONSerialization.data(withJSONObject: ["categories": categories]))
        }
        let partial = try await client.categorize(rows)
        precondition(partial.count == 80 && AIProtocol.calls == 2, "Keep completed batches and stop failed network work")

        AIProtocol.calls = 0
        AIProtocol.handler = { _, _ in throw URLError(.timedOut) }
        do { _ = try await client.categorize(rows); preconditionFailure("Expected timeout") } catch {}
        precondition(AIProtocol.calls == 1)
        AIProtocol.calls = 0
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await client.categorize(rows)
        }
        do { _ = try await cancelled.value; preconditionFailure("Expected cancellation") }
        catch { precondition(error is CancellationError) }
        precondition(AIProtocol.calls == 0)
        AIProtocol.calls = 0
        var audited: [CategoryAuditAssessment] = []
        AIProtocol.handler = { request, count in
            precondition(request.url!.path.hasSuffix("/api/category-audit"))
            if count == 2 { return (429, Data(#"{"error":"Limit"}"#.utf8)) }
            let assessments = (0..<40).map { index -> [String: Any] in
                ["id": String(index), "category": "cafes", "needsReview": false, "reason": "Кафе", "amount": 999999]
            }
            return (200, try JSONSerialization.data(withJSONObject: ["assessments": assessments]))
        }
        let audit = try await client.auditCategories(Array(rows.prefix(85)), onBatch: { audited.append(contentsOf: $0) })
        precondition(audit.checkedCount == 40 && audit.errorMessage == "Limit" && AIProtocol.calls == 2)
        precondition(audited.count == 40 && audited.allSatisfy { $0.snapshot.amount == -100 && $0.needsReview }, "Changed categories always require confirmation; model amounts are ignored")
        AIProtocol.calls = 0
        AIProtocol.handler = { _, _ in
            (200, Data(#"{"assessments":[{"id":"invented","category":"cafes","needsReview":false,"reason":""}]}"#.utf8))
        }
        do {
            _ = try await client.auditCategories(Array(rows.prefix(1)), onBatch: { _ in preconditionFailure("Must not mark fabricated operations as checked") })
            preconditionFailure("Expected incomplete response error")
        } catch { precondition(error is OpenRouterCategorizer.APIError) }
        AIProtocol.handler = { request, _ in
            precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
            return (429, Data(#"{"error":"Дневной лимит исчерпан","code":"DAILY_CHAT_LIMIT"}"#.utf8))
        }
        do {
            _ = try await client.review(message: "Проверь категорию этой операции", history: [], transactions: [rows[0]])
            preconditionFailure("Expected daily limit error")
        } catch {
            guard case OpenRouterCategorizer.APIError.dailyChatLimit = error else { preconditionFailure("Daily quota must be distinguished from provider rate limits") }
        }
        AIProtocol.handler = { request, _ in
            precondition(request.url!.path.hasSuffix("/api/chat-usage"))
            precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
            return (200, Data(#"{"limit":100000,"usedTokens":1500,"reservedTokens":0,"remainingTokens":98500,"resetsAt":"2026-11-17T19:00:00Z"}"#.utf8))
        }
        let usage = try await client.chatUsage()
        precondition(usage.remainingTokens == 98500 && usage.limit == 100000)
        var consent = true
        let revocable = OpenRouterCategorizer(session: session, chatTokenProvider: { "test-token" }, consentProvider: { consent })
        AIProtocol.calls = 0
        AIProtocol.handler = { request, _ in
            precondition(request.value(forHTTPHeaderField: "X-Tengely-AI-Consent") == AIPrivacyPreferences.version)
            let categories = (0..<80).map { ["id": String($0), "category": "food"] }
            return (200, try JSONSerialization.data(withJSONObject: ["categories": categories]))
        }
        let stopped = try await revocable.categorize(rows, progress: { _, _ in consent = false })
        precondition(stopped.count == 80 && AIProtocol.calls == 1, "Revocation must stop later statement batches")
        print("PASS: client quota identity/status/error, 429/offline short-circuit, partial batch retention, readable errors, cancellation; no real HTTP")
    }
}
