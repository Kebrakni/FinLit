// BattleViewController.swift
import UIKit

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

// MARK: - Cell

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
        case 1: rankLabel.text = "🥇"
        case 2: rankLabel.text = "🥈"
        case 3: rankLabel.text = "🥉"
        default: rankLabel.text = "\(rank)"
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

        statusBadge.text = isNeg ? "  📉 в минусе  " : "  📈 в плюсе  "
        statusBadge.backgroundColor = isNeg
            ? UIColor.systemRed.withAlphaComponent(0.15)
            : UIColor.systemGreen.withAlphaComponent(0.15)
        statusBadge.textColor = isNeg ? .systemRed : .systemGreen

        progressBar.setProgress(Float(participant.progress), animated: true)
        progressBar.progressTintColor = isMe ? .systemBlue : (isNeg ? .systemRed : .systemGreen)

        // ✅ Проценты до сотой (например: 12.47%)
        let pct = participant.progress * 100
        let targetStr = f.string(from: NSNumber(value: participant.targetAmount)) ?? "0"
        progressLabel.text = String(format: "%.2f%% к цели %@ ₸", pct, targetStr)

        cardView.layer.borderWidth = isMe ? 2 : 0
        cardView.layer.borderColor = UIColor.systemBlue.cgColor
    }
}

// MARK: - BattleViewController

