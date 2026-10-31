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
        let client = OpenRouterCategorizer(session: session)
        let rows = (0..<250).map { index in
            Transaction(id: String(index), date: Date(), amount: -100, merchant: "Opaque", details: "Purchases Opaque", category: .other)
        }
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
        print("PASS: client 429/offline short-circuit, partial batch retention, readable errors, cancellation; no real HTTP")
    }
}
