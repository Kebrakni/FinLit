// AnalyticsViewController.swift
import UIKit
import MobileCoreServices
import UniformTypeIdentifiers

final class AnalyticsViewController: UIViewController,
                                     UITableViewDataSource,
                                     UITableViewDelegate,
                                     UIDocumentPickerDelegate {

    // Все накопленные транзакции (из всех загруженных выписок)
    private var allTransactions: [Transaction] = []
    private var expenseTotals: [(TxCategory, Double)] = []
    private var incomeTotals:  [(TxCategory, Double)] = []

    private var totalIncome:  Double = 0
    private var totalExpense: Double = 0
    private var netSavings:   Double = 0

    // MARK: - UI

    private let importButton  = UIButton(type: .system)
    private let resetButton   = UIButton(type: .system)
    private let progressOverlay = ImportProgressView()
    private let summaryCard   = UIView()
    private let incomeRow     = SummaryRow(icon: "arrow.down", color: .systemGreen, title: "Доходы")
    private let expenseRow    = SummaryRow(icon: "arrow.up", color: .systemRed, title: "Расходы")
    private let netRow        = SummaryRow(icon: "chart.line.uptrend.xyaxis", color: FinLitTheme.accent, title: "Баланс")
    private let statLabel     = UILabel()   // сколько выписок загружено
    private let battleBanner  = UIView()
    private let battleLabel   = UILabel()
    private let tableView     = UITableView(frame: .zero, style: .insetGrouped)

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = FinLitTheme.background
        title = "Аналитика"
        let aiButton = UIButton(type: .system)
        aiButton.setImage(UIImage(systemName: "sparkles"), for: .normal)
        aiButton.tintColor = FinLitTheme.accent
        aiButton.backgroundColor = FinLitTheme.accentSoft
        aiButton.layer.cornerRadius = 18
        aiButton.layer.cornerCurve = .continuous
        aiButton.frame = CGRect(x: 0, y: 0, width: 36, height: 36)
        aiButton.addTarget(self, action: #selector(openAIChat), for: .touchUpInside)
        let aiItem = UIBarButtonItem(customView: aiButton)
        aiItem.accessibilityLabel = "AI-помощник"

        let toolsButton = UIButton(type: .system)
        toolsButton.setImage(UIImage(systemName: "calendar.badge.clock"), for: .normal)
        toolsButton.tintColor = .systemPurple
        toolsButton.backgroundColor = UIColor.systemPurple.withAlphaComponent(0.12)
        toolsButton.layer.cornerRadius = 18
        toolsButton.layer.cornerCurve = .continuous
        toolsButton.frame = CGRect(x: 0, y: 0, width: 36, height: 36)
        toolsButton.addTarget(self, action: #selector(openFinancialTools), for: .touchUpInside)
        let toolsItem = UIBarButtonItem(customView: toolsButton)
        toolsItem.accessibilityLabel = "Финансовые инструменты"
        navigationItem.rightBarButtonItems = [aiItem, toolsItem]
        setupUI()
        loadAndRender()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadAndRender()
    }

    // MARK: - Setup

    private func setupUI() {
        // Import button
        importButton.translatesAutoresizingMaskIntoConstraints = false
        FinLitTheme.configurePrimaryButton(
            importButton,
            title: "Загрузить PDF выписку",
            image: "doc.badge.arrow.up"
        )
        importButton.addTarget(self, action: #selector(importPDF), for: .touchUpInside)

        // Reset button
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        var resetConfiguration = UIButton.Configuration.gray()
        resetConfiguration.title = "Сбросить"
        resetConfiguration.image = UIImage(systemName: "trash")
        resetConfiguration.imagePadding = 6
        resetConfiguration.baseForegroundColor = .systemRed
        resetConfiguration.cornerStyle = .capsule
        resetConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 11, bottom: 7, trailing: 11)
        resetButton.configuration = resetConfiguration
        resetButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        resetButton.addTarget(self, action: #selector(didTapReset), for: .touchUpInside)

        // Stat label
        statLabel.translatesAutoresizingMaskIntoConstraints = false
        statLabel.font = .systemFont(ofSize: 13, weight: .medium)
        statLabel.textColor = .secondaryLabel
        statLabel.textAlignment = .left

        // Summary card
        summaryCard.translatesAutoresizingMaskIntoConstraints = false
        FinLitTheme.styleCard(summaryCard, radius: 24)

        for row in [incomeRow, expenseRow, netRow] {
            row.translatesAutoresizingMaskIntoConstraints = false
            summaryCard.addSubview(row)
        }

        // Battle banner
        battleBanner.translatesAutoresizingMaskIntoConstraints = false
        battleBanner.layer.cornerRadius = 18
        battleBanner.layer.cornerCurve = .continuous
        battleBanner.isHidden = true

        battleLabel.translatesAutoresizingMaskIntoConstraints = false
        battleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        battleLabel.textColor = .white
        battleLabel.textAlignment = .center
        battleLabel.numberOfLines = 2
        battleBanner.addSubview(battleLabel)

        // Table
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate   = self
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.showsVerticalScrollIndicator = false

        view.addSubview(importButton)
        view.addSubview(resetButton)
        view.addSubview(statLabel)
        view.addSubview(summaryCard)
        view.addSubview(battleBanner)
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            importButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            importButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            importButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            statLabel.topAnchor.constraint(equalTo: importButton.bottomAnchor, constant: 13),
            statLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            statLabel.trailingAnchor.constraint(lessThanOrEqualTo: resetButton.leadingAnchor, constant: -10),

            resetButton.centerYAnchor.constraint(equalTo: statLabel.centerYAnchor),
            resetButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            summaryCard.topAnchor.constraint(equalTo: statLabel.bottomAnchor, constant: 14),
            summaryCard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            summaryCard.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            incomeRow.topAnchor.constraint(equalTo: summaryCard.topAnchor, constant: 12),
            incomeRow.leadingAnchor.constraint(equalTo: summaryCard.leadingAnchor, constant: 12),
            incomeRow.trailingAnchor.constraint(equalTo: summaryCard.trailingAnchor, constant: -12),

            expenseRow.topAnchor.constraint(equalTo: incomeRow.bottomAnchor, constant: 8),
            expenseRow.leadingAnchor.constraint(equalTo: summaryCard.leadingAnchor, constant: 12),
            expenseRow.trailingAnchor.constraint(equalTo: summaryCard.trailingAnchor, constant: -12),

            netRow.topAnchor.constraint(equalTo: expenseRow.bottomAnchor, constant: 8),
            netRow.leadingAnchor.constraint(equalTo: summaryCard.leadingAnchor, constant: 12),
            netRow.trailingAnchor.constraint(equalTo: summaryCard.trailingAnchor, constant: -12),
            netRow.bottomAnchor.constraint(equalTo: summaryCard.bottomAnchor, constant: -12),

            battleBanner.topAnchor.constraint(equalTo: summaryCard.bottomAnchor, constant: 12),
            battleBanner.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            battleBanner.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            battleLabel.topAnchor.constraint(equalTo: battleBanner.topAnchor, constant: 10),
            battleLabel.bottomAnchor.constraint(equalTo: battleBanner.bottomAnchor, constant: -10),
            battleLabel.leadingAnchor.constraint(equalTo: battleBanner.leadingAnchor, constant: 12),
            battleLabel.trailingAnchor.constraint(equalTo: battleBanner.trailingAnchor, constant: -12),

            tableView.topAnchor.constraint(equalTo: battleBanner.bottomAnchor, constant: 6),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: - Load

    private func loadAndRender() {
        allTransactions = AppStorage.shared.loadAllTransactions()
        recompute()
        render()
        tableView.reloadData()
    }

    // MARK: - PDF Import

    @objc private func importPDF() {
        if #available(iOS 14.0, *) {
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.pdf], asCopy: true)
            picker.delegate = self; picker.allowsMultipleSelection = false
            present(picker, animated: true)
        } else {
            let picker = UIDocumentPickerViewController(documentTypes: ["com.adobe.pdf"], in: .import)
            picker.delegate = self; picker.allowsMultipleSelection = false
            present(picker, animated: true)
        }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        setImporting(true)
        progressOverlay.update(progress: 0.04, title: "Читаем выписку", detail: "Извлекаем операции из PDF")

        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await Task.detached(priority: .userInitiated) {
                let started = url.startAccessingSecurityScopedResource()
                defer { if started { url.stopAccessingSecurityScopedResource() } }
                return KaspiPDFParser().parse(pdfURL: url)
            }.value
            self.handleParsedStatement(result)
        }
    }

    private func handleParsedStatement(_ result: KaspiPDFParser.ParseResult) {
        progressOverlay.update(progress: 0.18, title: "Операции найдены", detail: "Проверяем данные и дубликаты")

        if !result.errors.isEmpty {
            setImporting(false)
            showAlert(title: "Ошибка парсинга", message: result.errors.prefix(5).joined(separator: "\n"))
            return
        }

        guard !result.transactions.isEmpty else {
            setImporting(false)
            showAlert(title: "Пусто", message: "Транзакции не найдены в этом PDF")
            return
        }

        // Keep only genuinely new calendar days. A wider statement can safely
        // add its extra days without duplicating the already imported period.
        let fingerprint = AppStorage.shared.makeFingerprint(result.transactions)
        let importPlan = AppStorage.shared.prepareStatementImport(result.transactions)
        if importPlan.isFullyOverlapping {
            let df = DateFormatter(); df.dateFormat = "dd.MM.yyyy"
            let overlapText: String
            if let from = importPlan.overlapFrom, let to = importPlan.overlapTo {
                overlapText = Calendar.current.isDate(from, inSameDayAs: to)
                    ? df.string(from: from)
                    : "\(df.string(from: from)) – \(df.string(from: to))"
            } else {
                overlapText = "весь период"
            }
            setImporting(false)
            showAlert(
                title: "Новых операций нет",
                message: "Период \(overlapText) уже загружен. Повторяющиеся дни и операции не были добавлены."
            )
            return
        }

        let parsedTransactions = importPlan.newTransactions
        Task { [weak self] in
            guard let self else { return }

            var categorizedTransactions = parsedTransactions
            var aiWasUsed = false

            do {
                await MainActor.run {
                    self.progressOverlay.beginEstimatedAIProgress(
                        totalTransactions: parsedTransactions.count
                    )
                }
                let categories = try await OpenRouterCategorizer.shared.categorize(
                    parsedTransactions,
                    progress: { [weak self] processed, total in
                        Task { @MainActor in
                            self?.progressOverlay.reportRealAIProgress(
                                processed: processed,
                                total: total
                            )
                        }
                    }
                )
                categorizedTransactions = parsedTransactions.map { transaction in
                    let learned = LearnedCategoryRules.category(for: transaction.merchant)
                    return transaction.withCategory(
                        learned ?? categories[transaction.id] ?? transaction.category
                    )
                }
                aiWasUsed = !categories.isEmpty
            } catch {
                // Local categorization is deliberately kept as a safe fallback.
                print("AI categorization failed: \(error.localizedDescription)")
                await MainActor.run {
                    self.progressOverlay.update(
                        progress: 0.92,
                        title: "Завершаем обработку",
                        detail: "AI недоступен — сохраняем локальный результат"
                    )
                }
            }

            await MainActor.run { [weak self] in
                self?.progressOverlay.update(
                    progress: 0.97,
                    title: "Сохраняем результат",
                    detail: "Обновляем аналитику"
                )
                self?.finishImport(
                    transactions: categorizedTransactions,
                    fingerprint: fingerprint,
                    aiWasUsed: aiWasUsed,
                    importPlan: importPlan
                )
            }
        }
    }

    private func finishImport(
        transactions: [Transaction],
        fingerprint: String,
        aiWasUsed: Bool,
        importPlan: StatementImportPlan
    ) {
        progressOverlay.update(progress: 1, title: "Готово", detail: "Аналитика обновлена")
        AppStorage.shared.markAsImported(fingerprint, plan: importPlan)
        allTransactions = AppStorage.shared.mergeTransactions(transactions)
        AppStorage.shared.recalculateAndSaveNet()
        GamificationManager.shared.recordStatementImport(
            eventID: fingerprint,
            count: transactions.count
        )

        recompute()
        render()
        tableView.reloadData()
        let df = DateFormatter(); df.dateFormat = "dd.MM.yyyy"
        let sorted = transactions.sorted { $0.date < $1.date }
        let from = df.string(from: sorted.first!.date)
        let to = df.string(from: sorted.last!.date)
        let mode = aiWasUsed ? "Категории назначены AI" : "Использованы локальные категории"

        var message = "Добавлено \(transactions.count) транзакций (\(from) – \(to))\n\(mode)"
        if importPlan.hasOverlap {
            message += "\nПропущено повторяющихся операций: \(importPlan.skippedTransactionCount)"
        }
        message += "\nВсего накоплено: \(allTransactions.count) транзакций"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self else { return }
            self.setImporting(false)
            self.showAlert(title: "Выписка добавлена", message: message)
        }
    }

    private func setImporting(_ importing: Bool) {
        importButton.isEnabled = !importing
        importButton.alpha = importing ? 0.65 : 1
        importButton.configuration?.title = importing ? "Анализируем выписку…" : "Загрузить PDF выписку"
        if importing {
            progressOverlay.present(in: view)
        } else {
            progressOverlay.dismiss()
        }
    }

    @objc private func openAIChat() {
        let chat = AIChatViewController(transactions: allTransactions) { [weak self] corrections in
            guard let self else { return }
            self.allTransactions = AppStorage.shared.applyTransactionCorrections(corrections)
            self.recompute()
            self.render()
            self.tableView.reloadData()
        }
        let navigation = UINavigationController(rootViewController: chat)
        navigation.modalPresentationStyle = .fullScreen
        present(navigation, animated: true)
    }

    @objc private func openFinancialTools() {
        let tools = FinancialToolsViewController()
        navigationController?.pushViewController(tools, animated: true)
    }

    // MARK: - Reset

    @objc private func didTapReset() {
        let alert = UIAlertController(
            title: "Сбросить все данные?",
            message: "Все загруженные выписки и история транзакций будут удалены. Это действие нельзя отменить.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "Сбросить", style: .destructive, handler: { [weak self] _ in
            AppStorage.shared.clearAllTransactions()
            self?.loadAndRender()
        }))
        present(alert, animated: true)
    }

    // MARK: - Computation

    private func recompute() {
        let expenses = allTransactions.filter { $0.amount < 0 }
        let incomes  = allTransactions.filter { $0.amount > 0 }

        totalIncome  = incomes.reduce(0.0)  { $0 + $1.amount }
        totalExpense = expenses.reduce(0.0) { $0 + (-$1.amount) }
        netSavings   = totalIncome - totalExpense

        let expenseGrouped = Dictionary(grouping: expenses, by: { $0.category })
        expenseTotals = expenseGrouped
            .map { (cat, list) in (cat, list.reduce(0.0) { $0 + (-$1.amount) }) }
            .sorted { $0.1 > $1.1 }

        let incomeGrouped = Dictionary(grouping: incomes, by: { $0.category })
        incomeTotals = incomeGrouped
            .map { (cat, list) in (cat, list.reduce(0.0) { $0 + $1.amount }) }
            .sorted { $0.1 > $1.1 }
    }

    private func render() {
        guard !allTransactions.isEmpty else {
            incomeRow.setValue("—")
            expenseRow.setValue("—")
            netRow.setValue("—")
            statLabel.text = "Выписки не загружены"
            battleBanner.isHidden = true
            resetButton.isHidden = true
            return
        }

        resetButton.isHidden = false

        // Диапазон дат
        let sorted = allTransactions.sorted { $0.date < $1.date }
        let df = DateFormatter(); df.dateFormat = "dd.MM.yyyy"
        let fromDate = df.string(from: sorted.first!.date)
        let toDate   = df.string(from: sorted.last!.date)
        statLabel.text = "\(fromDate) – \(toDate)  •  \(allTransactions.count) транзакций"

        incomeRow.setValue(formatMoneyAbs(totalIncome))
        expenseRow.setValue(formatMoneyAbs(totalExpense))
        netRow.setValue(formatMoneyNet(netSavings))
        netRow.setValueColor(netSavings >= 0 ? .systemGreen : .systemRed)

        // Battle banner
        battleBanner.isHidden = false
        if netSavings >= 0 {
            battleBanner.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.85)
            battleLabel.text = "Битва: +\(formatMoneyAbs(netSavings)) — твой счёт обновлён"
        } else {
            battleBanner.backgroundColor = UIColor.systemRed.withAlphaComponent(0.85)
            battleLabel.text = "Битва: \(formatMoneyNet(netSavings)) — расходы превышают доходы"
        }
    }

    // MARK: - TableView

    func numberOfSections(in tableView: UITableView) -> Int { 2 }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "Расходы по категориям" : "Доходы по категориям"
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? expenseTotals.count : incomeTotals.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell: UITableViewCell
        if let c = tableView.dequeueReusableCell(withIdentifier: "AnalyticsCell") {
            cell = c
        } else {
            cell = UITableViewCell(style: .value1, reuseIdentifier: "AnalyticsCell")
        }
        let item = indexPath.section == 0 ? expenseTotals[indexPath.row] : incomeTotals[indexPath.row]
        let cat = item.0
        let iconConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        cell.imageView?.image = UIImage(systemName: cat.icon, withConfiguration: iconConfig)?
            .withTintColor(cat.uiColor, renderingMode: .alwaysOriginal)
        cell.textLabel?.text = cat.rawValue
        cell.detailTextLabel?.text = formatMoneyAbs(item.1)
        cell.detailTextLabel?.textColor = indexPath.section == 0 ? .systemRed : .systemGreen
        cell.accessoryType = .disclosureIndicator
        cell.backgroundColor = FinLitTheme.surface
        cell.tintColor = FinLitTheme.accent
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = indexPath.section == 0 ? expenseTotals[indexPath.row] : incomeTotals[indexPath.row]
        let cat = item.0
        let wantIncome = indexPath.section == 1
        let list = allTransactions
            .filter { $0.category == cat && (wantIncome ? $0.amount > 0 : $0.amount < 0) }
            .sorted { $0.date > $1.date }
        let vc = CategoryDetailViewController(category: cat, transactions: list)
        navigationController?.pushViewController(vc, animated: true)
    }

    // MARK: - Formatting

    private func formatMoneyAbs(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        return "\(f.string(from: NSNumber(value: abs(v))) ?? "0") ₸"
    }

    private func formatMoneyNet(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        return "\(v < 0 ? "-" : "+")\(f.string(from: NSNumber(value: abs(v))) ?? "0") ₸"
    }

    private func showAlert(title: String, message: String) {
        let a = UIAlertController(title: title, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default))
        present(a, animated: true)
    }
}

