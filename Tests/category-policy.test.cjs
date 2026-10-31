const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const fixtures = require("./categorization-cases.json");
const { finalCategory, categoryEvidence } = require("../functions/category-policy");

for (const fixture of fixtures) {
  test(fixture.name, () => {
    const transaction = { currentCategory: "other", ...fixture };
    assert.equal(finalCategory(transaction, fixture.aiCategory), fixture.expected);
  });
}

test("Unknown bank purchase has no fabricated evidence", () => {
  assert.equal(categoryEvidence({ merchant: "UNKNOWN 12345", details: "Purchases UNKNOWN 12345" }), null);
});

test("A generic old shopping category cannot veto new subscription evidence", () => {
  assert.equal(finalCategory({ merchant: "POLAR", details: "Purchases POLAR SUBCR", currentCategory: "shopping" }, "shopping"), "subscriptions");
});

test("The actual API route validates the model decision before returning categories", async () => {
  const selected = fixtures.filter((fixture) => [
    "Dodo Pizza", "SUBSCR unknown service", "Transfer to merchant-like name",
    "AI can correct an unfamiliar merchant", "Explicit manual choice survives",
  ].includes(fixture.name));
  let upstreamPrompt = "";
  const context = {
    exports: {}, console, AbortSignal,
    require(name) {
      if (name === "firebase-functions/v2/https") return { onRequest: (_, handler) => handler };
      if (name === "firebase-functions/params") return { defineSecret: () => ({ value: () => "test-only-key" }) };
      if (name === "./category-policy") return require("../functions/category-policy");
      if (name === "./category-audit") return require("../functions/category-audit");
      throw new Error(`Unexpected dependency: ${name}`);
    },
    async fetch(_, options) {
      upstreamPrompt = JSON.parse(options.body).messages[1].content;
      return { ok: true, async json() {
        return { choices: [{ message: { tool_calls: [{ function: {
          name: "categorize_transactions",
          arguments: JSON.stringify({ categories: selected.map((fixture, index) => ({ id: `t${index}`, category: fixture.aiCategory })) }),
        } }] } }] };
      } };
    },
  };
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, "../functions/index.js"), "utf8"), context);
  const response = {
    code: null, body: null,
    set() {},
    status(code) { this.code = code; return this; },
    json(body) { this.body = body; return this; },
  };
  await context.exports.openrouterProxy({ method: "POST", path: "/api/categorize", body: {
    transactions: selected.map((fixture, index) => ({ ...fixture, id: `t${index}`, amount: -100, currentCategory: "shopping" })),
  } }, response);
  assert.equal(response.code, 200);
  assert.deepEqual(Array.from(response.body.categories, (row) => row.category), selected.map((fixture) => fixture.expected));
  assert.match(upstreamPrompt, /Purchases — это банковский тип оплаты/);
  assert.match(upstreamPrompt, /SUBCR/);
});
