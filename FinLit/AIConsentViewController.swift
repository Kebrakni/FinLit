import UIKit

@MainActor
enum AIConsent {
    static func request(from presenter: UIViewController, reconsider: Bool = false) async -> Bool {
        let preferences = AIPrivacyPreferences()
        if !reconsider {
            if preferences.choice == .allowed { return true }
            if preferences.choice == .declined { return false }
        }
        guard presenter.presentedViewController == nil, presenter.viewIfLoaded?.window != nil else { return false }
        return await withCheckedContinuation { continuation in
            let sheet = AIConsentViewController { continuation.resume(returning: $0) }
            presenter.present(sheet, animated: true)
        }
    }
}

final class AIConsentViewController: FinLitFormSheet, UIAdaptivePresentationControllerDelegate {
    private var completion: ((Bool) -> Void)?

    init(completion: @escaping (Bool) -> Void) {
        self.completion = completion
        super.init(title: "Разрешить обработку с AI?",
                   detail: "Вы сами выбираете, отправлять ли данные внешним AI-сервисам. Без разрешения выписка будет обработана на iPhone локальными правилами.",
                   symbol: "hand.raised.fill", action: "Разрешить AI", actionSymbol: "sparkles")
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        presentationController?.delegate = self
        addNote("Какие данные: даты и суммы операций, названия продавцов или контрагентов, назначения платежей и категории. Для чата — ваше сообщение, часть истории и подходящие операции. Для миссий — цель и недавние операции.", symbol: "doc.text")
        addNote("Кому: наш сервер Google Firebase → OpenRouter, Inc. → NVIDIA (провайдер модели Nemotron). PDF целиком не отправляется. Текст операции может содержать имена и другие личные сведения.", symbol: "arrow.up.forward.square")
        addNote("Зачем: предложить категории, ответить на вопрос по операциям и составить миссии. У OpenRouter и NVIDIA действуют собственные условия хранения и использования данных.", symbol: "sparkles")
        addNote("Разрешение можно отозвать в Настройках → Конфиденциальность. Это остановит новые AI-запросы; уже переданные данные нельзя отозвать из завершённого запроса.")
        let policy = UIButton(type: .system)
        var policyConfig = UIButton.Configuration.plain()
        policyConfig.title = "Политика конфиденциальности"
        policyConfig.image = UIImage(systemName: "doc.text.magnifyingglass")
        policyConfig.imagePadding = 8
        policy.configuration = policyConfig
        policy.addAction(UIAction { [weak self] _ in
            self?.present(UINavigationController(rootViewController: PrivacyPolicyViewController()), animated: true)
        }, for: .touchUpInside)
        if let dock = submitButton.superview as? UIStackView {
            dock.insertArrangedSubview(policy, at: max(0, dock.arrangedSubviews.count - 1))
        } else { contentStack.addArrangedSubview(policy) }
        let decline = UIButton(type: .system)
        var config = UIButton.Configuration.gray()
        config.title = AIPrivacyPreferences().isAllowed ? "Отключить AI" : "Продолжить без AI"
        config.baseForegroundColor = .label
        config.contentInsets = .init(top: 16, leading: 18, bottom: 16, trailing: 18)
        config.titleLineBreakMode = .byWordWrapping
        decline.configuration = config
        decline.addAction(UIAction { [weak self] _ in self?.choose(false) }, for: .touchUpInside)
        decline.heightAnchor.constraint(greaterThanOrEqualToConstant: 54).isActive = true
        if let dock = submitButton.superview as? UIStackView { dock.addArrangedSubview(decline) }
        else { contentStack.addArrangedSubview(decline) }
    }

    override func submit() { choose(true) }

    private func choose(_ allowed: Bool) {
        AIPrivacyPreferences().set(allowed ? .allowed : .declined)
        if !allowed { OpenRouterCategorizer.shared.cancelAIRequests() }
        dismiss(animated: true)
    }

    private func reply(_ allowed: Bool) {
        let callback = completion
        completion = nil
        callback?(allowed)
    }

    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        super.dismiss(animated: flag) { [self] in
            reply(AIPrivacyPreferences().isAllowed)
            completion?()
        }
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        reply(AIPrivacyPreferences().isAllowed)
    }
}
