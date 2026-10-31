// battle.swift
// Полностью заменяет существующий файл.
// Добавляет Firebase-баттл: создание комнаты, вход по коду, real-time лидерборд.

import UIKit
import FirebaseFirestore

// MARK: - Model

struct BattleParticipant: Codable {
    var id: String = UUID().uuidString
    var name: String
    var savedAmount: Double
    var targetAmount: Double
    var joinedAt: Date

    var progress: Double {
        guard targetAmount > 0 else { return 0 }
        return min(max(savedAmount / targetAmount, 0), 1.0)
    }
}

// MARK: - FirebaseBattleRoom (Firestore model)

struct FirebaseBattleRoom {
    let id: String               // documentID = 6-символьный код
    let hostId: String
    let goalAmount: Double
    var members: [[String: Any]] // [{uid, name, saved, target, updatedAt}]

    static func fromDict(_ id: String, _ d: [String: Any]) -> FirebaseBattleRoom? {
        guard let host = d["hostId"] as? String,
              let goal = number(d["goalAmount"]),
              let members = d["members"] as? [[String: Any]] else { return nil }
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
                joinedAt: Date()
            )
        }.sorted {
            if abs($0.progress - $1.progress) > 0.0001 {
                return $0.progress > $1.progress
            }
            return $0.savedAmount > $1.savedAmount
        }
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }
}

// MARK: - BattleCell

final class BattleCell: UITableViewCell {

