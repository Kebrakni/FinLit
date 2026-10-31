import UIKit

// MARK: - Hub

final class FinancialToolsViewController: UIViewController {
    private let segmentedControl = UISegmentedControl(items: [
        "Поиск", "Календарь", "Сравнение", "Платежи"
    ])
    private let containerView = UIView()
    private var currentChild: UIViewController?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Финансовые инструменты"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = FinLitTheme.background
        setupUI()
        showPage(at: 0)
    }

    private func setupUI() {
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.selectedSegmentTintColor = FinLitTheme.accent
        segmentedControl.setTitleTextAttributes([
            .foregroundColor: UIColor.white,
            .font: UIFont.systemFont(ofSize: 12, weight: .semibold)
        ], for: .selected)
        segmentedControl.setTitleTextAttributes([
            .foregroundColor: UIColor.secondaryLabel,
            .font: UIFont.systemFont(ofSize: 12, weight: .medium)
        ], for: .normal)
        segmentedControl.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)

        containerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(segmentedControl)
        view.addSubview(containerView)
        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            segmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            segmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            segmentedControl.heightAnchor.constraint(equalToConstant: 36),
            containerView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 8),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    @objc private func segmentChanged() {
        showPage(at: segmentedControl.selectedSegmentIndex)
    }

    private func showPage(at index: Int) {
        currentChild?.willMove(toParent: nil)
        currentChild?.view.removeFromSuperview()
        currentChild?.removeFromParent()

        let transactions = AppStorage.shared.loadAllTransactions()
        let child: UIViewController
        switch index {
        case 1: child = FinanceCalendarViewController(transactions: transactions)
        case 2: child = MonthComparisonViewController(transactions: transactions)
        case 3: child = RecurringPaymentsViewController(transactions: transactions)
        default: child = TransactionSearchViewController(transactions: transactions)
        }
        addChild(child)
        child.view.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(child.view)
        NSLayoutConstraint.activate([
            child.view.topAnchor.constraint(equalTo: containerView.topAnchor),
            child.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            child.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            child.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])
        child.didMove(toParent: self)
        currentChild = child
    }
}

// MARK: - Search and filters

