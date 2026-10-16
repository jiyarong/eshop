import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { test } from "node:test";

import { build } from "esbuild";

const bundle = await build({
  entryPoints: ["app/javascript/controllers/profit_prediction_values.js"],
  bundle: true,
  format: "esm",
  platform: "browser",
  write: false,
});

const [{ dualCurrencyAmounts, percentToRatioString, priceVariableCostRate, profitInputValue, ratioToPercentString, sellingPriceShortcuts, shortcutInputValue, targetPriceForMargin }] = await Promise.all(
  bundle.outputFiles.map((file) => import(`data:text/javascript;base64,${Buffer.from(file.text).toString("base64")}`)),
);

test("uses the original precise value until the displayed input is edited", () => {
  const input = {
    value: "0.12",
    dataset: { sourceValue: "0.123456" },
  };

  assert.equal(profitInputValue(input), "0.123456");

  input.dataset.valueChanged = "true";
  assert.equal(profitInputValue(input), "0.12");
});

test("uses the displayed value when no original source value exists", () => {
  const input = { value: "10.00", dataset: {} };

  assert.equal(profitInputValue(input), "10.00");
});

test("limits shortcut values to four decimal places without trailing zeroes", () => {
  assert.equal(shortcutInputValue("0.0750123"), "0.075");
  assert.equal(shortcutInputValue(12.345678), "12.3457");
  assert.equal(shortcutInputValue(12.5), "12.5");
});

test("converts CNY results to RUB without rounding the source amount first", () => {
  const amounts = dualCurrencyAmounts(1.005, "cny", 13);

  assert.equal(amounts.cny, 1.005);
  assert.ok(Math.abs(amounts.rub - 13.065) < 1e-12);
});

test("converts RUB results to CNY and keeps CNY first in the returned pair", () => {
  assert.deepEqual(dualCurrencyAmounts(13, "rub", 13), { cny: 1, rub: 13 });
});

test("does not convert non-currency values or values without a valid exchange rate", () => {
  assert.equal(dualCurrencyAmounts(10, "liter", 13), null);
  assert.equal(dualCurrencyAmounts(10, "cny", 0), null);
});

test("identifies only price-dependent cost rates for each platform context", () => {
  const sharedInputs = {
    commission_rate: 0.1,
    acquiring_rate: 0.02,
    advertising_rate: 0.15,
    sales_vat_rate: 0.2,
    tax_rate: 0.06,
  };

  assert.ok(Math.abs(priceVariableCostRate({
    platform: "wb", market: "ru", companyType: "general", inputs: sharedInputs,
  }) - (0.1 + 0.02 + 0.15 + 0.2 / 1.2)) < 1e-12);
  assert.ok(Math.abs(priceVariableCostRate({
    platform: "wb", market: "ru", companyType: "small", inputs: sharedInputs,
  }) - 0.33) < 1e-12);
  assert.ok(Math.abs(priceVariableCostRate({
    platform: "ozon", market: "by", companyType: "general", inputs: sharedInputs,
  }) - (0.1 + 0.02 + 0.15 + 0.2 / 1.2)) < 1e-12);
  assert.ok(Math.abs(priceVariableCostRate({
    platform: "ozon", market: "ru", companyType: "general", inputs: sharedInputs,
  }) - (0.1 + 0.02 + 0.15 + 0.06)) < 1e-12);
});

test("solves the target sale price from fixed costs and a target margin", () => {
  assert.ok(Math.abs(targetPriceForMargin({
    revenueCny: 100,
    totalCostCny: 80,
    variableCostRate: 0.3,
    targetMargin: 0.3,
    exchangeRate: 10,
  }) - 1250) < 1e-9);

  assert.equal(targetPriceForMargin({
    revenueCny: 100,
    totalCostCny: 80,
    variableCostRate: 0.7,
    targetMargin: 0.3,
    exchangeRate: 10,
  }), null);
});

