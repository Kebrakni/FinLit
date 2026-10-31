import UIKit

final class CategoryReviewViewController: UITableViewController {
    private var items: [CategoryReviewItem] = []
    private var rememberChoices: [String: Bool] = [:]
    private let header = UIView()
    private let headerStack = UIStackView()
    private let summary = UILabel()
    private let status = UILabel()
    private let scanButton = UIButton(type: .system)
    private var task: Task<Void, Never>?
    private var runID: UUID?
    var onChange: (() -> Void)?

    init() { super.init(style: .plain) }
    required init?(coder: NSCoder) { fatalError() }
    deinit { task?.cancel() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Проверка категорий"
        navigationItem.largeTitleDisplayMode = .never
        tableView.backgroundColor = FinLitTheme.background
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 360
        tableView.contentInset.bottom = 24
        tableView.register(CategoryReviewCell.self, forCellReuseIdentifier: "Review")
        setupHeader()
        reloadItems()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isMovingFromParent || navigationController?.isBeingDismissed == true { stopScan() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        sizeHeader()
    }

    private func setupHeader() {
        headerStack.axis = .vertical
        headerStack.spacing = 12
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        summary.font = FinLitTheme.font(23, weight: .bold, style: .title2)
        summary.numberOfLines = 0
        summary.adjustsFontForContentSizeCategory = true
        let detail = UILabel()
        detail.text = "Подтвердите категорию или исправьте её. Суммы останутся прежними. Можно запомнить выбор для того же продавца и типа платежа."
        detail.font = FinLitTheme.font(14, style: .subheadline)
        detail.numberOfLines = 0
        detail.textColor = .secondaryLabel
        detail.adjustsFontForContentSizeCategory = true
        status.font = FinLitTheme.font(13, style: .footnote)
        status.numberOfLines = 0
        status.textColor = .secondaryLabel
        FinLitTheme.configurePrimaryButton(scanButton, title: "Проверить с AI", image: "sparkles")
        scanButton.addTarget(self, action: #selector(scan), for: .touchUpInside)
        [summary, detail, scanButton, status].forEach { headerStack.addArrangedSubview($0) }
        header.addSubview(headerStack)
        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: header.topAnchor, constant: 18),
            headerStack.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 20),
            headerStack.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -20),
            headerStack.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -18)
        ])
        tableView.tableHeaderView = header
    }

    private func sizeHeader() {
        let width = tableView.bounds.width
        guard width > 0 else { return }
        let height = header.systemLayoutSizeFitting(CGSize(width: width, height: 0), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
        if abs(header.frame.height - height) > 0.5 || header.frame.width != width {
            header.frame = CGRect(x: 0, y: 0, width: width, height: height)
            tableView.tableHeaderView = header
        }
    }

    private func reloadItems() {
        items = AppStorage.shared.categoryReviewItems()
        let remaining = AppStorage.shared.transactionsForCategoryAudit().count
        summary.text = items.isEmpty ? (remaining > 0 ? "Проверим распределение" : "Всё разобрано") : "Ждут вашего решения: \(items.count)"
        if runID == nil {
            scanButton.configuration?.title = "Проверить с AI"
            scanButton.configuration?.showsActivityIndicator = false
            scanButton.isEnabled = remaining > 0
            if status.text == nil {
                status.text = remaining > 0 ? "AI ещё не проверил \(remaining) операций. Полученные предложения и ваши решения сохраняются." : "Все текущие операции проверены. Новые платежи появятся после импорта."
            }
        }
        if items.isEmpty {
            let empty = FinLitEmptyStateView(symbol: "checkmark.shield", title: "Спорных операций пока нет", detail: remaining > 0 ? "Запустите проверку выше: AI найдёт сомнительные категории." : "Ваши решения сохранены.")
            empty.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 250)
            tableView.tableFooterView = empty
        } else { tableView.tableFooterView = nil }
        tableView.reloadData()
        sizeHeader()
        onChange?()
    }

    @objc private func scan() {
        if runID != nil { stopScan(); return }
        let rows = AppStorage.shared.transactionsForCategoryAudit()
        guard !rows.isEmpty else { return }
        let id = UUID()
        runID = id
        scanButton.configuration?.title = "Остановить проверку"
        scanButton.configuration?.showsActivityIndicator = true
        status.text = "AI проверяет категории · 0 из \(rows.count)"
        sizeHeader()
        task = Task { [weak self] in
            do {
                let result = try await OpenRouterCategorizer.shared.auditCategories(rows, onBatch: { [weak self] assessments in
                    guard let self, self.runID == id else { return }
                    let saved = AppStorage.shared.saveCategoryAssessments(assessments)
                    GamificationManager.shared.recordAIReview(correctionCount: 0, reviewedCount: saved)
                    self.reloadItems()
                }, progress: { [weak self] checked, total in
                    guard let self, self.runID == id else { return }
                    self.status.text = "AI проверил \(checked) из \(total) операций"
                    self.sizeHeader()
                })
                guard let self, self.runID == id, !Task.isCancelled else { return }
                self.runID = nil
                let incomplete = rows.count - result.checkedCount
                self.status.text = result.errorMessage.map { "Проверено \(result.checkedCount) из \(rows.count). \($0) Нажмите проверку ещё раз, чтобы продолжить." }
                    ?? (incomplete > 0 ? "Проверено \(result.checkedCount) из \(rows.count). Для остальных не получен полный ответ; их можно проверить повторно." : "Проверено \(result.checkedCount) операций. AI ничего не меняет без вашего решения.")
                self.reloadItems()
            } catch {
                guard let self, self.runID == id, !Task.isCancelled else { return }
                self.runID = nil
                self.status.text = "Проверку не удалось завершить: \(error.localizedDescription) Можно повторить."
                self.reloadItems()
            }
        }
    }

    private func stopScan() {
        task?.cancel()
        task = nil
        runID = nil
        status.text = "Проверка остановлена. Уже полученные предложения сохранены."
        reloadItems()
    }

    private func resolve(_ item: CategoryReviewItem, category: TxCategory) {
        let saved = AppStorage.shared.resolveCategoryReview(item.snapshot, category: category, remember: rememberChoices[item.id] ?? true)
        if saved == nil {
            present(FinLitNoticeSheet(title: "Операция уже изменилась", detail: "Список обновлён. Проверьте актуальные данные перед выбором категории."), animated: true)
        } else {
            UISelectionFeedbackGenerator().selectionChanged()
            UIAccessibility.post(notification: .announcement, argument: "Категория подтверждена: \(category.rawValue)")
        }
        reloadItems()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { items.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = items[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "Review", for: indexPath) as! CategoryReviewCell
        cell.configure(item, remember: rememberChoices[item.id] ?? true,
                       onRemember: { [weak self] in self?.rememberChoices[item.id] = $0 },
                       onChoose: { [weak self] in self?.resolve(item, category: $0) })
        return cell
    }
}

