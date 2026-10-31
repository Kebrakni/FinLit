import Foundation

nonisolated struct BattleParticipant: Codable {
    var id: String = UUID().uuidString
    var name: String
    var savedAmount: Double
    var targetAmount: Double
    var joinedAt: Date

    var progress: Double {
        guard targetAmount.isFinite, savedAmount.isFinite, targetAmount > 0 else { return 0 }
        return min(max(savedAmount / targetAmount, 0), 1.0)
    }
}

// MARK: - FirebaseBattleRoom (Firestore model)

nonisolated struct FirebaseBattleRoom {
    let id: String               // documentID = 6-символьный код
    let hostId: String
    let goalAmount: Double
    var members: [[String: Any]] // [{uid, name, saved, target, updatedAt}]

    static func fromDict(_ id: String, _ d: [String: Any]) -> FirebaseBattleRoom? {
        guard let host = d["hostId"] as? String,
              let goal = number(d["goalAmount"]),
              goal > 0, let members = d["members"] as? [[String: Any]] else { return nil }
        return FirebaseBattleRoom(id: id, hostId: host, goalAmount: goal, members: members)
    }

    func toParticipants() -> [BattleParticipant] {
        members.compactMap { m in
            guard let uid  = m["uid"]   as? String,
                  let name = m["name"]  as? String,
                  let saved = Self.number(m["saved"])
            else { return nil }
            // Older rooms did not store personal targets. Their room goal is a
            // safe fallback until each member opens the updated app.
            let personalTarget = Self.number(m["target"]) ?? goalAmount
            return BattleParticipant(
                id: uid,
                name: name,
                savedAmount: saved,
                targetAmount: max(personalTarget, 1),
                joinedAt: m["joinedAt"] as? Date ?? .distantPast
            )
        }.sorted {
            if abs($0.progress - $1.progress) > 0.0001 {
                return $0.progress > $1.progress
            }
            return $0.savedAmount == $1.savedAmount ? $0.id < $1.id : $0.savedAmount > $1.savedAmount
        }
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? Double, value.isFinite { return value }
        if let value = value as? NSNumber, value.doubleValue.isFinite { return value.doubleValue }
        return nil
    }
}

nonisolated enum BattleMembership {
    static func upsert(_ member: [String: Any], into members: [[String: Any]]) -> [[String: Any]] {
        guard let uid = member["uid"] as? String, !uid.isEmpty else { return members }
        var merged = members.first { $0["uid"] as? String == uid } ?? [:]
        merged.merge(member) { _, new in new }
        return members.filter { $0["uid"] as? String != uid } + [merged]
    }

    static func removing(_ uid: String, from members: [[String: Any]]) -> [[String: Any]] {
        members.filter { $0["uid"] as? String != uid }
    }
}