test("saving reconciles the returned version in place without a Turbo visit", async () => {
  const source = await readFile("app/javascript/controllers/profit_prediction_controller.js", "utf8");
  const start = source.indexOf("  async saveVersion(");
  const end = source.indexOf("\n  setCalculationMode(", start);
  const saveFlow = source.slice(start, end);

  assert.ok(start >= 0 && end > start);
  assert.match(saveFlow, /this\.applySavedVersion\(data\)/);
  assert.match(saveFlow, /dataset\.saveMethod = "PATCH"/);
  assert.doesNotMatch(saveFlow, /Turbo\.visit/);
});

test("uses a temporary positive probe price when target margin has no sale price", async () => {
  const source = await readFile("app/javascript/controllers/profit_prediction_controller.js", "utf8");

  assert.match(source, /if \(!Number\.isFinite\(probePrice\) \|\| probePrice <= 0\) inputs\.commission_base_price_rub = "1"/);
  assert.doesNotMatch(source, /inputs\.rf_price_rub|inputs\.price_rub/);
  assert.match(source, /previewTargetMarginBaseData\(row\)/);
});

test("writes target-margin prices to the commission base input on every platform, never the buyer-paid price", async () => {
  const source = await readFile("app/javascript/controllers/profit_prediction_controller.js", "utf8");

  assert.ok(source.includes('row.querySelector("[data-field=\'commission_base_price_rub\']")'));
  assert.doesNotMatch(source, /targetPriceField/);
});

test("offers the shared actual return-rate shortcut for WB and Ozon", async () => {
  const source = await readFile("app/javascript/controllers/profit_prediction_controller.js", "utf8");
  const wbStart = source.indexOf("  appendWbProcessSteps(");
  const wbEnd = source.indexOf("\n  appendOzonProcessSteps(", wbStart);
  const wbSteps = source.slice(wbStart, wbEnd);

  assert.ok(wbStart >= 0 && wbEnd > wbStart);
  assert.match(wbSteps, /steps\.return_rate/);
  assert.match(wbSteps, /"actual_return_rate"/);
  assert.match(source, /this\.actualReturnRateData\.set\(platform, data\)/);
  assert.match(source, /url\.searchParams\.set\("platform", platform\)/);
});

