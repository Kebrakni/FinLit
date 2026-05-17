import UIKit

// MARK: - AIAnalyzerViewController

final class AIAnalyzerViewController: UIViewController {

    // MARK: - State

    private enum ViewState { case empty, loading(String), results }
    private var state: ViewState = .empty {
        didSet { applyState() }
    }
    private var analysis: AIAnalysis?
    private var allTransactions: [Transaction] = []
    private var uncertainItems: [AIAnalysis.Categorization] = []

    // MARK: - UI

    private let tableView       = UITableView(frame: .zero, style: .insetGrouped)
    private let emptyView       = UIView()
    private let loadingView     = UIView()
    private let loadingSpinner  = UIActivityIndicatorView(style: .large)
    private let loadingLabel    = UILabel()
    private let analyzeButton   = UIButton(type: .system)

    private lazy var dateFormatter: DateFormatter = {
        let df = DateFormatter(); df.locale = Locale(identifier: "ru_RU"); df.dateFormat = "dd.MM.yyyy"; return df
    }()
    private lazy var numFormatter: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0; return f
    }()

    // MARK: - Section enum

    private enum Section: Int, CaseIterable {
        case insights = 0, advice, uncertain, allTransactions
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "AI Анализатор"
        view.backgroundColor = .systemBackground
        setupNavBar()
        setupEmptyView()
        setupLoadingView()
        setupTableView()
        loadData()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadData()
    }

    // MARK: - Setup

    private func setupNavBar() {
        analyzeButton.setTitle("Анализировать", for: .normal)
        analyzeButton.setImage(UIImage(systemName: "sparkles"), for: .normal)
        analyzeButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        analyzeButton.addTarget(self, action: #selector(didTapAnalyze), for: .touchUpInside)
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: analyzeButton)
    }

    private func setupEmptyView() {
        emptyView.translatesAutoresizingMaskIntoConstraints = false
        emptyView.isHidden = true

        let icon = UIImageView(image: UIImage(systemName: "doc.text.magnifyingglass"))
        icon.tintColor = .secondaryLabel
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = "Загрузи PDF выписку\nв Аналитике, затем\nнажми «Анализировать»"
        label.font = .systemFont(ofSize: 16)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false

        emptyView.addSubview(icon); emptyView.addSubview(label)
        view.addSubview(emptyView)

        NSLayoutConstraint.activate([
            emptyView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            icon.centerXAnchor.constraint(equalTo: emptyView.centerXAnchor),
            icon.topAnchor.constraint(equalTo: emptyView.topAnchor),
            icon.widthAnchor.constraint(equalToConstant: 64),
            icon.heightAnchor.constraint(equalToConstant: 64),
            label.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 16),
            label.leadingAnchor.constraint(equalTo: emptyView.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: emptyView.trailingAnchor),
            label.bottomAnchor.constraint(equalTo: emptyView.bottomAnchor),
            emptyView.widthAnchor.constraint(equalToConstant: 260),
        ])
    }

    private func setupLoadingView() {
        loadingView.translatesAutoresizingMaskIntoConstraints = false
        loadingView.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.92)
        loadingView.isHidden = true
        loadingView.layer.cornerRadius = 20

        loadingSpinner.translatesAutoresizingMaskIntoConstraints = false
        loadingSpinner.color = .systemBlue

        loadingLabel.translatesAutoresizingMaskIntoConstraints = false
        loadingLabel.font = .systemFont(ofSize: 15, weight: .medium)
        loadingLabel.textColor = .secondaryLabel
        loadingLabel.textAlignment = .center
        loadingLabel.numberOfLines = 2

        loadingView.addSubview(loadingSpinner)
        loadingView.addSubview(loadingLabel)
        view.addSubview(loadingView)

        NSLayoutConstraint.activate([
            loadingView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            loadingView.widthAnchor.constraint(equalToConstant: 220),
            loadingView.heightAnchor.constraint(equalToConstant: 130),
            loadingSpinner.topAnchor.constraint(equalTo: loadingView.topAnchor, constant: 24),
            loadingSpinner.centerXAnchor.constraint(equalTo: loadingView.centerXAnchor),
            loadingLabel.topAnchor.constraint(equalTo: loadingSpinner.bottomAnchor, constant: 16),
            loadingLabel.leadingAnchor.constraint(equalTo: loadingView.leadingAnchor, constant: 16),
            loadingLabel.trailingAnchor.constraint(equalTo: loadingView.trailingAnchor, constant: -16),
        ])
    }

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate   = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "BasicCell")
        tableView.register(InsightsCell.self,    forCellReuseIdentifier: "InsightsCell")
        tableView.register(TxEditCell.self,      forCellReuseIdentifier: "TxEditCell")
        tableView.isHidden = true
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: - Data

    private func loadData() {
        allTransactions = AppStorage.shared.loadAllTransactions()
        if allTransactions.isEmpty {
            state = .empty
        } else if analysis == nil {
            tableView.isHidden = true
            emptyView.isHidden = false
            loadingView.isHidden = true
        }
    }

    private func applyState() {
        switch state {
        case .empty:
            tableView.isHidden = true
            emptyView.isHidden = false
            loadingView.isHidden = true
            loadingSpinner.stopAnimating()
            analyzeButton.isEnabled = true

        case .loading(let msg):
            tableView.isHidden = false
            emptyView.isHidden = true
            loadingView.isHidden = false
            loadingLabel.text = msg
            loadingSpinner.startAnimating()
            analyzeButton.isEnabled = false

        case .results:
            loadingView.isHidden = true
            loadingSpinner.stopAnimating()
            tableView.isHidden = false
            emptyView.isHidden = true
            analyzeButton.isEnabled = true
            tableView.reloadData()
        }
    }

    // MARK: - Analyze action

    @objc private func didTapAnalyze() {
        allTransactions = AppStorage.shared.loadAllTransactions()
        guard !allTransactions.isEmpty else {
            showAlert("Нет данных", "Сначала загрузи PDF выписку в разделе «Аналитика».")
            return
        }
        state = .loading("Отправляю запрос к AI...")

        Task { @MainActor in
            do {
                loadingLabel.text = "AI анализирует транзакции..."
                let result = try await AIService.shared.analyzeTransactions(allTransactions)
                self.analysis = result
                self.uncertainItems = result.categorizations.filter { $0.isUncertain }
                self.applyAISuggestions(result)
                self.state = .results
            } catch {
                self.state = allTransactions.isEmpty ? .empty : .results
                self.showAlert("Ошибка AI", error.localizedDescription)
            }
        }
    }

    // Auto-apply high-confidence categorizations
    private func applyAISuggestions(_ analysis: AIAnalysis) {
        for cat in analysis.categorizations where !cat.isUncertain && cat.confidence >= 0.75 {
            AppStorage.shared.saveCategoryOverride(transactionId: cat.transactionId,
                                                   categoryName: cat.suggestedCategory)
        }
        allTransactions = AppStorage.shared.loadAllTransactions()
    }

    // MARK: - Category editing

    func showCategoryPicker(for tx: Transaction, aiSuggestions: [String] = [], at indexPath: IndexPath) {
        let picker = CategoryPickerViewController(
            transaction: tx,
            aiSuggestions: aiSuggestions
        ) { [weak self] chosenName in
            AppStorage.shared.saveCategoryOverride(transactionId: tx.id, categoryName: chosenName)
            // Update uncertain list
            self?.uncertainItems.removeAll { $0.transactionId == tx.id }
            self?.tableView.reloadData()
        }
        let nav = UINavigationController(rootViewController: picker)
        if let sheet = nav.sheetPresentationController {
            if #available(iOS 16.0, *) {
                sheet.detents = [.custom { _ in 520 }, .large()]
            } else {
                sheet.detents = [.medium(), .large()]
            }
            sheet.prefersGrabberVisible = true
        }
        present(nav, animated: true)
    }

    // MARK: - Helpers

    private func transaction(for indexPath: IndexPath) -> Transaction? {
        switch Section(rawValue: indexPath.section) {
        case .uncertain:
            guard indexPath.row < uncertainItems.count else { return nil }
            let id = uncertainItems[indexPath.row].transactionId
            return allTransactions.first { $0.id == id }
        case .allTransactions:
            let sorted = allTransactions.sorted { $0.date > $1.date }
            guard indexPath.row < sorted.count else { return nil }
            return sorted[indexPath.row]
        default: return nil
        }
    }

    private func effectiveCategoryName(for tx: Transaction) -> String {
        let overrides = AppStorage.shared.loadCategoryOverrides()
        return overrides[tx.id] ?? tx.category.rawValue
    }

    private func effectiveCategoryColor(for tx: Transaction) -> UIColor {
        let name = effectiveCategoryName(for: tx)
        return TxCategory(rawValue: name)?.uiColor ?? .systemGray
    }

    private func formattedAmount(_ v: Double) -> String {
        let s = numFormatter.string(from: NSNumber(value: abs(v))) ?? "0"
        return "\(v < 0 ? "-" : "+")\(s) ₸"
    }

    private func showAlert(_ title: String, _ message: String) {
        let a = UIAlertController(title: title, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default))
        present(a, animated: true)
    }
}

