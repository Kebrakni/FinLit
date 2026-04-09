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
    var members: [[String: Any]] // [{uid, name, saved, updatedAt}]

    static func fromDict(_ id: String, _ d: [String: Any]) -> FirebaseBattleRoom? {
        guard
            let host = d["hostId"] as? String,
            let goal = d["goalAmount"] as? Double,
            let members = d["members"] as? [[String: Any]]
        else { return nil }
        return FirebaseBattleRoom(id: id, hostId: host, goalAmount: goal, members: members)
    }

    func toParticipants() -> [BattleParticipant] {
        members.compactMap { m in
            guard let uid  = m["uid"]   as? String,
                  let name = m["name"]  as? String,
                  let saved = m["saved"] as? Double
            else { return nil }
            return BattleParticipant(
                id: uid,
                name: name,
                savedAmount: saved,
                targetAmount: goalAmount,
                joinedAt: Date()
            )
        }.sorted { $0.savedAmount > $1.savedAmount }
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
        cardView.backgroundColor = .secondarySystemBackground
        cardView.layer.cornerRadius = 16

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
        let absStr = f.string(from: NSNumber(value: abs(participant.savedAmount))) ?? "0"
        amountLabel.text  = "\(isNeg ? "-" : "+")\(absStr) ₸"
        amountLabel.textColor = isNeg ? .systemRed : .systemGreen

        let badgeSymbol = isNeg ? "chart.line.downtrend.xyaxis" : "chart.line.uptrend.xyaxis"
        let badgeImg = UIImage(systemName: badgeSymbol)?.withRenderingMode(.alwaysOriginal)
            .withTintColor(isNeg ? .systemRed : .systemGreen)
        let badgeAttachment = NSTextAttachment()
        badgeAttachment.image = badgeImg
        badgeAttachment.bounds = CGRect(x: 0, y: -3, width: 14, height: 14)
        let badgeAttr = NSMutableAttributedString(string: "  ")
        badgeAttr.append(NSAttributedString(attachment: badgeAttachment))
        badgeAttr.append(NSAttributedString(string: isNeg ? " в минусе  " : " в плюсе  "))
        statusBadge.attributedText = badgeAttr
        statusBadge.backgroundColor = isNeg
            ? UIColor.systemRed.withAlphaComponent(0.15)
            : UIColor.systemGreen.withAlphaComponent(0.15)
        statusBadge.textColor = isNeg ? .systemRed : .systemGreen

        progressBar.setProgress(Float(participant.progress), animated: true)
        progressBar.progressTintColor = isMe ? .systemBlue : (isNeg ? .systemRed : .systemGreen)

        let pct = participant.progress * 100
        let targetStr = f.string(from: NSNumber(value: participant.targetAmount)) ?? "0"
        progressLabel.text = String(format: "%.2f%% к цели %@ ₸", pct, targetStr)

        cardView.layer.borderWidth = isMe ? 2 : 0
        cardView.layer.borderColor = UIColor.systemBlue.cgColor
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
    private let db = Firestore.firestore()

    // MARK: UI

    private let tableView       = UITableView(frame: .zero, style: .plain)
    private let headerContainer = UIView()
    private let trophyLabel     = UILabel()
    private let subtitleLabel   = UILabel()
    private let myStatsCard     = UIView()
    private let myNetLabel      = UILabel()
    private let myNetTitle      = UILabel()
    private let myNetHint       = UILabel()
    private let roomCodeLabel   = UILabel()   // показывает текущий код комнаты
    private let actionButton    = UIButton(type: .system)

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Битва накоплений"
        view.backgroundColor = .systemBackground
        setupNav()
        setupUI()
        loadLocalFallback()

        NotificationCenter.default.addObserver(
            self, selector: #selector(onPDFUpdated),
            name: .pdfNetSavingsUpdated, object: nil
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
            style: .plain, target: self, action: #selector(showMenu)
        )
        navigationItem.rightBarButtonItem = menuBtn
    }

    @objc private func showMenu() {
        let sheet = UIAlertController(title: "Баттл", message: nil, preferredStyle: .actionSheet)

        sheet.addAction(UIAlertAction(title: "Создать комнату", style: .default) { [weak self] _ in
            self?.didTapCreateRoom()
        })
        sheet.addAction(UIAlertAction(title: "Войти по коду", style: .default) { [weak self] _ in
            self?.didTapJoinRoom()
        })
        if currentRoomId != nil {
            sheet.addAction(UIAlertAction(title: "Скопировать код комнаты", style: .default) { [weak self] _ in
                UIPasteboard.general.string = self?.currentRoomId
                self?.showBanner("Код скопирован!")
            })
            sheet.addAction(UIAlertAction(title: "Покинуть комнату", style: .destructive) { [weak self] _ in
                self?.leaveRoom()
            })
        }
        sheet.addAction(UIAlertAction(title: "Моё имя", style: .default) { [weak self] _ in
            self?.didTapChangeName()
        })
        sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))

        present(sheet, animated: true)
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
        subtitleLabel.text = "Кто больше накопил?"
        subtitleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        subtitleLabel.textAlignment = .center

        // Карточка "Мой счёт"
        myStatsCard.translatesAutoresizingMaskIntoConstraints = false
        myStatsCard.layer.cornerRadius = 14; myStatsCard.layer.borderWidth = 1.5
        myStatsCard.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.08)
        myStatsCard.layer.borderColor = UIColor.systemGreen.withAlphaComponent(0.3).cgColor

        myNetTitle.translatesAutoresizingMaskIntoConstraints = false
        myNetTitle.text = "Твой счёт в битве (из выписок)"
        myNetTitle.font = .systemFont(ofSize: 13); myNetTitle.textColor = .secondaryLabel

        myNetLabel.translatesAutoresizingMaskIntoConstraints = false
        myNetLabel.font = .systemFont(ofSize: 26, weight: .bold)
        myNetLabel.text = "Загрузи PDF →"; myNetLabel.textColor = .secondaryLabel

        myNetHint.translatesAutoresizingMaskIntoConstraints = false
        myNetHint.text = "обновляется автоматически после загрузки PDF в Аналитике"
        myNetHint.font = .systemFont(ofSize: 11); myNetHint.textColor = .secondaryLabel
        myNetHint.numberOfLines = 2

        roomCodeLabel.translatesAutoresizingMaskIntoConstraints = false
        roomCodeLabel.font = .monospacedSystemFont(ofSize: 13, weight: .semibold)
        roomCodeLabel.textColor = .systemBlue; roomCodeLabel.textAlignment = .center
        roomCodeLabel.numberOfLines = 1
        updateRoomCodeLabel()

        myStatsCard.addSubview(myNetTitle)
        myStatsCard.addSubview(myNetLabel)
        myStatsCard.addSubview(myNetHint)
        myStatsCard.addSubview(roomCodeLabel)

        // Кнопка действия (создать/войти)
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.backgroundColor = .systemBlue; actionButton.tintColor = .white
        actionButton.layer.cornerRadius = 14
        actionButton.contentEdgeInsets = UIEdgeInsets(top: 12, left: 20, bottom: 12, right: 20)
        actionButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
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

            roomCodeLabel.topAnchor.constraint(equalTo: myNetHint.bottomAnchor, constant: 8),
            roomCodeLabel.leadingAnchor.constraint(equalTo: myStatsCard.leadingAnchor, constant: 14),
            roomCodeLabel.trailingAnchor.constraint(equalTo: myStatsCard.trailingAnchor, constant: -14),
            roomCodeLabel.bottomAnchor.constraint(equalTo: myStatsCard.bottomAnchor, constant: -12),

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
        hdr.text = "  Таблица лидеров"
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
        let alert = UIAlertController(title: "Создать комнату", message: "Введи общую цель накопления", preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "Цель ₸ (например: 350000)"
            tf.keyboardType = .numberPad
        }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "Создать", style: .default) { [weak self] _ in
            guard let self else { return }
            let goalStr = (alert.textFields?.first?.text ?? "").replacingOccurrences(of: " ", with: "")
            let goal = Double(goalStr) ?? AppStorage.shared.loadGoal().targetAmount

            let roomId = self.makeRoomCode()
            let net = AppStorage.shared.loadPDFNetSavings()

            let data: [String: Any] = [
                "hostId": self.myUid,
                "goalAmount": goal,
                "createdAt": FieldValue.serverTimestamp(),
                "members": [
                    [
                        "uid": self.myUid,
                        "name": self.myName,
                        "saved": net,
                        "updatedAt": Timestamp(date: Date())
                    ]
                ]
            ]

            self.db.collection("battleRooms").document(roomId).setData(data) { error in
                if let error {
                    self.showAlert("Ошибка", error.localizedDescription); return
                }
                self.currentRoomId = roomId
                self.subscribeToRoom(roomId)
                self.updateRoomCodeLabel()
                self.updateActionButton()
                // Запланировать еженедельные напоминания
                BattleNotificationManager.shared.requestPermissionAndSchedule()

                // Покажем код чтобы поделиться
                let share = UIAlertController(
                    title: "Комната создана!",
                    message: "Код для друга:\n\n\(roomId)\n\nОтправь этот код другу — он введёт его через «Войти по коду»",
                    preferredStyle: .alert
                )
                share.addAction(UIAlertAction(title: "Скопировать", style: .default) { _ in
                    UIPasteboard.general.string = roomId
                })
                share.addAction(UIAlertAction(title: "OK", style: .cancel))
                self.present(share, animated: true)
            }
        })
        present(alert, animated: true)
    }

    // MARK: - Firebase: Join Room

    @objc private func didTapJoinRoom() {
        let alert = UIAlertController(title: "Войти по коду", message: "Введи код комнаты от друга", preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "Код (6 символов)"
            tf.autocapitalizationType = .allCharacters
        }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "Войти", style: .default) { [weak self] _ in
            guard let self else { return }
            let code = (alert.textFields?.first?.text ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            guard !code.isEmpty else { return }

            let ref = self.db.collection("battleRooms").document(code)
            ref.getDocument { snapshot, error in
                if let error {
                    self.showAlert("Ошибка", error.localizedDescription); return
                }
                guard let data = snapshot?.data() else {
                    self.showAlert("Не найдено", "Комната с кодом «\(code)» не существует"); return
                }

                // Проверяем не в ней ли уже
                var members = data["members"] as? [[String: Any]] ?? []
                let alreadyIn = members.contains { $0["uid"] as? String == self.myUid }

                let net = AppStorage.shared.loadPDFNetSavings()

                if alreadyIn {
                    // просто обновить сумму
                    for i in members.indices where members[i]["uid"] as? String == self.myUid {
                        members[i]["saved"] = net
                        members[i]["updatedAt"] = Timestamp(date: Date())
                    }
                } else {
                    members.append([
                        "uid": self.myUid,
                        "name": self.myName,
                        "saved": net,
                        "updatedAt": Timestamp(date: Date())
                    ])
                }

                ref.updateData(["members": members]) { error in
                    if let error {
                        self.showAlert("Ошибка", error.localizedDescription); return
                    }
                    self.currentRoomId = code
                    self.subscribeToRoom(code)
                    self.updateRoomCodeLabel()
                    self.updateActionButton()
                    // Запланировать еженедельные напоминания
                    BattleNotificationManager.shared.requestPermissionAndSchedule()
                    self.showBanner("Ты в комнате \(code)!")
                }
            }
        })
        present(alert, animated: true)
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
                              let saved = member["saved"]  as? Double,
                              uid != self.myUid
                        else { continue }
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
        let net = AppStorage.shared.loadPDFNetSavings()
        let ref = db.collection("battleRooms").document(roomId)

        ref.getDocument { [weak self] snapshot, _ in
            guard let self, var members = snapshot?.data()?["members"] as? [[String: Any]] else { return }

            var found = false
            for i in members.indices where members[i]["uid"] as? String == self.myUid {
                members[i]["saved"] = net
                members[i]["updatedAt"] = Timestamp(date: Date())
                found = true
            }
            if !found {
                members.append(["uid": self.myUid, "name": self.myName, "saved": net, "updatedAt": Timestamp(date: Date())])
            }
            ref.updateData(["members": members])
        }

        updateMyCard(net: net)
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
                    self.updateRoomCodeLabel()
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
        let net  = AppStorage.shared.loadPDFNetSavings()
        let goal = AppStorage.shared.loadGoal()
        let myId = "me_local"

        if let idx = localParticipants.firstIndex(where: { $0.id == myId }) {
            localParticipants[idx].savedAmount  = net
            localParticipants[idx].targetAmount = goal.targetAmount
            localParticipants[idx].name         = myName
        } else {
            localParticipants.insert(
                BattleParticipant(id: myId, name: myName, savedAmount: net,
                                  targetAmount: goal.targetAmount, joinedAt: Date()), at: 0
            )
        }
        AppStorage.shared.saveBattleParticipants(localParticipants)

        // Показываем локальных только если нет Firebase комнаты
        if currentRoomId == nil {
            sorted = localParticipants.sorted { $0.savedAmount > $1.savedAmount }
            tableView.reloadData()
        }
        updateMyCard(net: net)
    }

    @objc private func onPDFUpdated() {
        pushMyAmountIfNeeded()
    }

    // MARK: - UI Helpers

    private func updateMyCard(net: Double) {
        let hasPDF = AppStorage.shared.loadAllTransactions().count > 0
        guard hasPDF else { return }

        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        let isNeg  = net < 0
        let absStr = f.string(from: NSNumber(value: abs(net))) ?? "0"

        myNetLabel.text      = "\(isNeg ? "-" : "+")\(absStr) ₸"
        myNetLabel.textColor = isNeg ? .systemRed : .systemGreen

        myStatsCard.backgroundColor  = isNeg
            ? UIColor.systemRed.withAlphaComponent(0.1)
            : UIColor.systemGreen.withAlphaComponent(0.1)
        myStatsCard.layer.borderColor = (isNeg ? UIColor.systemRed : UIColor.systemGreen)
            .withAlphaComponent(0.4).cgColor
    }

    private func updateMyCardFromRoom(_ room: FirebaseBattleRoom) {
        let me = room.members.first { $0["uid"] as? String == myUid }
        let saved = me?["saved"] as? Double ?? 0
        updateMyCard(net: saved)
    }

    private func updateRoomCodeLabel() {
        if let code = currentRoomId {
            roomCodeLabel.text = "Код комнаты: \(code)  (нажми ··· чтобы скопировать)"
            roomCodeLabel.isHidden = false
        } else {
            roomCodeLabel.text = "Нет активной комнаты"
            roomCodeLabel.textColor = .secondaryLabel
            roomCodeLabel.isHidden = false
        }
    }

    private func updateActionButton() {
        if currentRoomId == nil {
            actionButton.setTitle("Создать или войти в комнату", for: .normal)
        } else {
            actionButton.setTitle("Пригласить друга (скопировать код)", for: .normal)
        }
    }

    @objc private func didTapActionButton() {
        if currentRoomId == nil {
            showMenu()
        } else {
            UIPasteboard.general.string = currentRoomId
            showBanner("Код \(currentRoomId ?? "") скопирован!")
        }
    }

    @objc private func didTapChangeName() {
        let alert = UIAlertController(title: "Твоё имя в битве", message: nil, preferredStyle: .alert)
        alert.addTextField { tf in
            tf.text = self.myName
            tf.placeholder = "Имя"
            tf.autocapitalizationType = .words
        }
        alert.addAction(UIAlertAction(title: "Сохранить", style: .default) { [weak self] _ in
            guard let self else { return }
            let name = (alert.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            UserDefaults.standard.set(name, forKey: "battle_my_name")
            self.pushMyAmountIfNeeded()
            self.showBanner("Имя обновлено: \(name)")
        })
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        present(alert, animated: true)
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
        let a = UIAlertController(title: t, message: m, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default))
        present(a, animated: true)
    }
}