// MARK: - SummaryRow

final class SummaryRow: UIView {
    private let iconBackground = UIView()
    private let iconView  = UIImageView()
    private let titleLbl  = UILabel()
    private let valueLbl  = UILabel()

    init(icon: String, color: UIColor, title: String) {
        super.init(frame: .zero)

        iconBackground.translatesAutoresizingMaskIntoConstraints = false
        iconBackground.backgroundColor = color.withAlphaComponent(0.13)
        iconBackground.layer.cornerRadius = 15
        iconBackground.layer.cornerCurve = .continuous

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = UIImage(systemName: icon); iconView.tintColor = color
        iconView.contentMode = .scaleAspectFit
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)

        titleLbl.translatesAutoresizingMaskIntoConstraints = false
        titleLbl.text = title; titleLbl.font = .systemFont(ofSize: 15, weight: .medium)
        titleLbl.textColor = .secondaryLabel

        valueLbl.translatesAutoresizingMaskIntoConstraints = false
        valueLbl.font = .systemFont(ofSize: 16, weight: .bold)
        valueLbl.textColor = color; valueLbl.textAlignment = .right; valueLbl.text = "—"

        addSubview(iconBackground); iconBackground.addSubview(iconView)
        addSubview(titleLbl); addSubview(valueLbl)

