import UIKit

final class PrivacyPolicyViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.text("Конфиденциальность")
        view.backgroundColor = FinLitTheme.background
        navigationItem.largeTitleDisplayMode = .never
        if presentingViewController != nil || navigationController?.presentingViewController != nil {
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: L10n.text("Готово"), primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        }
        let scroll = UIScrollView()
        let stack = UIStackView()
        stack.axis = .vertical; stack.spacing = 18
        [scroll, stack].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        view.addSubview(scroll); scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -32),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -24)
        ])
        let sections: [(String, String)] = [
            (L10n.text("Политика конфиденциальности Tengely"), L10n.text("Редакция от 17 ноября 2026 года. Версия согласия: {0}.", String(describing: AIPrivacyPreferences.version))),
            (L10n.text("Данные на устройстве"), L10n.text("Tengely сохраняет операции, категории, цели, ручные накопления, историю чата, настройки и решения по категориям на iPhone. Исходный PDF читается на устройстве и целиком в AI не загружается. Работа без AI сохраняет локальную категоризацию и аналитику.")),
            (L10n.text("AI — только с разрешения"), L10n.text("До вашего согласия приложение не отправляет данные в AI. После согласия через сервер Google Firebase / Google Cloud в OpenRouter, Inc. и далее NVIDIA передаются даты, суммы, продавцы или контрагенты, описания платежей и категории. Для чата также отправляются сообщение, часть истории и относящиеся к вопросу операции; для миссий — цель и недавние операции. Описания могут содержать имена и другую личную информацию. Назначение обработки — категоризация, проверка ошибок, ответы и миссии.")),
            (L10n.text("Сторонние сервисы"), L10n.text("Google предоставляет серверную инфраструктуру Firebase. OpenRouter маршрутизирует запросы к NVIDIA, которая выполняет генерацию модели Nemotron. Хранение и использование переданных данных этими организациями регулируются их политиками и условиями. Мы не обещаем отсутствие хранения или использования данных провайдером для улучшения моделей. Получателей нельзя автоматически менять без обновления согласия в приложении.")),
            (L10n.text("Сетевые функции и лимит"), L10n.text("Битвы являются отдельной сетевой функцией: Firebase хранит комнату, игровое имя, сумму накоплений, цель и прогресс; эти сведения видят другие участники. Это не зависит от включения AI. Для AI-чата используется анонимный профиль Firebase; токен обновления хранится в Keychain. Сервер сохраняет хеш идентификатора профиля, день и расход токенов для дневного лимита. Счётчики хранятся до удаления администратором; автоматическое удаление пока не настроено.")),
            (L10n.text("Хранение и удаление"), L10n.text("Отдельная серверная база ваших выписок и сообщений в Tengely не создаётся: они передаются на обработку. У инфраструктуры и AI-поставщиков могут быть технические журналы и собственные сроки хранения. Локальные операции можно удалить в Аналитике, историю чата — через меню чата. Уже переданные сторонним сервисам данные не удаляются автоматически при очистке приложения. По вопросам обработки и удаления серверных данных обращайтесь к разработчику.")),
            (L10n.text("Ваш выбор"), L10n.text("Вы можете отказаться от AI или отозвать разрешение: Настройки → Конфиденциальность → Обработка с AI. Отзыв прекращает новые отправки, отменяет незавершённые клиентские AI-запросы и сохраняет локальные функции. Данные, уже отправленные на сервер или провайдеру, нельзя вернуть отменой запроса. Повторное включение потребует явного разрешения.")),
            (L10n.text("Разработчик и обращения"), contactText()),
        ]
        for (heading, body) in sections {
            let title = UILabel(); title.text = heading; title.numberOfLines = 0
            title.font = FinLitTheme.font(19, weight: .semibold, style: .headline)
            let text = UILabel(); text.text = body; text.numberOfLines = 0
            text.font = FinLitTheme.font(15); text.textColor = .secondaryLabel
            [title, text].forEach { $0.adjustsFontForContentSizeCategory = true; stack.addArrangedSubview($0) }
        }
        var links = [
            (L10n.text("Политика Google / Firebase"), "https://policies.google.com/privacy"),
            (L10n.text("Политика OpenRouter"), "https://openrouter.ai/privacy"),
            (L10n.text("Политика NVIDIA"), "https://www.nvidia.com/en-us/about-nvidia/privacy-policy/"),
        ]
        if let address = Bundle.main.object(forInfoDictionaryKey: "PRIVACY_POLICY_URL") as? String,
           let url = URL(string: address), url.scheme == "https" {
            links.insert((L10n.text("Открыть веб-версию политики"), L10n.privacyURL(address)), at: 0)
        }
        for (name, address) in links {
            let button = UIButton(type: .system)
            var config = UIButton.Configuration.tinted(); config.title = name; config.image = UIImage(systemName: "arrow.up.right.square"); config.imagePadding = 8
            config.contentInsets = .init(top: 14, leading: 12, bottom: 14, trailing: 12); config.titleLineBreakMode = .byWordWrapping
            button.configuration = config
            button.addAction(UIAction { _ in UIApplication.shared.open(URL(string: address)!) }, for: .touchUpInside)
            stack.addArrangedSubview(button)
        }
    }

    private func contactText() -> String {
        let name = Bundle.main.object(forInfoDictionaryKey: "PRIVACY_DEVELOPER_NAME") as? String ?? L10n.text("Разработчик Tengely")
        if let email = Bundle.main.object(forInfoDictionaryKey: "PRIVACY_CONTACT_EMAIL") as? String, !email.isEmpty {
            return L10n.text("{0}. Контакт для вопросов о данных и запросов на удаление: {1}.", String(describing: name), String(describing: email))
        }
        return L10n.text("{0}. Контакт для обращений ещё не указан. Перед публичным выпуском здесь должны быть опубликованы контактные данные разработчика.", String(describing: name))
    }
}
