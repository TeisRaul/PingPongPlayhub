// Teste pentru logica reminderelor. Rulează: npm test (în folderul functions)
const test = require("node:test");
const assert = require("node:assert/strict");
const {normalize, fireTimes, startMs, whenText, DEFAULTS} = require("../reminders")._test;

const iso = (ms) => new Date(ms).toISOString();
const MIN = 60000;

test("startMs: ora României, vară (+03) și iarnă (+02)", () => {
  assert.equal(iso(startMs("2026-07-20", 18.5)), "2026-07-20T15:30:00.000Z");
  assert.equal(iso(startMs("2026-12-20", 18.5)), "2026-12-20T16:30:00.000Z");
});

test("startMs: schimbarea orei de iarnă (25 oct 2026) nu strică orele de după", () => {
  assert.equal(iso(startMs("2026-10-25", 12)), "2026-10-25T10:00:00.000Z");
  assert.equal(iso(startMs("2026-10-24", 12)), "2026-10-24T09:00:00.000Z");
});

test("startMs: valori invalide întorc null", () => {
  assert.equal(startMs("nu-e-data", 10), null);
  assert.equal(startMs("2026-10-20", "x"), null);
});

test("normalize: fără setări → valorile implicite", () => {
  assert.deepEqual(normalize(null), DEFAULTS);
  assert.deepEqual(normalize(undefined), DEFAULTS);
});

test("normalize: valorile ilegale revin la implicit", () => {
  const c = normalize({firstMin: 45, repeatEveryMin: 7, repeatMode: "altceva", repeatCount: 99});
  assert.equal(c.firstMin, 60);
  assert.equal(c.repeatEveryMin, 0);
  assert.equal(c.repeatMode, "count");
  assert.equal(c.repeatCount, 10);
  assert.equal(normalize({repeatCount: -3}).repeatCount, 0);
});

test("normalize: enabled=false se păstrează", () => {
  assert.equal(normalize({enabled: false}).enabled, false);
  assert.equal(normalize({}).enabled, true);
});

test("fireTimes: implicit, un singur reminder cu 1 oră înainte", () => {
  const start = startMs("2026-10-20", 18.5);
  assert.deepEqual(fireTimes(start, normalize(null)), [start - 60 * MIN]);
});

test("fireTimes: toate opțiunile pentru prima notificare", () => {
  const start = startMs("2026-10-20", 18);
  for (const m of [60, 120, 180, 1440, 2880, 4320, 10080]) {
    assert.deepEqual(fireTimes(start, normalize({firstMin: m})), [start - m * MIN]);
  }
});

test("fireTimes: repetare de un număr de ori", () => {
  const start = startMs("2026-10-20", 18.5);
  const c = normalize({firstMin: 1440, repeatEveryMin: 30, repeatMode: "count", repeatCount: 2});
  const t = fireTimes(start, c);
  assert.equal(t.length, 3);
  assert.equal(t[1] - t[0], 30 * MIN);
  assert.equal(t[2] - t[1], 30 * MIN);
});

test("fireTimes: repetările se opresc cu 10 min înainte de meci", () => {
  const start = startMs("2026-10-20", 18.5);
  const c = normalize({firstMin: 180, repeatEveryMin: 60, repeatMode: "count", repeatCount: 5});
  const t = fireTimes(start, c);
  assert.deepEqual(t.map(iso), [
    "2026-10-20T12:30:00.000Z", "2026-10-20T13:30:00.000Z", "2026-10-20T14:30:00.000Z",
  ]);
  assert.ok(t.every((x) => x <= start - 10 * MIN));
});

test("fireTimes: până începe meciul", () => {
  const start = startMs("2026-10-20", 18.5);
  const c = normalize({firstMin: 120, repeatEveryMin: 30, repeatMode: "until_start"});
  const t = fireTimes(start, c);
  assert.deepEqual(t.map(iso), [
    "2026-10-20T13:30:00.000Z", "2026-10-20T14:00:00.000Z",
    "2026-10-20T14:30:00.000Z", "2026-10-20T15:00:00.000Z",
  ]);
});

test("fireTimes: maximum 20 de notificări", () => {
  const start = startMs("2026-10-20", 18);
  const c = normalize({firstMin: 10080, repeatEveryMin: 30, repeatMode: "until_start"});
  assert.equal(fireTimes(start, c).length, 20);
});

test("fireTimes: prima notificare e mereu trimisă chiar dacă repetarea e prea lungă", () => {
  const start = startMs("2026-10-20", 18);
  const c = normalize({firstMin: 60, repeatEveryMin: 1440, repeatMode: "until_start"});
  assert.equal(fireTimes(start, c).length, 1);
});

test("whenText: minute, ore, zile", () => {
  assert.equal(whenText("ro", 45 * MIN), "în 45 min");
  assert.equal(whenText("ro", 3 * 60 * MIN), "în 3 ore");
  assert.equal(whenText("ro", 24 * 60 * MIN), "în 1 zi");
  assert.equal(whenText("ro", 3 * 24 * 60 * MIN), "în 3 zile");
});

test("whenText: 20-36 de ore se spune 'în 1 zi'", () => {
  assert.equal(whenText("ro", 20 * 60 * MIN), "în 1 zi");
  assert.equal(whenText("ro", 30 * 60 * MIN), "în 1 zi");
  assert.equal(whenText("ro", 19 * 60 * MIN), "în 19 ore");
});