// MARK: - UITableViewDataSource

extension AIAnalyzerViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        guard analysis != nil else { return 0 }
        return Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let a = analysis else { return 0 }
        switch Section(rawValue: section) {
        case .insights:        return 1
        case .advice:          return a.advice.count
        case .uncertain:       return uncertainItems.count
        case .allTransactions: return allTransactions.count
        default:               return 0
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard analysis != nil else { return nil }
        switch Section(rawValue: section) {
        case .insights:        return "AI Анализ"
        case .advice:          return analysis?.advice.isEmpty == true ? nil : "Советы по экономии"
        case .uncertain:       return uncertainItems.isEmpty ? nil : "Требуют уточнения (\(uncertainItems.count))"
        case .allTransactions: return "Все транзакции — редактируй категории"
        default:               return nil
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section) {

        case .insights:
            let cell = tableView.dequeueReusableCell(withIdentifier: "InsightsCell", for: indexPath) as! InsightsCell
            cell.configure(text: analysis?.insights ?? "")
            return cell

        case .advice:
            let cell: UITableViewCell
            if let c = tableView.dequeueReusableCell(withIdentifier: "AdviceCell") { cell = c }
            else { cell = UITableViewCell(style: .default, reuseIdentifier: "AdviceCell") }
            let advice = analysis?.advice[indexPath.row] ?? ""
            cell.textLabel?.text = "• \(advice)"
            cell.textLabel?.numberOfLines = 0
            cell.textLabel?.font = .systemFont(ofSize: 14)
            cell.textLabel?.textColor = .label
            cell.selectionStyle = .none
            return cell

        case .uncertain:
            let cell = tableView.dequeueReusableCell(withIdentifier: "TxEditCell", for: indexPath) as! TxEditCell
            let item = uncertainItems[indexPath.row]
            if let tx = allTransactions.first(where: { $0.id == item.transactionId }) {
                let catName = effectiveCategoryName(for: tx)
                let altText = item.alternatives.isEmpty ? item.suggestedCategory
                            : item.alternatives.prefix(2).joined(separator: " / ")
                cell.configure(
                    merchant: tx.merchant,
                    date: dateFormatter.string(from: tx.date),
                    amount: formattedAmount(tx.amount),
                    categoryName: catName,
                    categoryColor: effectiveCategoryColor(for: tx),
                    hint: "AI: \(altText) — уточни!",
                    isUncertain: true
                )
            }
            return cell

        case .allTransactions:
            let cell = tableView.dequeueReusableCell(withIdentifier: "TxEditCell", for: indexPath) as! TxEditCell
            let sorted = allTransactions.sorted { $0.date > $1.date }
            let tx = sorted[indexPath.row]
            let catName = effectiveCategoryName(for: tx)
            cell.configure(
                merchant: tx.merchant,
                date: dateFormatter.string(from: tx.date),
                amount: formattedAmount(tx.amount),
                categoryName: catName,
                categoryColor: effectiveCategoryColor(for: tx),
                hint: nil,
                isUncertain: false
            )
            return cell

        default:
            return UITableViewCell()
        }
    }
}

