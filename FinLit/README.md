# FinLit
App for financial literacy.

## AI-сортировка выписки

После разбора PDF приложение отправляет операции на локальный/развёрнутый proxy, а proxy вызывает OpenRouter с моделью `nvidia/nemotron-3-ultra-550b-a55b:free`. Если proxy недоступен, остаются локальные категории из `Categorizer.swift`.

1. Создайте ключ на [OpenRouter](https://openrouter.ai/keys).
2. Запустите proxy:

```bash
cd openrouter-proxy
cp .env.example .env
# впишите OPENROUTER_API_KEY в .env
npm start
```

3. Для iOS Simulator адрес уже настроен на `http://127.0.0.1:8787`.
   Для физического iPhone замените `AI_API_BASE_URL` в `FinLit/Info.plist` на HTTPS-адрес опубликованного proxy (или адрес Mac в локальной сети для разработки).

Ключ OpenRouter нельзя добавлять в iOS-приложение: любой пользователь сможет извлечь его из бинарника.