final class BattleViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    private var myName: String {
        UserDefaults.standard.string(forKey: "battle_my_name") ?? "Я"
    }

    private var participants: [BattleParticipant] = []
    private var sorted: [BattleParticipant] = []

    private let tableView = UITableView(frame: .zero, style: .plain)

    private let headerContainer = UIView()
    private let trophyLabel     = UILabel()
    private let subtitleLabel   = UILabel()
    private let myStatsCard     = UIView()
    private let myNetLabel      = UILabel()
    private let myNetTitle      = UILabel()
    private let myNetHint       = UILabel()
    private let inviteButton    = UIButton(type: .system)

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "⚔️ Битва накоплений"
        view.backgroundColor = .systemBackground
        setupNav()
        setupUI()
        loadData()

        NotificationCenter.default.addObserver(
            self, selector: #selector(onPDFUpdated),
            name: .pdfNetSavingsUpdated, object: nil
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadData()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func setupNav() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "person.badge.plus"),
            style: .plain, target: self, action: #selector(didTapInvite)
        )
    }

    // MARK: - UI

    private func setupUI() {
        headerContainer.translatesAutoresizingMaskIntoConstraints = false

        trophyLabel.translatesAutoresizingMaskIntoConstraints = false
        trophyLabel.text = "🏆"; trophyLabel.font = .systemFont(ofSize: 44)
        trophyLabel.textAlignment = .center

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = "Кто больше накопил?"
        subtitleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        subtitleLabel.textAlignment = .center

        myStatsCard.translatesAutoresizingMaskIntoConstraints = false
        myStatsCard.layer.cornerRadius = 14; myStatsCard.layer.borderWidth = 1.5

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

        myStatsCard.addSubview(myNetTitle)
        myStatsCard.addSubview(myNetLabel)
        myStatsCard.addSubview(myNetHint)

        inviteButton.translatesAutoresizingMaskIntoConstraints = false
        inviteButton.setTitle("⚔️  Пригласить соперника", for: .normal)
        inviteButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        inviteButton.backgroundColor = .systemBlue; inviteButton.tintColor = .white
        inviteButton.layer.cornerRadius = 14
        inviteButton.contentEdgeInsets = UIEdgeInsets(top: 12, left: 20, bottom: 12, right: 20)
        inviteButton.addTarget(self, action: #selector(didTapInvite), for: .touchUpInside)

        headerContainer.addSubview(trophyLabel)
        headerContainer.addSubview(subtitleLabel)
        headerContainer.addSubview(myStatsCard)
        headerContainer.addSubview(inviteButton)

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
            myNetHint.bottomAnchor.constraint(equalTo: myStatsCard.bottomAnchor, constant: -12),

            inviteButton.topAnchor.constraint(equalTo: myStatsCard.bottomAnchor, constant: 12),
            inviteButton.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor, constant: 16),
            inviteButton.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor, constant: -16),
            inviteButton.bottomAnchor.constraint(equalTo: headerContainer.bottomAnchor, constant: -12),
        ])

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

    // MARK: - Data

    private func loadData() {
        participants = AppStorage.shared.loadBattleParticipants()
        let net  = AppStorage.shared.loadPDFNetSavings()
        let goal = AppStorage.shared.loadGoal()
        let myId = "me_local"

        if let idx = participants.firstIndex(where: { $0.id == myId }) {
            participants[idx].savedAmount  = net
            participants[idx].targetAmount = goal.targetAmount
            participants[idx].name         = myName
        } else {
            participants.insert(
                BattleParticipant(id: myId, name: myName, savedAmount: net,
                                  targetAmount: goal.targetAmount, joinedAt: Date()),
                at: 0
            )
        }

        AppStorage.shared.saveBattleParticipants(participants)
        sorted = participants.sorted { $0.savedAmount > $1.savedAmount }

        updateMyCard(net: net)
        tableView.reloadData()
    }

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

    @objc private func onPDFUpdated() { loadData() }

    // MARK: - Invite

    @objc private func didTapInvite() {
        let alert = UIAlertController(
            title: "⚔️ Добавить соперника",
            message: "Введи имя и его чистые накопления (доходы − расходы, может быть отрицательным)",
            preferredStyle: .alert
        )
        alert.addTextField { tf in tf.placeholder = "Имя (например: Алия)"; tf.autocapitalizationType = .words }
        alert.addTextField { tf in tf.placeholder = "Накопления ₸ (например: 45000 или -5000)"; tf.keyboardType = .numbersAndPunctuation }
        alert.addTextField { tf in tf.placeholder = "Цель ₸ (например: 350000)"; tf.keyboardType = .numberPad }

        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "Добавить", style: .default, handler: { [weak self] _ in
            guard let self else { return }
            let name   = (alert.textFields?[0].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let netStr = (alert.textFields?[1].text ?? "").replacingOccurrences(of: " ", with: "")
            let tgtStr = (alert.textFields?[2].text ?? "").replacingOccurrences(of: " ", with: "")
            guard !name.isEmpty else { self.showAlert("Ошибка", "Введи имя"); return }

            let p = BattleParticipant(
                name: name,
                savedAmount: Double(netStr) ?? 0,
                targetAmount: Double(tgtStr) ?? 350_000,
                joinedAt: Date()
            )
            self.participants.append(p)
            AppStorage.shared.saveBattleParticipants(self.participants)
            self.loadData()
            self.showBanner("⚔️ \(name) добавлен в битву!")
        }))
        present(alert, animated: true)
    }

    // MARK: - TableView

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { sorted.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "BattleCell", for: indexPath) as! BattleCell
        let p = sorted[indexPath.row]
        cell.configure(participant: p, rank: indexPath.row + 1, isMe: p.id == "me_local")
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { 110 }

    func tableView(_ tableView: UITableView,
                   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let p = sorted[indexPath.row]
        guard p.id != "me_local" else { return nil }
        let del = UIContextualAction(style: .destructive, title: "Удалить") { [weak self] _, _, done in
            self?.participants.removeAll { $0.id == p.id }
            AppStorage.shared.saveBattleParticipants(self?.participants ?? [])
            self?.loadData(); done(true)
        }
        del.image = UIImage(systemName: "trash")
        return UISwipeActionsConfiguration(actions: [del])
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let p = sorted[indexPath.row]; guard p.id != "me_local" else { return }
        let alert = UIAlertController(title: "Обновить", message: p.name, preferredStyle: .alert)
        alert.addTextField { tf in tf.keyboardType = .numbersAndPunctuation; tf.text = "\(Int(p.savedAmount))" }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "Сохранить", style: .default, handler: { [weak self] _ in
            guard let self else { return }
            let str = (alert.textFields?.first?.text ?? "").replacingOccurrences(of: " ", with: "")
            if let val = Double(str), let idx = self.participants.firstIndex(where: { $0.id == p.id }) {
                self.participants[idx].savedAmount = val
                AppStorage.shared.saveBattleParticipants(self.participants)
                self.loadData()
            }
        }))
        present(alert, animated: true)
    }

    // MARK: - Helpers

    private func showBanner(_ text: String) {
        let b = UIView(); b.backgroundColor = .systemGreen; b.layer.cornerRadius = 12
        b.translatesAutoresizingMaskIntoConstraints = false
        let l = UILabel(); l.text = text; l.textColor = .white
        l.font = .systemFont(ofSize: 14, weight: .semibold)
        l.translatesAutoresizingMaskIntoConstraints = false
        b.addSubview(l); view.addSubview(b)
        NSLayoutConstraint.activate([
            b.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            b.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            b.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            l.topAnchor.constraint(equalTo: b.topAnchor, constant: 12),
            l.bottomAnchor.constraint(equalTo: b.bottomAnchor, constant: -12),
            l.centerXAnchor.constraint(equalTo: b.centerXAnchor),
        ])
        b.alpha = 0
        UIView.animate(withDuration: 0.3) { b.alpha = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            UIView.animate(withDuration: 0.3) { b.alpha = 0 } completion: { _ in b.removeFromSuperview() }
        }
    }

    private func showAlert(_ t: String, _ m: String) {
        let a = UIAlertController(title: t, message: m, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default)); present(a, animated: true)
    }
}