    private let cardView      = UIView()
    private let avatarView    = UIView()
    private let avatarLabel   = UILabel()
    private let rankLabel     = UILabel()
    private let nameLabel     = UILabel()
    private let amountLabel   = UILabel()
    private let progressBar   = UIProgressView(progressViewStyle: .default)
    private let progressLabel = UILabel()
    private let statusBadge   = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier); setupUI()
    }
    required init?(coder: NSCoder) { super.init(coder: coder); setupUI() }

    private func setupUI() {
        backgroundColor = .clear; selectionStyle = .none

        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.backgroundColor = FinLitTheme.surface
        cardView.layer.cornerRadius = 20
        cardView.layer.cornerCurve = .continuous
        cardView.layer.shadowColor = UIColor.black.cgColor
        cardView.layer.shadowOpacity = 0.055
        cardView.layer.shadowRadius = 10
        cardView.layer.shadowOffset = CGSize(width: 0, height: 5)

        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.layer.cornerRadius = 24; avatarView.clipsToBounds = true

        avatarLabel.translatesAutoresizingMaskIntoConstraints = false
        avatarLabel.font = .systemFont(ofSize: 18, weight: .bold)
        avatarLabel.textColor = .white; avatarLabel.textAlignment = .center

        rankLabel.translatesAutoresizingMaskIntoConstraints = false
        rankLabel.font = .systemFont(ofSize: 22); rankLabel.textAlignment = .center

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .systemFont(ofSize: 16, weight: .semibold); nameLabel.textColor = .label

        amountLabel.translatesAutoresizingMaskIntoConstraints = false
        amountLabel.font = .systemFont(ofSize: 15, weight: .bold); amountLabel.textAlignment = .right

        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.layer.cornerRadius = 3; progressBar.clipsToBounds = true
        progressBar.trackTintColor = .systemFill

        progressLabel.translatesAutoresizingMaskIntoConstraints = false
        progressLabel.font = .systemFont(ofSize: 12); progressLabel.textColor = .secondaryLabel

        statusBadge.translatesAutoresizingMaskIntoConstraints = false
        statusBadge.font = .systemFont(ofSize: 11, weight: .semibold)
        statusBadge.layer.cornerRadius = 8; statusBadge.clipsToBounds = true
        statusBadge.textAlignment = .center

        avatarView.addSubview(avatarLabel)
        cardView.addSubview(rankLabel)
        cardView.addSubview(avatarView)
        cardView.addSubview(nameLabel)
        cardView.addSubview(statusBadge)
        cardView.addSubview(amountLabel)
        cardView.addSubview(progressBar)
        cardView.addSubview(progressLabel)
        contentView.addSubview(cardView)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            rankLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 10),
            rankLabel.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            rankLabel.widthAnchor.constraint(equalToConstant: 32),

            avatarView.leadingAnchor.constraint(equalTo: rankLabel.trailingAnchor, constant: 6),
            avatarView.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 48),
            avatarView.heightAnchor.constraint(equalToConstant: 48),

            avatarLabel.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
            avatarLabel.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),

            nameLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 14),
            nameLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 10),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: amountLabel.leadingAnchor, constant: -8),

            statusBadge.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            statusBadge.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 10),
            statusBadge.heightAnchor.constraint(equalToConstant: 18),
            statusBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 60),

            amountLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 14),
            amountLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -14),
            amountLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 100),

            progressBar.topAnchor.constraint(equalTo: statusBadge.bottomAnchor, constant: 8),
            progressBar.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 10),
            progressBar.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -14),
            progressBar.heightAnchor.constraint(equalToConstant: 6),

            progressLabel.topAnchor.constraint(equalTo: progressBar.bottomAnchor, constant: 4),
            progressLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 10),
            progressLabel.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -12),
        ])
    }

    func configure(participant: BattleParticipant, rank: Int, isMe: Bool) {
        switch rank {
        case 1:
            rankLabel.text = nil
            let img = UIImage(systemName: "medal.fill")
            let attachment = NSTextAttachment()
            attachment.image = img?.withTintColor(.systemYellow, renderingMode: .alwaysOriginal)
            attachment.bounds = CGRect(x: 0, y: -4, width: 22, height: 22)
            rankLabel.attributedText = NSAttributedString(attachment: attachment)
        case 2:
            rankLabel.text = nil
            let img = UIImage(systemName: "medal.fill")
            let attachment = NSTextAttachment()
            attachment.image = img?.withTintColor(.systemGray2, renderingMode: .alwaysOriginal)
            attachment.bounds = CGRect(x: 0, y: -4, width: 22, height: 22)
            rankLabel.attributedText = NSAttributedString(attachment: attachment)
        case 3:
            rankLabel.text = nil
            let img = UIImage(systemName: "medal.fill")
            let attachment = NSTextAttachment()
            attachment.image = img?.withTintColor(.systemOrange, renderingMode: .alwaysOriginal)
            attachment.bounds = CGRect(x: 0, y: -4, width: 22, height: 22)
            rankLabel.attributedText = NSAttributedString(attachment: attachment)
        default:
            rankLabel.attributedText = nil
            rankLabel.text = "\(rank)"
        }

        nameLabel.text = isMe ? "\(participant.name) (Ты)" : participant.name

        let initials = participant.name
            .components(separatedBy: " ")
            .compactMap { $0.first.map { String($0) } }
            .prefix(2).joined().uppercased()
        avatarLabel.text = initials.isEmpty ? "?" : initials

        let colors: [UIColor] = [.systemYellow, .systemGray2, .systemOrange, .systemBlue, .systemPurple, .systemTeal]
        avatarView.backgroundColor = colors[(rank - 1) % colors.count]

        let isNeg = participant.savedAmount < 0
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        let pct = participant.progress * 100
        amountLabel.text = String(format: "%.0f%%", pct)
        amountLabel.textColor = isMe ? FinLitTheme.accent : (isNeg ? .systemRed : .systemGreen)

        let reachedGoal = participant.progress >= 1
        let badgeSymbol = reachedGoal
            ? "checkmark.circle.fill"
            : (isNeg ? "arrow.counterclockwise" : "flag.fill")
        let badgeImg = UIImage(systemName: badgeSymbol)?.withRenderingMode(.alwaysOriginal)
            .withTintColor(reachedGoal ? FinLitTheme.accent : (isNeg ? .systemOrange : .systemGreen))
        let badgeAttachment = NSTextAttachment()
        badgeAttachment.image = badgeImg
        badgeAttachment.bounds = CGRect(x: 0, y: -3, width: 14, height: 14)
        let badgeAttr = NSMutableAttributedString(string: "  ")
        badgeAttr.append(NSAttributedString(attachment: badgeAttachment))
        let badgeText = reachedGoal ? " цель достигнута  " : (isNeg ? " начинаем заново  " : " личная цель  ")
        badgeAttr.append(NSAttributedString(string: badgeText))
        statusBadge.attributedText = badgeAttr
        let badgeColor = reachedGoal ? FinLitTheme.accent : (isNeg ? UIColor.systemOrange : .systemGreen)
        statusBadge.backgroundColor = badgeColor.withAlphaComponent(0.15)
        statusBadge.textColor = badgeColor

        progressBar.setProgress(Float(participant.progress), animated: true)
        progressBar.progressTintColor = isMe ? FinLitTheme.accent : (isNeg ? .systemRed : .systemGreen)

        let savedStr = f.string(from: NSNumber(value: max(participant.savedAmount, 0))) ?? "0"
        let targetStr = f.string(from: NSNumber(value: participant.targetAmount)) ?? "0"
        progressLabel.text = "\(savedStr) из \(targetStr) ₸"

        cardView.layer.borderWidth = isMe ? 2 : 0
        cardView.layer.borderColor = FinLitTheme.accent.cgColor
    }
}