// MARK: - UITableViewDelegate

extension AIAnalyzerViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let tx = transaction(for: indexPath) else { return }

        var aiSuggestions: [String] = []
        if let item = analysis?.categorizations.first(where: { $0.transactionId == tx.id }) {
            aiSuggestions = [item.suggestedCategory] + item.alternatives
        }
        showCategoryPicker(for: tx, aiSuggestions: Array(Set(aiSuggestions)), at: indexPath)
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        UITableView.automaticDimension
    }
    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat { 80 }
}

// MARK: - InsightsCell

private final class InsightsCell: UITableViewCell {
    private let bodyLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        bodyLabel.font = .systemFont(ofSize: 15)
        bodyLabel.numberOfLines = 0
        bodyLabel.textColor = .label
        contentView.addSubview(bodyLabel)
        NSLayoutConstraint.activate([
            bodyLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            bodyLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14),
            bodyLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            bodyLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
    func configure(text: String) { bodyLabel.text = text }
}

// MARK: - TxEditCell

final class TxEditCell: UITableViewCell {

    private let merchantLabel  = UILabel()
    private let dateAmtLabel   = UILabel()
    private let categoryBadge  = UILabel()
    private let hintLabel      = UILabel()
    private let editIcon       = UIImageView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        selectionStyle = .default

