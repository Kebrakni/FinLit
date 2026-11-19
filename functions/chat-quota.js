const { randomUUID, createHash } = require("node:crypto");
const DAILY_LIMIT = 100_000;

function dayInfo(now = new Date()) {
  const parts = new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Almaty", year: "numeric", month: "2-digit", day: "2-digit" }).formatToParts(now);
  const get = (type) => parts.find((part) => part.type === type).value;
  const day = `${get("year")}-${get("month")}-${get("day")}`;
  return { day, resetsAt: new Date(Date.parse(`${day}T00:00:00+05:00`) + 86400000).toISOString() };
}

function quotaError(message, statusCode = 429) {
  const error = new Error(message);
  error.statusCode = statusCode; error.publicMessage = message;
  if (statusCode === 429) error.code = "DAILY_CHAT_LIMIT";
  return error;
}

function summary(state, now, limit) {
  const reservedTokens = Object.values(state.pending || {}).reduce((sum, amount) => sum + amount, 0);
  return { limit, usedTokens: Math.max(0, (state.used || 0) - reservedTokens), reservedTokens,
    remainingTokens: Math.max(0, limit - (state.used || 0)), ...dayInfo(now), timeZone: "Asia/Almaty" };
}

/// Store methods are atomic per user/day and never use client-supplied counts.
function createBudget({ store, upstreamFetch, now = () => new Date(), limit = DAILY_LIMIT }) {
  const key = (uid, date) => createHash("sha256").update(uid).digest("hex") + "_" + dayInfo(date).day;
  return {
    async usage(uid) { const date = now(); return summary(await store.read(key(uid, date)), date, limit); },
    fetchFor(uid) {
      return async (url, options) => {
        const payload = JSON.parse(options.body);
        const output = Number(payload.max_tokens);
        if (!Number.isSafeInteger(output) || output <= 0) throw quotaError("Некорректный размер AI-ответа", 400);
        // A conservative byte-based input bound includes tools/history plus
        // framing overhead. Unused capacity is released after actual usage arrives.
        const reservation = Buffer.byteLength(options.body, "utf8") + 2048 + output;
        const date = now(); const doc = key(uid, date); const id = randomUUID();
        await store.update(doc, (state) => {
          if ((state.used || 0) + reservation > limit) {
            throw quotaError("Недостаточно дневного лимита для этого сообщения. Лимит чата — 100 000 токенов, включая контекст и ответ. Он обновится в 00:00 по времени Алматы. Анализ выписок доступен отдельно.");
          }
          return { used: (state.used || 0) + reservation, pending: { ...state.pending, [id]: reservation } };
        });
        let charged = reservation;
        try {
          const response = await upstreamFetch(url, options);
          const body = await response.clone().json().catch(() => ({}));
          const reported = body.usage?.total_tokens ?? (Number.isFinite(body.usage?.prompt_tokens) && Number.isFinite(body.usage?.completion_tokens) ? body.usage.prompt_tokens + body.usage.completion_tokens : undefined);
          if (Number.isSafeInteger(reported) && reported >= 0) charged = reported;
          else if (!response.ok) charged = 0;
          return response;
        } finally {
          // On an ambiguous timeout/missing usage retain the reservation;
          // the upstream may have completed and incurred token usage.
          await store.update(doc, (state) => {
            if (state.pending?.[id] == null) return state;
            const pending = { ...state.pending }; delete pending[id];
            return { used: Math.max(0, state.used - reservation + charged), pending };
          });
        }
      };
    },
  };
}

let service;
function getService() {
  if (service) return service;
  const { initializeApp, getApps } = require("firebase-admin/app");
  const { getFirestore } = require("firebase-admin/firestore");
  const { getAuth } = require("firebase-admin/auth");
  if (!getApps().length) initializeApp();
  const db = getFirestore();
  const collection = db.collection("_aiChatQuotas");
  const store = {
    async read(key) { return (await collection.doc(key).get()).data() || {}; },
    async update(key, change) {
      const ref = collection.doc(key);
      await db.runTransaction(async (transaction) => {
        const state = (await transaction.get(ref)).data() || {};
        transaction.set(ref, change(state));
      });
    },
  };
  const budget = createBudget({ store, upstreamFetch: (...args) => fetch(...args) });
  service = { ...budget, async user(request) {
    const token = /^Bearer (\S+)$/u.exec(request.headers?.authorization || "")?.[1];
    if (!token) throw quotaError("Для AI-чата нужен профиль приложения. Обновите приложение и попробуйте снова.", 401);
    try { return (await getAuth().verifyIdToken(token)).uid; }
    catch { throw quotaError("Не удалось подтвердить профиль AI-чата. Откройте чат ещё раз.", 401); }
  } };
  return service;
}

module.exports = { getService, createBudget, dayInfo, DAILY_LIMIT };