private final class TransactionSearchViewController: UIViewController,
    UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate {

    private enum Period: Int, CaseIterable {
        case all, thirtyDays, thisMonth, thisYear

        var title: String {
            switch self {
            case .all: return "За всё время"
            case .thirtyDays: return "Последние 30 дней"
            case .thisMonth: return "Текущий месяц"
            case .thisYear: return "Текущий год"
            }
        }
    }

    private var all: [Transaction]
    private var filtered: [Transaction] = []
    private var selectedCategory: TxCategory?
    private var selectedPeriod: Period = .all
    private let searchBar = UISearchBar()
    private let categoryButton = UIButton(type: .system)
    private let periodButton = UIButton(type: .system)
    private let resultLabel = UILabel()
    private let tableView = UITableView(frame: .zero, style: .plain)

    init(transactions: [Transaction]) {
        self.all = transactions.sorted { $0.date > $1.date }
        self.filtered = self.all
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = FinLitTheme.background
        setupUI()
        updateMenus()
        applyFilters()
    }

    private func setupUI() {
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        searchBar.delegate = self
        searchBar.placeholder = "Название, сумма или категория"
        searchBar.searchBarStyle = .minimal
        searchBar.autocapitalizationType = .none

        let filters = UIStackView(arrangedSubviews: [categoryButton, periodButton])
        filters.translatesAutoresizingMaskIntoConstraints = false
        filters.axis = .horizontal
        filters.spacing = 9
        filters.distribution = .fillEqually
        [categoryButton, periodButton].forEach { button in
            var configuration = UIButton.Configuration.gray()
            configuration.cornerStyle = .large
            configuration.imagePlacement = .trailing
            configuration.image = UIImage(systemName: "chevron.down")
            configuration.imagePadding = 6
            button.configuration = configuration
            button.showsMenuAsPrimaryAction = true
        }

        resultLabel.translatesAutoresizingMaskIntoConstraints = false
        resultLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        resultLabel.textColor = .secondaryLabel

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.keyboardDismissMode = .onDrag
        tableView.register(TransactionCell.self, forCellReuseIdentifier: "SearchTransaction")

        view.addSubview(searchBar)
        view.addSubview(filters)
        view.addSubview(resultLabel)
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            filters.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 2),
            filters.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            filters.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            filters.heightAnchor.constraint(equalToConstant: 42),
            resultLabel.topAnchor.constraint(equalTo: filters.bottomAnchor, constant: 10),
            resultLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            resultLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            tableView.topAnchor.constraint(equalTo: resultLabel.bottomAnchor, constant: 3),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func updateMenus() {
        let categoryActions = [UIAction(title: "Все категории", state: selectedCategory == nil ? .on : .off) { [weak self] _ in
            self?.selectedCategory = nil
            self?.updateMenus()
            self?.applyFilters()
        }] + TxCategory.allCases.map { category in
            UIAction(
                title: category.rawValue,
                image: UIImage(systemName: category.icon),
                state: selectedCategory == category ? .on : .off
            ) { [weak self] _ in
                self?.selectedCategory = category
                self?.updateMenus()
                self?.applyFilters()
            }
        }
        categoryButton.menu = UIMenu(title: "Категория", options: .displayInline, children: categoryActions)
        categoryButton.configuration?.title = selectedCategory?.rawValue ?? "Все категории"

        periodButton.menu = UIMenu(title: "Период", options: .displayInline, children: Period.allCases.map { period in
            UIAction(title: period.title, state: selectedPeriod == period ? .on : .off) { [weak self] _ in
                self?.selectedPeriod = period
                self?.updateMenus()
                self?.applyFilters()
            }
        })
        periodButton.configuration?.title = selectedPeriod.title
    }

    private func applyFilters() {
        let query = (searchBar.text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let calendar = Calendar.current
        let now = Date()
        let start: Date?
        switch selectedPeriod {
        case .all: start = nil
        case .thirtyDays: start = calendar.date(byAdding: .day, value: -30, to: now)
        case .thisMonth: start = calendar.dateInterval(of: .month, for: now)?.start
        case .thisYear: start = calendar.dateInterval(of: .year, for: now)?.start
        }

        filtered = all.filter { transaction in
            if let selectedCategory, transaction.category != selectedCategory { return false }
            if let start, transaction.date < start { return false }
            guard !query.isEmpty else { return true }
            let amount = String(format: "%.0f", abs(transaction.amount))
            let text = "\(transaction.merchant) \(transaction.details) \(transaction.category.rawValue) \(amount)".lowercased()
            return text.contains(query)
        }
        let expenses = filtered.filter { $0.amount < 0 }.reduce(0.0) { $0 + abs($1.amount) }
        resultLabel.text = "\(filtered.count) операций · расходы \(FinancialToolsFormat.money(expenses))"
        tableView.reloadData()
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        applyFilters()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        filtered.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SearchTransaction", for: indexPath) as! TransactionCell
        let transaction = filtered[indexPath.row]
        cell.configure(
            with: transaction,
            date: FinancialToolsFormat.date(transaction.date),
            amount: FinancialToolsFormat.signedMoney(transaction.amount)
        )
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { 94 }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let transaction = filtered[indexPath.row]
        let editor = TransactionEditorViewController(transaction: transaction) { [weak self] updated in
            guard let self,
                  let index = self.all.firstIndex(where: { $0.id == updated.id }) else { return }
            self.all[index] = updated
            self.applyFilters()
        }
        presentEditor(editor)
    }

    private func presentEditor(_ editor: TransactionEditorViewController) {
        let navigation = UINavigationController(rootViewController: editor)
        navigation.modalPresentationStyle = .pageSheet
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 28
        }
        present(navigation, animated: true)
    }
}

// MARK: - Financial calendar