        merchantLabel.translatesAutoresizingMaskIntoConstraints = false
        merchantLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        merchantLabel.numberOfLines = 1

        dateAmtLabel.translatesAutoresizingMaskIntoConstraints = false
        dateAmtLabel.font = .systemFont(ofSize: 12)
        dateAmtLabel.textColor = .secondaryLabel

        categoryBadge.translatesAutoresizingMaskIntoConstraints = false
        categoryBadge.font = .systemFont(ofSize: 11, weight: .semibold)
        categoryBadge.layer.cornerRadius = 8
        categoryBadge.clipsToBounds = true
        categoryBadge.textAlignment = .center
        categoryBadge.setContentHuggingPriority(.required, for: .horizontal)
        categoryBadge.setContentCompressionResistancePriority(.required, for: .horizontal)

        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .systemOrange
        hintLabel.numberOfLines = 1

        editIcon.translatesAutoresizingMaskIntoConstraints = false
        editIcon.image = UIImage(systemName: "pencil.circle.fill")
        editIcon.tintColor = .systemBlue.withAlphaComponent(0.7)
        editIcon.contentMode = .scaleAspectFit
        editIcon.setContentHuggingPriority(.required, for: .horizontal)

        let leftStack = UIStackView(arrangedSubviews: [merchantLabel, dateAmtLabel, hintLabel])
        leftStack.axis = .vertical
        leftStack.spacing = 2
        leftStack.translatesAutoresizingMaskIntoConstraints = false

        let rightStack = UIStackView(arrangedSubviews: [categoryBadge, editIcon])
        rightStack.axis = .vertical
        rightStack.spacing = 4
        rightStack.alignment = .trailing
        rightStack.translatesAutoresizingMaskIntoConstraints = false

        let row = UIStackView(arrangedSubviews: [leftStack, rightStack])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            editIcon.widthAnchor.constraint(equalToConstant: 20),
            editIcon.heightAnchor.constraint(equalToConstant: 20),
        ])
    }

    func configure(merchant: String, date: String, amount: String,
                   categoryName: String, categoryColor: UIColor,
                   hint: String?, isUncertain: Bool) {
        merchantLabel.text  = merchant
        dateAmtLabel.text   = "\(date) · \(amount)"
        hintLabel.text      = hint
        hintLabel.isHidden  = hint == nil

        categoryBadge.text            = "  \(categoryName)  "
        categoryBadge.backgroundColor = categoryColor.withAlphaComponent(0.15)
        categoryBadge.textColor       = categoryColor
        categoryBadge.layer.borderColor = categoryColor.cgColor
        categoryBadge.layer.borderWidth = isUncertain ? 1.5 : 0

        editIcon.tintColor = isUncertain ? .systemOrange : .systemBlue.withAlphaComponent(0.5)
    }
}

// MARK: - CategoryPickerViewController