private final class CategoryReviewCell: UITableViewCell {
    private let card = UIView()
    private let stack = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        FinLitTheme.styleCard(card)
        stack.axis = .vertical
        stack.spacing = 12
        [card, stack].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        contentView.addSubview(card)
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    private func label(_ text: String, size: CGFloat = 14, weight: UIFont.Weight = .regular, color: UIColor = .label) -> UILabel {
        let label = UILabel()
        label.text = text
        label.numberOfLines = 0
        label.font = FinLitTheme.font(size, weight: weight)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = color
        return label
    }

    func configure(_ item: CategoryReviewItem, remember: Bool, onRemember: @escaping (Bool) -> Void, onChoose: @escaping (TxCategory) -> Void) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let row = item.transaction
        let date = DateFormatter(); date.dateFormat = "dd.MM.yyyy"
        stack.addArrangedSubview(label(item.fromAI ? "ПРЕДЛОЖЕНИЕ AI" : "НУЖНО УТОЧНИТЬ", size: 11, weight: .bold, color: FinLitTheme.accent))
        stack.addArrangedSubview(label(row.merchant, size: 19, weight: .semibold))
        stack.addArrangedSubview(label("\(date.string(from: row.date)) · \(AssistantAnalytics.money(row.amount))", color: .secondaryLabel))
        stack.addArrangedSubview(label("Сейчас: \(row.category.rawValue)", weight: .medium))
        if let proposed = item.suggestedCategory, proposed != row.category {
            stack.addArrangedSubview(label("Предложение: \(proposed.rawValue)", weight: .semibold, color: FinLitTheme.accent))
        }
        stack.addArrangedSubview(label(OpenRouterCategorizer.assistantDisplayText(item.reason), color: .secondaryLabel))
        let toggle = UISwitch()
        toggle.isOn = remember
        toggle.onTintColor = FinLitTheme.buttonFill
        toggle.accessibilityLabel = "Запомнить категорию для похожих платежей"
        toggle.addAction(UIAction { [weak toggle] _ in if let toggle { onRemember(toggle.isOn) } }, for: .valueChanged)
        let rememberRow = UIStackView(arrangedSubviews: [label("Запомнить для похожих платежей", size: 13), toggle])
        rememberRow.alignment = .center
        rememberRow.spacing = 12
        stack.addArrangedSubview(rememberRow)
        if let proposed = item.suggestedCategory, proposed != row.category {
            let accept = UIButton(type: .system)
            FinLitTheme.configurePrimaryButton(accept, title: "Принять · \(proposed.rawValue)", image: "checkmark")
            accept.addAction(UIAction { _ in onChoose(proposed) }, for: .touchUpInside)
            stack.addArrangedSubview(accept)
        }
        let keep = UIButton(type: .system)
        var keepConfig = UIButton.Configuration.gray()
        keepConfig.title = "Оставить · \(row.category.rawValue)"
        keepConfig.titleLineBreakMode = .byWordWrapping
        keepConfig.image = UIImage(systemName: "checkmark.circle")
        keepConfig.imagePadding = 8
        keepConfig.baseForegroundColor = .label
        keepConfig.contentInsets = .init(top: 13, leading: 12, bottom: 13, trailing: 12)
        keep.configuration = keepConfig
        keep.addAction(UIAction { _ in onChoose(row.category) }, for: .touchUpInside)
        stack.addArrangedSubview(keep)
        let choose = UIButton(type: .system)
        var config = UIButton.Configuration.plain()
        config.title = "Выбрать другую категорию"
        config.titleLineBreakMode = .byWordWrapping
        config.image = UIImage(systemName: "slider.horizontal.3")
        config.imagePadding = 8
        config.baseForegroundColor = FinLitTheme.accent
        config.contentInsets = .init(top: 12, leading: 8, bottom: 12, trailing: 8)
        choose.configuration = config
        choose.showsMenuAsPrimaryAction = true
        choose.menu = UIMenu(title: "Категория операции", children: TxCategory.allCases.map { category in
            UIAction(title: category.rawValue, image: UIImage(systemName: category.icon), state: category == row.category ? .on : .off) { _ in onChoose(category) }
        })
        stack.addArrangedSubview(choose)
    }
}
