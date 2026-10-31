const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const source = fs.readFileSync(path.join(__dirname, "../functions/index.js"), "utf8");

function api(fetch) {
  const context = {
    exports: {}, AbortSignal, console: { error() {} }, fetch,
    require(name) {
      if (name === "firebase-functions/v2/https") return { onRequest: (_, handler) => handler };
      if (name === "firebase-functions/params") return { defineSecret: () => ({ value: () => "test-only" }) };
      if (name === "./category-policy") return require("../functions/category-policy");
      throw Error(name);
    },
  };
  vm.runInNewContext(source, context);
  return async (transactions, route = "/api/categorize", extra = {}) => {
    const response = { code: null, body: null, set() {}, status(code) { this.code = code; return this; }, json(body) { this.body = body; } };
    await context.exports.openrouterProxy({ method: "POST", path: route, body: { transactions, ...extra } }, response);
    return response;
  };
}
const row = (id, amount = -100) => ({ id, amount, merchant: "Test", details: "Purchases Test", currentCategory: "shopping" });

for (const amount of [0, NaN, Infinity, -Infinity, 1e13, "100", null, true]) {
  test(`Reject invalid money: ${String(amount)}`, async () => {
    const response = await api(() => { throw Error("must not call model"); })([row("a", amount)]);
    assert.equal(response.code, 400);
  });
}
test("Reject duplicate IDs and excessive batches", async () => {
  const call = api(() => { throw Error("must not call model"); });
  assert.equal((await call([row("a"), row("a")])).code, 400);
  assert.equal((await call(Array.from({ length: 121 }, (_, i) => row(String(i))))).code, 400);
  assert.equal((await call([row("x".repeat(1025))])).code, 400);
});
test("Mission goals reject non-finite and negative amounts before calling the model", async () => {
  const call = api(() => { throw Error("must not call model"); });
  for (const goal of [null, { targetAmount: Infinity, savedAmount: 0 }, { targetAmount: 100, savedAmount: -1 }, { targetAmount: 0, savedAmount: 0 }]) {
    assert.equal((await call([row("a")], "/api/missions", { goal })).code, 400);
  }
});
test("Long IDs with the same first 200 characters remain distinct", async () => {
  const ids = ["x".repeat(201) + "a", "x".repeat(201) + "b"];
  const response = await api(async () => ({ ok: true, json: async () => ({ choices: [{ message: { tool_calls: [{ function: {
    name: "categorize_transactions", arguments: JSON.stringify({ categories: ids.map((id) => ({ id, category: "cafes" })) }),
  } }] } }] }) }))(ids.map((id) => row(id)));
  assert.equal(response.code, 200);
  assert.deepEqual(Array.from(response.body.categories, (item) => item.id), ids);
  assert.ok(response.body.categories.every((item) => item.category === "cafes"));
});
test("Timeouts return a retryable 504 instead of an unexplained 500", async () => {
  const response = await api(async () => { const error = Error("timed out"); error.name = "TimeoutError"; throw error; })([row("a")]);
  assert.equal(response.code, 504);
  assert.match(response.body.error, /не успел ответить/);
});
test("Retry of an incomplete chat response shares the same overall timeout", async () => {
  const signals = [];
  const call = api(async (_, options) => {
    signals.push(options.signal);
    return { ok: true, json: async () => ({ choices: [{ message: { tool_calls: [{ function: {
      name: "review_transactions", arguments: JSON.stringify({ reply: signals.length === 1 ? "Вот что нашёл:" : "Проверка завершена.", changes: [] }),
    } }] } }] }) };
  });
  const response = await call([row("a")], "/api/chat", { message: "Проверь операцию" });
  assert.equal(response.code, 200);
  assert.equal(signals.length, 2);
  assert.equal(signals[0], signals[1]);
  assert.equal(response.body.reply, "Проверка завершена.");
});