        NSLayoutConstraint.activate([
            iconBackground.leadingAnchor.constraint(equalTo: leadingAnchor),
            iconBackground.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconBackground.widthAnchor.constraint(equalToConstant: 30),
            iconBackground.heightAnchor.constraint(equalToConstant: 30),

            iconView.centerXAnchor.constraint(equalTo: iconBackground.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconBackground.centerYAnchor),

            titleLbl.leadingAnchor.constraint(equalTo: iconBackground.trailingAnchor, constant: 10),
            titleLbl.centerYAnchor.constraint(equalTo: centerYAnchor),

            valueLbl.trailingAnchor.constraint(equalTo: trailingAnchor),
            valueLbl.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueLbl.leadingAnchor.constraint(greaterThanOrEqualTo: titleLbl.trailingAnchor, constant: 8),

            heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func setValue(_ text: String) { valueLbl.text = text }
    func setValueColor(_ color: UIColor) { valueLbl.textColor = color }
}

// MARK: - Import progress

final class ImportProgressView: UIView {
    private let card = UIView()
    private let iconBackground = UIView()
    private let symbol = UIImageView(image: UIImage(systemName: "sparkles"))
    private let stageLabel = UILabel()
    private let percentLabel = UILabel()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let estimateLabel = UILabel()

    private var estimationTimer: Timer?
    private var aiStartedAt: Date?
    private var estimatedDuration: TimeInterval = 30
    private var aiTransactionCount = 0
    private var realProcessedCount = 0
    private var realProgressFloor = 0.22
    private var displayedProgress = 0.0

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = UIColor.black.withAlphaComponent(0.52)
        alpha = 0

        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = FinLitTheme.elevatedSurface
        card.layer.cornerRadius = 28
        card.layer.cornerCurve = .continuous
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.28
        card.layer.shadowRadius = 30
        card.layer.shadowOffset = CGSize(width: 0, height: 16)

        iconBackground.translatesAutoresizingMaskIntoConstraints = false
        iconBackground.backgroundColor = FinLitTheme.accentSoft
        iconBackground.layer.cornerRadius = 22
        iconBackground.layer.cornerCurve = .continuous

        symbol.translatesAutoresizingMaskIntoConstraints = false
        symbol.tintColor = FinLitTheme.accent
        symbol.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 23, weight: .semibold)

        stageLabel.translatesAutoresizingMaskIntoConstraints = false
        stageLabel.text = "ОБРАБОТКА ВЫПИСКИ"
        stageLabel.font = .systemFont(ofSize: 11, weight: .bold)
        stageLabel.textColor = .secondaryLabel

        percentLabel.translatesAutoresizingMaskIntoConstraints = false
        percentLabel.font = .monospacedDigitSystemFont(ofSize: 30, weight: .bold)
        percentLabel.textColor = .label
        percentLabel.textAlignment = .right
        percentLabel.text = "0%"

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.textAlignment = .left

        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.font = .systemFont(ofSize: 14, weight: .medium)
        detailLabel.textColor = .secondaryLabel
        detailLabel.textAlignment = .left
        detailLabel.numberOfLines = 2

        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.progressTintColor = FinLitTheme.accent
        progressView.trackTintColor = .systemFill
        progressView.layer.cornerRadius = 5
        progressView.clipsToBounds = true

        estimateLabel.translatesAutoresizingMaskIntoConstraints = false
        estimateLabel.font = .systemFont(ofSize: 12, weight: .medium)
        estimateLabel.textColor = .tertiaryLabel
        estimateLabel.text = "Подготавливаем данные…"

        addSubview(card)
        [iconBackground, stageLabel, percentLabel, titleLabel, detailLabel, progressView, estimateLabel].forEach(card.addSubview)
        iconBackground.addSubview(symbol)

        NSLayoutConstraint.activate([
            card.centerYAnchor.constraint(equalTo: centerYAnchor),
            card.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            card.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -28),

            iconBackground.topAnchor.constraint(equalTo: card.topAnchor, constant: 24),
            iconBackground.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
            iconBackground.widthAnchor.constraint(equalToConstant: 44),
            iconBackground.heightAnchor.constraint(equalToConstant: 44),

            symbol.centerXAnchor.constraint(equalTo: iconBackground.centerXAnchor),
            symbol.centerYAnchor.constraint(equalTo: iconBackground.centerYAnchor),

            stageLabel.leadingAnchor.constraint(equalTo: iconBackground.trailingAnchor, constant: 12),
            stageLabel.centerYAnchor.constraint(equalTo: iconBackground.centerYAnchor),
            stageLabel.trailingAnchor.constraint(lessThanOrEqualTo: percentLabel.leadingAnchor, constant: -10),

            percentLabel.centerYAnchor.constraint(equalTo: iconBackground.centerYAnchor),
            percentLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),

            titleLabel.topAnchor.constraint(equalTo: iconBackground.bottomAnchor, constant: 22),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),

            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            detailLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
            detailLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),

            progressView.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: 24),
            progressView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
            progressView.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),
            progressView.heightAnchor.constraint(equalToConstant: 10),

            estimateLabel.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 11),
            estimateLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
            estimateLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),
            estimateLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -24),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func present(in container: UIView) {
        guard superview == nil else { return }
        container.addSubview(self)
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: container.topAnchor),
            leadingAnchor.constraint(equalTo: container.leadingAnchor),
            trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        container.layoutIfNeeded()
        UIView.animate(withDuration: 0.22) { self.alpha = 1 }
    }

    func update(progress: Double, title: String, detail: String) {
        let value = min(max(progress, 0), 1)
        if value >= 0.92 { stopEstimation() }
        titleLabel.text = title
        detailLabel.text = detail
        if value < 0.22 {
            estimateLabel.text = "Подготавливаем данные…"
        } else if value >= 0.97 {
            estimateLabel.text = value >= 1 ? "Все этапы завершены" : "Осталось совсем немного"
        }
        setVisualProgress(value)
    }

    func beginEstimatedAIProgress(totalTransactions: Int) {
        stopEstimation()
        aiStartedAt = Date()
        aiTransactionCount = max(totalTransactions, 1)
        realProcessedCount = 0
        realProgressFloor = 0.22
        estimatedDuration = max(8, Double(aiTransactionCount) * 0.60)
        titleLabel.text = "AI анализирует операции"
        detailLabel.text = "\(aiTransactionCount) операций • прогресс приблизительный"
        estimateLabel.text = "Обычно около \(formattedTime(estimatedDuration))"
        setVisualProgress(0.22)

        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.advanceEstimatedProgress()
        }
        estimationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func reportRealAIProgress(processed: Int, total: Int) {
        guard total > 0 else { return }
        realProcessedCount = max(realProcessedCount, min(processed, total))
        let fraction = Double(realProcessedCount) / Double(total)
        realProgressFloor = min(0.92, 0.22 + fraction * 0.70)
        detailLabel.text = "AI подтвердил \(realProcessedCount) из \(total) операций"
        setVisualProgress(max(displayedProgress, realProgressFloor))
        if realProcessedCount >= total {
            stopEstimation()
            estimateLabel.text = "Ответ получен • формируем аналитику"
        }
    }

    private func advanceEstimatedProgress() {
        guard let aiStartedAt else { return }
        let elapsed = Date().timeIntervalSince(aiStartedAt)
        let normalized = min(max(elapsed / estimatedDuration, 0), 1)
        var estimate = 0.22 + normalized * 0.65
        if elapsed > estimatedDuration {
            let overtime = min((elapsed - estimatedDuration) / max(estimatedDuration, 1), 1)
            estimate = 0.87 + overtime * 0.04
        }
        setVisualProgress(max(realProgressFloor, min(estimate, 0.91)))

        let remaining = max(estimatedDuration - elapsed, 0)
        if remaining > 0 {
            estimateLabel.text = "Примерно \(formattedTime(remaining)) до завершения"
        } else {
            estimateLabel.text = "AI завершает последнюю проверку"
        }
        if realProcessedCount == 0 {
            detailLabel.text = "\(aiTransactionCount) операций • прогресс приблизительный"
        }
    }

    private func setVisualProgress(_ progress: Double) {
        let value = min(max(progress, displayedProgress), 1)
        displayedProgress = value
        percentLabel.text = "\(Int(value * 100))%"
        progressView.setProgress(Float(value), animated: true)
    }

    private func formattedTime(_ interval: TimeInterval) -> String {
        let seconds = max(Int(ceil(interval)), 1)
        if seconds < 60 { return "\(seconds) сек."
        }
        let minutes = seconds / 60
        let remainder = seconds % 60
        return remainder == 0 ? "\(minutes) мин." : "\(minutes) мин. \(remainder) сек."
    }

    private func stopEstimation() {
        estimationTimer?.invalidate()
        estimationTimer = nil
        aiStartedAt = nil
    }

    func dismiss() {
        guard superview != nil else { return }
        stopEstimation()
        UIView.animate(withDuration: 0.2, animations: { self.alpha = 0 }) { _ in
            self.removeFromSuperview()
            self.progressView.progress = 0
            self.displayedProgress = 0
            self.percentLabel.text = "0%"
        }
    }
}

