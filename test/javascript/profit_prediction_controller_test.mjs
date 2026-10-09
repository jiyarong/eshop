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

const [{ dualCurrencyAmounts, priceVariableCostRate, profitInputValue, sellingPriceShortcuts, shortcutInputValue, targetPriceForMargin }] = await Promise.all(
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

  assert.match(source, /if \(!Number\.isFinite\(probePrice\) \|\| probePrice <= 0\) inputs\.price_rub = "1"/);
  assert.match(source, /if \(!Number\.isFinite\(referencePrice\) \|\| referencePrice <= 0\) inputs\.rf_price_rub = "1"/);
  assert.match(source, /previewTargetMarginBaseData\(row\)/);
});

test("writes Ozon target-margin prices to the seller price, not the buyer-paid price", async () => {
  const source = await readFile("app/javascript/controllers/profit_prediction_controller.js", "utf8");

  assert.ok(source.includes('const targetPriceField = row.dataset.platform === "ozon" ? "rf_price_rub" : "price_rub"'));
  assert.ok(source.includes("row.querySelector(`[data-field='${targetPriceField}']`)"));
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

test("renders Ozon target and customer-paid prices as separate controls", async () => {
  const source = await readFile("app/javascript/controllers/profit_prediction_controller.js", "utf8");

  assert.match(source, /\["rf_price_rub", "target_margin", "exchange_rate_rub_cny"\]/);
  assert.match(source, /process\.by_target_price_label/);
  assert.match(source, /detailReferencePriceItemTarget\.hidden = !applicable/);
});

test("commission base price fills the platform's commission base input on both platforms", () => {
  const data = { commission_base_price: { average_rub: "1450.05" }, buyer_paid_price: { average_rub: "1131.1" } };

  assert.deepEqual(sellingPriceShortcuts("wb", data), [
    { kind: "commission_base", field: "price_rub", priceRub: 1450.05 },
    { kind: "buyer_paid", field: null, priceRub: 1131.1 },
  ]);
  assert.deepEqual(sellingPriceShortcuts("ozon", data), [
    { kind: "commission_base", field: "rf_price_rub", priceRub: 1450.05 },
    { kind: "buyer_paid", field: "price_rub", priceRub: 1131.1 },
  ]);
});

test("selling price shortcuts skip prices that are missing or not positive", () => {
  assert.deepEqual(sellingPriceShortcuts("wb", { commission_base_price: { average_rub: null }, buyer_paid_price: { average_rub: "0" } }), []);
  assert.deepEqual(sellingPriceShortcuts("ozon", {}), []);
  assert.deepEqual(
    sellingPriceShortcuts("wb", { commission_base_price: { average_rub: "" }, buyer_paid_price: { average_rub: "952" } }),
    [{ kind: "buyer_paid", field: null, priceRub: 952 }],
  );
});
