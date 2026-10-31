import UIKit

private struct ChatOption {
    let title: String
    var detail: String? = nil
    var symbol: String = "chevron.right"
    let action: () -> Void
}

private struct ChatMenu {
    let id = UUID()
    let title: String
    let detail: String
    let options: [ChatOption]
}

private enum ChatRow {
    case message(AIChatMessage)
    case menu(ChatMenu)
    case typing
}

final class AIChatViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UITextViewDelegate {
    private var transactions: [Transaction]
    private var messages: [AIChatMessage]
    private var rows: [ChatRow] = []
    private let onApply: ([String: (amount: Double, category: TxCategory)]) -> Void
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let dock = UIStackView()
    private let input = UITextView()
    private let sendButton = UIButton(type: .system)
    private let placeholder = UILabel()
    private var inputHeight: NSLayoutConstraint!
    private var activeMenuID: UUID? {
        didSet {
            guard isViewLoaded, oldValue != activeMenuID else { return }
            let menus = rows.indices.compactMap { index -> IndexPath? in
                if case .menu = rows[index] { return IndexPath(row: index, section: 0) }
                return nil
            }
            if !menus.isEmpty { tableView.reloadRows(at: menus, with: .none) }
        }
    }
    private var requestID: UUID?
    private var requestTask: Task<Void, Never>?
    private var statusText = "Готовлю ответ…"
    private var didScrollInitially = false

    init(transactions: [Transaction], onApply: @escaping ([String: (amount: Double, category: TxCategory)]) -> Void) {
        self.transactions = transactions
        messages = AppStorage.shared.loadAIChatMessages()
        self.onApply = onApply
        super.init(nibName: nil, bundle: nil)
        title = "Tengely AI"
    }