private final class FinanceCalendarViewController: UIViewController,
    UICollectionViewDataSource, UICollectionViewDelegateFlowLayout,
    UITableViewDataSource, UITableViewDelegate {

    private var transactions: [Transaction]
    private var displayMonth: Date
    private var selectedDate: Date
    private var selectedTransactions: [Transaction] = []
    private let calendar = Calendar.current
    private let monthLabel = UILabel()
    private let collectionView: UICollectionView
    private let summaryLabel = UILabel()
    private let tableView = UITableView(frame: .zero, style: .plain)

    init(transactions: [Transaction]) {
        self.transactions = transactions
        let seed = transactions.map(\.date).max() ?? Date()
        self.displayMonth = Calendar.current.dateInterval(of: .month, for: seed)?.start ?? seed
        self.selectedDate = Calendar.current.startOfDay(for: seed)
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 5
        layout.minimumInteritemSpacing = 4
        self.collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = FinLitTheme.background
        setupUI()
        refreshMonth()
    }

    private func setupUI() {
        let previousButton = UIButton(type: .system)
        let nextButton = UIButton(type: .system)
        [previousButton, nextButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.tintColor = FinLitTheme.accent
            var configuration = UIButton.Configuration.gray()
            configuration.cornerStyle = .capsule
            $0.configuration = configuration
        }
        previousButton.configuration?.image = UIImage(systemName: "chevron.left")
        nextButton.configuration?.image = UIImage(systemName: "chevron.right")
        previousButton.addTarget(self, action: #selector(previousMonth), for: .touchUpInside)
        nextButton.addTarget(self, action: #selector(nextMonth), for: .touchUpInside)

        monthLabel.translatesAutoresizingMaskIntoConstraints = false
        monthLabel.font = .systemFont(ofSize: 20, weight: .bold)
        monthLabel.textAlignment = .center

        let weekdays = UIStackView()
        weekdays.translatesAutoresizingMaskIntoConstraints = false
        weekdays.axis = .horizontal
        weekdays.distribution = .fillEqually
        ["ПН", "ВТ", "СР", "ЧТ", "ПТ", "СБ", "ВС"].forEach { value in
            let label = UILabel()
            label.text = value
            label.textAlignment = .center
            label.font = .systemFont(ofSize: 10, weight: .bold)
            label.textColor = .tertiaryLabel
            weekdays.addArrangedSubview(label)
        }

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(FinancialCalendarDayCell.self, forCellWithReuseIdentifier: "CalendarDay")

        summaryLabel.translatesAutoresizingMaskIntoConstraints = false
        summaryLabel.backgroundColor = FinLitTheme.surface
        summaryLabel.layer.cornerRadius = 16
        summaryLabel.layer.cornerCurve = .continuous
        summaryLabel.clipsToBounds = true
        summaryLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        summaryLabel.textAlignment = .center
        summaryLabel.numberOfLines = 2

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .none
        tableView.backgroundColor = .clear
        tableView.register(TransactionCell.self, forCellReuseIdentifier: "CalendarTransaction")

        view.addSubview(previousButton)
        view.addSubview(monthLabel)
        view.addSubview(nextButton)
        view.addSubview(weekdays)
        view.addSubview(collectionView)
        view.addSubview(summaryLabel)
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            previousButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            previousButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            previousButton.widthAnchor.constraint(equalToConstant: 38),
            previousButton.heightAnchor.constraint(equalToConstant: 38),
            nextButton.topAnchor.constraint(equalTo: previousButton.topAnchor),
            nextButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            nextButton.widthAnchor.constraint(equalToConstant: 38),
            nextButton.heightAnchor.constraint(equalToConstant: 38),
            monthLabel.centerYAnchor.constraint(equalTo: previousButton.centerYAnchor),
            monthLabel.leadingAnchor.constraint(equalTo: previousButton.trailingAnchor, constant: 8),
            monthLabel.trailingAnchor.constraint(equalTo: nextButton.leadingAnchor, constant: -8),
            weekdays.topAnchor.constraint(equalTo: previousButton.bottomAnchor, constant: 10),
            weekdays.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            weekdays.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            weekdays.heightAnchor.constraint(equalToConstant: 18),
            collectionView.topAnchor.constraint(equalTo: weekdays.bottomAnchor, constant: 4),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            collectionView.heightAnchor.constraint(equalToConstant: 244),
            summaryLabel.topAnchor.constraint(equalTo: collectionView.bottomAnchor, constant: 9),
            summaryLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            summaryLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            summaryLabel.heightAnchor.constraint(equalToConstant: 48),
            tableView.topAnchor.constraint(equalTo: summaryLabel.bottomAnchor, constant: 3),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    @objc private func previousMonth() { shiftMonth(by: -1) }
    @objc private func nextMonth() { shiftMonth(by: 1) }

    private func shiftMonth(by value: Int) {
        guard let month = calendar.date(byAdding: .month, value: value, to: displayMonth) else { return }
        displayMonth = month
        selectedDate = month
        refreshMonth()
    }

    private func refreshMonth() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "LLLL yyyy"
        monthLabel.text = formatter.string(from: displayMonth).capitalized
        collectionView.reloadData()
        refreshSelectedDay()
    }

    private func refreshSelectedDay() {
        selectedTransactions = transactions
            .filter { calendar.isDate($0.date, inSameDayAs: selectedDate) }
            .sorted { $0.date > $1.date }
        let income = selectedTransactions.filter { $0.amount > 0 }.reduce(0.0) { $0 + $1.amount }
        let expense = selectedTransactions.filter { $0.amount < 0 }.reduce(0.0) { $0 + abs($1.amount) }
        summaryLabel.text = "\(FinancialToolsFormat.longDate(selectedDate))\nДоходы \(FinancialToolsFormat.money(income))  ·  Расходы \(FinancialToolsFormat.money(expense))"
        tableView.reloadData()
    }

    private var leadingEmptyDays: Int {
        let weekday = calendar.component(.weekday, from: displayMonth)
        return (weekday + 5) % 7
    }

    private var daysInMonth: Int {
        calendar.range(of: .day, in: .month, for: displayMonth)?.count ?? 30
    }

    private func date(for indexPath: IndexPath) -> Date? {
        let day = indexPath.item - leadingEmptyDays + 1
        guard day >= 1, day <= daysInMonth else { return nil }
        return calendar.date(byAdding: .day, value: day - 1, to: displayMonth)
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { 42 }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "CalendarDay", for: indexPath) as! FinancialCalendarDayCell
        guard let date = date(for: indexPath) else {
            cell.configure(day: nil, hasTransactions: false, selected: false, positive: false)
            return cell
        }
        let rows = transactions.filter { calendar.isDate($0.date, inSameDayAs: date) }
        cell.configure(
            day: calendar.component(.day, from: date),
            hasTransactions: !rows.isEmpty,
            selected: calendar.isDate(date, inSameDayAs: selectedDate),
            positive: rows.reduce(0.0) { $0 + $1.amount } >= 0
        )
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let date = date(for: indexPath) else { return }
        selectedDate = date
        collectionView.reloadData()
        refreshSelectedDay()
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        let width = floor((collectionView.bounds.width - 24) / 7)
        return CGSize(width: width, height: 36)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { selectedTransactions.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "CalendarTransaction", for: indexPath) as! TransactionCell
        let transaction = selectedTransactions[indexPath.row]
        cell.configure(with: transaction, date: transaction.category.rawValue, amount: FinancialToolsFormat.signedMoney(transaction.amount))
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { 92 }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let transaction = selectedTransactions[indexPath.row]
        let editor = TransactionEditorViewController(transaction: transaction) { [weak self] updated in
            guard let self,
                  let index = self.transactions.firstIndex(where: { $0.id == updated.id }) else { return }
            self.transactions[index] = updated
            self.refreshSelectedDay()
            self.collectionView.reloadData()
        }
        let navigation = UINavigationController(rootViewController: editor)
        navigation.modalPresentationStyle = .pageSheet
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 28
        }
        present(navigation, animated: true)
    }
}

