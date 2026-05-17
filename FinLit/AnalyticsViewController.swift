// AnalyticsViewController.swift
// Изменения относительно оригинала:
//   - После парсинга PDF транзакции с category == .other (неизвестные Purchases)
//     отправляются пакетом в Gemini для уточнения категории.
//   - Кнопка импорта блокируется на время AI-классификации, показывается индикатор.

import UIKit
import MobileCoreServices
import UniformTypeIdentifiers

final class AnalyticsViewController: UIViewController,
                                     UITableViewDataSource,
                                     UITableViewDelegate,
                                     UIDocumentPickerDelegate {

    private let pdfParser = KaspiPDFParser()

    private var allTransactions: [Transaction] = []
    private var expenseTotals: [(TxCategory, Double)] = []
    private var incomeTotals:  [(TxCategory, Double)] = []

    private var totalIncome:  Double = 0
    private var totalExpense: Double = 0
    private var netSavings:   Double = 0

    // MARK: - UI

    private let importButton  = UIButton(type: .system)
    private let resetButton   = UIButton(type: .system)
    private let summaryCard   = UIView()
    private let incomeRow     = SummaryRow(icon: "arrow.down.circle.fill",     color: .systemGreen, title: "Доходы (все выписки)")
    private let expenseRow    = SummaryRow(icon: "arrow.up.circle.fill",       color: .systemRed,   title: "Расходы (все выписки)")
    private let netRow        = SummaryRow(icon: "chart.line.uptrend.xyaxis",  color: .systemBlue,  title: "Чистые накопления")
    private let statLabel     = UILabel()
    private let battleBanner  = UIView()
    private let battleLabel   = UILabel()
    private let aiStatusLabel = UILabel()   // NEW: показывает прогресс Gemini

    private let spendingCard  = UIView()
    private let spendingTitle = UILabel()
    private let spendingBar   = SpendingBreakdownBar()

    private let tableView     = UITableView(frame: .zero, style: .insetGrouped)

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "Аналитика"
        setupUI()
        loadAndRender()
    }

    // MARK: - Setup

    private func setupUI() {
        importButton.translatesAutoresizingMaskIntoConstraints = false
        importButton.setTitle("📄  Загрузить PDF выписку", for: .normal)
        importButton.backgroundColor = .systemBlue
        importButton.tintColor = .white
        importButton.layer.cornerRadius = 14
        importButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        importButton.contentEdgeInsets = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        importButton.addTarget(self, action: #selector(importPDF), for: .touchUpInside)

        resetButton.translatesAutoresizingMaskIntoConstraints = false
        resetButton.setTitle("🗑 Сбросить все выписки", for: .normal)
        resetButton.tintColor = .systemRed
        resetButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        resetButton.addTarget(self, action: #selector(didTapReset), for: .touchUpInside)

        statLabel.translatesAutoresizingMaskIntoConstraints = false
        statLabel.font = .systemFont(ofSize: 12)
        statLabel.textColor = .secondaryLabel
        statLabel.textAlignment = .center

        // NEW: AI status label
        aiStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        aiStatusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        aiStatusLabel.textColor = .systemBlue
        aiStatusLabel.textAlignment = .center
        aiStatusLabel.isHidden = true

        summaryCard.translatesAutoresizingMaskIntoConstraints = false
        summaryCard.backgroundColor = .secondarySystemBackground
        summaryCard.layer.cornerRadius = 18

        for row in [incomeRow, expenseRow, netRow] {
            row.translatesAutoresizingMaskIntoConstraints = false
            summaryCard.addSubview(row)
        }

        spendingCard.translatesAutoresizingMaskIntoConstraints = false
        spendingCard.backgroundColor = .secondarySystemBackground
        spendingCard.layer.cornerRadius = 18
        spendingCard.isHidden = true

        spendingTitle.translatesAutoresizingMaskIntoConstraints = false
        spendingTitle.text = "Расходы по категориям"
        spendingTitle.font = .systemFont(ofSize: 14, weight: .semibold)
        spendingTitle.textColor = .secondaryLabel

        spendingBar.translatesAutoresizingMaskIntoConstraints = false
        spendingCard.addSubview(spendingTitle)
        spendingCard.addSubview(spendingBar)

        battleBanner.translatesAutoresizingMaskIntoConstraints = false
        battleBanner.layer.cornerRadius = 14
        battleBanner.isHidden = true

        battleLabel.translatesAutoresizingMaskIntoConstraints = false
        battleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        battleLabel.textColor = .white
        battleLabel.textAlignment = .center
        battleLabel.numberOfLines = 2
        battleBanner.addSubview(battleLabel)

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate   = self

        view.addSubview(importButton)
        view.addSubview(resetButton)
        view.addSubview(statLabel)
        view.addSubview(aiStatusLabel)
        view.addSubview(summaryCard)
        view.addSubview(spendingCard)
        view.addSubview(battleBanner)
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            importButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            importButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            importButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            resetButton.topAnchor.constraint(equalTo: importButton.bottomAnchor, constant: 6),
            resetButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            statLabel.topAnchor.constraint(equalTo: resetButton.bottomAnchor, constant: 2),
            statLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            statLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            // NEW: AI status below stat label
            aiStatusLabel.topAnchor.constraint(equalTo: statLabel.bottomAnchor, constant: 2),
            aiStatusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            aiStatusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            summaryCard.topAnchor.constraint(equalTo: aiStatusLabel.bottomAnchor, constant: 10),
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

            spendingCard.topAnchor.constraint(equalTo: summaryCard.bottomAnchor, constant: 10),
            spendingCard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            spendingCard.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            spendingTitle.topAnchor.constraint(equalTo: spendingCard.topAnchor, constant: 12),
            spendingTitle.leadingAnchor.constraint(equalTo: spendingCard.leadingAnchor, constant: 14),
            spendingTitle.trailingAnchor.constraint(equalTo: spendingCard.trailingAnchor, constant: -14),

            spendingBar.topAnchor.constraint(equalTo: spendingTitle.bottomAnchor, constant: 10),
            spendingBar.leadingAnchor.constraint(equalTo: spendingCard.leadingAnchor, constant: 14),
            spendingBar.trailingAnchor.constraint(equalTo: spendingCard.trailingAnchor, constant: -14),
            spendingBar.bottomAnchor.constraint(equalTo: spendingCard.bottomAnchor, constant: -14),

            battleBanner.topAnchor.constraint(equalTo: spendingCard.bottomAnchor, constant: 10),
            battleBanner.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            battleBanner.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            battleLabel.topAnchor.constraint(equalTo: battleBanner.topAnchor, constant: 10),
            battleLabel.bottomAnchor.constraint(equalTo: battleBanner.bottomAnchor, constant: -10),
            battleLabel.leadingAnchor.constraint(equalTo: battleBanner.leadingAnchor, constant: 12),
            battleLabel.trailingAnchor.constraint(equalTo: battleBanner.trailingAnchor, constant: -12),

            tableView.topAnchor.constraint(equalTo: battleBanner.bottomAnchor, constant: 8),
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
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }

        let result = pdfParser.parse(pdfURL: url)

        if !result.errors.isEmpty {
            showAlert(title: "Ошибка парсинга", message: result.errors.prefix(5).joined(separator: "\n"))
            return
        }
        guard !result.transactions.isEmpty else {
            showAlert(title: "Пусто", message: "Транзакции не найдены в этом PDF")
            return
        }

        let fingerprint = AppStorage.shared.makeFingerprint(result.transactions)
        if AppStorage.shared.isAlreadyImported(fingerprint) {
            let df = DateFormatter(); df.dateFormat = "dd.MM.yyyy"
            let sorted = result.transactions.sorted { $0.date < $1.date }
            showAlert(
<<<<<<< Updated upstream
                title: "⚠️ Выписка уже загружена",
                message: "Эта выписка (\(from) – \(to), \(result.transactions.count) транзакций) уже была использована ранее и не будет добавлена повторно."
=======
                title: "Выписка уже загружена",
                message: "Эта выписка (\(df.string(from: sorted.first!.date)) – \(df.string(from: sorted.last!.date)), \(result.transactions.count) транзакций) уже была использована ранее."
>>>>>>> Stashed changes
            )
            return
        }

        AppStorage.shared.markAsImported(fingerprint)

        // ── Шаг 1: сохраняем транзакции с rule-based категориями ──
        allTransactions = AppStorage.shared.mergeTransactions(result.transactions)
        AppStorage.shared.recalculateAndSaveNet()
        recompute(); render(); tableView.reloadData()

        // ── Шаг 2: Gemini AI улучшает категории для неопознанных Purchases ──
        let unknownTxs = allTransactions.filter {
            // Переводы и внутренние переводы оставляем как есть — Gemini их не улучшит
            $0.category != .transfers && $0.category != .internalTransfers
        }

<<<<<<< Updated upstream
        let df = DateFormatter(); df.dateFormat = "dd.MM.yyyy"
        let sorted = result.transactions.sorted { $0.date < $1.date }
        let from = df.string(from: sorted.first!.date)
        let to   = df.string(from: sorted.last!.date)
        showAlert(
            title: "✅ Выписка добавлена",
            message: "Добавлено \(result.transactions.count) транзакций (\(from) – \(to))\nВсего накоплено: \(allTransactions.count) транзакций"
        )
=======
        guard !unknownTxs.isEmpty else {
            let df = DateFormatter(); df.dateFormat = "dd.MM.yyyy"
            let sorted = result.transactions.sorted { $0.date < $1.date }
            showAlert(
                title: "Выписка добавлена",
                message: "Добавлено \(result.transactions.count) транзакций (\(df.string(from: sorted.first!.date)) – \(df.string(from: sorted.last!.date)))\nВсего: \(allTransactions.count) транзакций"
            )
            return
        }

        // Показываем статус AI
        importButton.isEnabled = false
        importButton.alpha = 0.5
        aiStatusLabel.isHidden = false
        aiStatusLabel.text = "🤖 Gemini классифицирует \(unknownTxs.count) неопознанных транзакций..."

        let pairs = unknownTxs.map { (merchant: $0.merchant, details: $0.details) }

        GeminiCategorizer.shared.classifyBatch(transactions: pairs) { [weak self] categories in
            guard let self else { return }

            // Применяем полученные категории
            var updatedAll = self.allTransactions
            for (idx, tx) in unknownTxs.enumerated() {
                guard idx < categories.count else { continue }
                let newCategory = categories[idx]
                guard newCategory != .other else { continue } // не менять если всё ещё .other

                // Ищем транзакцию в allTransactions и пересоздаём с новой категорией
                if let i = updatedAll.firstIndex(where: { $0.id == tx.id }) {
                    let old = updatedAll[i]
                    updatedAll[i] = Transaction(
                        id: old.id,
                        date: old.date,
                        amount: old.amount,
                        merchant: old.merchant,
                        details: old.details,
                        category: newCategory
                    )
                }
            }

            // Сохраняем обновлённые транзакции напрямую через UserDefaults
            if let data = try? JSONEncoder().encode(updatedAll) {
                UserDefaults.standard.set(data, forKey: "all_transactions_v2")
            }

            self.allTransactions = updatedAll
            AppStorage.shared.recalculateAndSaveNet()
            self.recompute()
            self.render()
            self.tableView.reloadData()

            // Убираем статус AI
            self.importButton.isEnabled = true
            self.importButton.alpha = 1.0
            self.aiStatusLabel.isHidden = true

            let improved = categories.filter { $0 != .other }.count
            let df = DateFormatter(); df.dateFormat = "dd.MM.yyyy"
            let sorted = result.transactions.sorted { $0.date < $1.date }
            self.showAlert(
                title: "Выписка добавлена",
                message: "Добавлено \(result.transactions.count) транзакций (\(df.string(from: sorted.first!.date)) – \(df.string(from: sorted.last!.date)))\nGemini уточнил категории для \(improved) из \(unknownTxs.count) транзакций.\nВсего: \(self.allTransactions.count) транзакций"
            )
        }
>>>>>>> Stashed changes
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
            spendingCard.isHidden = true
            return
        }

        let sorted = allTransactions.sorted { $0.date < $1.date }
        let df = DateFormatter(); df.dateFormat = "dd.MM.yyyy"
<<<<<<< Updated upstream
        let fromDate = df.string(from: sorted.first!.date)
        let toDate   = df.string(from: sorted.last!.date)
        statLabel.text = "📅 \(fromDate) – \(toDate)  •  \(allTransactions.count) транзакций"
=======
        statLabel.text = "\(df.string(from: sorted.first!.date)) – \(df.string(from: sorted.last!.date))  •  \(allTransactions.count) транзакций"
>>>>>>> Stashed changes

        incomeRow.setValue(formatMoneyAbs(totalIncome))
        expenseRow.setValue(formatMoneyAbs(totalExpense))
        netRow.setValue(formatMoneyNet(netSavings))
        netRow.setValueColor(netSavings >= 0 ? .systemGreen : .systemRed)

        spendingCard.isHidden = expenseTotals.isEmpty
        spendingBar.configure(totals: expenseTotals)

        battleBanner.isHidden = false
        if netSavings >= 0 {
            battleBanner.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.85)
            battleLabel.text = "⚔️ Битва: +\(formatMoneyAbs(netSavings)) — твой счёт обновлён"
        } else {
            battleBanner.backgroundColor = UIColor.systemRed.withAlphaComponent(0.85)
            battleLabel.text = "⚔️ Битва: \(formatMoneyNet(netSavings)) — расходы превышают доходы"
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
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        let item = indexPath.section == 0 ? expenseTotals[indexPath.row] : incomeTotals[indexPath.row]
        cell.textLabel?.text = item.0.rawValue
        cell.detailTextLabel?.text = formatMoneyAbs(item.1)
        cell.accessoryType = .disclosureIndicator
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

// MARK: - SummaryRow (без изменений)

final class SummaryRow: UIView {
    private let iconView  = UIImageView()
    private let titleLbl  = UILabel()
    private let valueLbl  = UILabel()

    init(icon: String, color: UIColor, title: String) {
        super.init(frame: .zero)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = UIImage(systemName: icon); iconView.tintColor = color
        iconView.contentMode = .scaleAspectFit
        titleLbl.translatesAutoresizingMaskIntoConstraints = false
        titleLbl.text = title; titleLbl.font = .systemFont(ofSize: 14)
        titleLbl.textColor = .secondaryLabel
        valueLbl.translatesAutoresizingMaskIntoConstraints = false
        valueLbl.font = .systemFont(ofSize: 15, weight: .semibold)
        valueLbl.textColor = color; valueLbl.textAlignment = .right; valueLbl.text = "—"
        addSubview(iconView); addSubview(titleLbl); addSubview(valueLbl)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22),
            titleLbl.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            titleLbl.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueLbl.trailingAnchor.constraint(equalTo: trailingAnchor),
            valueLbl.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueLbl.leadingAnchor.constraint(greaterThanOrEqualTo: titleLbl.trailingAnchor, constant: 8),
            heightAnchor.constraint(equalToConstant: 36),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
    func setValue(_ text: String) { valueLbl.text = text }
    func setValueColor(_ color: UIColor) { valueLbl.textColor = color }
}

// MARK: - SpendingBreakdownBar (без изменений)

final class SpendingBreakdownBar: UIView {

    private let barContainer = UIView()
    private let legendStack  = UIStackView()
    private var segments: [(color: UIColor, fraction: CGFloat)] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        barContainer.translatesAutoresizingMaskIntoConstraints = false
        barContainer.layer.cornerRadius = 8
        barContainer.clipsToBounds = true
        barContainer.backgroundColor = .systemFill

        legendStack.translatesAutoresizingMaskIntoConstraints = false
        legendStack.axis    = .vertical
        legendStack.spacing = 5

        addSubview(barContainer)
        addSubview(legendStack)

        NSLayoutConstraint.activate([
            barContainer.topAnchor.constraint(equalTo: topAnchor),
            barContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            barContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            barContainer.heightAnchor.constraint(equalToConstant: 22),

            legendStack.topAnchor.constraint(equalTo: barContainer.bottomAnchor, constant: 10),
            legendStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            legendStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            legendStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    func configure(totals: [(TxCategory, Double)]) {
        barContainer.subviews.forEach { $0.removeFromSuperview() }
        legendStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let totalAmt = totals.reduce(0.0) { $0 + $1.1 }
        guard totalAmt > 0 else { return }

        var items = totals.filter { $0.1 / totalAmt >= 0.01 }
        let smallAmt = totals.filter { $0.1 / totalAmt < 0.01 }.reduce(0.0) { $0 + $1.1 }

        if smallAmt > 0 {
            if let idx = items.firstIndex(where: { $0.0 == .other }) {
                items[idx] = (.other, items[idx].1 + smallAmt)
            } else {
                items.append((.other, smallAmt))
            }
        }

        segments = items.map { (categoryColor($0.0), CGFloat($0.1 / totalAmt)) }

        for seg in segments {
            let v = UIView()
            v.backgroundColor = seg.color
            barContainer.addSubview(v)
        }

        let rows = stride(from: 0, to: items.count, by: 2).map {
            Array(items[$0..<min($0 + 2, items.count)])
        }
        for pair in rows {
            let hStack = UIStackView()
            hStack.axis         = .horizontal
            hStack.spacing      = 12
            hStack.distribution = .fillEqually
            for (cat, amt) in pair {
                let pct = Int(round(amt / totalAmt * 100))
                hStack.addArrangedSubview(legendItem(color: categoryColor(cat),
                                                     name: cat.rawValue,
                                                     percent: "\(pct)%"))
            }
            legendStack.addArrangedSubview(hStack)
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let totalWidth = barContainer.bounds.width
        guard totalWidth > 0, !segments.isEmpty,
              barContainer.subviews.count == segments.count else { return }
        var x: CGFloat = 0
        for (i, seg) in segments.enumerated() {
            let view = barContainer.subviews[i]
            let w: CGFloat = i == segments.count - 1
                ? totalWidth - x
                : floor(totalWidth * seg.fraction)
            view.frame = CGRect(x: x, y: 0, width: max(w, 0), height: barContainer.bounds.height)
            x += w
        }
    }

    private func legendItem(color: UIColor, name: String, percent: String) -> UIView {
        let hStack = UIStackView()
        hStack.axis      = .horizontal
        hStack.spacing   = 5
        hStack.alignment = .center

        let dot = UIView()
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.backgroundColor  = color
        dot.layer.cornerRadius = 4
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
        ])

        let nameLbl = UILabel()
        nameLbl.text      = name
        nameLbl.font      = .systemFont(ofSize: 11)
        nameLbl.textColor = .secondaryLabel
        nameLbl.lineBreakMode = .byTruncatingTail
        nameLbl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let pctLbl = UILabel()
        pctLbl.text      = percent
        pctLbl.font      = .systemFont(ofSize: 12, weight: .bold)
        pctLbl.textColor = .label
        pctLbl.setContentHuggingPriority(.required, for: .horizontal)

        hStack.addArrangedSubview(dot)
        hStack.addArrangedSubview(nameLbl)
        hStack.addArrangedSubview(pctLbl)
        return hStack
    }

    private func categoryColor(_ cat: TxCategory) -> UIColor {
        switch cat {
        case .food:              return UIColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1)
        case .cafes:             return UIColor(red: 1.00, green: 0.55, blue: 0.00, alpha: 1)
        case .transport:         return UIColor(red: 0.20, green: 0.50, blue: 1.00, alpha: 1)
        case .subscriptions:     return UIColor(red: 0.60, green: 0.20, blue: 0.90, alpha: 1)
        case .utilities:         return UIColor(red: 0.95, green: 0.75, blue: 0.00, alpha: 1)
        case .shopping:          return UIColor(red: 1.00, green: 0.25, blue: 0.45, alpha: 1)
        case .health:            return UIColor(red: 1.00, green: 0.18, blue: 0.18, alpha: 1)
        case .education:         return UIColor(red: 0.00, green: 0.70, blue: 0.70, alpha: 1)
        case .entertainment:     return UIColor(red: 0.35, green: 0.35, blue: 0.85, alpha: 1)
        case .transfers:         return UIColor(red: 0.55, green: 0.55, blue: 0.60, alpha: 1)
        case .internalTransfers: return UIColor(red: 0.72, green: 0.72, blue: 0.75, alpha: 1)
        case .other:             return UIColor(red: 0.80, green: 0.80, blue: 0.82, alpha: 1)
        }
    }
}