    required init?(coder: NSCoder) { fatalError() }
    deinit { requestTask?.cancel(); NotificationCenter.default.removeObserver(self) }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = FinLitTheme.background
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "xmark"), style: .plain, target: self, action: #selector(close))
        navigationItem.leftBarButtonItem?.accessibilityLabel = "Закрыть помощника"
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "ellipsis"), menu: UIMenu(children: [
            UIAction(title: "Что умеет помощник", image: UIImage(systemName: "sparkles")) { [weak self] _ in self?.showActions() },
            UIAction(title: "Очистить историю", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in self?.clearChat() }
        ]))
        setupUI()
        rows = messages.map(ChatRow.message)
        if messages.isEmpty { showActions() }
        tableView.reloadData()
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardChanged), name: UIResponder.keyboardDidChangeFrameNotification, object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !didScrollInitially { didScrollInitially = true; scrollToBottom(animated: false) }
    }

    private func setupUI() {
        dock.axis = .vertical
        dock.spacing = 8
        dock.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dock)

        let shortcutScroll = UIScrollView()
        shortcutScroll.showsHorizontalScrollIndicator = false
        let shortcuts = UIStackView()
        shortcuts.spacing = 8
        shortcuts.translatesAutoresizingMaskIntoConstraints = false
        shortcutScroll.addSubview(shortcuts)
        let actions: [(String, String, () -> Void)] = [
            ("Переводы", "arrow.left.arrow.right", { [weak self] in self?.showTransferDirections() }),
            ("Расходы", "chart.pie", { [weak self] in self?.showCategories() }),
            ("Проверить", "sparkles", { [weak self] in self?.showReviewActions() }),
            ("Обзор", "chart.bar", { [weak self] in self?.showPeriods(for: .overview) })
        ]
        for (title, symbol, action) in actions {
            let button = UIButton(type: .system)
            var config = UIButton.Configuration.tinted()
            config.title = title
            config.image = UIImage(systemName: symbol)
            config.imagePadding = 6
            config.baseForegroundColor = FinLitTheme.accent
            config.cornerStyle = .capsule
            config.contentInsets = .init(top: 9, leading: 12, bottom: 9, trailing: 12)
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var result = attributes; result.font = .systemFont(ofSize: 12, weight: .semibold); return result
            }
            button.configuration = config
            button.addAction(UIAction { _ in action() }, for: .touchUpInside)
            shortcuts.addArrangedSubview(button)
        }
        NSLayoutConstraint.activate([
            shortcutScroll.heightAnchor.constraint(equalToConstant: 40),
            shortcuts.leadingAnchor.constraint(equalTo: shortcutScroll.contentLayoutGuide.leadingAnchor),
            shortcuts.trailingAnchor.constraint(equalTo: shortcutScroll.contentLayoutGuide.trailingAnchor),
            shortcuts.topAnchor.constraint(equalTo: shortcutScroll.contentLayoutGuide.topAnchor),
            shortcuts.bottomAnchor.constraint(equalTo: shortcutScroll.contentLayoutGuide.bottomAnchor),
            shortcuts.heightAnchor.constraint(equalTo: shortcutScroll.frameLayoutGuide.heightAnchor)
        ])
        dock.addArrangedSubview(shortcutScroll)

        let composer = UIView()
        composer.backgroundColor = FinLitTheme.surface
        composer.layer.cornerRadius = 24
        composer.layer.cornerCurve = .continuous
        input.backgroundColor = .clear
        input.font = .preferredFont(forTextStyle: .body)
        input.adjustsFontForContentSizeCategory = true
        input.textContainerInset = .init(top: 10, left: 0, bottom: 10, right: 0)
        input.isScrollEnabled = false
        input.delegate = self
        input.accessibilityLabel = "Сообщение помощнику"
        placeholder.text = "Сообщение…"
        placeholder.font = .preferredFont(forTextStyle: .body)
        placeholder.textColor = .placeholderText
        placeholder.isUserInteractionEnabled = false
        var sendConfig = UIButton.Configuration.filled()
        sendConfig.image = UIImage(systemName: "arrow.up", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .bold))
        sendConfig.baseBackgroundColor = FinLitTheme.buttonFill
        sendConfig.baseForegroundColor = .white
        sendConfig.cornerStyle = .capsule
        sendButton.configuration = sendConfig
        sendButton.addTarget(self, action: #selector(sendOrStop), for: .touchUpInside)
        [input, placeholder, sendButton].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; composer.addSubview($0) }
        inputHeight = input.heightAnchor.constraint(equalToConstant: 42)
        NSLayoutConstraint.activate([
            input.leadingAnchor.constraint(equalTo: composer.leadingAnchor, constant: 14),
            input.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),
            input.topAnchor.constraint(equalTo: composer.topAnchor, constant: 5),
            input.bottomAnchor.constraint(equalTo: composer.bottomAnchor, constant: -5),
            inputHeight,
            placeholder.leadingAnchor.constraint(equalTo: input.leadingAnchor, constant: 5),
            placeholder.topAnchor.constraint(equalTo: input.topAnchor, constant: 10),
            sendButton.trailingAnchor.constraint(equalTo: composer.trailingAnchor, constant: -7),
            sendButton.bottomAnchor.constraint(equalTo: composer.bottomAnchor, constant: -7),
            sendButton.widthAnchor.constraint(equalToConstant: 38),
            sendButton.heightAnchor.constraint(equalToConstant: 38)
        ])
        dock.addArrangedSubview(composer)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.keyboardDismissMode = .interactive
        tableView.showsVerticalScrollIndicator = false
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 120
        tableView.contentInset = .init(top: 14, left: 0, bottom: 12, right: 0)
        tableView.register(ChatTimelineCell.self, forCellReuseIdentifier: "ChatRow")
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            dock.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            dock.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            dock.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -8),
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: dock.topAnchor, constant: -4)
        ])
        updateComposer()
    }

    func textViewDidChange(_ textView: UITextView) { updateComposer() }

    private func updateComposer() {
        placeholder.isHidden = !input.text.isEmpty
        let height = input.sizeThatFits(CGSize(width: max(input.bounds.width, 200), height: .greatestFiniteMagnitude)).height
        inputHeight.constant = min(max(height, 42), 112)
        input.isScrollEnabled = height > 112
        let sending = requestID != nil
        sendButton.isEnabled = sending || !input.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        sendButton.configuration?.image = UIImage(systemName: sending ? "stop.fill" : "arrow.up")
        sendButton.accessibilityLabel = sending ? "Остановить запрос" : "Отправить сообщение"
        navigationItem.rightBarButtonItem?.isEnabled = !sending
        dock.arrangedSubviews.first?.isUserInteractionEnabled = !sending
        dock.arrangedSubviews.first?.alpha = sending ? 0.45 : 1
    }

    @objc private func keyboardChanged() { scrollToBottom(animated: false) }

    private func append(_ row: ChatRow, scroll: Bool = true) {
        rows.append(row)
        tableView.insertRows(at: [IndexPath(row: rows.count - 1, section: 0)], with: .none)
        if scroll { scrollToBottom(animated: true) }
    }

    private func addMessage(_ text: String, user: Bool = false, insight: AIChatInsight? = nil) {
        let message = AIChatMessage(text: text, role: user ? .user : .assistant, insight: insight)
        messages.append(message)
        AppStorage.shared.saveAIChatMessages(messages)
        append(.message(message))
    }

    private func showMenu(title: String, detail: String, options: [ChatOption]) {
        guard requestID == nil else { return }
        input.resignFirstResponder()
        let menu = ChatMenu(title: title, detail: detail, options: options)
        activeMenuID = menu.id
        // Replace a pending menu instead of piling up unused keyboards.
        if case .menu? = rows.last { rows.removeLast(); rows.append(.menu(menu)); tableView.reloadData(); scrollToBottom(animated: true) }
        else { append(.menu(menu)) }
    }

    private func showActions() {
        showMenu(title: "С чего начнём?", detail: "Выберите действие или напишите свой вопрос ниже.", options: [
            ChatOption(title: "Сколько кому перевёл", detail: "Человек → период → точная сумма", symbol: "arrow.up.right") { [weak self] in self?.showTransferDirections() },
            ChatOption(title: "Сколько на что потратил", detail: "Категория → период → операции", symbol: "chart.pie") { [weak self] in self?.showCategories() },
            ChatOption(title: "Поправить распределение", detail: "AI-проверка или ручное исправление", symbol: "sparkles") { [weak self] in self?.showReviewActions() },
            ChatOption(title: "Обзор за период", detail: "Доходы, расходы и основные категории", symbol: "chart.bar") { [weak self] in self?.showPeriods(for: .overview) }
        ])
    }

    private func showTransferDirections() {
        showMenu(title: "Какие переводы посмотреть?", detail: "Выберите направление перевода.", options: [
            ChatOption(title: "Кому я переводил", symbol: "arrow.up.right") { [weak self] in self?.showPeople(.outgoing) },
            ChatOption(title: "Кто переводил мне", symbol: "arrow.down.left") { [weak self] in self?.showPeople(.incoming) }
        ])
    }

    private func showPeople(_ direction: AssistantAnalytics.Direction) {
        let people = AssistantAnalytics.people(in: transactions, direction: direction)
        guard !people.isEmpty else { addMessage("В загруженных выписках не найдено \(direction == .outgoing ? "исходящих" : "входящих") переводов людям."); return }
        var options = people.prefix(6).map { person in
            ChatOption(title: person.name, detail: "\(person.count) операций", symbol: "person.crop.circle") { [weak self] in
                self?.selectPerson(person, direction: direction)
            }
        }
        if people.count > 6 {
            options.append(ChatOption(title: "Все люди · \(people.count)", detail: "Открыть список с поиском", symbol: "magnifyingglass") { [weak self] in
                self?.showChoices(title: direction.title, choices: people.map { .init(id: $0.key, title: $0.name, detail: "\($0.count) операций") }) { [weak self] key in
                    guard let person = people.first(where: { $0.key == key }) else { return }
                    self?.selectPerson(person, direction: direction)
                }
            })
        }
        showMenu(title: direction.title, detail: "Люди из ваших выписок. Затем выберем период.", options: options)
    }

    private func selectPerson(_ person: AssistantAnalytics.Person, direction: AssistantAnalytics.Direction) {
        addMessage("\(direction == .outgoing ? "Мои переводы →" : "Переводы от") \(person.name)", user: true)
        showPeriods(for: .person(key: person.key, name: person.name, direction: direction))
    }

    private func showCategories(review: Bool = false) {
        let categories = Set(transactions.filter { review || $0.amount < 0 }.map(\.category)).sorted { $0.sortOrder < $1.sortOrder }
        guard !categories.isEmpty else { addMessage("Сначала добавьте выписку в аналитике — здесь появятся её категории."); return }
        var options = categories.map { category in
            ChatOption(title: category.rawValue, symbol: category.icon) { [weak self] in
                self?.addMessage(category.rawValue, user: true)
                self?.showPeriods(for: review ? .review(category) : .category(category))
            }
        }
        if review {
            options.insert(ChatOption(title: "Все категории", symbol: "square.grid.2x2") { [weak self] in self?.showPeriods(for: .review(nil)) }, at: 0)
        }
        showMenu(title: review ? "Что проверим?" : "Расходы по категории", detail: "Выберите категорию из загруженных операций.", options: options)
    }

    private func showPeriods(for query: AssistantAnalytics.Query) {
        let selected = AssistantAnalytics.rows(for: query, in: transactions)
        guard !selected.isEmpty else { addMessage("Для этого действия пока нет подходящих операций. Добавьте выписку или выберите другую категорию."); return }
        let periods = AssistantAnalytics.periods(in: selected)
        let options = periods.map { period in
            ChatOption(title: period.title, symbol: period == .all ? "calendar" : "calendar.badge.clock") { [weak self] in
                guard let self, self.requestID == nil else { return }
                self.activeMenuID = nil
                self.addMessage(period.title, user: true)
                if case .review = query { self.reviewCategories(query: query, period: period) }
                else { self.answerLocally(query: query, period: period) }
            }
        }
        showMenu(title: "За какой период?", detail: query.title, options: options)
    }

    private func showReviewActions() {
        showMenu(title: "Проверим распределение", detail: "Предложенные AI изменения применяются после вашего подтверждения.", options: [
            ChatOption(title: "Спорные операции", detail: "Подтвердить категории и запомнить выбор", symbol: "checkmark.shield") { [weak self] in
                guard let self else { return }
                let review = CategoryReviewViewController()
                review.onChange = { [weak self] in self?.transactions = AppStorage.shared.loadAllTransactions() }
                self.navigationController?.pushViewController(review, animated: true)
            },
            ChatOption(title: "Проверить категории с AI", detail: "Выберите категории и период проверки", symbol: "sparkles") { [weak self] in self?.showCategories(review: true) },
            ChatOption(title: "Исправить операцию вручную", detail: "Выберите операцию из списка", symbol: "slider.horizontal.3") { [weak self] in self?.selectOperation() }
        ])
    }

    private func answerLocally(query: AssistantAnalytics.Query, period: AssistantAnalytics.Period) {
        let token = beginRequest("Считаю по выписке…")
        let snapshot = transactions
        requestTask = Task { [weak self] in
            let answer = await Task.detached(priority: .userInitiated) {
                AssistantAnalytics.answer(query: query, period: period, transactions: snapshot)
            }.value
            guard let self, self.requestID == token, !Task.isCancelled else { return }
            self.endRequest()
            self.addMessage(answer.text, insight: answer.insight)
        }
    }

    private func selectOperation() {
        let choices = transactions.sorted { $0.date > $1.date }.map { transaction in
            ChatChoice(id: transaction.id, title: transaction.merchant, detail: "\(AssistantAnalytics.money(transaction.amount)) · \(transaction.category.rawValue)")
        }
        guard !choices.isEmpty else { addMessage("Сначала загрузите выписку."); return }
        showChoices(title: "Выберите операцию", choices: choices) { [weak self] id in
            guard let self, let transaction = self.transactions.first(where: { $0.id == id }) else { return }
            let editor = TransactionEditorViewController(transaction: transaction) { [weak self] updated in
                guard let self else { return }
                self.transactions = AppStorage.shared.loadAllTransactions()
                self.addMessage("Сохранено: \(updated.merchant) · \(AssistantAnalytics.money(updated.amount)) · \(updated.category.rawValue).")
            }
            let navigation = UINavigationController(rootViewController: editor)
            navigation.modalPresentationStyle = .pageSheet
            self.present(navigation, animated: true)
        }
    }

    private func showChoices(title: String, choices: [ChatChoice], onPick: @escaping (String) -> Void) {
        let picker = ChatChoiceViewController(title: title, choices: choices, onPick: onPick)
        let navigation = UINavigationController(rootViewController: picker)
        navigation.modalPresentationStyle = .pageSheet
        navigation.sheetPresentationController?.prefersGrabberVisible = true
        present(navigation, animated: true)
    }

    @objc private func sendOrStop() {
        if requestID != nil { cancelRequest(); return }
        let text = input.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let history = messages
        input.text = ""
        input.resignFirstResponder()
        activeMenuID = nil
        addMessage(text, user: true)
        let token = beginRequest("Готовлю ответ…")
        let snapshot = transactions
        requestTask = Task { [weak self] in
            do {
                let result = try await OpenRouterCategorizer.shared.review(message: text, history: history, transactions: snapshot)
                guard let self, self.requestID == token, !Task.isCancelled else { return }
                self.endRequest()
                self.addMessage(result.reply, insight: result.insight)
                self.offer(result.changes)
            } catch {
                guard let self, self.requestID == token, !Task.isCancelled else { return }
                self.endRequest()
                self.showRetry(message: text, detail: error.localizedDescription)
            }
        }
    }

    private func reviewCategories(query: AssistantAnalytics.Query, period: AssistantAnalytics.Period) {
        let selected = AssistantAnalytics.rows(for: query, period: period, in: transactions)
        let token = beginRequest("Проверяю категории · 0 из \(selected.count)")
        requestTask = Task { [weak self] in
            do {
                let categories = try await OpenRouterCategorizer.shared.categorize(selected) { [weak self] done, total in
                    Task { @MainActor [weak self] in
                        guard let self, self.requestID == token else { return }
                        self.statusText = "Проверяю категории · \(done) из \(total)"
                        self.reloadTyping()
                    }
                }
                guard let self, self.requestID == token, !Task.isCancelled else { return }
                self.endRequest()
                let changes = selected.compactMap { row -> OpenRouterCategorizer.ReviewChange? in
                    guard let category = categories[row.id], category != row.category else { return nil }
                    return .init(id: row.id, category: category, amount: row.amount, reason: "Повторная AI-проверка категории")
                }
                let coverage = "Проверено \(categories.count) из \(selected.count) операций."
                GamificationManager.shared.recordAIReview(correctionCount: 0, reviewedCount: categories.count)
                self.addMessage(changes.isEmpty ? "\(coverage) По проверенным операциям AI не предложил менять категории." : "\(coverage) Предложений изменить категорию: \(changes.count). Проверьте их перед применением.")
                self.offer(changes, alreadyReviewed: true)
            } catch {
                guard let self, self.requestID == token, !Task.isCancelled else { return }
                self.endRequest()
                self.showMenu(title: "Не удалось завершить проверку", detail: error.localizedDescription, options: [
                    ChatOption(title: "Повторить", symbol: "arrow.clockwise") { [weak self] in self?.reviewCategories(query: query, period: period) }
                ])
            }
        }
    }

    private func beginRequest(_ status: String) -> UUID {
        activeMenuID = nil
        let token = UUID()
        requestID = token
        statusText = status
        append(.typing)
        updateComposer()
        return token
    }

    private func endRequest() {
        requestID = nil
        requestTask = nil
        if let index = rows.lastIndex(where: { if case .typing = $0 { return true }; return false }) {
            rows.remove(at: index)
            tableView.deleteRows(at: [IndexPath(row: index, section: 0)], with: .none)
        }
        updateComposer()
    }

    private func cancelRequest() {
        requestTask?.cancel()
        endRequest()
    }

    private func reloadTyping() {
        guard let index = rows.lastIndex(where: { if case .typing = $0 { return true }; return false }) else { return }
        tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .none)
    }

    private func showRetry(message: String, detail: String) {
        showMenu(title: "Ответ пока не получен", detail: detail, options: [
            ChatOption(title: "Повторить вопрос", symbol: "arrow.clockwise") { [weak self] in
                self?.input.text = message
                self?.sendOrStop()
            }
        ])
    }

    private func offer(_ proposed: [OpenRouterCategorizer.ReviewChange], alreadyReviewed: Bool = false) {
        let byID = Dictionary(transactions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        let changes = proposed.filter { change in
            guard seen.insert(change.id).inserted, change.amount.isFinite, change.amount != 0, abs(change.amount) <= 1_000_000_000_000,
                  let row = byID[change.id] else { return false }
            return row.category != change.category || abs(row.amount - change.amount) > 0.001
        }
        guard !changes.isEmpty else { return }
        var lines = changes.prefix(6).compactMap { change -> String? in
            guard let row = byID[change.id] else { return nil }
            let amount = abs(row.amount - change.amount) > 0.001 ? " · \(AssistantAnalytics.money(row.amount)) → \(AssistantAnalytics.money(change.amount))" : ""
            return "\(row.merchant)\n\(row.category.rawValue) → \(change.category.rawValue)\(amount)"
        }
        if changes.count > 6 { lines.append("И ещё \(changes.count - 6) исправлений. Откройте полный список перед применением.") }
        var options: [ChatOption] = []
        if changes.count > 6 {
            options.append(ChatOption(title: "Все исправления · \(changes.count)", symbol: "list.bullet") { [weak self] in
                let detail = changes.compactMap { change -> String? in
                    guard let row = byID[change.id] else { return nil }
                    return "\(row.merchant) · \(AssistantAnalytics.money(row.amount))\n\(row.category.rawValue) → \(change.category.rawValue) · \(AssistantAnalytics.money(change.amount))"
                }.joined(separator: "\n\n")
                self?.present(FinLitNoticeSheet(title: "Предлагаемые изменения", detail: detail), animated: true)
            })
        }
        options.append(ChatOption(title: "Применить · \(changes.count)", symbol: "checkmark.circle.fill") { [weak self] in
            guard let self else { return }
            self.activeMenuID = nil
            let corrections = Dictionary(changes.map { ($0.id, (amount: $0.amount, category: $0.category)) }, uniquingKeysWith: { first, _ in first })
            self.onApply(corrections)
            self.transactions = AppStorage.shared.loadAllTransactions()
            GamificationManager.shared.recordAIReview(correctionCount: changes.count, reviewedCount: alreadyReviewed ? 0 : changes.count)
            self.addMessage("Изменения применены: \(changes.count). Аналитика обновлена.")
        })
        options.append(ChatOption(title: "Оставить как есть", symbol: "xmark") { [weak self] in
            self?.activeMenuID = nil
            self?.addMessage("Категории оставлены без изменений.")
        })
        showMenu(title: "Предлагаю исправления", detail: lines.joined(separator: "\n\n"), options: options)
    }

    @objc private func close() { cancelRequest(); dismiss(animated: true) }

    private func clearChat() {
        guard requestID == nil else { return }
        let alert = UIAlertController(title: "Очистить переписку?", message: "Сообщения будут удалены с этого устройства.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "Очистить", style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.messages.removeAll()
            self.rows.removeAll()
            AppStorage.shared.clearAIChatMessages()
            self.tableView.reloadData()
            self.showActions()
        })
        present(alert, animated: true)
    }

    private func scrollToBottom(animated: Bool) {
        guard !rows.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.rows.isEmpty else { return }
            let position: UITableView.ScrollPosition
            if case .menu? = self.rows.last { position = .top }
            else { position = .bottom }
            self.tableView.scrollToRow(at: IndexPath(row: self.rows.count - 1, section: 0), at: position, animated: animated && !UIAccessibility.isReduceMotionEnabled)
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ChatRow", for: indexPath) as! ChatTimelineCell
        switch rows[indexPath.row] {
        case let .message(message): cell.configure(message: message)
        case let .menu(menu):
            cell.configure(menu: menu, active: menu.id == activeMenuID, onPick: { [weak self] option in
                guard let self, self.activeMenuID == menu.id, self.requestID == nil else { return }
                UISelectionFeedbackGenerator().selectionChanged()
                option.action()
            })
        case .typing: cell.configureTyping(statusText)
        }
        return cell
    }
}