final class CategoryPickerViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    private let transaction: Transaction
    private let aiSuggestions: [String]
    private let onPick: (String) -> Void

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var customFieldCell: UITableViewCell?

    private var sections: [(header: String, items: [String])] = []

    init(transaction: Transaction, aiSuggestions: [String], onPick: @escaping (String) -> Void) {
        self.transaction  = transaction
        self.aiSuggestions = aiSuggestions.filter { !$0.isEmpty }
        self.onPick       = onPick
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Изменить категорию"
        view.backgroundColor = .systemGroupedBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(dismissSelf))

        buildSections()
        setupTable()
    }

    private func buildSections() {
        let currentName = AppStorage.shared.loadCategoryOverrides()[transaction.id] ?? transaction.category.rawValue

        // Section 0: transaction info (1 static cell)
        // Section 1: AI suggestions (if any)
        // Section 2: standard categories
        // Section 3: custom text entry

        if !aiSuggestions.isEmpty {
            let unique = Array(OrderedSet(aiSuggestions))
            sections.append((header: "Предложения AI", items: unique))
        }
        sections.append((header: "Стандартные категории", items: TxCategory.allCases.map { $0.rawValue }))
        sections.append((header: "Своя категория", items: ["__custom__"]))
    }

    private func setupTable() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // Header showing the transaction
        let header = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 72))
        let merchantLbl = UILabel()
        merchantLbl.text = transaction.merchant
        merchantLbl.font = .systemFont(ofSize: 16, weight: .semibold)
        merchantLbl.translatesAutoresizingMaskIntoConstraints = false
        let amtLbl = UILabel()
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        let s = f.string(from: NSNumber(value: abs(transaction.amount))) ?? "0"
        amtLbl.text = "\(transaction.amount < 0 ? "-" : "+")\(s) ₸"
        amtLbl.font = .systemFont(ofSize: 15, weight: .bold)
        amtLbl.textColor = transaction.amount < 0 ? .systemRed : .systemGreen
        amtLbl.translatesAutoresizingMaskIntoConstraints = false
        let df = DateFormatter(); df.dateFormat = "dd.MM.yyyy"
        let dateLbl = UILabel()
        dateLbl.text = df.string(from: transaction.date)
        dateLbl.font = .systemFont(ofSize: 13); dateLbl.textColor = .secondaryLabel
        dateLbl.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(merchantLbl); header.addSubview(amtLbl); header.addSubview(dateLbl)
        NSLayoutConstraint.activate([
            merchantLbl.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 20),
            merchantLbl.topAnchor.constraint(equalTo: header.topAnchor, constant: 16),
            amtLbl.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -20),
            amtLbl.topAnchor.constraint(equalTo: header.topAnchor, constant: 16),
            dateLbl.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 20),
            dateLbl.topAnchor.constraint(equalTo: merchantLbl.bottomAnchor, constant: 4),
        ])
        tableView.tableHeaderView = header
    }

    // MARK: - TableView

    func numberOfSections(in tableView: UITableView) -> Int { sections.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].items.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].header
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = sections[indexPath.section].items[indexPath.row]

        if item == "__custom__" {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.selectionStyle = .none
            let tf = UITextField()
            tf.placeholder = "Введи название категории..."
            tf.font = .systemFont(ofSize: 15)
            tf.returnKeyType = .done
            tf.translatesAutoresizingMaskIntoConstraints = false
            tf.addTarget(self, action: #selector(customFieldChanged(_:)), for: .editingChanged)
            tf.addTarget(self, action: #selector(customFieldDone(_:)), for: .editingDidEndOnExit)
            cell.contentView.addSubview(tf)
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
                tf.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),
                tf.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
                tf.heightAnchor.constraint(equalToConstant: 44),
            ])
            customFieldCell = cell
            return cell
        }

        let cell: UITableViewCell
        if let c = tableView.dequeueReusableCell(withIdentifier: "CatCell") { cell = c }
        else { cell = UITableViewCell(style: .default, reuseIdentifier: "CatCell") }

        cell.textLabel?.text = item
        let color = TxCategory(rawValue: item)?.uiColor ?? .systemBlue
        cell.imageView?.image = UIImage(systemName: TxCategory(rawValue: item)?.icon ?? "tag.fill")?
            .withTintColor(color, renderingMode: .alwaysOriginal)

        let currentName = AppStorage.shared.loadCategoryOverrides()[transaction.id] ?? transaction.category.rawValue
        cell.accessoryType = (item == currentName) ? .checkmark : .none

        // AI badge
        if aiSuggestions.contains(item) {
            let badge = UILabel()
            badge.text = " AI "
            badge.font = .systemFont(ofSize: 10, weight: .bold)
            badge.textColor = .white
            badge.backgroundColor = .systemBlue
            badge.layer.cornerRadius = 5
            badge.clipsToBounds = true
            badge.sizeToFit()
            cell.accessoryView = badge
        } else {
            cell.accessoryView = nil
        }

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = sections[indexPath.section].items[indexPath.row]
        if item == "__custom__" { return }
        pickCategory(item)
    }

    private func pickCategory(_ name: String) {
        onPick(name)
        dismiss(animated: true)
    }

    @objc private func customFieldChanged(_ tf: UITextField) {}

    @objc private func customFieldDone(_ tf: UITextField) {
        let name = (tf.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        pickCategory(name)
    }

    @objc private func dismissSelf() { dismiss(animated: true) }
}

// MARK: - Minimal ordered set for dedup preserving order

private struct OrderedSet<T: Hashable>: Sequence {
    private var items: [T] = []
    private var seen = Set<T>()
    init(_ seq: [T]) { seq.forEach { if seen.insert($0).inserted { items.append($0) } } }
    func makeIterator() -> IndexingIterator<[T]> { items.makeIterator() }
}
