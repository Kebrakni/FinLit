// Request-scoped presentation only. Never translate merchant/details or IDs.
const english = {
  "AI не вернул полную проверку. Операции не помечены проверенными; попробуйте ещё раз.": "AI did not return a complete review. The transactions have not been marked as reviewed; try again.",
  "OpenRouter не смог создать задания": "OpenRouter could not create missions",
  "OpenRouter не смог обработать запрос": "OpenRouter could not process the request",
  "Нужно передать от 1 до 120 операций": "Send between 1 and 120 transactions",
  "У операций должны быть уникальные id": "Transactions must have unique IDs",
  "Сумма операции должна быть конечным ненулевым числом": "Transaction amounts must be finite, non-zero numbers",
  "Проверьте сумму цели и накоплений": "Check the goal and savings amounts",
  "Курсовая корректировка": "Exchange adjustment",
  "Перемещение между своими счетами или внесение наличных": "Moving money between your own accounts or depositing cash",
  "Явная пометка подписки": "Explicit subscription marker",
  "Dodo Pizza — готовая еда": "Dodo Pizza — prepared food",
  "Некорректный размер AI-ответа": "Invalid AI response size",
  "Недостаточно дневного лимита для этого сообщения. Лимит чата — 100 000 токенов, включая контекст и ответ. Он обновится в 00:00 по времени Алматы. Анализ выписок доступен отдельно.": "Not enough daily allowance for this message. The chat limit is 100,000 tokens including context and replies. It resets at 00:00 Almaty time. Statement analysis is available separately.",
  "Для AI-чата нужен профиль приложения. Обновите приложение и попробуйте снова.": "AI chat requires an app profile. Update the app and try again.",
  "Не удалось подтвердить профиль AI-чата. Откройте чат ещё раз.": "Could not verify your AI chat profile. Reopen the chat.",
  "Банк указал перевод или пополнение": "The bank marked this as a transfer or top-up",
  "Банк указал снятие наличных": "The bank marked this as a cash withdrawal",
  "Все": "All",
  "Категория": "Category",
  "Назначение платежа нужно уточнить у вас.": "Please clarify the purpose of this payment.",
  "Платёж по кредиту или рассрочке": "Loan or installment payment",
  "Проверить": "Review",
  "Финансовая ревизия": "Financial checkup",
  "Цель": "Goal",
  "Я": "Me",
  "банк": "bank",
  "банковское приложение": "banking app",
  "бизнес-счёт": "business account",
  "карта": "card",
  "кредит или рассрочка": "loan or installment plan",
  "Категория, которую вы ранее выбрали для этого продавца и типа операции.": "The category you previously chose for this merchant and transaction type.",
  "AI предлагает уточнить категорию по назначению платежа.": "AI suggests a different category based on the payment purpose.",
  "Не удалось получить лимит чата": "Could not retrieve the chat limit",
  "Не удалось проверить категории": "Could not review categories",
  "Напишите вопрос об операции": "Enter a question about a transaction",
  "Для AI-обработки нужно явное согласие на передачу данных Firebase, OpenRouter и NVIDIA. Обновите приложение и выберите режим в настройках конфиденциальности.": "AI processing requires explicit consent to sharing data with Firebase, OpenRouter and NVIDIA. Update the app and choose a mode in privacy settings.",
  "AI не успел ответить. Попробуйте ещё раз или выберите меньший период проверки.": "AI did not respond in time. Try again or select a shorter review period.",
  "AI-проверка временно недоступна. Уже полученные предложения сохранены.": "AI review is temporarily unavailable. Suggestions already received have been saved.",
  "За один запрос можно проверить до 40 операций": "You can review up to 40 transactions per request",
  "OpenRouter не смог проверить операции": "OpenRouter could not review transactions"
};
function localizeText(text, language) { return language === "en" ? (english[text] || text) : text; }
function localizePayload(body, language) {
  if (language !== "en" || !body || typeof body !== "object") return body;
  if (Array.isArray(body)) return body.map((value) => localizePayload(value, language));
  return Object.fromEntries(Object.entries(body).map(([key, value]) => [key,
    ["error", "reason"].includes(key) && typeof value === "string" ? localizeText(value, language)
      : value && typeof value === "object" ? localizePayload(value, language) : value]));
}
module.exports = { localizeText, localizePayload };