private final class FinancialCalendarDayCell: UICollectionViewCell {
    private let dayLabel = UILabel()
    private let dotView = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 12
        contentView.layer.cornerCurve = .continuous
        dayLabel.translatesAutoresizingMaskIntoConstraints = false
        dayLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        dayLabel.textAlignment = .center
        dotView.translatesAutoresizingMaskIntoConstraints = false
        dotView.layer.cornerRadius = 2
        contentView.addSubview(dayLabel)
        contentView.addSubview(dotView)
        NSLayoutConstraint.activate([
            dayLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            dayLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor, constant: -2),
            dotView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            dotView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            dotView.widthAnchor.constraint(equalToConstant: 4),
            dotView.heightAnchor.constraint(equalToConstant: 4),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(day: Int?, hasTransactions: Bool, selected: Bool, positive: Bool) {
        dayLabel.text = day.map(String.init)
        contentView.backgroundColor = selected ? FinLitTheme.accent : .clear
        dayLabel.textColor = selected ? .white : .label
        dotView.isHidden = !hasTransactions
        dotView.backgroundColor = selected ? .white : (positive ? .systemGreen : .systemRed)
        isUserInteractionEnabled = day != nil
    }
}

// MARK: - Month comparison

private final class MonthComparisonViewController: UIViewController {
    private struct Metrics {
        let income: Double
        let expense: Double
        var balance: Double { income - expense }
    }

    private let transactions: [Transaction]
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private let calendar = Calendar.current

    init(transactions: [Transaction]) {
        self.transactions = transactions
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = FinLitTheme.background
        setupUI()
        render()
    }

