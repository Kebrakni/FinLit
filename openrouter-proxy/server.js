const http = require("node:http");
const fs = require("node:fs");
const path = require("node:path");
const { requestCategoryAudit } = require("../functions/category-audit");

loadDotEnv();

const PORT = Number(process.env.PORT || 8787);
const MODEL = process.env.OPENROUTER_MODEL || "nvidia/nemotron-3-ultra-550b-a55b:free";
const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions";
const MAX_TRANSACTIONS = 120;
const MAX_BODY_BYTES = 1_500_000;

const categoryCodes = [
  "food", "cafes", "transport", "entertainment", "health", "education",
  "utilities", "subscriptions", "shopping", "loans", "taxes",
  "cash_withdrawals", "transfers", "internal_transfers", "other"
];

const categoryDescriptions = {
  food: "продукты и супермаркеты",
  cafes: "кафе, рестораны, доставка еды",
  transport: "такси, автобус, метро, транспорт",
  entertainment: "кино, игры, мероприятия и развлечения",
  health: "аптеки, врачи, клиники и здоровье",
  education: "курсы, книги, обучение",
  utilities: "коммунальные услуги, связь, интернет",
  subscriptions: "регулярные цифровые подписки и облачные сервисы",
  shopping: "товары, техника, маркетплейсы и прочие покупки",
  loans: "кредиты, займы, рассрочки и погашения долгов",
  taxes: "налоги, штрафы и государственные платежи",
  cash_withdrawals: "снятие наличных в банкомате",
  transfers: "переводы другим людям или на другие счета",
  internal_transfers: "перевод между своими счетами, депозитом или бизнес-счётом",
  other: "если нельзя уверенно выбрать другую категорию"
};

const tool = {
  type: "function",
  function: {
    name: "categorize_transactions",
    description: "Assign exactly one category to every transaction by its id.",
    parameters: {
      type: "object",
      additionalProperties: false,
      properties: {
        categories: {
          type: "array",
          items: {
            type: "object",
            additionalProperties: false,
            properties: {
              id: { type: "string" },
              category: { type: "string", enum: categoryCodes }
            },
            required: ["id", "category"]
          }
        }
      },
      required: ["categories"]
    }
  }
};

const server = http.createServer(async (request, response) => {
  setCorsHeaders(response);

  if (request.method === "OPTIONS") {
    response.writeHead(204);
    response.end();
    return;
  }

  if (request.method === "GET" && request.url === "/health") {
    sendJSON(response, 200, { ok: true, model: MODEL });
    return;
  }

  if (request.method === "POST" && request.url === "/api/category-audit") {
    try {
      const body = await readJSON(request);
      const transactions = validateTransactions(body.transactions);
      if (!process.env.OPENROUTER_API_KEY) {
        sendJSON(response, 503, { error: "На proxy-сервере не настроен OPENROUTER_API_KEY" }); return;
      }
      const assessments = await requestCategoryAudit({ fetch, apiKey: process.env.OPENROUTER_API_KEY,
        model: MODEL, url: OPENROUTER_URL, transactions, codes: categoryCodes, descriptions: categoryDescriptions });
      sendJSON(response, 200, { assessments });
    } catch (error) {
      sendJSON(response, error.statusCode || 502, { error: error.publicMessage || "Не удалось проверить категории. Попробуйте ещё раз." });
    }
    return;
  }

  if (request.method !== "POST" || request.url !== "/api/categorize") {
    sendJSON(response, 404, { error: "Not found" });
    return;
  }

  try {
    const body = await readJSON(request);
    const transactions = validateTransactions(body.transactions);
    const categories = await categorizeWithOpenRouter(transactions);
    sendJSON(response, 200, { categories });
  } catch (error) {
    const status = error.statusCode || 500;
    console.error(`[${new Date().toISOString()}] ${error.message}`);
    sendJSON(response, status, { error: error.publicMessage || "AI categorization failed" });
  }
});

server.listen(PORT, "0.0.0.0", () => {
  console.log(`Tengely OpenRouter proxy listening on http://127.0.0.1:${PORT}`);
  console.log(`Model: ${MODEL}`);
});