test("offers actual WB logistics and writes the explicit outbound and return inputs", async () => {
  const source = await readFile("app/javascript/controllers/profit_prediction_controller.js", "utf8");
  const wbSourceStart = source.indexOf("  renderWbLogisticsSource(");
  const wbSourceEnd = source.indexOf("\n  renderActualStorageSource(", wbSourceStart);
  const wbSource = source.slice(wbSourceStart, wbSourceEnd);

  assert.ok(wbSourceStart >= 0 && wbSourceEnd > wbSourceStart);
  assert.match(wbSource, /profit-prediction#loadActualLogistics/);
  assert.match(source, /this\.actualLogisticsData\.set\(logisticsKey, data\)/);
  assert.match(source, /url\.searchParams\.set\("delivery_mode", deliveryMode/);
  assert.match(source, /outbound_logistics_rub: event\.currentTarget\.dataset\.outboundRate/);
  assert.match(source, /return_logistics_rub: event\.currentTarget\.dataset\.returnRate/);
});

test("keeps commission base and buyer-paid prices separate in the actual-price shortcut on both platforms", async () => {
  const source = await readFile("app/javascript/controllers/profit_prediction_controller.js", "utf8");

  assert.match(source, /sellingPriceShortcuts\(this\.selectedRow\?\.dataset\.platform, data\)/);
  assert.match(source, /data\.commission_base_price/);
  assert.match(source, /data\.buyer_paid_price/);
  // A reference-only price (no matching input) must never be written to an input.
  assert.match(source, /const field = event\.currentTarget\.dataset\.field;\n\s+if \(!field\) return;/);
  assert.doesNotMatch(source, /dataset\.field \|\| "price_rub"/);
  assert.doesNotMatch(source, /data\.seller_price/);
  assert.doesNotMatch(source, /russianScenarioPrice\(/);
});

test("renders the commission base and buyer-paid prices as separate controls on every platform", async () => {
  const source = await readFile("app/javascript/controllers/profit_prediction_controller.js", "utf8");

  assert.match(source, /\["commission_base_price_rub", "target_margin", "exchange_rate_rub_cny"\]/);
  assert.match(source, /detailCommissionBasePriceTarget/);
  assert.match(source, /detailBuyerPaidPriceTarget/);
  assert.doesNotMatch(source, /by_target_price_label|by_price_label|wb_price_label|detailReferencePrice/);
});

test("derives the platform subsidy step whenever a buyer-paid price exists, on every platform", async () => {
  const source = await readFile("app/javascript/controllers/profit_prediction_controller.js", "utf8");

  assert.match(source, /steps\.platform_subsidy/);
  assert.match(source, /buyer_price_vat_rate/);
  // WB general companies pass the VAT on their invoice to the platform; nobody else does.
  assert.match(source, /row\.dataset\.platform === "wb" && row\.dataset\.companyType === "general"/);
  assert.match(source, /invoiceVatRate/);
  assert.doesNotMatch(source, /row\.dataset\.market === "by"\) \{\s+const vatRate/);
});

test("each actual price fills the same input on every platform", () => {
  const data = { commission_base_price: { average_rub: "1450.05" }, buyer_paid_price: { average_rub: "1131.1" } };

  const expected = [
    { kind: "commission_base", field: "commission_base_price_rub", priceRub: 1450.05 },
    { kind: "buyer_paid", field: "buyer_paid_price_rub", priceRub: 1131.1 },
  ];
  assert.deepEqual(sellingPriceShortcuts("wb", data), expected);
  assert.deepEqual(sellingPriceShortcuts("ozon", data), expected);
});

test("selling price shortcuts skip prices that are missing or not positive", () => {
  assert.deepEqual(sellingPriceShortcuts("wb", { commission_base_price: { average_rub: null }, buyer_paid_price: { average_rub: "0" } }), []);
  assert.deepEqual(sellingPriceShortcuts("ozon", {}), []);
  assert.deepEqual(
    sellingPriceShortcuts("wb", { commission_base_price: { average_rub: "" }, buyer_paid_price: { average_rub: "952" } }),
    [{ kind: "buyer_paid", field: "buyer_paid_price_rub", priceRub: 952 }],
  );
});

test("shows the platform subsidy in the header summary for every platform and clears it with the rest", async () => {
  const source = await readFile("app/javascript/controllers/profit_prediction_controller.js", "utf8");
  const summary = source.slice(source.indexOf("  renderProcessSummary("), source.indexOf("  renderPriceSummary("));
  const clear = source.slice(source.indexOf("  clearProcessSummary("), source.indexOf("  interpolate("));

  assert.match(source, /"detailPlatformSubsidy"/);
  assert.match(summary, /detailPlatformSubsidyTarget\.textContent = this\.number\(data\.intermediate\?\.platform_subsidy_rub\)/);
  assert.match(clear, /detailPlatformSubsidyTarget\.textContent = "-"/);
  // No platform condition: the same summary item is filled for WB and Ozon.
  assert.doesNotMatch(summary, /dataset\.platform/);
});

test("lists the platform subsidy as the second calculation step, right after revenue", async () => {
  const source = await readFile("app/javascript/controllers/profit_prediction_controller.js", "utf8");
  const start = source.indexOf("  renderCalculationSteps(");
  const end = source.indexOf("\n  renderIncompleteCalculationProcess(", start);
  const steps = source.slice(start, end);
  const common = source.slice(source.indexOf("  appendCommonCostSteps("), source.indexOf("  taxFormula("));

  const revenue = steps.indexOf("steps.revenue");
  const subsidy = steps.indexOf("appendPlatformSubsidyStep(");
  const goods = steps.indexOf("steps.goods");
  assert.ok(revenue >= 0 && revenue < subsidy && subsidy < goods);
  // It is no longer appended among the common cost steps.
  assert.doesNotMatch(common, /steps\.platform_subsidy/);
  // Inputs already shown on the revenue and commission rows are not repeated on this row.
  const method = source.slice(source.indexOf("  appendPlatformSubsidyStep("), source.indexOf("  appendCommonCostSteps("));
  assert.match(method, /\["buyer_paid_price_rub", "buyer_price_vat_rate"\]/);
});

test("shows ratios as percentages without floating point noise", () => {
  assert.equal(ratioToPercentString("0.075"), "7.5");
  assert.equal(ratioToPercentString("0.2"), "20");
  assert.equal(ratioToPercentString("0.031"), "3.1");
  assert.equal(ratioToPercentString("0.2169"), "21.69");
  assert.equal(ratioToPercentString("0"), "0");
  assert.equal(ratioToPercentString(0.175), "17.5");
  assert.equal(ratioToPercentString(""), "");
  assert.equal(ratioToPercentString(null), "");
});

test("turns an entered percentage back into the stored ratio", () => {
  assert.equal(percentToRatioString("7.5"), "0.075");
  assert.equal(percentToRatioString("20"), "0.2");
  assert.equal(percentToRatioString("3.1"), "0.031");
  assert.equal(percentToRatioString("21.69"), "0.2169");
  assert.equal(percentToRatioString("0"), "0");
  assert.equal(percentToRatioString(""), "");
  assert.equal(percentToRatioString(undefined), "");
  // Text that is not a number is passed through so the server can reject it.
  assert.equal(percentToRatioString("abc"), "abc");
});

test("a percent input submits a ratio: the exact source value until edited, then percent / 100", () => {
  const input = { value: "7.5", dataset: { percent: "true", sourceValue: "0.0753" } };
  assert.equal(profitInputValue(input), "0.0753");

  input.dataset.valueChanged = "true";
  assert.equal(profitInputValue(input), "0.075");

  input.value = "";
  assert.equal(profitInputValue(input), "");

  // Non-percent inputs are untouched.
  assert.equal(profitInputValue({ value: "10.00", dataset: { valueChanged: "true" } }), "10.00");
});

test("percent inputs get percent steppers, percent shortcut values and a percent label", async () => {
  const source = await readFile("app/javascript/controllers/profit_prediction_controller.js", "utf8");

  // Shortcuts hand a ratio to one helper that converts it for percent inputs.
  assert.match(source, /assignShortcutValue\(input, /);
  assert.doesNotMatch(source, /input\.value = shortcutInputValue\(/);
  assert.doesNotMatch(source, /priceInput\.value = shortcutInputValue\(/);
  assert.match(source, /dataset\.percent === "true"/);
  // Percent steppers move one point at a time within 0-100.
  assert.doesNotMatch(source, /step: "0\.01", min: "0", max: "1"/);
  assert.match(source, /if \(rateFields\.includes\(field\)\) return \{ step: "1", min: "0", max: "100" \}/);
});

test("explains the Ozon return rate as returns billed per outbound posting, not as buyer returns", async () => {
  const source = await readFile("app/javascript/controllers/profit_prediction_controller.js", "utf8");
  const start = source.indexOf("  renderActualReturnRateResult(");
  const end = source.indexOf("\n  applyActualReturnRate(", start);
  const render = source.slice(start, end);

  assert.match(render, /data\.platform === "ozon" \? messages\.meta_ozon : messages\.meta/);
});

// The controller itself is bundled with the Hotwire imports stubbed, so the "load all actual
// data" orchestration can run against hand-made cells instead of a browser DOM.
const controllerBundle = await build({
  entryPoints: ["app/javascript/controllers/profit_prediction_controller.js"],
  bundle: true,
  format: "esm",
  platform: "browser",
  write: false,
  plugins: [{
    name: "hotwire-stubs",
    setup(build) {
      build.onResolve({ filter: /^@hotwired\// }, (args) => ({ path: args.path, namespace: "stub" }));
      build.onLoad({ filter: /.*/, namespace: "stub" }, (args) => ({
        contents: args.path.includes("stimulus")
          ? "export class Controller {}"
          : "export const Turbo = { visit(...args) { (globalThis.__turboVisits ||= []).push(args); } };",
        loader: "js"
      }));
    }
  }]
});
const { default: ProfitPredictionController } = await import(
  `data:text/javascript;base64,${Buffer.from(controllerBundle.outputFiles[0].text).toString("base64")}`
);

function bulkActualsHarness({ readonly = false, cells }) {
  const calls = [];
  const row = { id: "row-1" };
  const buttons = [{ disabled: false }, { disabled: false }];
  const controller = new ProfitPredictionController();
  Object.assign(controller, {
    selectedRow: row,
    readonlyValue: readonly,
    hasDetailBodyTarget: true,
    hasBulkActualButtonTarget: true,
    bulkActualButtonTargets: buttons,
    detailBodyTarget: { querySelectorAll: () => cells }
  });
  return { controller, calls, row, buttons };
}

function sourceCell(sourceKey, { loadAction, links = [], calls, order }) {
  const button = loadAction ? { dataset: { action: `profit-prediction#${loadAction}` }, disabled: false } : null;
  return {
    dataset: { sourceKey },
    button,
    querySelector(selector) {
      if (selector.includes("data-action^='profit-prediction#loadActual'")) {
        const known = loadAction?.startsWith("loadActual") || loadAction === "loadOfficialCommission";
        return button && known ? button : null;
      }
      return links[0] || null;
    },
    querySelectorAll() { return links; },
    links,
    calls,
    order
  };
}

function link(name, calls, { disabled = false } = {}) {
  return { disabled, click() { calls.push(`apply:${name}`); } };
}

test("get-all runs every loader, official commission included, top to bottom and leaves the inputs alone", async () => {
  const calls = [];
  const cells = [
    sourceCell("actual_selling_price", { loadAction: "loadActualSellingPrice", links: [link("price", calls)], calls }),
    sourceCell("official_commission", { loadAction: "loadOfficialCommission", links: [link("commission", calls)], calls }),
    sourceCell("wb_logistics_tariffs", { loadAction: "loadActualLogistics", links: [link("logistics", calls)], calls }),
    sourceCell("actual_return_rate", { loadAction: "loadActualReturnRate", links: [link("return", calls)], calls }),
    sourceCell(null, { calls })
  ].filter((cell) => cell.dataset.sourceKey);
  const { controller, buttons } = bulkActualsHarness({ cells });
  const disabledDuring = [];
  ["loadActualSellingPrice", "loadActualLogistics", "loadActualReturnRate", "loadOfficialCommission"].forEach((name) => {
    controller[name] = async () => {
      disabledDuring.push(buttons.map((button) => button.disabled));
      calls.push(name);
    };
  });

  await controller.loadAllActuals();

  assert.deepEqual(calls, ["loadActualSellingPrice", "loadOfficialCommission", "loadActualLogistics", "loadActualReturnRate"]);
  assert.deepEqual(disabledDuring, [[true, true], [true, true], [true, true], [true, true]]);
  assert.deepEqual(buttons.map((button) => button.disabled), [false, false]);
  assert.equal(controller.bulkActualsRunning, false);
});

test("get-and-fill applies each result right after its own load, in order, skipping disabled links", async () => {
  const calls = [];
  const cells = [
    sourceCell("actual_selling_price", {
      loadAction: "loadActualSellingPrice",
      links: [link("commission_base", calls), link("buyer_paid", calls), link("reference", calls, { disabled: true })],
      calls
    }),
    sourceCell("actual_storage", { loadAction: "loadActualStorage", links: [link("storage", calls)], calls }),
    sourceCell("actual_advertising", { loadAction: "loadActualAdvertising", links: [], calls })
  ];
  const { controller } = bulkActualsHarness({ cells });
  ["loadActualSellingPrice", "loadActualStorage", "loadActualAdvertising"].forEach((name) => {
    controller[name] = async () => { calls.push(name); };
  });
  // A cell with no rendered result must be rebuilt from the already loaded data before applying.
  const rebuilt = [];
  controller.renderProcessSource = (cell, sourceKey) => { rebuilt.push(sourceKey); };

  await controller.loadAndApplyAllActuals();

  assert.deepEqual(calls, [
    "loadActualSellingPrice", "apply:commission_base", "apply:buyer_paid",
    "loadActualStorage", "apply:storage",
    "loadActualAdvertising"
  ]);
  assert.deepEqual(rebuilt, ["actual_advertising"]);
});

test("get-and-fill applies a single official commission rate but never guesses between several", async () => {
  const calls = [];
  const single = bulkActualsHarness({
    cells: [sourceCell("official_commission", { loadAction: "loadOfficialCommission", links: [link("rate", calls)], calls })]
  });
  single.controller.loadOfficialCommission = async () => { calls.push("load"); };
  await single.controller.loadAndApplyAllActuals();
  assert.deepEqual(calls, ["load", "apply:rate"]);

  calls.length = 0;
  const several = bulkActualsHarness({
    cells: [sourceCell("official_commission", {
      loadAction: "loadOfficialCommission",
      links: [link("rate_a", calls), link("rate_b", calls)],
      calls
    })]
  });
  several.controller.loadOfficialCommission = async () => { calls.push("load"); };
  await several.controller.loadAndApplyAllActuals();
  assert.deepEqual(calls, ["load"]);
});

test("get-and-fill is refused on archived versions, and a second run cannot overlap the first", async () => {
  const calls = [];
  const cells = [sourceCell("actual_return_rate", { loadAction: "loadActualReturnRate", links: [link("return", calls)], calls })];
  const readonlyRun = bulkActualsHarness({ readonly: true, cells });
  readonlyRun.controller.loadActualReturnRate = async () => { calls.push("load"); };
  await readonlyRun.controller.loadAndApplyAllActuals();
  assert.deepEqual(calls, []);

  const running = bulkActualsHarness({ cells });
  let release;
  running.controller.loadActualReturnRate = () => new Promise((resolve) => { release = resolve; calls.push("load"); });
  const first = running.controller.loadAllActuals();
  await running.controller.loadAllActuals();
  release();
  await first;
  assert.deepEqual(calls, ["load"]);
});

test("get-all stops when the selected scenario changes while a request is in flight", async () => {
  const calls = [];
  const cells = [
    sourceCell("actual_selling_price", { loadAction: "loadActualSellingPrice", links: [link("price", calls)], calls }),
    sourceCell("actual_return_rate", { loadAction: "loadActualReturnRate", links: [link("return", calls)], calls })
  ];
  const { controller } = bulkActualsHarness({ cells });
  controller.loadActualSellingPrice = async () => {
    calls.push("loadActualSellingPrice");
    controller.selectedRow = { id: "row-2" };
  };
  controller.loadActualReturnRate = async () => { calls.push("loadActualReturnRate"); };

  await controller.loadAndApplyAllActuals();

  assert.deepEqual(calls, ["loadActualSellingPrice"]);
});

test("the source column header offers both bulk buttons, and the fill one is hidden on archived versions", async () => {
  const view = await readFile("app/views/reports/_sku_profit_prediction.html.erb", "utf8");
  const head = view.slice(view.indexOf("profit-prediction-process__source-head"), view.indexOf("<tbody", view.indexOf("profit-prediction-process__source-head")) );

  assert.match(head, /profit-prediction#loadAllActuals/);
  assert.match(head, /<% unless profit_version_readonly %>[\s\S]*profit-prediction#loadAndApplyAllActuals[\s\S]*<% end %>/);
});

test("offers the actual acquiring rate on the acquiring step, writes the acquiring input, and joins the bulk load", async () => {
  const source = await readFile("app/javascript/controllers/profit_prediction_controller.js", "utf8");
  const stepStart = source.indexOf("this.appendProcessStep(steps.acquiring,");
  const step = source.slice(stepStart, source.indexOf(");", stepStart) + 2);

  assert.match(step, /"actual_acquiring"/);
  assert.match(source, /profit-prediction#loadActualAcquiring/);
  assert.match(source, /\[data-field='acquiring_rate'\]/);
  assert.match(source, /this\.actualAcquiringData\.set\(platform, data\)/);
  // The bulk buttons pick every "loadActual*" loader up by that prefix.
  assert.match(source, /data-action\^='profit-prediction#loadActual'/);
});

function currentVersionSetter({ dirty = false, incomplete = 0, response = { ok: true } } = {}) {
  const fetches = [];
  const alerts = [];
  const { controller, confirmations, answer } = versionSwitcher({ frame: { id: "sku_detail_tab_profit_prediction" }, dirty });
  globalThis.fetch = async (url, options) => { fetches.push([ url, options ]); return response; };
  Object.assign(controller, {
    setCurrentUrlValue: "/reports/skus/KJ-217-GD/profit_versions/9/set_current",
    versionIdValue: 9,
    incompleteCountValue: incomplete,
    hasModeStatusTarget: true,
    modeStatusTarget: { textContent: "" },
    messagesValue: {
      confirm_leave: "discard?",
      current_version: { needs_save: "save first", incomplete_confirm: "__COUNT__ incomplete", failed: "failed" }
    },
    jsonHeaders: () => ({ "X-CSRF-Token": "t" })
  });
  const button = { disabled: false };
  return { controller, button, fetches, alerts, confirmations, answer };
}

test("setting the current version refuses while there are unsaved edits", async () => {
  const { controller, button, fetches } = currentVersionSetter({ dirty: true });

  await controller.setCurrent({ currentTarget: button });

  assert.equal(fetches.length, 0);
  assert.equal(controller.modeStatusTarget.textContent, "save first");
});

test("setting the current version asks when scenarios are not fully calculated", async () => {
  const { controller, button, fetches, confirmations, answer } = currentVersionSetter({ incomplete: 2 });
  answer.value = false;
  await controller.setCurrent({ currentTarget: button });
  assert.deepEqual(confirmations, [ "2 incomplete" ]);
  assert.equal(fetches.length, 0);

  answer.value = true;
  await controller.setCurrent({ currentTarget: button });
  assert.equal(fetches.length, 1);
});

test("setting the current version PATCHes the version, then reloads this version's tab frame", async () => {
  const { controller, button, fetches } = currentVersionSetter();

  await controller.setCurrent({ currentTarget: button });

  assert.equal(fetches.length, 1);
  assert.equal(fetches[0][0], "/reports/skus/KJ-217-GD/profit_versions/9/set_current");
  assert.equal(fetches[0][1].method, "PATCH");
  const [url, options] = globalThis.__turboVisits.at(-1);
  assert.deepEqual(options, { frame: "sku_detail_tab_profit_prediction" });
  assert.equal(new URL(url).searchParams.get("version_id"), "9");
});

test("a failed set-current request is reported and the button works again", async () => {
  const { controller, button } = currentVersionSetter({ response: { ok: false, status: 422 } });
  globalThis.__turboVisits = [];

  await controller.setCurrent({ currentTarget: button });

  assert.equal(controller.modeStatusTarget.textContent, "failed");
  assert.equal(button.disabled, false);
  assert.equal(globalThis.__turboVisits.length, 0);
});

function versionSwitcher({ frame, dirty = false, switchUrl = "/reports/skus/KJ-217-GD?tab=profit_prediction", currentVersion = "3" } = {}) {
  globalThis.__turboVisits = [];
  const confirmations = [];
  const answer = { value: true };
  globalThis.window = {
    location: { href: "http://localhost:4010/operator_skus?q=KJ", origin: "http://localhost:4010" },
    confirm(message) { confirmations.push(message); return answer.value; }
  };
  const controller = new ProfitPredictionController();
  Object.assign(controller, {
    element: { closest: () => frame },
    switchUrlValue: switchUrl,
    messagesValue: { confirm_leave: "discard?" },
    calculationMode: true,
    dirtyRows: new Set(dirty ? [ "row-1" ] : []),
    versionDirty: false
  });
  const select = {
    value: "9",
    querySelector: (selector) => (selector === "option[selected]" ? { value: currentVersion } : null)
  };
  return { controller, select, confirmations, answer };
}

test("switching version reloads only the tab's own frame from the SKU detail URL", () => {
  const { controller, select, confirmations } = versionSwitcher({ frame: { id: "sku_detail_tab_profit_prediction" } });

  controller.changeVersion({ target: select });

  assert.equal(globalThis.__turboVisits.length, 1);
  const [url, options] = globalThis.__turboVisits[0];
  assert.deepEqual(options, { frame: "sku_detail_tab_profit_prediction" });
  const parsed = new URL(url);
  assert.equal(parsed.pathname, "/reports/skus/KJ-217-GD", "not the host page (/operator_skus)");
  assert.equal(parsed.searchParams.get("tab"), "profit_prediction");
  assert.equal(parsed.searchParams.get("version_id"), "9");
  assert.equal(parsed.searchParams.get("copy_version_id"), null);
  assert.deepEqual(confirmations, [], "nothing unsaved, nothing to confirm");
});

test("switching version with unsaved edits asks first: cancel keeps the version and restores the dropdown", () => {
  const { controller, select, confirmations, answer } = versionSwitcher({ frame: { id: "sku_detail_tab" }, dirty: true });
  answer.value = false;

  controller.changeVersion({ target: select });

  assert.deepEqual(confirmations, [ "discard?" ]);
  assert.equal(globalThis.__turboVisits.length, 0);
  assert.equal(select.value, "3");

  answer.value = true;
  controller.changeVersion({ target: { ...select, value: "9", querySelector: select.querySelector } });
  assert.equal(globalThis.__turboVisits.length, 1);
  assert.equal(confirmations.length, 2);
});

test("without a frame the switch falls back to a top-level visit that does not ask a second time", () => {
  const { controller, select } = versionSwitcher({ frame: null });

  controller.changeVersion({ target: select });

  assert.deepEqual(globalThis.__turboVisits[0][1], { action: "replace" });
  assert.equal(controller.allowNavigation, true);
});

test("copy and new links ask before discarding edits and can be cancelled", () => {
  const { controller, answer } = versionSwitcher({ frame: { id: "sku_detail_tab" }, dirty: true });
  let prevented = 0;
  answer.value = false;
  controller.confirmLeave({ preventDefault() { prevented += 1; } });
  assert.equal(prevented, 1);

  answer.value = true;
  controller.confirmLeave({ preventDefault() { prevented += 1; } });
  assert.equal(prevented, 1, "confirmed: the link goes ahead");

  const clean = versionSwitcher({ frame: { id: "sku_detail_tab" } });
  clean.controller.confirmLeave({ preventDefault() { prevented += 1; } });
  assert.equal(prevented, 1);
  assert.deepEqual(clean.confirmations, []);
});