    private func setupUI() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 12
        view.addSubview(scrollView)
        scrollView.addSubview(stackView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 10),
            stackView.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -16),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -28),
        ])
    }

    private func render() {
        guard let newestDate = transactions.map(\.date).max(),
              let currentInterval = calendar.dateInterval(of: .month, for: newestDate),
              let previousSeed = calendar.date(byAdding: .month, value: -1, to: currentInterval.start),
              let previousInterval = calendar.dateInterval(of: .month, for: previousSeed) else {
            stackView.addArrangedSubview(emptyView())
            return
        }

        let currentRows = transactions.filter { currentInterval.contains($0.date) }
        let previousRows = transactions.filter { previousInterval.contains($0.date) }
        let current = metrics(for: currentRows)
        let previous = metrics(for: previousRows)

        let title = UILabel()
        title.numberOfLines = 0
        let comparisonAvailable = !previousRows.isEmpty
        title.attributedText = comparisonTitle(
            current: currentInterval.start,
            previous: previousInterval.start,
            comparisonAvailable: comparisonAvailable
        )
        stackView.addArrangedSubview(title)

        let grid = UIStackView()
        grid.axis = .horizontal
        grid.spacing = 10
        grid.distribution = .fillEqually
        grid.addArrangedSubview(metricCard(
            title: "Расходы",
            value: current.expense,
            previous: previous.expense,
            comparisonAvailable: comparisonAvailable,
            lowerIsBetter: true,
            color: .systemRed,
            icon: "arrow.down.circle.fill"
        ))
        grid.addArrangedSubview(metricCard(
            title: "Доходы",
            value: current.income,
            previous: previous.income,
            comparisonAvailable: comparisonAvailable,
            lowerIsBetter: false,
            color: .systemGreen,
            icon: "arrow.up.circle.fill"
        ))
        stackView.addArrangedSubview(grid)
        let balanceCard = metricCard(
            title: "Баланс месяца",
            value: current.balance,
            previous: previous.balance,
            comparisonAvailable: comparisonAvailable,
            lowerIsBetter: false,
            color: current.balance >= 0 ? .systemGreen : .systemOrange,
            icon: "equal.circle.fill",
            wide: true
        )
        stackView.addArrangedSubview(balanceCard)

        let categoryTitle = UILabel()
        categoryTitle.text = comparisonAvailable ? "Что изменилось в расходах" : "Расходы за месяц"
        categoryTitle.font = .systemFont(ofSize: 20, weight: .bold)
        stackView.setCustomSpacing(22, after: balanceCard)
        stackView.addArrangedSubview(categoryTitle)

        let currentCategories = categoryExpenses(currentRows)
        let previousCategories = categoryExpenses(previousRows)
        let categorySet = Set(currentCategories.keys).union(previousCategories.keys)
        let changes = categorySet.map { category -> (TxCategory, Double, Double, Double) in
            let currentValue = currentCategories[category] ?? 0
            let previousValue = previousCategories[category] ?? 0
            return (category, currentValue, previousValue, currentValue - previousValue)
        }.sorted { abs($0.3) > abs($1.3) }

        if changes.isEmpty {
            let label = UILabel()
            label.text = "Недостаточно расходов для сравнения"
            label.textColor = .secondaryLabel
            label.font = .systemFont(ofSize: 14, weight: .medium)
            stackView.addArrangedSubview(label)
        } else {
            changes.prefix(7).forEach {
                stackView.addArrangedSubview(categoryChangeRow($0, showsComparison: comparisonAvailable))
            }
        }
    }

    private func metrics(for rows: [Transaction]) -> Metrics {
        Metrics(
            income: rows.filter { $0.amount > 0 }.reduce(0.0) { $0 + $1.amount },
            expense: rows.filter { $0.amount < 0 }.reduce(0.0) { $0 + abs($1.amount) }
        )
    }

    private func categoryExpenses(_ rows: [Transaction]) -> [TxCategory: Double] {
        Dictionary(grouping: rows.filter { $0.amount < 0 }, by: \.category)
            .mapValues { values in values.reduce(0.0) { $0 + abs($1.amount) } }
    }

    private func comparisonTitle(
        current: Date,
        previous: Date,
        comparisonAvailable: Bool
    ) -> NSAttributedString {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "LLLL"
        let value = NSMutableAttributedString(
            string: "\(formatter.string(from: current).capitalized) против \(formatter.string(from: previous))\n",
            attributes: [.font: UIFont.systemFont(ofSize: 22, weight: .bold), .foregroundColor: UIColor.label]
        )
        let subtitle = comparisonAvailable
            ? "Сравниваем два соседних календарных месяца"
            : "За \(formatter.string(from: previous)) нет операций — показываем итоги месяца"
        value.append(NSAttributedString(
            string: subtitle,
            attributes: [.font: UIFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: UIColor.secondaryLabel]
        ))
        return value
    }

    private func metricCard(
        title: String,
        value: Double,
        previous: Double,
        comparisonAvailable: Bool,
        lowerIsBetter: Bool,
        color: UIColor,
        icon: String,
        wide: Bool = false
    ) -> UIView {
        let card = UIView()
        FinLitTheme.styleCard(card, radius: 20)
        let iconView = UIImageView(image: UIImage(systemName: icon))
        let titleLabel = UILabel()
        let valueLabel = UILabel()
        let changeLabel = UILabel()
        [iconView, titleLabel, valueLabel, changeLabel].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        iconView.tintColor = color
        iconView.contentMode = .scaleAspectFit
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .secondaryLabel
        valueLabel.text = FinancialToolsFormat.signedMoney(value)
        valueLabel.font = .monospacedDigitSystemFont(ofSize: wide ? 21 : 17, weight: .bold)
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.72

        let delta = value - previous
        let percent = previous == 0 ? nil : delta / abs(previous) * 100
        let improvement = lowerIsBetter ? delta <= 0 : delta >= 0
        if !comparisonAvailable {
            changeLabel.text = "Нет данных за прошлый месяц"
            changeLabel.textColor = .secondaryLabel
        } else if let percent {
            changeLabel.text = String(format: "%@%.0f%% к прошлому", delta >= 0 ? "+" : "", percent)
            changeLabel.textColor = improvement ? .systemGreen : .systemOrange
        } else {
            changeLabel.text = previous == value ? "Без изменений" : "Нет базы сравнения"
            changeLabel.textColor = improvement ? .systemGreen : .systemOrange
        }
        changeLabel.font = .systemFont(ofSize: 11, weight: .semibold)

        card.addSubview(iconView)
        card.addSubview(titleLabel)
        card.addSubview(valueLabel)
        card.addSubview(changeLabel)
        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: card.topAnchor, constant: 15),
            iconView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 15),
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22),
            titleLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            valueLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 12),
            valueLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 15),
            valueLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -15),
            changeLabel.topAnchor.constraint(equalTo: valueLabel.bottomAnchor, constant: 6),
            changeLabel.leadingAnchor.constraint(equalTo: valueLabel.leadingAnchor),
            changeLabel.trailingAnchor.constraint(equalTo: valueLabel.trailingAnchor),
            changeLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -15),
        ])
        return card
    }

    private func categoryChangeRow(
        _ change: (TxCategory, Double, Double, Double),
        showsComparison: Bool
    ) -> UIView {
        let (category, current, _, delta) = change
        let card = UIView()
        card.backgroundColor = FinLitTheme.surface
        card.layer.cornerRadius = 16
        card.layer.cornerCurve = .continuous
        let icon = UIImageView(image: UIImage(systemName: category.icon))
        let title = UILabel()
        let amount = UILabel()
        let deltaLabel = UILabel()
        [icon, title, amount, deltaLabel].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        icon.tintColor = category.uiColor
        icon.contentMode = .scaleAspectFit
        title.text = category.rawValue
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        amount.text = FinancialToolsFormat.money(current)
        amount.font = .monospacedDigitSystemFont(ofSize: 14, weight: .bold)
        amount.textAlignment = .right
        deltaLabel.text = showsComparison
            ? "\(delta >= 0 ? "+" : "")\(FinancialToolsFormat.money(delta))"
            : nil
        deltaLabel.font = .systemFont(ofSize: 11, weight: .bold)
        deltaLabel.textColor = delta <= 0 ? .systemGreen : .systemRed
        deltaLabel.textAlignment = .right
        card.addSubview(icon); card.addSubview(title); card.addSubview(amount); card.addSubview(deltaLabel)
        NSLayoutConstraint.activate([
            card.heightAnchor.constraint(equalToConstant: 58),
            icon.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 15),
            icon.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 24),
            icon.heightAnchor.constraint(equalToConstant: 24),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            title.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            amount.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            amount.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            deltaLabel.topAnchor.constraint(equalTo: amount.bottomAnchor, constant: 2),
            deltaLabel.trailingAnchor.constraint(equalTo: amount.trailingAnchor),
        ])
        return card
    }

    private func emptyView() -> UIView {
        let label = UILabel()
        label.text = "Загрузите выписку хотя бы за один месяц — здесь появится сравнение."
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.font = .systemFont(ofSize: 15, weight: .medium)
        return label
    }
}

