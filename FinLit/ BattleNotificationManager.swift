// BattleNotificationManager.swift
// Уведомления: напоминает участникам баттла загрузить еженедельную выписку

import Foundation
import UserNotifications

final class BattleNotificationManager {

    static let shared = BattleNotificationManager()
    private init() {}

    // ID уведомлений чтобы можно было отменить/перепланировать
    private let weeklyReminderID = "battle_weekly_pdf_reminder"
    private let mondayMorningID  = "battle_monday_morning"

    // MARK: - Запросить разрешение (вызвать при входе в баттл-комнату)

    func requestPermissionAndSchedule() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                self.scheduleWeeklyReminders()
            }
        }
    }

    // MARK: - Запланировать уведомления

    func scheduleWeeklyReminders() {
        let center = UNUserNotificationCenter.current()

        // Сначала убираем старые
        center.removePendingNotificationRequests(withIdentifiers: [
            weeklyReminderID, mondayMorningID
        ])

        // 1) Каждое воскресенье в 19:00 — напоминание загрузить выписку
        scheduleWeekly(
            id: weeklyReminderID,
            weekday: 1,
            hour: 19,
            minute: 0,
            title: L10n.text("Битва накоплений"),
            body: L10n.text("Загрузи выписку за эту неделю, чтобы обновить счёт в баттле!")
        )

        // 2) Каждый понедельник в 9:00 — если кто-то ещё не загрузил
        scheduleWeekly(
            id: mondayMorningID,
            weekday: 2,
            hour: 9,
            minute: 0,
            title: L10n.text("Не забудь про баттл"),
            body: L10n.text("Новая неделя — новая выписка! Открой Аналитику в Tengely и загрузи выписку по карте на английском в формате PDF.")
        )
    }

    // MARK: - Отменить все уведомления (при выходе из комнаты)

    func cancelAllReminders() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [weeklyReminderID, mondayMorningID]
        )
    }

    func refreshLanguageIfScheduled() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { [weak self] requests in
            guard let self, requests.contains(where: { $0.identifier == self.weeklyReminderID || $0.identifier == self.mondayMorningID }) else { return }
            DispatchQueue.main.async { self.scheduleWeeklyReminders() }
        }
    }

    // MARK: - Отправить немедленное уведомление (когда соперник обновил счёт)

    func notifyOpponentUpdated(opponentName: String, newAmount: Double) {
        let f = NumberFormatter()
        f.locale = L10n.locale
        f.numberStyle = .decimal
        f.maximumFractionDigits = 2
        let amountStr = f.string(from: NSNumber(value: abs(newAmount))) ?? "0"
        let sign = newAmount >= 0 ? "+" : "-"

        sendImmediate(
            id: "opponent_update_\(opponentName)_\(Int(Date().timeIntervalSince1970))",
            title: L10n.text("{0} обновил(а) счёт!", String(describing: opponentName)),
            body: L10n.text("Теперь у {0}: {1}{2} ₸. Не отставай!", String(describing: opponentName), String(describing: sign), String(describing: amountStr))
        )
    }

    // MARK: - Private helpers

    private func scheduleWeekly(id: String, weekday: Int, hour: Int, minute: Int,
                                 title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = .default

        var components = DateComponents()
        components.weekday = weekday
        components.hour    = hour
        components.minute  = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error { print("Notification schedule error: \(error)") }
        }
    }

    private func sendImmediate(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}