// MARK: - AI transaction assistant

final class AIChatViewController: UIViewController, UITextFieldDelegate {
    private var transactions: [Transaction]
    private var chatMessages: [AIChatMessage]
    private let onApply: ([String: (amount: Double, category: TxCategory)]) -> Void
    private let scrollView = UIScrollView()
    private let messageStack = UIStackView()
    private let emptyStateView = UIStackView()
    private let composer = UIView()
    private let textField = UITextField()
    private let sendButton = UIButton(type: .system)
    private var typingRow: UIView?

    init(
        transactions: [Transaction],
        onApply: @escaping ([String: (amount: Double, category: TxCategory)]) -> Void
    ) {
        self.transactions = transactions
        self.chatMessages = AppStorage.shared.loadAIChatMessages()
        self.onApply = onApply
        super.init(nibName: nil, bundle: nil)
        title = "AI-помощник"
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = FinLitTheme.background
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "xmark"),
            style: .plain,
            target: self,
            action: #selector(close)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "trash"),
            style: .plain,
            target: self,
            action: #selector(clearChat)
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel = "Очистить историю чата"
        setupComposer()
        setupMessages()
        setupEmptyState()
        chatMessages.forEach { message in
            addBubble(
                text: message.text,
                isUser: message.role == .user,
                animated: false,
                persist: false
            )
        }
        updateEmptyState()
    }

    private func setupMessages() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .interactive
        scrollView.contentInset = UIEdgeInsets(top: 16, left: 0, bottom: 18, right: 0)
        scrollView.showsVerticalScrollIndicator = false

        messageStack.translatesAutoresizingMaskIntoConstraints = false
        messageStack.axis = .vertical
        messageStack.spacing = 10
        messageStack.alignment = .fill

        scrollView.addSubview(messageStack)
        view.insertSubview(scrollView, belowSubview: composer)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: composer.topAnchor, constant: -8),

            messageStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            messageStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            messageStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 14),
            messageStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -14),
        ])
    }

    private func setupEmptyState() {
        let icon = UIImageView(image: UIImage(systemName: "bubble.left.and.bubble.right"))
        let titleLabel = UILabel()
        let subtitleLabel = UILabel()
        emptyStateView.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView.axis = .vertical
        emptyStateView.alignment = .center
        emptyStateView.spacing = 8
        emptyStateView.isUserInteractionEnabled = false

        icon.tintColor = FinLitTheme.accent
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 32, weight: .medium)
        titleLabel.text = "Я умею искать и считать"
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.textColor = .label
        subtitleLabel.text = "Например: «Сколько я перевёл Даниялу?»,\n«Покажи траты на еду за сентябрь»\nили «Найди регулярные платежи»"
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .tertiaryLabel
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0

        emptyStateView.addArrangedSubview(icon)
        emptyStateView.addArrangedSubview(titleLabel)
        emptyStateView.addArrangedSubview(subtitleLabel)
        view.insertSubview(emptyStateView, aboveSubview: scrollView)
        NSLayoutConstraint.activate([
            emptyStateView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
            emptyStateView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            emptyStateView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
        ])
    }

    private func setupComposer() {
        composer.translatesAutoresizingMaskIntoConstraints = false
        composer.backgroundColor = FinLitTheme.surface
        composer.layer.cornerRadius = 24
        composer.layer.cornerCurve = .continuous
        composer.layer.borderWidth = 1
        composer.layer.borderColor = UIColor.separator.withAlphaComponent(0.35).cgColor
        composer.layer.shadowColor = UIColor.black.cgColor
        composer.layer.shadowOpacity = 0.10
        composer.layer.shadowRadius = 14
        composer.layer.shadowOffset = CGSize(width: 0, height: 7)

        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.placeholder = "Спросить про операции…"
        textField.returnKeyType = .send
        textField.delegate = self
        textField.clearButtonMode = .whileEditing

        sendButton.translatesAutoresizingMaskIntoConstraints = false
        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(systemName: "arrow.up")
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = FinLitTheme.accent
        configuration.baseForegroundColor = .white
        sendButton.configuration = configuration
        sendButton.addTarget(self, action: #selector(send), for: .touchUpInside)

        composer.addSubview(textField)
        composer.addSubview(sendButton)
        view.addSubview(composer)

        NSLayoutConstraint.activate([
            composer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            composer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            composer.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -8),
            composer.heightAnchor.constraint(equalToConstant: 54),

            textField.leadingAnchor.constraint(equalTo: composer.leadingAnchor, constant: 16),
            textField.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),
            textField.topAnchor.constraint(equalTo: composer.topAnchor, constant: 7),
            textField.bottomAnchor.constraint(equalTo: composer.bottomAnchor, constant: -7),

            sendButton.trailingAnchor.constraint(equalTo: composer.trailingAnchor, constant: -6),
            sendButton.centerYAnchor.constraint(equalTo: composer.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 38),
            sendButton.heightAnchor.constraint(equalToConstant: 38),
        ])
    }

    @objc private func close() { dismiss(animated: true) }

    @objc private func clearChat() {
        guard !chatMessages.isEmpty else { return }
        let alert = UIAlertController(
            title: "Очистить переписку?",
            message: "Все сообщения AI-чата будут удалены с этого устройства.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "Очистить", style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.chatMessages.removeAll()
            AppStorage.shared.clearAIChatMessages()
            self.messageStack.arrangedSubviews.forEach { view in
                self.messageStack.removeArrangedSubview(view)
                view.removeFromSuperview()
            }
            self.typingRow = nil
            self.updateEmptyState()
        })
        present(alert, animated: true)
    }

    @objc private func send() {
        let text = (textField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, sendButton.isEnabled else { return }
        let history = chatMessages
        textField.text = nil
        textField.resignFirstResponder()
        addBubble(text: text, isUser: true)
        setSending(true)
        let testerMode = text.range(
            of: #"^\s*тестер\s*:"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        showTyping(testerMode: testerMode)

        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await OpenRouterCategorizer.shared.review(
                    message: text,
                    history: history,
                    transactions: self.transactions
                )
                await MainActor.run {
                    self.hideTyping()
                    self.setSending(false)
                    self.addBubble(text: result.reply, isUser: false)
                    self.offer(result.changes)
                }
            } catch {
                await MainActor.run {
                    self.hideTyping()
                    self.setSending(false)
                    self.addBubble(
                        text: "Не удалось получить ответ. \(error.localizedDescription)",
                        isUser: false,
                        isError: true,
                        persist: false
                    )
                }
            }
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        send()
        return false
    }

    private func setSending(_ sending: Bool) {
        sendButton.isEnabled = !sending
        textField.isEnabled = !sending
        sendButton.configuration?.showsActivityIndicator = sending
        sendButton.configuration?.image = sending ? nil : UIImage(systemName: "arrow.up")
        navigationItem.rightBarButtonItem?.isEnabled = !sending && !chatMessages.isEmpty
    }

    private func addBubble(
        text: String,
        isUser: Bool,
        isError: Bool = false,
        animated: Bool = true,
        persist: Bool = true
    ) {
        if persist {
            chatMessages.append(
                AIChatMessage(text: text, role: isUser ? .user : .assistant)
            )
            AppStorage.shared.saveAIChatMessages(chatMessages)
        }
        let row = UIView()
        let bubble = UIView()
        let label = UILabel()
        row.translatesAutoresizingMaskIntoConstraints = false
        bubble.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false

        bubble.layer.cornerRadius = 20
        bubble.layer.cornerCurve = .continuous
        bubble.backgroundColor = isUser
            ? FinLitTheme.accent
            : (isError ? UIColor.systemRed.withAlphaComponent(0.13) : FinLitTheme.surface)
        label.text = text
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 16)
        label.textColor = isUser ? .white : (isError ? .systemRed : .label)

        row.addSubview(bubble)
        bubble.addSubview(label)
        messageStack.addArrangedSubview(row)

        var constraints = [
            bubble.topAnchor.constraint(equalTo: row.topAnchor),
            bubble.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            bubble.widthAnchor.constraint(lessThanOrEqualTo: row.widthAnchor, multiplier: 0.82),
            label.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -12),
            label.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 15),
            label.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -15),
        ]
        if isUser {
            constraints.append(bubble.trailingAnchor.constraint(equalTo: row.trailingAnchor))
            constraints.append(bubble.leadingAnchor.constraint(greaterThanOrEqualTo: row.leadingAnchor, constant: 48))
        } else {
            constraints.append(bubble.leadingAnchor.constraint(equalTo: row.leadingAnchor))
            constraints.append(bubble.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -48))
        }
        NSLayoutConstraint.activate(constraints)

        if animated {
            row.alpha = 0
            row.transform = CGAffineTransform(translationX: isUser ? 18 : -18, y: 6)
            UIView.animate(withDuration: 0.22) {
                row.alpha = 1
                row.transform = .identity
            }
        }
        updateEmptyState()
        scrollToBottom()
    }

    private func updateEmptyState() {
        let isEmpty = chatMessages.isEmpty
        emptyStateView.isHidden = !isEmpty
        navigationItem.rightBarButtonItem?.isEnabled = !isEmpty && sendButton.isEnabled
    }

    private func showTyping(testerMode: Bool = false) {
        hideTyping()
        let row = UIView()
        let bubble = UIView()
        let spinner = UIActivityIndicatorView(style: .medium)
        let label = UILabel()
        [row, bubble, spinner, label].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        bubble.backgroundColor = FinLitTheme.surface
        bubble.layer.cornerRadius = 18
        bubble.layer.cornerCurve = .continuous
        label.text = testerMode ? "Выполняю тестовую команду…" : "AI готовит ответ…"
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .secondaryLabel
        spinner.color = FinLitTheme.accent
        spinner.startAnimating()

        row.addSubview(bubble)
        bubble.addSubview(spinner)
        bubble.addSubview(label)
        messageStack.addArrangedSubview(row)
        NSLayoutConstraint.activate([
            bubble.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            bubble.topAnchor.constraint(equalTo: row.topAnchor),
            bubble.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            bubble.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -48),
            spinner.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 14),
            spinner.centerYAnchor.constraint(equalTo: bubble.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: spinner.trailingAnchor, constant: 9),
            label.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -14),
            label.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -12),
        ])
        typingRow = row
        scrollToBottom()
    }

    private func hideTyping() {
        guard let typingRow else { return }
        messageStack.removeArrangedSubview(typingRow)
        typingRow.removeFromSuperview()
        self.typingRow = nil
    }

    private func scrollToBottom() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.view.layoutIfNeeded()
            let y = max(
                -self.scrollView.adjustedContentInset.top,
                self.scrollView.contentSize.height - self.scrollView.bounds.height + self.scrollView.adjustedContentInset.bottom
            )
            self.scrollView.setContentOffset(CGPoint(x: 0, y: y), animated: true)
        }
    }

    private func offer(_ proposed: [OpenRouterCategorizer.ReviewChange]) {
        let byId = Dictionary(uniqueKeysWithValues: transactions.map { ($0.id, $0) })
        let changes = proposed.filter { change in
            guard let transaction = byId[change.id] else { return false }
            return transaction.category != change.category || abs(transaction.amount - change.amount) > 0.001
        }
        guard !changes.isEmpty else { return }

        let lines = changes.prefix(5).compactMap { change -> String? in
            guard let transaction = byId[change.id] else { return nil }
            var line = "• \(transaction.merchant): \(transaction.category.rawValue) → \(change.category.rawValue)"
            if abs(transaction.amount - change.amount) > 0.001 {
                line += "\n  Сумма: \(formatAmount(transaction.amount)) → \(formatAmount(change.amount))"
            }
            return line
        }
        addCorrectionCard(details: lines.joined(separator: "\n")) { [weak self] in
            guard let self else { return false }
            let corrections = Dictionary(uniqueKeysWithValues: changes.map {
                ($0.id, (amount: $0.amount, category: $0.category))
            })
            self.transactions = self.transactions.map { transaction in
                guard let correction = corrections[transaction.id] else { return transaction }
                return transaction.withCorrections(
                    amount: correction.amount,
                    category: correction.category
                )
            }
            self.onApply(corrections)
            GamificationManager.shared.recordAIReview(correctionCount: changes.count)
            self.addBubble(text: "Готово — изменения применены к аналитике.", isUser: false)
            return true
        }
    }

    private func addCorrectionCard(details: String, apply: @escaping () -> Bool) {
        let card = UIView()
        let icon = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
        let titleLabel = UILabel()
        let detailsLabel = UILabel()
        let buttonStack = UIStackView()
        let dismissButton = UIButton(type: .system)
        let applyButton = UIButton(type: .system)
        [card, icon, titleLabel, detailsLabel, buttonStack].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }

        card.backgroundColor = FinLitTheme.accentSoft
        card.layer.cornerRadius = 20
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1
        card.layer.borderColor = FinLitTheme.accent.withAlphaComponent(0.25).cgColor
        icon.tintColor = FinLitTheme.accent
        titleLabel.text = "Предлагаю исправление"
        titleLabel.font = .systemFont(ofSize: 16, weight: .bold)
        detailsLabel.text = details
        detailsLabel.font = .systemFont(ofSize: 14)
        detailsLabel.textColor = .secondaryLabel
        detailsLabel.numberOfLines = 0
        buttonStack.axis = .horizontal
        buttonStack.spacing = 10
        buttonStack.distribution = .fillEqually

        var dismissConfig = UIButton.Configuration.gray()
        dismissConfig.title = "Оставить как есть"
        dismissConfig.cornerStyle = .medium
        dismissButton.configuration = dismissConfig
        var applyConfig = UIButton.Configuration.filled()
        applyConfig.title = "Применить"
        applyConfig.cornerStyle = .medium
        applyButton.configuration = applyConfig

        card.addSubview(icon)
        card.addSubview(titleLabel)
        card.addSubview(detailsLabel)
        card.addSubview(buttonStack)
        buttonStack.addArrangedSubview(dismissButton)
        buttonStack.addArrangedSubview(applyButton)
        messageStack.addArrangedSubview(card)

        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            icon.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            icon.widthAnchor.constraint(equalToConstant: 24),
            icon.heightAnchor.constraint(equalToConstant: 24),
            titleLabel.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 9),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            detailsLabel.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 12),
            detailsLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            detailsLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            buttonStack.topAnchor.constraint(equalTo: detailsLabel.bottomAnchor, constant: 16),
            buttonStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            buttonStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            buttonStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
            buttonStack.heightAnchor.constraint(equalToConstant: 42),
        ])

        dismissButton.addAction(UIAction { [weak self, weak card] _ in
            guard let self, let card else { return }
            self.messageStack.removeArrangedSubview(card)
            card.removeFromSuperview()
        }, for: .touchUpInside)
        applyButton.addAction(UIAction { [weak card] _ in
            guard apply() else { return }
            card?.isUserInteractionEnabled = false
            card?.alpha = 0.55
            applyButton.configuration?.title = "Применено"
            applyButton.configuration?.image = UIImage(systemName: "checkmark")
        }, for: .touchUpInside)
        scrollToBottom()
    }

    private func formatAmount(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        let value = formatter.string(from: NSNumber(value: abs(amount))) ?? "0"
        return "\(amount < 0 ? "−" : "+")\(value) ₸"
    }

}
