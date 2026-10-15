// Teste pentru logica voucherelor (calculul reducerii și validarea codurilor). Rulează: npm test
const test = require("node:test");
const assert = require("node:assert/strict");
const {evaluate, normalizeCode, parseInput, round2} = require("../vouchers")._test;

const base = {active: true, type: "percent", value: 10, maxUses: 0, usedCount: 0, minAmount: 0};

test("reducere procentuală", () => {
  assert.deepEqual(evaluate({...base, value: 10}, 80), {ok: true, discount: 8});
  assert.deepEqual(evaluate({...base, value: 25}, 60), {ok: true, discount: 15});
});

test("reducere fixă, limitată la prețul mesei", () => {
  assert.deepEqual(evaluate({...base, type: "fixed", value: 20}, 100), {ok: true, discount: 20});
  assert.deepEqual(evaluate({...base, type: "fixed", value: 20}, 15), {ok: true, discount: 15});
});

test("procentul e limitat între 0 și 100", () => {
  assert.deepEqual(evaluate({...base, value: 150}, 50), {ok: true, discount: 50});
  assert.equal(evaluate({...base, value: -5}, 50).ok, false);
});

test("rotunjire la 2 zecimale", () => {
  assert.equal(evaluate({...base, value: 15}, 33.33).discount, 5);
  assert.equal(round2(1.005 * 100) / 100 > 0, true);
});

test("cod inactiv sau lipsă", () => {
  assert.deepEqual(evaluate({...base, active: false}, 50), {ok: false, reason: "inactive"});
  assert.deepEqual(evaluate(null, 50), {ok: false, reason: "inactive"});
});

test("valoare 0 nu e o reducere", () => {
  assert.equal(evaluate({...base, value: 0}, 50).ok, false);
});

test("perioadă de valabilitate", () => {
  assert.deepEqual(evaluate({...base, validFrom: "2999-01-01"}, 50), {ok: false, reason: "not_started"});
  assert.deepEqual(evaluate({...base, validTo: "2000-01-01"}, 50), {ok: false, reason: "expired"});
  assert.equal(evaluate({...base, validFrom: "2000-01-01", validTo: "2999-12-31"}, 50).ok, true);
});

test("număr maxim de folosiri", () => {
  assert.deepEqual(evaluate({...base, maxUses: 5, usedCount: 5}, 50), {ok: false, reason: "exhausted"});
  assert.equal(evaluate({...base, maxUses: 5, usedCount: 4}, 50).ok, true);
  assert.equal(evaluate({...base, maxUses: 0, usedCount: 1000}, 50).ok, true); // 0 = nelimitat
});

test("sumă minimă", () => {
  const r = evaluate({...base, minAmount: 60}, 50);
  assert.equal(r.ok, false);
  assert.equal(r.reason, "min_amount");
  assert.equal(r.minAmount, 60);
  assert.equal(evaluate({...base, minAmount: 60}, 60).ok, true);
});

test("codul de bun venit: 20 RON fix", () => {
  const welcome = {type: "fixed", value: 20, maxUses: 0, perUserOnce: true, newUsersOnly: true, minAmount: 0, active: true};
  assert.deepEqual(evaluate(welcome, 40), {ok: true, discount: 20});
  assert.deepEqual(evaluate(welcome, 12), {ok: true, discount: 12});
});

test("normalizeCode: majuscule, fără spații, doar caractere permise", () => {
  assert.equal(normalizeCode(" bun-venit "), "BUN-VENIT");
  assert.equal(normalizeCode("vara 2026"), "VARA2026");
  assert.equal(normalizeCode("ab"), null); // prea scurt
  assert.equal(normalizeCode("cod!"), null);
  assert.equal(normalizeCode(""), null);
  assert.equal(normalizeCode(undefined), null);
  assert.equal(normalizeCode("A".repeat(25)), null);
});

test("parseInput: validează sala, codul și suma", () => {
  assert.deepEqual(parseInput({venueId: "v1", code: "vara", amount: 50}), {venueId: "v1", code: "VARA", amount: 50});
  assert.equal(parseInput({venueId: "", code: "vara", amount: 50}), null);
  assert.equal(parseInput({venueId: "v1", code: "vara", amount: 0}), null);
  assert.equal(parseInput({venueId: "v1", code: "vara", amount: -5}), null);
  assert.equal(parseInput({venueId: "v1", code: "vara", amount: 5000}), null);
  assert.equal(parseInput({venueId: "v1", code: "vara", amount: "abc"}), null);
  assert.equal(parseInput({venueId: 7, code: "vara", amount: 50}), null);
});