private final class ChatTimelineCell: UITableViewCell {
    private let card = UIView()
    private let stack = UIStackView()
    private var left: NSLayoutConstraint!
    private var userLeft: NSLayoutConstraint!

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        card.translatesAutoresizingMaskIntoConstraints = false
        card.layer.cornerRadius = 22
        card.layer.cornerCurve = .continuous
        stack.axis = .vertical
        stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(card)
        card.addSubview(stack)
        left = card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14)
        userLeft = card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 56)
        left.isActive = true
        NSLayoutConstraint.activate([
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    private func reset(user: Bool = false) {
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
        left.isActive = false
        userLeft.isActive = false
        (user ? userLeft : left)?.isActive = true
        card.backgroundColor = user ? FinLitTheme.buttonFill : FinLitTheme.surface
    }

    private func label(_ text: String, size: CGFloat, weight: UIFont.Weight = .regular, color: UIColor = .label) -> UILabel {
        let label = UILabel()
        label.text = text
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }

    func configure(message: AIChatMessage) {
        let user = message.role == .user
        reset(user: user)
        let date = DateFormatter()
        date.locale = Locale(identifier: "ru_RU")
        date.dateFormat = "dd MMM · HH:mm"
        let caption = message.insight == nil ? "Tengely" : "По вашей выписке"
        stack.addArrangedSubview(label("\(user ? "Вы" : caption) · \(date.string(from: message.date))", size: 11, weight: .semibold, color: user ? UIColor.white.withAlphaComponent(0.75) : FinLitTheme.accent))
        if let insight = message.insight {
            stack.addArrangedSubview(label(insight.title, size: 15, weight: .semibold))
            let amount = label(AssistantAnalytics.money(insight.amount), size: 29, weight: .bold)
            amount.font = .monospacedDigitSystemFont(ofSize: 29, weight: .bold)
            amount.adjustsFontSizeToFitWidth = true
            amount.minimumScaleFactor = 0.65
            stack.addArrangedSubview(amount)
            stack.addArrangedSubview(label(insight.subtitle, size: 12, color: .secondaryLabel))
            if !insight.lines.isEmpty { stack.addArrangedSubview(label(insight.lines.joined(separator: "\n\n"), size: 13, color: .secondaryLabel)) }
        } else {
            let displayText = user ? message.text : OpenRouterCategorizer.assistantDisplayText(message.text)
            let text = label(displayText, size: 16, color: user ? .white : .label)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 3
            text.attributedText = NSAttributedString(string: displayText, attributes: [.font: text.font!, .foregroundColor: text.textColor!, .paragraphStyle: paragraph])
            stack.addArrangedSubview(text)
        }
    }

    func configure(menu: ChatMenu, active: Bool, onPick: @escaping (ChatOption) -> Void) {
        reset()
        stack.addArrangedSubview(label(menu.title, size: 18, weight: .bold))
        stack.addArrangedSubview(label(menu.detail, size: 13, color: .secondaryLabel))
        for option in menu.options {
            let button = UIButton(type: .system)
            var config = UIButton.Configuration.tinted()
            config.title = option.title
            config.subtitle = option.detail
            config.image = UIImage(systemName: option.symbol)
            config.preferredSymbolConfigurationForImage = .init(pointSize: 17, weight: .semibold)
            config.imagePadding = 12
            config.baseForegroundColor = FinLitTheme.accent
            config.cornerStyle = .medium
            config.titleLineBreakMode = .byTruncatingTail
            config.contentInsets = .init(top: 13, leading: 14, bottom: 13, trailing: 14)
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var result = attributes; result.font = .systemFont(ofSize: 14, weight: .semibold); return result
            }
            button.configuration = config
            button.contentHorizontalAlignment = .leading
            button.isEnabled = active
            button.addAction(UIAction { _ in onPick(option) }, for: .touchUpInside)
            stack.addArrangedSubview(button)
        }
    }

    func configureTyping(_ text: String) {
        reset()
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.color = FinLitTheme.accent
        spinner.startAnimating()
        let row = UIStackView(arrangedSubviews: [spinner, label(text, size: 13, color: .secondaryLabel)])
        row.spacing = 10
        row.alignment = .center
        stack.addArrangedSubview(row)
    }
}

