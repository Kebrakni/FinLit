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
            title: "Добавить выписку",
            image: "doc.badge.arrow.up"
        )
        importButton.addTarget(self, action: #selector(importPDF), for: .touchUpInside)

        // Reset button
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        var resetConfiguration = UIButton.Configuration.gray()
        resetConfiguration.image = UIImage(systemName: "trash")
        resetConfiguration.baseForegroundColor = .systemRed
        resetConfiguration.cornerStyle = .capsule
        resetConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 11, bottom: 7, trailing: 11)
        resetButton.configuration = resetConfiguration
        resetButton.accessibilityLabel = "Удалить загруженные выписки"
        resetButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        resetButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        resetButton.addTarget(self, action: #selector(didTapReset), for: .touchUpInside)

        // Stat label
        statLabel.translatesAutoresizingMaskIntoConstraints = false
        statLabel.font = .systemFont(ofSize: 13, weight: .medium)
        statLabel.numberOfLines = 2
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
        tableView.register(AnalyticsCategoryCell.self, forCellReuseIdentifier: "AnalyticsCategory")
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 88

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
            statLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),

            resetButton.centerYAnchor.constraint(equalTo: statLabel.centerYAnchor),
            resetButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            resetButton.widthAnchor.constraint(equalToConstant: 44),
            resetButton.heightAnchor.constraint(equalToConstant: 44),

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
                    return transaction.withCategory(
                        Categorizer.finalCategory(for: transaction, aiCategory: categories[transaction.id])
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
        importButton.configuration?.title = importing ? "Анализируем выписку…" : "Добавить выписку"
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
        tableView.backgroundView = allTransactions.isEmpty ? FinLitEmptyStateView(
            symbol: "chart.bar.xaxis",
            title: "Ваша история денег",
            detail: "Добавьте первую выписку — здесь появятся категории, структура расходов и доходы."
        ) : nil
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
            battleBanner.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.12)
            battleLabel.textColor = .systemGreen
            battleLabel.text = "+\(formatMoneyAbs(netSavings)) из выписок учтено в цели"
        } else {
            battleBanner.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.12)
            battleLabel.textColor = .systemOrange
            battleLabel.text = "Расходы превышают доходы на \(formatMoneyAbs(netSavings))"
        }
    }

    // MARK: - TableView

    func numberOfSections(in tableView: UITableView) -> Int { allTransactions.isEmpty ? 0 : 2 }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "Расходы по категориям" : "Доходы по категориям"
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? expenseTotals.count : incomeTotals.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "AnalyticsCategory", for: indexPath) as! AnalyticsCategoryCell
        let item = indexPath.section == 0 ? expenseTotals[indexPath.row] : incomeTotals[indexPath.row]
        cell.configure(category: item.0, value: item.1, total: indexPath.section == 0 ? totalExpense : totalIncome)
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
        present(FinLitNoticeSheet(title: title, detail: message), animated: true)
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
