import assert from "node:assert/strict";
import { test } from "node:test";

import { build } from "esbuild";

const bundle = await build({
  entryPoints: ["app/javascript/controllers/profit_prediction_scenarios.js"],
  bundle: true,
  format: "esm",
  platform: "browser",
  write: false,
});

const { fill, hiddenScenarios, missedScenarios, missedSummary, scenarioShownIn, scenarioWarning, soldScenarios, soldSummary, visibleScenarios } = await import(
  `data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString("base64")}`
);

const scenario = (key, units, hidden = false) => ({ key, label: key.toUpperCase(), units, hidden });
const state = (scenarios, overrides = {}) => ({
  min_units: 5,
  missed_share_percent: 1,
  measured: true,
  total_units: scenarios.reduce((sum, item) => sum + item.units, 0),
  scenarios,
  ...overrides
});

test("a shown scenario under the minimum is warned about, at the minimum it is not", () => {
  const current = state([scenario("a", 4), scenario("b", 5), scenario("c", 0)]);

  assert.equal(scenarioWarning(current, current.scenarios[0]), true);
  assert.equal(scenarioWarning(current, current.scenarios[1]), false);
  assert.equal(scenarioWarning(current, current.scenarios[2]), true);
});

test("a hidden scenario is never warned about, and nothing is when sales were not measured", () => {
  const hidden = state([scenario("a", 0, true)]);
  assert.equal(scenarioWarning(hidden, hidden.scenarios[0]), false);

  const unmeasured = state([scenario("a", 0)], { measured: false });
  assert.equal(scenarioWarning(unmeasured, unmeasured.scenarios[0]), false);
});

test("a hidden scenario is missed at five units and one percent of the signed units", () => {
  const current = state([scenario("big", 400), scenario("edge", 5, true), scenario("few", 4, true), scenario("tiny", 5, true)], {
    total_units: 500
  });

  assert.deepEqual(missedScenarios(current).map((item) => item.key), ["edge", "tiny"]);
});

test("one percent is measured against the SKU's signed units", () => {
  const items = [scenario("big", 9990), scenario("edge", 5, true)];
  assert.deepEqual(missedScenarios(state(items)).map((item) => item.key), []);

  const sold = [scenario("big", 495), scenario("edge", 5, true)];
  assert.deepEqual(missedScenarios(state(sold)).map((item) => item.key), ["edge"]);
});

test("a scenario that is shown is never missed", () => {
  assert.deepEqual(missedScenarios(state([scenario("a", 100)])), []);
});

test("nothing is missed without measured sales or with zero units", () => {
  assert.deepEqual(missedScenarios(state([scenario("a", 50, true)], { measured: false })), []);
  assert.deepEqual(missedScenarios(state([scenario("a", 0, true)])), []);
});

test("the summary names the missed scenarios and their share", () => {
  const summary = missedSummary(state([scenario("big", 90), scenario("a", 6, true), scenario("b", 4, true), scenario("c", 6, true)]));

  assert.equal(summary.count, 2);
  assert.equal(summary.units, 12);
  assert.equal(summary.share, 11);
  assert.equal(summary.labels, "A、C");
});

test("visible and hidden scenarios partition the list", () => {
  const current = state([scenario("a", 1), scenario("b", 1, true), scenario("c", 1)]);

  assert.deepEqual(visibleScenarios(current).map((item) => item.key), ["a", "c"]);
  assert.deepEqual(hiddenScenarios(current).map((item) => item.key), ["b"]);
});

test("fill replaces every placeholder, also repeated ones", () => {
  assert.equal(fill("__N__ units, __N__ again, __NAME__", { n: 3, name: "WB" }), "3 units, 3 again, WB");
  assert.equal(fill("x __GONE__", { gone: null }), "x ");
});

test("actual scenarios are the ones with signed units, whatever the SKU hid", () => {
  const current = state([scenario("a", 12), scenario("b", 0), scenario("c", 3, true), scenario("d", 0, true)]);

  assert.deepEqual(soldScenarios(current).map((item) => item.key), ["a", "c"]);
  assert.deepEqual(soldSummary(current), { count: 2, units: 15 });
});

test("the scenario bar shows by what the SKU chose in custom mode and by what sold in actual mode", () => {
  const hiddenAndSold = scenario("a", 8, true);
  const shownAndUnsold = scenario("b", 0);

  assert.equal(scenarioShownIn("custom", hiddenAndSold), false);
  assert.equal(scenarioShownIn("custom", shownAndUnsold), true);
  assert.equal(scenarioShownIn("actual", hiddenAndSold), true);
  assert.equal(scenarioShownIn("actual", shownAndUnsold), false);
  assert.equal(scenarioShownIn("actual", { key: "x", hidden: false }), false, "no figure means nothing sold");
});