private struct ChatChoice {
    let id: String
    let title: String
    let detail: String
}

private final class ChatChoiceViewController: UITableViewController, UISearchResultsUpdating {
    private let choices: [ChatChoice]
    private var filtered: [ChatChoice]
    private let onPick: (String) -> Void

    init(title: String, choices: [ChatChoice], onPick: @escaping (String) -> Void) {
        self.choices = choices
        filtered = choices
        self.onPick = onPick
        super.init(style: .insetGrouped)
        self.title = title
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = FinLitTheme.background
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        let search = UISearchController(searchResultsController: nil)
        search.searchResultsUpdater = self
        search.searchBar.placeholder = "Имя, название или сумма"
        search.obscuresBackgroundDuringPresentation = false
        navigationItem.searchController = search
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
    }

    func updateSearchResults(for searchController: UISearchController) {
        let query = (searchController.searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        filtered = query.isEmpty ? choices : choices.filter { "\($0.title) \($0.detail)".localizedCaseInsensitiveContains(query) }
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { filtered.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Choice") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "Choice")
        let choice = filtered[indexPath.row]
        cell.textLabel?.text = choice.title
        cell.detailTextLabel?.text = choice.detail
        cell.backgroundColor = FinLitTheme.surface
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let id = filtered[indexPath.row].id
        let callback = onPick
        // Dismiss the whole sheet, even if UISearchController is currently active.
        navigationController?.presentingViewController?.dismiss(animated: true) { callback(id) }
    }
}