// MARK: - BattleViewController

final class BattleViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    // MARK: State

    private var myUid: String {
        if let uid = UserDefaults.standard.string(forKey: "battle_uid") { return uid }
        let uid = UUID().uuidString
        UserDefaults.standard.set(uid, forKey: "battle_uid")
        return uid
    }

    private var myName: String {
        UserDefaults.standard.string(forKey: "battle_my_name") ?? "Я"
    }

    private var currentRoomId: String? {
        get { UserDefaults.standard.string(forKey: "battle_room_id") }
        set { UserDefaults.standard.set(newValue, forKey: "battle_room_id") }
    }

    // Участники для таблицы (из Firebase)
    private var sorted: [BattleParticipant] = []
    // Локальные участники (резерв если Firebase недоступен)
    private var localParticipants: [BattleParticipant] = []

    private var firestoreListener: ListenerRegistration?
    private lazy var db = Firestore.firestore()

    // MARK: UI

    private let tableView       = UITableView(frame: .zero, style: .plain)
    private let headerContainer = UIView()
    private let trophyLabel     = UILabel()
    private let subtitleLabel   = UILabel()
    private let myStatsCard     = UIView()
    private let myNetLabel      = UILabel()
    private let myNetTitle      = UILabel()
    private let myNetHint       = UILabel()
    private let actionButton    = UIButton(type: .system)

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Битва"
        view.backgroundColor = FinLitTheme.background
        setupNav()
        setupUI()
        loadLocalFallback()

        NotificationCenter.default.addObserver(
            self, selector: #selector(onPDFUpdated),
            name: .pdfNetSavingsUpdated, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(onPDFUpdated),
            name: GamificationManager.updatedNotification, object: nil
        )

        // Переподключиться к комнате если была
        if let roomId = currentRoomId {
            subscribeToRoom(roomId)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Обновить свою сумму в Firebase если есть комната
        pushMyAmountIfNeeded()
    }

    deinit {
        firestoreListener?.remove()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Nav

    private func setupNav() {
        let menuBtn = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            menu: battleMenu()
        )
        navigationItem.rightBarButtonItem = menuBtn
    }

    @objc private func showMenu() {
        let sheet = FinLitFormSheet(
            title: "Копить вместе интереснее",
            detail: "Создайте комнату и пригласите друзей или присоединитесь по коду. В рейтинге учитывается процент личной цели.",
            symbol: "person.2.fill", action: "Закрыть"
        )
        sheet.sheetPresentationController?.detents = [
            .custom(identifier: .init("battleActions")) { min(630, $0.maximumDetentValue) }, .large()
        ]
        sheet.loadViewIfNeeded()
        sheet.submitButton.addAction(UIAction { [weak sheet] _ in sheet?.finish() }, for: .touchUpInside)
        for (title, symbol, action) in [
            ("Создать комнату", "plus.circle.fill", { [weak self] in self?.didTapCreateRoom() }),
            ("У меня есть код", "rectangle.and.pencil.and.ellipsis", { [weak self] in self?.didTapJoinRoom() })
        ] {
            let button = UIButton(type: .system)
            var config = UIButton.Configuration.tinted()
            config.title = title
            config.image = UIImage(systemName: symbol)
            config.imagePadding = 12
            config.baseForegroundColor = FinLitTheme.accent
            config.cornerStyle = .large
            config.contentInsets = .init(top: 22, leading: 18, bottom: 22, trailing: 18)
            button.configuration = config
            button.contentHorizontalAlignment = .leading
            button.addAction(UIAction { [weak sheet] _ in sheet?.finish { action() } }, for: .touchUpInside)
            sheet.contentStack.addArrangedSubview(button)
        }
        present(sheet, animated: true)
    }

    private func battleMenu() -> UIMenu {
        UIMenu(children: [
            UIAction(title: "Создать комнату", image: UIImage(systemName: "plus.circle")) { [weak self] _ in self?.didTapCreateRoom() },
            UIAction(title: "Войти по коду", image: UIImage(systemName: "person.badge.plus")) { [weak self] _ in self?.didTapJoinRoom() },
            UIAction(title: "Моё имя", image: UIImage(systemName: "person.crop.circle")) { [weak self] _ in self?.didTapChangeName() },
            UIAction(title: "Скопировать код", image: UIImage(systemName: "doc.on.doc"), attributes: currentRoomId == nil ? .hidden : []) { [weak self] _ in
                guard let self, let code = self.currentRoomId else { return }
                UIPasteboard.general.string = code
                self.showBanner("Код скопирован")
            },
            UIAction(title: "Покинуть комнату", image: UIImage(systemName: "rectangle.portrait.and.arrow.right"), attributes: currentRoomId == nil ? [.hidden, .destructive] : .destructive) { [weak self] _ in self?.leaveRoom() }
        ])
    }

    // MARK: - UI Setup

    private func setupUI() {
        headerContainer.translatesAutoresizingMaskIntoConstraints = false

        trophyLabel.translatesAutoresizingMaskIntoConstraints = false
        let trophyImage = UIImage(systemName: "trophy.fill")
        let trophyAttachment = NSTextAttachment()
        trophyAttachment.image = trophyImage?.withTintColor(.systemYellow, renderingMode: .alwaysOriginal)
        trophyAttachment.bounds = CGRect(x: 0, y: -6, width: 44, height: 44)
        trophyLabel.attributedText = NSAttributedString(attachment: trophyAttachment)
        trophyLabel.textAlignment = .center

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = "Кто ближе к своей цели?"
        subtitleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        subtitleLabel.textAlignment = .center

        // Карточка "Мой счёт"
        myStatsCard.translatesAutoresizingMaskIntoConstraints = false
        FinLitTheme.styleCard(myStatsCard, radius: 24)

        myNetTitle.translatesAutoresizingMaskIntoConstraints = false
        myNetTitle.text = "Твой прогресс в битве"
        myNetTitle.font = .systemFont(ofSize: 13); myNetTitle.textColor = .secondaryLabel

        myNetLabel.translatesAutoresizingMaskIntoConstraints = false
        myNetLabel.font = .monospacedDigitSystemFont(ofSize: 34, weight: .bold)
        myNetLabel.adjustsFontSizeToFitWidth = true
        myNetLabel.minimumScaleFactor = 0.7
        myNetLabel.text = "Загрузи PDF →"; myNetLabel.textColor = .secondaryLabel

        myNetHint.translatesAutoresizingMaskIntoConstraints = false
        myNetHint.text = "Сравниваем процент личной цели — так честнее при разных доходах"
        myNetHint.font = .systemFont(ofSize: 11); myNetHint.textColor = .secondaryLabel
        myNetHint.numberOfLines = 2

        myStatsCard.addSubview(myNetTitle)
        myStatsCard.addSubview(myNetLabel)
        myStatsCard.addSubview(myNetHint)

        // Кнопка действия (создать/войти)
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        FinLitTheme.configurePrimaryButton(
            actionButton,
            title: "Создать или войти в комнату",
            image: "person.2.fill"
        )
        actionButton.addTarget(self, action: #selector(didTapActionButton), for: .touchUpInside)
        updateActionButton()

        headerContainer.addSubview(trophyLabel)
        headerContainer.addSubview(subtitleLabel)
        headerContainer.addSubview(myStatsCard)
        headerContainer.addSubview(actionButton)

        NSLayoutConstraint.activate([
            trophyLabel.topAnchor.constraint(equalTo: headerContainer.topAnchor, constant: 12),
            trophyLabel.centerXAnchor.constraint(equalTo: headerContainer.centerXAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: trophyLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor, constant: 16),
            subtitleLabel.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor, constant: -16),

            myStatsCard.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 12),
            myStatsCard.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor, constant: 16),
            myStatsCard.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor, constant: -16),

            myNetTitle.topAnchor.constraint(equalTo: myStatsCard.topAnchor, constant: 12),
            myNetTitle.leadingAnchor.constraint(equalTo: myStatsCard.leadingAnchor, constant: 14),

            myNetLabel.topAnchor.constraint(equalTo: myNetTitle.bottomAnchor, constant: 2),
            myNetLabel.leadingAnchor.constraint(equalTo: myStatsCard.leadingAnchor, constant: 14),
            myNetLabel.trailingAnchor.constraint(equalTo: myStatsCard.trailingAnchor, constant: -14),

            myNetHint.topAnchor.constraint(equalTo: myNetLabel.bottomAnchor, constant: 4),
            myNetHint.leadingAnchor.constraint(equalTo: myStatsCard.leadingAnchor, constant: 14),
            myNetHint.trailingAnchor.constraint(equalTo: myStatsCard.trailingAnchor, constant: -14),

            myNetHint.bottomAnchor.constraint(equalTo: myStatsCard.bottomAnchor, constant: -18),

            actionButton.topAnchor.constraint(equalTo: myStatsCard.bottomAnchor, constant: 12),
            actionButton.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor, constant: 16),
            actionButton.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor, constant: -16),
            actionButton.bottomAnchor.constraint(equalTo: headerContainer.bottomAnchor, constant: -12),
        ])

        // TableView
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self; tableView.delegate = self
        tableView.register(BattleCell.self, forCellReuseIdentifier: "BattleCell")
        tableView.separatorStyle = .none; tableView.backgroundColor = .clear

        let hdr = UILabel()
        hdr.text = "  Рейтинг по проценту личной цели"
        hdr.font = .systemFont(ofSize: 13, weight: .semibold); hdr.textColor = .secondaryLabel
        hdr.frame = CGRect(x: 0, y: 0, width: 200, height: 32)
        tableView.tableHeaderView = hdr

        view.addSubview(headerContainer); view.addSubview(tableView)

        NSLayoutConstraint.activate([
            headerContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            tableView.topAnchor.constraint(equalTo: headerContainer.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: - Firebase: Create Room

    @objc private func didTapCreateRoom() {
        let sheet = FinLitInputSheet(
            title: "Своя команда",
            detail: "У каждого своя цель. В рейтинге вы сравниваете прогресс к ней — в процентах.",
            symbol: "trophy.fill", action: "Создать комнату", fieldTitle: "Ваша цель в битве · ₸",
            placeholder: "350 000", value: String(format: "%.0f", AppStorage.shared.loadGoal().targetAmount), amount: true
        )
        sheet.onSubmit = { [weak self] sheet in
            guard let self else { return }
            guard let goal = FinLitDisplay.amount(sheet.field.input.text) else {
                sheet.showError("Укажите сумму цели больше нуля.")
                return
            }
            sheet.showError(nil)
            sheet.setLoading(true)
            sheet.view.endEditing(true)

            let roomId = self.makeRoomCode()
            let saved = AppStorage.shared.loadCombinedSavings()

            let data: [String: Any] = [
                "hostId": self.myUid,
                "goalAmount": goal,
                "createdAt": FieldValue.serverTimestamp(),
                "members": [
                    [
                        "uid": self.myUid,
                        "name": self.myName,
                        "saved": saved,
                        "target": goal,
                        "updatedAt": Timestamp(date: Date())
                    ]
                ]
            ]

            self.db.collection("battleRooms").document(roomId).setData(data) { error in
                if let error {
                    sheet.setLoading(false)
                    sheet.showError(error.localizedDescription); return
                }
                self.currentRoomId = roomId
                self.subscribeToRoom(roomId)
                self.updateActionButton()
                // Запланировать еженедельные напоминания
                BattleNotificationManager.shared.requestPermissionAndSchedule()

                // Покажем код чтобы поделиться
                sheet.finish { self.presentRoomInvite(roomId) }
            }
        }
        present(sheet, animated: true)
    }

    private func presentRoomInvite(_ code: String) {
        let sheet = FinLitFormSheet(
            title: "Команда готова", detail: "Отправьте код друзьям. Они смогут присоединиться к вашей битве через «Войти по коду».",
            symbol: "checkmark.seal.fill", action: "Скопировать код", actionSymbol: "doc.on.doc"
        )
        sheet.sheetPresentationController?.detents = [
            .custom(identifier: .init("roomInvite")) { min(580, $0.maximumDetentValue) }, .large()
        ]
        sheet.loadViewIfNeeded()
        let label = UILabel()
        label.text = code
        label.font = .monospacedSystemFont(ofSize: 38, weight: .bold)
        label.textAlignment = .center
        label.textColor = FinLitTheme.accent
        label.backgroundColor = FinLitTheme.accentSoft
        label.layer.cornerRadius = 22
        label.clipsToBounds = true
        label.heightAnchor.constraint(equalToConstant: 100).isActive = true
        sheet.contentStack.addArrangedSubview(label)
        sheet.submitButton.addAction(UIAction { [weak sheet] _ in
            UIPasteboard.general.string = code
            sheet?.finish()
        }, for: .touchUpInside)
        present(sheet, animated: true)
    }

    // MARK: - Firebase: Join Room

    @objc private func didTapJoinRoom() {
        let sheet = FinLitInputSheet(
            title: "Вместе к цели", detail: "Введите шестизначный код, которым поделился друг.",
            symbol: "person.badge.plus", action: "Присоединиться", fieldTitle: "Код комнаты", placeholder: "ABC234"
        )
        sheet.field.input.autocapitalizationType = .allCharacters
        sheet.field.input.autocorrectionType = .no
        sheet.field.input.font = .monospacedSystemFont(ofSize: 30, weight: .bold)
        sheet.onSubmit = { [weak self] sheet in
            guard let self else { return }
            let code = (sheet.field.input.text ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            guard code.count == 6, code.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
                sheet.showError("Код состоит из 6 латинских букв и цифр."); return
            }
            sheet.showError(nil)
            sheet.setLoading(true)
            sheet.view.endEditing(true)

            let ref = self.db.collection("battleRooms").document(code)
            ref.getDocument { snapshot, error in
                if let error {
                    sheet.setLoading(false)
                    sheet.showError(error.localizedDescription); return
                }
                guard let data = snapshot?.data() else {
                    sheet.setLoading(false)
                    sheet.showError("Комната с кодом «\(code)» не найдена. Проверьте код."); return
                }

                // Проверяем не в ней ли уже
                var members = data["members"] as? [[String: Any]] ?? []
                let alreadyIn = members.contains { $0["uid"] as? String == self.myUid }

                let personalGoal = AppStorage.shared.loadGoal()
                let saved = AppStorage.shared.loadCombinedSavings()
                let personalTarget = personalGoal.targetAmount

                if alreadyIn {
                    // просто обновить сумму
                    for i in members.indices where members[i]["uid"] as? String == self.myUid {
                        members[i]["saved"] = saved
                        members[i]["target"] = personalTarget
                        members[i]["updatedAt"] = Timestamp(date: Date())
                    }
                } else {
                    members.append([
                        "uid": self.myUid,
                        "name": self.myName,
                        "saved": saved,
                        "target": personalTarget,
                        "updatedAt": Timestamp(date: Date())
                    ])
                }

                ref.updateData(["members": members]) { error in
                    if let error {
                        sheet.setLoading(false)
                        sheet.showError(error.localizedDescription); return
                    }
                    self.currentRoomId = code
                    self.subscribeToRoom(code)
                    self.updateActionButton()
                    // Запланировать еженедельные напоминания
                    BattleNotificationManager.shared.requestPermissionAndSchedule()
                    sheet.finish { self.showBanner("Ты в комнате \(code)!") }
                }
            }
        }
        present(sheet, animated: true)
    }

    // MARK: - Firebase: Real-time listener

    private func subscribeToRoom(_ roomId: String) {
        firestoreListener?.remove()
        firestoreListener = db.collection("battleRooms").document(roomId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    print("Firestore listener error: \(error)")
                    return
                }
                guard let data = snapshot?.data(),
                      let room = FirebaseBattleRoom.fromDict(roomId, data)
                else { return }

                self.sorted = room.toParticipants()
                DispatchQueue.main.async {
                    self.tableView.reloadData()
                    self.updateMyCardFromRoom(room)

                    // Уведомить если соперник обновил счёт
                    for member in room.members {
                        guard let uid   = member["uid"]   as? String,
                              let name  = member["name"]  as? String,
                              uid != self.myUid
                        else { continue }
                        let saved = (member["saved"] as? NSNumber)?.doubleValue
                            ?? member["saved"] as? Double
                            ?? 0
                        let key = "last_known_\(uid)"
                        let prev = UserDefaults.standard.double(forKey: key)
                        if prev != saved && prev != 0 {
                            BattleNotificationManager.shared.notifyOpponentUpdated(
                                opponentName: name, newAmount: saved
                            )
                        }
                        UserDefaults.standard.set(saved, forKey: key)
                    }
                }
            }
    }

    // MARK: - Push my amount to Firebase

    private func pushMyAmountIfNeeded() {
        guard let roomId = currentRoomId else {
            // Нет Firebase комнаты — обновляем локально
            loadLocalFallback()
            return
        }
        let personalGoal = AppStorage.shared.loadGoal()
        let saved = AppStorage.shared.loadCombinedSavings()
        let personalTarget = personalGoal.targetAmount
        let ref = db.collection("battleRooms").document(roomId)

        ref.getDocument { [weak self] snapshot, _ in
            guard let self, var members = snapshot?.data()?["members"] as? [[String: Any]] else { return }

            var found = false
            for i in members.indices where members[i]["uid"] as? String == self.myUid {
                members[i]["saved"] = saved
                members[i]["target"] = personalTarget
                members[i]["updatedAt"] = Timestamp(date: Date())
                found = true
            }
            if !found {
                members.append([
                    "uid": self.myUid,
                    "name": self.myName,
                    "saved": saved,
                    "target": personalTarget,
                    "updatedAt": Timestamp(date: Date()),
                ])
            }
            ref.updateData(["members": members])
        }

        updateMyCard(net: saved, target: personalTarget)
    }

    // MARK: - Leave Room

    private func leaveRoom() {
        guard let roomId = currentRoomId else { return }
        let ref = db.collection("battleRooms").document(roomId)

        ref.getDocument { [weak self] snapshot, _ in
            guard let self, var members = snapshot?.data()?["members"] as? [[String: Any]] else { return }
            members.removeAll { $0["uid"] as? String == self.myUid }
            ref.updateData(["members": members]) { _ in
                self.firestoreListener?.remove()
                self.currentRoomId = nil
                self.sorted = []
                // Отменить уведомления если вышел из всех комнат
                BattleNotificationManager.shared.cancelAllReminders()
                DispatchQueue.main.async {
                    self.tableView.reloadData()
                    self.updateActionButton()
                    self.loadLocalFallback()
                    self.showBanner("Ты покинул комнату")
                }
            }
        }
    }

    // MARK: - Local fallback (как было раньше)

    private func loadLocalFallback() {
        localParticipants = AppStorage.shared.loadBattleParticipants()
        let goal = AppStorage.shared.loadGoal()
        let saved = AppStorage.shared.loadCombinedSavings()
        let myId = "me_local"

        if let idx = localParticipants.firstIndex(where: { $0.id == myId }) {
            localParticipants[idx].savedAmount  = saved
            localParticipants[idx].targetAmount = goal.targetAmount
            localParticipants[idx].name         = myName
        } else {
            localParticipants.insert(
                BattleParticipant(id: myId, name: myName, savedAmount: saved,
                                  targetAmount: goal.targetAmount, joinedAt: Date()), at: 0
            )
        }
        AppStorage.shared.saveBattleParticipants(localParticipants)

        // Показываем локальных только если нет Firebase комнаты
        if currentRoomId == nil {
            sorted = localParticipants.sorted {
                if abs($0.progress - $1.progress) > 0.0001 {
                    return $0.progress > $1.progress
                }
                return $0.savedAmount > $1.savedAmount
            }
            tableView.reloadData()
        }
        updateMyCard(net: saved, target: goal.targetAmount)
    }

    @objc private func onPDFUpdated() {
        pushMyAmountIfNeeded()
    }

    // MARK: - UI Helpers

    private func updateMyCard(net: Double, target: Double? = nil) {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        let isNeg  = net < 0
        let personalTarget = max(target ?? AppStorage.shared.loadGoal().targetAmount, 1)
        let progress = min(max(net / personalTarget, 0), 1)
        let savedStr = f.string(from: NSNumber(value: max(net, 0))) ?? "0"
        let targetStr = f.string(from: NSNumber(value: personalTarget)) ?? "0"

        myNetLabel.text = String(format: "%.0f%% цели", progress * 100)
        myNetLabel.textColor = isNeg ? .systemOrange : FinLitTheme.accent
        myNetHint.text = "\(savedStr) из \(targetStr) ₸ • выписка + добавлено вручную"

        myStatsCard.backgroundColor = FinLitTheme.surface
    }

    private func updateMyCardFromRoom(_ room: FirebaseBattleRoom) {
        let me = room.members.first { $0["uid"] as? String == myUid }
        let saved = (me?["saved"] as? NSNumber)?.doubleValue
            ?? me?["saved"] as? Double
            ?? 0
        let target = (me?["target"] as? NSNumber)?.doubleValue
            ?? me?["target"] as? Double
            ?? room.goalAmount
        updateMyCard(net: saved, target: target)
    }

    private func updateActionButton() {
        navigationItem.rightBarButtonItem?.menu = battleMenu()
        let title: String
        if currentRoomId == nil {
            title = "Создать или войти в комнату"
        } else {
            title = "Пригласить друга"
        }
        actionButton.configuration?.title = title
    }

    @objc private func didTapActionButton() {
        if currentRoomId == nil {
            showMenu()
        } else if let code = currentRoomId {
            presentRoomInvite(code)
        }
    }

    @objc private func didTapChangeName() {
        let sheet = FinLitInputSheet(
            title: "Как вас узнают", detail: "Это имя увидят друзья в рейтинге комнаты.",
            symbol: "person.crop.circle.fill", action: "Сохранить имя", fieldTitle: "Имя в битве",
            placeholder: "Ваше имя", value: myName
        )
        sheet.field.input.autocapitalizationType = .words
        sheet.onSubmit = { [weak self] sheet in
            guard let self else { return }
            let name = (sheet.field.input.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.count <= 40 else {
                sheet.showError("Введите имя от 1 до 40 символов."); return
            }
            UserDefaults.standard.set(name, forKey: "battle_my_name")
            self.pushMyAmountIfNeeded()
            sheet.finish { self.showBanner("Имя обновлено: \(name)") }
        }
        present(sheet, animated: true)
    }

    // MARK: - Make room code

    private func makeRoomCode() -> String {
        let chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return String((0..<6).map { _ in chars.randomElement()! })
    }

    // MARK: - TableView

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sorted.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "BattleCell", for: indexPath) as! BattleCell
        let p = sorted[indexPath.row]
        let isMe = (currentRoomId != nil) ? (p.id == myUid) : (p.id == "me_local")
        cell.configure(participant: p, rank: indexPath.row + 1, isMe: isMe)
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { 110 }

    func tableView(_ tableView: UITableView,
                   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let p = sorted[indexPath.row]
        let isMe = (currentRoomId != nil) ? (p.id == myUid) : (p.id == "me_local")
        guard !isMe, currentRoomId == nil else { return nil } // удалять можно только в локальном режиме

        let del = UIContextualAction(style: .destructive, title: "Удалить") { [weak self] _, _, done in
            guard let self else { return }
            self.localParticipants.removeAll { $0.id == p.id }
            AppStorage.shared.saveBattleParticipants(self.localParticipants)
            self.loadLocalFallback()
            done(true)
        }
        del.image = UIImage(systemName: "trash")
        return UISwipeActionsConfiguration(actions: [del])
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }

    // MARK: - Banners / Alerts

    private func showBanner(_ text: String, color: UIColor = .systemGreen) {
        let b = UIView(); b.backgroundColor = color; b.layer.cornerRadius = 12
        b.translatesAutoresizingMaskIntoConstraints = false
        let l = UILabel(); l.text = text; l.textColor = .white
        l.font = .systemFont(ofSize: 14, weight: .semibold); l.numberOfLines = 0
        l.translatesAutoresizingMaskIntoConstraints = false
        b.addSubview(l); view.addSubview(b)
        NSLayoutConstraint.activate([
            b.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            b.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            b.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            l.topAnchor.constraint(equalTo: b.topAnchor, constant: 12),
            l.bottomAnchor.constraint(equalTo: b.bottomAnchor, constant: -12),
            l.leadingAnchor.constraint(equalTo: b.leadingAnchor, constant: 16),
            l.trailingAnchor.constraint(equalTo: b.trailingAnchor, constant: -16),
        ])
        b.alpha = 0
        UIView.animate(withDuration: 0.3) { b.alpha = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            UIView.animate(withDuration: 0.3) { b.alpha = 0 } completion: { _ in b.removeFromSuperview() }
        }
    }

    private func showAlert(_ t: String, _ m: String) {
        present(FinLitNoticeSheet(title: t, detail: m), animated: true)
    }
}
