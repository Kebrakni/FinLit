import UIKit

final class ChallengeViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    private var challenges: [Challenge] = AppStorage.shared.loadChallenges()

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Challenges"
        view.backgroundColor = .systemBackground
        setupNav()
        setupTable()
    }

    private func setupNav() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Создать",
                                                            style: .done,
                                                            target: self,
                                                            action: #selector(didTapCreate))
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Пригласить",
                                                           style: .plain,
                                                           target: self,
                                                           action: #selector(didTapInvite))
    }

    private func setupTable() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")

        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: Actions

    @objc private func didTapCreate() {
        // 1) выбрать тип
        let sheet = UIAlertController(title: "Новый челлендж",
                                      message: "Выбери тип",
                                      preferredStyle: .actionSheet)

        ChallengeType.allCases.forEach { type in
            sheet.addAction(UIAlertAction(title: type.rawValue, style: .default, handler: { [weak self] _ in
                self?.askTitleAndCreate(type: type)
            }))
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(sheet, animated: true)
    }

    private func askTitleAndCreate(type: ChallengeType) {
        let alert = UIAlertController(title: "Название",
                                      message: "Например: Save 10k this week",
                                      preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "Название челленджа"
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Create", style: .default, handler: { [weak self] _ in
            guard let self else { return }
            let title = (alert.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return }

            let newItem = Challenge(title: title, type: type, createdAt: Date(), participants: ["You"])
            self.challenges.insert(newItem, at: 0)
            AppStorage.shared.saveChallenges(self.challenges)
            self.tableView.reloadData()
        }))
        present(alert, animated: true)
    }

    @objc private func didTapInvite() {
        // MVP: просто копируем "код приглашения" (id)
        let alert = UIAlertController(title: "Invite friend",
                                      message: "Пока без Firebase: делимся кодом челленджа.",
                                      preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "Вставь код (опц.)"
        }

        alert.addAction(UIAlertAction(title: "Скопировать код первого", style: .default, handler: { [weak self] _ in
            guard let self else { return }
            guard let first = self.challenges.first else { return }
            UIPasteboard.general.string = first.id
        }))

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    // MARK: Table

    func numberOfSections(in tableView: UITableView) -> Int { 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        challenges.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = challenges[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)

        var content = cell.defaultContentConfiguration()
        content.text = item.title
        content.secondaryText = "\(item.type.rawValue) • Participants: \(item.participants.count)"
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let item = challenges[indexPath.row]
        let alert = UIAlertController(title: item.title,
                                      message: "Type: \(item.type.rawValue)\nCode: \(item.id)",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    // swipe delete
    func tableView(_ tableView: UITableView,
                   commit editingStyle: UITableViewCell.EditingStyle,
                   forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            challenges.remove(at: indexPath.row)
            AppStorage.shared.saveChallenges(challenges)
            tableView.deleteRows(at: [indexPath], with: .automatic)
        }
    }
}
