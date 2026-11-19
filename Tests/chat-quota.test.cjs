const { test } = require("node:test");
const assert = require("node:assert/strict");
const { createBudget, dayInfo } = require("../functions/chat-quota");

function memoryStore() {
  const values = new Map();
  let queue = Promise.resolve();
  return {
    async read(key) { await queue; return values.get(key) || {}; },
    update(key, change) {
      const next = queue.then(() => values.set(key, change(values.get(key) || {})));
      queue = next.catch(() => {});
      return next;
    },
  };
}
const options = { body: JSON.stringify({ model: "test", messages: [{ role: "user", content: "Привет" }], max_tokens: 100 }) };
const response = (usage, ok = true) => ({ ok, clone: () => ({ json: async () => usage == null ? {} : { usage: { total_tokens: usage } } }) });

test("Quota uses actual input+output usage and survives service instances", async () => {
  const store = memoryStore();
  const budget = createBudget({ store, upstreamFetch: async () => response(123) });
  await budget.fetchFor("a")("test", options);
  const after = await createBudget({ store }).usage("a");
  assert.equal(after.usedTokens, 123); assert.equal(after.remainingTokens, 99877); assert.equal(after.reservedTokens, 0);
  assert.equal((await budget.usage("b")).usedTokens, 0);
});
test("Simultaneous requests cannot oversubscribe a daily budget", async () => {
  let release;
  const pending = new Promise(resolve => { release = resolve; });
  let calls = 0;
  const budget = createBudget({ store: memoryStore(), limit: 4000, upstreamFetch: async () => { calls++; await pending; return response(10); } });
  const first = budget.fetchFor("a")("test", options);
  // Wait for the reservation, without sleeping or relying on wall time.
  while (calls === 0) await new Promise(resolve => setImmediate(resolve));
  await assert.rejects(budget.fetchFor("a")("test", options), error => error.code === "DAILY_CHAT_LIMIT");
  assert.equal(calls, 1);
  release(); await first;
  assert.equal((await budget.usage("a")).usedTokens, 10);
});
test("Provider rejections refund the reservation, ambiguous timeouts retain it", async () => {
  const store = memoryStore();
  const rejected = createBudget({ store, upstreamFetch: async () => response(null, false) });
  await rejected.fetchFor("a")("test", options);
  assert.equal((await rejected.usage("a")).usedTokens, 0);
  const failed = createBudget({ store, upstreamFetch: async () => { throw new Error("timeout"); } });
  await assert.rejects(failed.fetchFor("a")("test", options));
  assert.ok((await failed.usage("a")).usedTokens > 2000);
  assert.equal((await failed.usage("a")).reservedTokens, 0);
});
test("Midnight reset is per Almaty day; an in-flight request stays on its original day", async () => {
  let date = new Date("2026-11-17T18:59:59Z");
  let complete;
  const pending = new Promise(resolve => { complete = resolve; });
  const store = memoryStore();
  const budget = createBudget({ store, now: () => date, upstreamFetch: async () => { await pending; return response(123); } });
  assert.equal(dayInfo(date).day, "2026-11-17");
  assert.equal(dayInfo(date).resetsAt, "2026-11-17T19:00:00.000Z");
  const call = budget.fetchFor("a")("test", options);
  while ((await budget.usage("a")).reservedTokens === 0) await new Promise(resolve => setImmediate(resolve));
  date = new Date("2026-11-17T19:00:01Z");
  complete(); await call;
  assert.equal((await budget.usage("a")).usedTokens, 0);
  date = new Date("2026-11-17T18:59:59Z");
  assert.equal((await budget.usage("a")).usedTokens, 123);
});
test("Missing upstream usage never grants an unlimited chat", async () => {
  const budget = createBudget({ store: memoryStore(), upstreamFetch: async () => response(null) });
  await budget.fetchFor("a")("test", options);
  assert.ok((await budget.usage("a")).usedTokens > 2000);
});