// MARK: - Recurring payments

private struct RecurringPaymentPattern {
    let merchant: String
    let category: TxCategory
    let averageAmount: Double
    let frequency: String
    let intervalDays: Int
    let occurrences: Int
    let lastDate: Date
    let nextDate: Date
}

private final class RecurringPaymentsViewController: UIViewController,
    UITableViewDataSource, UITableViewDelegate {

    private let patterns: [RecurringPaymentPattern]
    private let headerLabel = UILabel()
    private let tableView = UITableView(frame: .zero, style: .plain)

    init(transactions: [Transaction]) {
        self.patterns = Self.detectPatterns(in: transactions)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = FinLitTheme.background
        setupUI()
    }

    private func setupUI() {
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        headerLabel.numberOfLines = 0
        headerLabel.font = .systemFont(ofSize: 14, weight: .medium)
        headerLabel.textColor = .secondaryLabel
        headerLabel.text = patterns.isEmpty
            ? "Пока регулярные списания не найдены. Обычно нужно минимум 2–3 похожих платежа."
            : "Найдено \(patterns.count) регулярных платежей. Даты следующего списания рассчитаны приблизительно."

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .none
        tableView.backgroundColor = .clear
        tableView.register(RecurringPaymentCell.self, forCellReuseIdentifier: "RecurringPayment")
        tableView.contentInset.bottom = 24

        view.addSubview(headerLabel)
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            headerLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            headerLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            tableView.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { patterns.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "RecurringPayment", for: indexPath) as! RecurringPaymentCell
        cell.configure(patterns[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { 132 }

    private static func detectPatterns(in transactions: [Transaction]) -> [RecurringPaymentPattern] {
        let expenses = transactions.filter { $0.amount < 0 && abs($0.amount) >= 50 }
        let groups = Dictionary(grouping: expenses) { transaction in
            "\(normalizedMerchant(transaction.merchant))|\(transaction.category.aiCode)"
        }
        let calendar = Calendar.current

        return groups.values.compactMap { values -> RecurringPaymentPattern? in
            let rows = values.sorted { $0.date < $1.date }
            guard rows.count >= 2,
                  let first = rows.first,
                  let last = rows.last,
                  normalizedMerchant(first.merchant).count >= 3 else { return nil }

            let intervals = zip(rows, rows.dropFirst()).map { pair in
                max(calendar.dateComponents([.day], from: pair.0.date, to: pair.1.date).day ?? 0, 0)
            }.filter { $0 > 0 }
            guard !intervals.isEmpty else { return nil }
            let sortedIntervals = intervals.sorted()
            let medianInterval = sortedIntervals[sortedIntervals.count / 2]
            let averageAmount = rows.reduce(0.0) { $0 + abs($1.amount) } / Double(rows.count)
            let maxAmountDeviation = rows.map { abs(abs($0.amount) - averageAmount) / max(averageAmount, 1) }.max() ?? 1

            let frequency: String
            let allowedIntervalDeviation: Int
            if (6...8).contains(medianInterval) {
                frequency = "Примерно каждую неделю"
                allowedIntervalDeviation = 3
            } else if (25...35).contains(medianInterval) {
                frequency = "Примерно раз в месяц"
                allowedIntervalDeviation = 8
            } else if rows.count >= 3, (2...45).contains(medianInterval) {
                frequency = "Примерно каждые \(medianInterval) дн."
                allowedIntervalDeviation = max(3, Int(Double(medianInterval) * 0.25))
            } else {
                return nil
            }

            let intervalIsStable = intervals.allSatisfy {
                abs($0 - medianInterval) <= allowedIntervalDeviation
            }
            let categoryIsUsuallyRecurring: Bool = [
                TxCategory.subscriptions, .utilities, .loans, .education
            ].contains(first.category)
            guard intervalIsStable,
                  maxAmountDeviation <= (categoryIsUsuallyRecurring ? 0.35 : 0.18),
                  rows.count >= (categoryIsUsuallyRecurring ? 2 : 3),
                  let nextDate = calendar.date(byAdding: .day, value: medianInterval, to: last.date) else {
                return nil
            }

            return RecurringPaymentPattern(
                merchant: mostCommonMerchant(in: rows),
                category: first.category,
                averageAmount: averageAmount,
                frequency: frequency,
                intervalDays: medianInterval,
                occurrences: rows.count,
                lastDate: last.date,
                nextDate: nextDate
            )
        }.sorted { $0.nextDate < $1.nextDate }
    }

    private static func normalizedMerchant(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"[^a-zа-яё0-9]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func mostCommonMerchant(in transactions: [Transaction]) -> String {
        Dictionary(grouping: transactions, by: \.merchant)
            .max { $0.value.count < $1.value.count }?.key
            ?? transactions.first?.merchant
            ?? "Регулярный платёж"
    }
}

private final class RecurringPaymentCell: UITableViewCell {
    private let card = UIView()
    private let iconBackground = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let categoryLabel = UILabel()
    private let amountLabel = UILabel()
    private let frequencyLabel = UILabel()
    private let nextLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        backgroundColor = .clear
        selectionStyle = .none
        card.translatesAutoresizingMaskIntoConstraints = false
        FinLitTheme.styleCard(card, radius: 20)
        iconBackground.translatesAutoresizingMaskIntoConstraints = false
        iconBackground.layer.cornerRadius = 20
        iconView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        categoryLabel.translatesAutoresizingMaskIntoConstraints = false
        amountLabel.translatesAutoresizingMaskIntoConstraints = false
        frequencyLabel.translatesAutoresizingMaskIntoConstraints = false
        nextLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 16, weight: .bold)
        titleLabel.numberOfLines = 1
        categoryLabel.font = .systemFont(ofSize: 11, weight: .medium)
        categoryLabel.textColor = .secondaryLabel
        amountLabel.font = .monospacedDigitSystemFont(ofSize: 16, weight: .bold)
        amountLabel.textAlignment = .right
        frequencyLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        frequencyLabel.textColor = .secondaryLabel
        nextLabel.font = .systemFont(ofSize: 12, weight: .bold)
        nextLabel.textColor = FinLitTheme.accent

        contentView.addSubview(card)
        card.addSubview(iconBackground); iconBackground.addSubview(iconView)
        card.addSubview(titleLabel); card.addSubview(categoryLabel); card.addSubview(amountLabel)
        card.addSubview(frequencyLabel); card.addSubview(nextLabel)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 7),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -7),
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            iconBackground.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            iconBackground.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            iconBackground.widthAnchor.constraint(equalToConstant: 40),
            iconBackground.heightAnchor.constraint(equalToConstant: 40),
            iconView.centerXAnchor.constraint(equalTo: iconBackground.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconBackground.centerYAnchor),
            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 15),
            titleLabel.leadingAnchor.constraint(equalTo: iconBackground.trailingAnchor, constant: 11),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: amountLabel.leadingAnchor, constant: -8),
            categoryLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            categoryLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            amountLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            amountLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            frequencyLabel.topAnchor.constraint(equalTo: iconBackground.bottomAnchor, constant: 13),
            frequencyLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            frequencyLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            nextLabel.topAnchor.constraint(equalTo: frequencyLabel.bottomAnchor, constant: 5),
            nextLabel.leadingAnchor.constraint(equalTo: frequencyLabel.leadingAnchor),
            nextLabel.trailingAnchor.constraint(equalTo: frequencyLabel.trailingAnchor),
            nextLabel.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -13),
        ])
    }

    func configure(_ pattern: RecurringPaymentPattern) {
        iconBackground.backgroundColor = pattern.category.uiColor.withAlphaComponent(0.14)
        iconView.image = UIImage(systemName: pattern.category.icon)
        iconView.tintColor = pattern.category.uiColor
        titleLabel.text = pattern.merchant
        categoryLabel.text = "\(pattern.category.rawValue) · \(pattern.occurrences) платежа"
        amountLabel.text = "≈ \(FinancialToolsFormat.money(pattern.averageAmount))"
        frequencyLabel.text = pattern.frequency
        nextLabel.text = "Следующее списание: около \(FinancialToolsFormat.longDate(pattern.nextDate))"
    }
}

// MARK: - Shared formatting

private enum FinancialToolsFormat {
    static func money(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        let text = formatter.string(from: NSNumber(value: value)) ?? String(Int(value))
        return "\(text) ₸"
    }

    static func signedMoney(_ value: Double) -> String {
        let sign = value > 0 ? "+" : (value < 0 ? "−" : "")
        return "\(sign)\(money(abs(value)))"
    }

    static func date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter.string(from: date)
    }

    static func longDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMMM yyyy"
        return formatter.string(from: date)
    }
}



