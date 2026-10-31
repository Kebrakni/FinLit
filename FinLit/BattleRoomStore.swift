import Foundation
import FirebaseFirestore

/// Every membership mutation reads and writes within a Firestore transaction.
/// No caller sends a stale copy of the entire room's members array.
final class BattleRoomStore {
    private let db: Firestore
    init(db: Firestore) { self.db = db }

    func enter(code: String, member: [String: Any], creating: Bool, previousCode: String?, completion: @escaping (Error?) -> Void) {
        let ref = db.collection("battleRooms").document(code)
        let previous = previousCode.flatMap { $0 == code ? nil : db.collection("battleRooms").document($0) }
        db.runTransaction({ transaction, errorPointer in
            do {
                let room = try transaction.getDocument(ref)
                let oldRoom = try previous.map { try transaction.getDocument($0) }
                if creating && room.exists { throw Self.failure("Код комнаты уже занят. Попробуйте создать комнату ещё раз.") }
                if !creating && !room.exists { throw Self.failure("Комната с таким кодом не найдена.") }
                let members = room.data()?["members"] as? [[String: Any]] ?? []
                let next = BattleMembership.upsert(member, into: members)
                if creating {
                    transaction.setData([
                        "hostId": member["uid"] ?? "", "goalAmount": member["target"] ?? 1,
                        "createdAt": FieldValue.serverTimestamp(), "members": next
                    ], forDocument: ref)
                } else { transaction.updateData(["members": next], forDocument: ref) }
                if let previous, let oldRoom, oldRoom.exists, let uid = member["uid"] as? String {
                    let oldMembers = oldRoom.data()?["members"] as? [[String: Any]] ?? []
                    transaction.updateData(["members": BattleMembership.removing(uid, from: oldMembers)], forDocument: previous)
                }
                return nil
            } catch { errorPointer?.pointee = error as NSError; return nil }
        }) { _, error in completion(error) }
    }

    func update(code: String, member: [String: Any], completion: @escaping (Error?) -> Void) {
        let ref = db.collection("battleRooms").document(code)
        db.runTransaction({ transaction, errorPointer in
            do {
                let room = try transaction.getDocument(ref)
                guard room.exists, let members = room.data()?["members"] as? [[String: Any]],
                      let uid = member["uid"] as? String,
                      let old = members.first(where: { $0["uid"] as? String == uid }) else {
                    throw Self.failure("Вы больше не состоите в этой комнате. Войдите по коду повторно.")
                }
                if let oldTime = old["updatedAt"] as? Timestamp, let newTime = member["updatedAt"] as? Timestamp,
                   oldTime.dateValue() > newTime.dateValue() { return nil }
                transaction.updateData(["members": BattleMembership.upsert(member, into: members)], forDocument: ref)
                return nil
            } catch { errorPointer?.pointee = error as NSError; return nil }
        }) { _, error in completion(error) }
    }

    func leave(code: String, uid: String, completion: @escaping (Error?) -> Void) {
        let ref = db.collection("battleRooms").document(code)
        db.runTransaction({ transaction, errorPointer in
            do {
                let room = try transaction.getDocument(ref)
                if room.exists {
                    let members = room.data()?["members"] as? [[String: Any]] ?? []
                    transaction.updateData(["members": BattleMembership.removing(uid, from: members)], forDocument: ref)
                }
                return nil
            } catch { errorPointer?.pointee = error as NSError; return nil }
        }) { _, error in completion(error) }
    }

    nonisolated private static func failure(_ message: String) -> NSError {
        NSError(domain: "FinLit.Battle", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
