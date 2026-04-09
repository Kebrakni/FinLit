// AnalyticsViewController.swift
import UIKit
import MobileCoreServices
import UniformTypeIdentifiers

final class AnalyticsViewController: UIViewController,
                                     UITableViewDataSource,
                                     UITableViewDelegate,
                                     UIDocumentPickerDelegate {

    private let pdfParser = KaspiPDFParser()

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
    private let summaryCard   = UIView()
    private let incomeRow     = SummaryRow(icon: "arrow.down.circle.fill",     color: .systemGreen, title: "Доходы (все выписки)")
    private let expenseRow    = SummaryRow(icon: "arrow.up.circle.fill",       color: .systemRed,   title: "Расходы (все выписки)")
    private let netRow        = SummaryRow(icon: "chart.line.uptrend.xyaxis",  color: .systemBlue,  title: "Чистые накопления")
    private let statLabel     = UILabel()   // сколько выписок загружено
    private let battleBanner  = UIView()
    private let battleLabel   = UILabel()
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
        // Import button
        importButton.translatesAutoresizingMaskIntoConstraints = false
        importButton.setTitle("Загрузить PDF выписку", for: .normal)
        importButton.setImage(UIImage(systemName: "doc.badge.arrow.up"), for: .normal)
        importButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 8)
        importButton.titleEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 0)
        importButton.backgroundColor = .systemBlue
        importButton.tintColor = .white
        importButton.layer.cornerRadius = 14
        importButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        importButton.contentEdgeInsets = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        importButton.addTarget(self, action: #selector(importPDF), for: .touchUpInside)

        // Reset button
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        resetButton.setTitle("Сбросить все выписки", for: .normal)
        resetButton.setImage(UIImage(systemName: "trash"), for: .normal)
        resetButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 6)
        resetButton.titleEdgeInsets = UIEdgeInsets(top: 0, left: 6, bottom: 0, right: 0)
        resetButton.tintColor = .systemRed
        resetButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        resetButton.addTarget(self, action: #selector(didTapReset), for: .touchUpInside)

        // Stat label
        statLabel.translatesAutoresizingMaskIntoConstraints = false
        statLabel.font = .systemFont(ofSize: 12)
        statLabel.textColor = .secondaryLabel
        statLabel.textAlignment = .center

        // Summary card
        summaryCard.translatesAutoresizingMaskIntoConstraints = false
        summaryCard.backgroundColor = .secondarySystemBackground
        summaryCard.layer.cornerRadius = 18

        for row in [incomeRow, expenseRow, netRow] {
            row.translatesAutoresizingMaskIntoConstraints = false
            summaryCard.addSubview(row)
        }

        // Battle banner
        battleBanner.translatesAutoresizingMaskIntoConstraints = false
        battleBanner.layer.cornerRadius = 14
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

        view.addSubview(importButton)
        view.addSubview(resetButton)
        view.addSubview(statLabel)
        view.addSubview(summaryCard)
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

            summaryCard.topAnchor.constraint(equalTo: statLabel.bottomAnchor, constant: 10),
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

            battleBanner.topAnchor.constraint(equalTo: summaryCard.bottomAnchor, constant: 10),
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

        // Проверка на дубликат выписки
        let fingerprint = AppStorage.shared.makeFingerprint(result.transactions)
        if AppStorage.shared.isAlreadyImported(fingerprint) {
            let df = DateFormatter(); df.dateFormat = "dd.MM.yyyy"
            let sorted = result.transactions.sorted { $0.date < $1.date }
            let from = df.string(from: sorted.first!.date)
            let to   = df.string(from: sorted.last!.date)
            showAlert(
                title: "Выписка уже загружена",
                message: "Эта выписка (\(from) – \(to), \(result.transactions.count) транзакций) уже была использована ранее и не будет добавлена повторно."
            )
            return
        }

        // Сохраняем fingerprint
        AppStorage.shared.markAsImported(fingerprint)

        // Добавляем транзакции к накопленным
        allTransactions = AppStorage.shared.mergeTransactions(result.transactions)

        // Пересчитываем net и обновляем Battle
        AppStorage.shared.recalculateAndSaveNet()

        recompute()
        render()
        tableView.reloadData()

        let df = DateFormatter(); df.dateFormat = "dd.MM.yyyy"
        let sorted = result.transactions.sorted { $0.date < $1.date }
        let from = df.string(from: sorted.first!.date)
        let to   = df.string(from: sorted.last!.date)
        showAlert(
            title: "Выписка добавлена",
            message: "Добавлено \(result.transactions.count) транзакций (\(from) – \(to))\nВсего накоплено: \(allTransactions.count) транзакций"
        )
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
            return
        }

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

// MARK: - SummaryRow

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