async function categorizeWithOpenRouter(transactions) {
  const apiKey = process.env.OPENROUTER_API_KEY;
  if (!apiKey || apiKey === "sk-or-v1-replace-me") {
    const error = new Error("OPENROUTER_API_KEY is not configured");
    error.statusCode = 503;
    error.publicMessage = "На proxy-сервере не настроен OPENROUTER_API_KEY";
    throw error;
  }

  const prompt = [
    "Разнеси операции банковской выписки по категориям.",
    "Purchases — тип оплаты, а не категория shopping. Определяй назначение по merchant/details: Dodo Pizza / Додо Пицца → cafes; явные пометки SUBCR/SUBSCR/SUBSCRIPTION/RECURRING → subscriptions.",
    "Перевод человеку остаётся transfers, даже если имя похоже на магазин. Не копируй currentCategory автоматически и не выдумывай назначение незнакомого продавца: при нехватке данных выбирай other.",
    "Используй merchant, details, сумму, знак суммы и тип операции.",
    "Положительный amount — поступление, отрицательный — расход.",
    "Верни ровно одну категорию для каждой переданной операции, используя только id из входных данных.",
    "Не меняй id и не придумывай новые операции.",
    "Категории:",
    ...categoryCodes.map((code) => `- ${code}: ${categoryDescriptions[code]}`),
    "Операции JSON:",
    JSON.stringify(transactions)
  ].join("\n");

  const upstreamResponse = await fetch(OPENROUTER_URL, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${apiKey}`,
      "Content-Type": "application/json",
      ...(process.env.OPENROUTER_SITE_URL ? { "HTTP-Referer": process.env.OPENROUTER_SITE_URL } : {}),
      ...(process.env.OPENROUTER_APP_NAME ? { "X-Title": process.env.OPENROUTER_APP_NAME } : {})
    },
    body: JSON.stringify({
      model: MODEL,
      messages: [
        {
          role: "system",
          content: "Ты аккуратный классификатор банковских операций. Отвечай только вызовом функции категоризации."
        },
        { role: "user", content: prompt }
      ],
      tools: [tool],
      tool_choice: { type: "function", function: { name: "categorize_transactions" } },
      temperature: 0.1,
      max_tokens: Math.min(4096, Math.max(512, transactions.length * 35)),
      seed: 42
    })
  });

  const upstreamBody = await upstreamResponse.json().catch(() => ({}));
  if (!upstreamResponse.ok) {
    const error = new Error(`OpenRouter HTTP ${upstreamResponse.status}`);
    error.statusCode = upstreamResponse.status === 429 ? 429 : 502;
    error.publicMessage = upstreamBody?.error?.message || "OpenRouter не смог обработать запрос";
    throw error;
  }

  const message = upstreamBody?.choices?.[0]?.message;
  const toolCall = message?.tool_calls?.find((call) => call?.function?.name === "categorize_transactions");
  const rawArguments = toolCall?.function?.arguments || message?.content;
  const parsed = parseModelJSON(rawArguments);
  const categories = Array.isArray(parsed?.categories) ? parsed.categories : [];
  const validIds = new Set(transactions.map((transaction) => transaction.id));

  return categories
    .filter((item) => validIds.has(item?.id) && categoryCodes.includes(item?.category))
    .map((item) => ({ id: item.id, category: item.category }));
}

function parseModelJSON(value) {
  if (value && typeof value === "object") return value;
  if (typeof value !== "string") return null;

  try {
    return JSON.parse(value);
  } catch (_) {
    const match = value.match(/\{[\s\S]*\}/);
    if (!match) return null;
    try {
      return JSON.parse(match[0]);
    } catch (_) {
      return null;
    }
  }
}

function validateTransactions(value) {
  if (!Array.isArray(value) || value.length === 0 || value.length > MAX_TRANSACTIONS) {
    const error = new Error("Invalid transactions payload");
    error.statusCode = 400;
    error.publicMessage = `Нужно передать от 1 до ${MAX_TRANSACTIONS} операций`;
    throw error;
  }

  const ids = new Set();
  return value.map((item) => {
    if (!item || typeof item.id !== "string" || !item.id.trim() || item.id.length > 1024 || ids.has(item.id)) {
      const error = new Error("Invalid transaction id");
      error.statusCode = 400;
      error.publicMessage = "У операций должны быть уникальные id";
      throw error;
    }
    ids.add(item.id);
    if (typeof item.amount !== "number" || !Number.isFinite(item.amount) || item.amount === 0 || Math.abs(item.amount) > 1_000_000_000_000) {
      const error = new Error("Invalid transaction amount");
      error.statusCode = 400;
      error.publicMessage = "Сумма операции должна быть конечным ненулевым числом";
      throw error;
    }
    return {
      id: item.id,
      date: String(item.date || "").slice(0, 80),
      amount: item.amount,
      merchant: String(item.merchant || "").slice(0, 500),
      details: String(item.details || "").slice(0, 1000),
      currentCategory: categoryCodes.includes(item.currentCategory) ? item.currentCategory : "other",
      manualCategory: categoryCodes.includes(item.manualCategory) ? item.manualCategory : null,
    };
  });
}

function readJSON(request) {
  return new Promise((resolve, reject) => {
    let size = 0;
    let raw = "";
    request.setEncoding("utf8");
    request.on("data", (chunk) => {
      size += Buffer.byteLength(chunk);
      if (size > MAX_BODY_BYTES) {
        const error = new Error("Request too large");
        error.statusCode = 413;
        error.publicMessage = "Выписка слишком большая для AI-сортировки";
        reject(error);
        request.destroy();
        return;
      }
      raw += chunk;
    });
    request.on("end", () => {
      try {
        resolve(JSON.parse(raw));
      } catch (_) {
        const error = new Error("Invalid JSON");
        error.statusCode = 400;
        error.publicMessage = "Proxy получил некорректный JSON";
        reject(error);
      }
    });
    request.on("error", reject);
  });
}

function setCorsHeaders(response) {
  response.setHeader("Access-Control-Allow-Origin", "*");
  response.setHeader("Access-Control-Allow-Headers", "Content-Type");
}

function sendJSON(response, statusCode, body) {
  response.writeHead(statusCode, { "Content-Type": "application/json; charset=utf-8" });
  response.end(JSON.stringify(body));
}

function loadDotEnv() {
  const envPath = path.join(__dirname, ".env");
  if (!fs.existsSync(envPath)) return;
  for (const line of fs.readFileSync(envPath, "utf8").split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const separator = trimmed.indexOf("=");
    if (separator < 1) continue;
    const key = trimmed.slice(0, separator).trim();
    const value = trimmed.slice(separator + 1).trim().replace(/^['"]|['"]$/g, "");
    if (!process.env[key]) process.env[key] = value;
  }
}
