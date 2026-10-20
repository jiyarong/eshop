import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { test } from "node:test";

import { build } from "esbuild";

const bundle = await build({
  entryPoints: ["app/javascript/controllers/profit_prediction_formula.js"],
  bundle: true,
  format: "esm",
  platform: "browser",
  write: false,
});
const { buildCalculationSteps, evaluateFormula, formulaFieldName, formulaLines } = await import(
  `data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString("base64")}`
);

// The cases and the figures the Ruby calculators produce for them; the Rails test
// test/services/ec/profit_prediction_formula_cases_test.rb keeps the figures honest.
const cases = JSON.parse(await readFile("test/fixtures/files/profit_prediction_formula_cases.json", "utf8"));

const labels = {
  fields: {
    purchase_price_cny: "采购价 CNY", freight_cny: "头程运费 CNY", customs_misc_cny: "清关杂费 CNY",
    duty_rate: "关税率", import_vat_rate: "进口增值税率", length_cm: "长 cm", width_cm: "宽 cm", height_cm: "高 cm",
    wb_logistics_base_rub: "WB 基础物流费 RUB", wb_logistics_liter_rub: "WB 每升物流费 RUB/L",
    wb_fixed_return_base_rub: "WB 固定退货费基数（RUB）", sales_vat_rate: "销售增值税率",
    commission_base_price_rub: "佣金基准价（RUB）", buyer_paid_price_rub: "买家实付价（含 VAT，RUB）",
    buyer_price_vat_rate: "买家价含 VAT 税率", exchange_rate_rub_cny: "汇率（RUB/CNY）", logistics_coeff: "物流系数",
    return_rate: "退货率", fbo_delivery_cny: "送仓费（CNY）", storage_cny: "仓储费（CNY）", commission_rate: "佣金率",
    acquiring_rate: "收单费率", advertising_rate: "广告费率", tax_rate: "税率", damage_rate: "货损率",
    misc_cny: "杂费（CNY）", other_cny: "其他费用（CNY）", outbound_logistics_rub: "去程物流（RUB）",
    return_logistics_rub: "返程物流（RUB）", warehouse_operation_rub: "仓库操作费（RUB）", cross_docking_cny: "越库费（CNY）",
    fbs_handover_rub: "交接与末端处理费（RUB）",
  },
  steps: {
    revenue: "收入", goods: "商品成本", duty: "关税", import_vat: "进口增值税", volume: "商品体积",
    billed_volume: "计费体积", delivered_rate: "成交签收率", logistics_mode: "物流费模式", return_rate: "退货率", return_amortized: "退货分摊费用",
    platform_logistics: "平台物流费", outbound_logistics: "去程物流费", fbo_delivery: "送仓费", total_logistics: "总物流费", cross_docking: "越库费", returns: "退货分摊费用", storage: "仓储费", commission: "佣金",
    platform_subsidy: "平台净补贴（参考）", acquiring: "收单费", advertising: "广告费", tax: "销售税", other: "其他成本",
    total_cost: "总成本", profit: "利润", margin: "利润率",
  },
  formula: {
    ozon_warehouse_rate: "仓库附加费率", ozon_import_vat_cost_rate: "进口增值税计入成本比例", advertising_fixed_rub: "固定广告费",
    wb_logistics_override_cny: "WB 物流费覆盖值", logistics_ex_fbo: "去程物流费", return_amortization_factor_override: "退货折算系数",
  },
  sumCosts: "以上各项成本合计",
  crossDockingNotApplicable: "白俄场景不适用",
  crossDockingInOther: "已计入其他成本",
  ozonRouteNote: "最常用 __COUNT__ 条路线 __VOLUME__ L __RATE__",
  ozonRouteNoteAll: "所有路线 __VOLUME__ L __RATE__",
};

// What the workbench form can hold: the legacy sheet parameters have no input, so the page
// only learns them from the calculator's `intermediate`.
const NO_INPUT = ["ozon_warehouse_rate", "ozon_import_vat_cost_rate", "advertising_fixed_rub", "wb_logistics_override_cny", "return_amortization_factor_override"];

function stepsFor(testCase) {
  const inputs = Object.fromEntries(Object.entries(testCase.inputs).filter(([field]) => !NO_INPUT.includes(field)));
  if (testCase.platform === "ozon" && testCase.context.market === "ru") delete inputs.tax_rate;
  const { expected } = testCase;

  return buildCalculationSteps({
    platform: testCase.platform,
    market: testCase.context.market,
    deliveryMode: testCase.context.delivery_mode,
    companyType: testCase.context.company_type,
    inputs,
    data: expected,
    labels,
  });
}

const format = { number: (value) => String(Number(Number(value).toFixed(2))), percent: (value) => `${Number((Number(value) * 100).toFixed(2))}%` };

test("every formula evaluates to the figure the Ruby calculator produced for that step", () => {
  cases.forEach((testCase) => {
    const steps = stepsFor(testCase);
    let checked = 0;

    steps.forEach((step) => {
      if (!Array.isArray(step.formula) || !Number.isFinite(Number(step.result))) return;

      const computed = evaluateFormula(step.formula) * (step.unit === "percent" ? 100 : 1);
      assert.ok(
        Math.abs(computed - Number(step.result)) < 1e-9 * Math.max(1, Math.abs(computed)),
        `${testCase.name} / ${step.key}: formula gives ${computed}, calculator gives ${step.result}`,
      );
      checked += 1;
    });

    // An Ozon FBS scenario has no cross-docking row, hence one step fewer.
    const floor = testCase.context.delivery_mode === "fbs" && testCase.platform === "ozon" ? 17 : 18;
    assert.ok(checked >= floor, `${testCase.name}: only ${checked} formulas were compared`);
  });
});

test("the cost steps add up to the calculator's total cost, counting cross-docking once", () => {
  cases.forEach((testCase) => {
    const steps = Object.fromEntries(stepsFor(testCase).map((step) => [step.key, step]));
    const costKeys = ["goods", "duty", "import_vat", "platform_logistics", "storage", "commission", "acquiring", "advertising", "tax", "other"]
      .concat(testCase.platform === "wb" ? ["returns"] : ["return_amortized"])
      .map((key) => (key === "platform_logistics" && testCase.platform === "wb" ? "outbound_logistics" : key))
      .concat(testCase.platform === "wb" ? ["fbo_delivery"] : []);
    const total = costKeys.filter((key) => steps[key]).reduce((sum, key) => {
      // The fee steps are worked out in roubles.
      const result = Number(steps[key].result);
      return sum + (steps[key].unit === "rub" ? result / testCase.inputs.exchange_rate_rub_cny : result);
    }, 0);
    // WB books import VAT as a cost line even when Ozon Russia does not show one.
    const expectedTotal = testCase.expected.total_cost_cny - (steps.import_vat ? 0 : testCase.expected.cost_breakdown.import_vat);

    assert.ok(Math.abs(total - expectedTotal) < 1e-9, `${testCase.name}: steps add up to ${total}, calculator says ${expectedTotal}`);
  });
});

test("formulas name the parameters and then substitute the numbers", () => {
  const wb = stepsFor(cases.find((testCase) => testCase.name === "wb_general_coefficient"));
  const named = (key) => formulaLines(wb.find((step) => step.key === key).formula, format).named;
  const outbound = formulaLines(wb.find((step) => step.key === "outbound_logistics").formula, format);

  assert.equal(outbound.named, "( WB 基础物流费 + ( 计费体积 − 1 ) × WB 每升物流费 ) × 物流系数");
  assert.match(outbound.values, /^\( 60 \+ \( 7 − 1 \) × 14 \) × /);
  assert.equal(named("fbo_delivery"), "送仓费 × 汇率");
  assert.equal(named("total_logistics"), "去程物流费 + 退货分摊费用 + 送仓费", "the total sits below the return cost and the delivery row");
  assert.ok(!wb.some((step) => step.key === "base_logistics"), "WB's base fee is part of the outbound logistics row");
  assert.equal(formulaLines(wb.find((step) => step.key === "revenue").formula, format).named, "佣金基准价 ÷ 汇率");
  assert.equal(formulaLines(wb.find((step) => step.key === "margin").formula, format).named, "利润 ÷ 收入");
});

test("parameter names drop the unit that the table already shows", () => {
  assert.equal(formulaFieldName("WB 基础物流费 RUB"), "WB 基础物流费");
  assert.equal(formulaFieldName("WB 每升物流费 RUB/L"), "WB 每升物流费");
  assert.equal(formulaFieldName("买家实付价（含 VAT，RUB）"), "买家实付价");
  assert.equal(formulaFieldName("长 cm"), "长");
  assert.equal(formulaFieldName("关税率"), "关税率");
});

test("WB's return step uses the outbound fee without the inbound delivery, and no longer lists the unused logistics tax rate", () => {
  cases.filter((testCase) => testCase.platform === "wb").forEach((testCase) => {
    const steps = stepsFor(testCase);
    const named = (key) => formulaLines(steps.find((step) => step.key === key).formula, format).named;

    const returns = steps.find((step) => step.key === "returns");

    assert.ok(!returns.fields.includes("logistics_tax_rate"), testCase.name);
    assert.match(named("returns"), /^\( 去程物流费 \+ .* \) × 退货率 ÷ 成交签收率$/);
  });
});

test("WB names the logistics source the calculator actually used", () => {
  const platformLogistics = (name) => stepsFor(cases.find((testCase) => testCase.name === name))
    .find((step) => step.key === "outbound_logistics");

  assert.match(formulaLines(platformLogistics("wb_general_coefficient").formula, format).named, /^\( WB 基础物流费 .* \) × 物流系数$/);
  assert.equal(formulaLines(platformLogistics("wb_small_actual_logistics").formula, format).named, "去程物流");
  assert.equal(formulaLines(platformLogistics("wb_small_override_and_fixed_return").formula, format).named, "WB 物流费覆盖值 × 汇率");
});

test("Ozon FBO and FBS have the same logistics structure: the route freight plus the handover and last-mile fee", () => {
  const standard = stepsFor(cases.find((testCase) => testCase.name === "ozon_ru_standard"));
  const logistics = standard.find((step) => step.key === "platform_logistics");

  assert.deepEqual(logistics.fields, ["outbound_logistics_rub", "fbs_handover_rub"]);
  assert.equal(formulaLines(logistics.formula, format).named, "去程物流 + 交接与末端处理费");
  assert.equal(formulaLines(logistics.formula, format).values, "92 + 14");
});

test("Ozon cross-docking is flagged as already inside other costs; Belarus shows it as not applicable", () => {
  const crossDocking = (name) => stepsFor(cases.find((testCase) => testCase.name === name)).find((step) => step.key === "cross_docking");

  assert.equal(crossDocking("ozon_ru_standard").note, "已计入其他成本");
  assert.equal(crossDocking("ozon_by").formula, "白俄场景不适用");
  assert.equal(crossDocking("ozon_by").note, null);
  assert.equal(crossDocking("ozon_by").result, 0);
});

test("legacy sheet parameters the calculator applies are shown in the formulas", () => {
  const hidden = stepsFor(cases.find((testCase) => testCase.name === "ozon_ru_hidden_parameters"));
  const standard = stepsFor(cases.find((testCase) => testCase.name === "ozon_ru_standard"));
  const named = (steps, key) => formulaLines(steps.find((step) => step.key === key).formula, format).named;

  assert.match(named(hidden, "advertising"), /广告费率 \+ 固定广告费 ÷ 汇率$/);
  assert.doesNotMatch(named(standard, "advertising"), /固定广告费/);
  assert.match(named(hidden, "import_vat"), /进口增值税率 × 进口增值税计入成本比例$/);
  assert.ok(hidden.some((step) => step.key === "import_vat"));
  assert.ok(!standard.some((step) => step.key === "import_vat"), "Ozon Russia shows no import VAT line unless part of it is a cost");
  assert.equal(named(hidden, "tax"), "收入 × 税率");
  assert.equal(named(hidden, "return_amortized"), "( 去程物流 + 返程物流 ) × 退货折算系数");
  assert.equal(named(standard, "return_amortized"), "( 去程物流 + 返程物流 ) × 退货率 ÷ 成交签收率");
  assert.equal(named(standard, "delivered_rate"), "1 − 退货率");
});

test("an incomplete scenario still builds every step, with blanks instead of numbers", () => {
  const inputs = { exchange_rate_rub_cny: 11, purchase_price_cny: 100 };
  const steps = buildCalculationSteps({
    platform: "wb", market: "ru", companyType: "small", inputs, data: { cost_breakdown: {}, intermediate: {} }, labels,
  });

  assert.equal(steps[0].key, "revenue");
  assert.equal(steps.at(-1).key, "margin");
  assert.ok(steps.every((step) => step.formula !== undefined));
});

test("an Ozon FBS scenario has no cross-docking row", () => {
  const fbsCases = cases.filter((testCase) => testCase.platform === "ozon" && testCase.context.delivery_mode === "fbs");
  assert.ok(fbsCases.length >= 2);

  fbsCases.forEach((testCase) => {
    const steps = stepsFor(testCase);
    const logistics = steps.find((step) => step.key === "platform_logistics");

    assert.equal(formulaLines(logistics.formula, format).named, "去程物流 + 交接与末端处理费", testCase.name);
    assert.deepEqual(logistics.fields, ["outbound_logistics_rub", "fbs_handover_rub"]);
    assert.ok(!steps.some((step) => step.key === "cross_docking"), `${testCase.name}: FBS has no cross-docking row`);
    assert.ok(!formulaLines(steps.find((step) => step.key === "other").formula, format).named.includes("越库"), testCase.name);
  });
});

test("an FBS scenario without a handover input uses the calculator's default of 36", () => {
  const testCase = cases.find((candidate) => candidate.name === "ozon_by_fbs_default_handover");
  const logistics = stepsFor(testCase).find((step) => step.key === "platform_logistics");

  assert.equal(formulaLines(logistics.formula, format).values, "280 + 36");
});

test("only a scenario that pays storage offers the actual storage shortcut: an Ozon FBS one does not", () => {
  const source = (name) => stepsFor(cases.find((candidate) => candidate.name === name)).find((step) => step.key === "storage").source;

  assert.equal(source("ozon_ru_fbs"), null);
  assert.equal(source("ozon_by_fbs_default_handover"), null);
  assert.equal(source("ozon_ru_standard"), "actual_storage");
  assert.equal(source("wb_general_coefficient"), "actual_storage");
});

test("WB keeps every freight row and parameter in place and flags what does not apply", () => {
  const base = cases.find((testCase) => testCase.name === "wb_general_coefficient");
  const stepsIn = (logisticsMode, inputs = {}, source = "coefficient") => {
    const input = { ...base.inputs, ...inputs };
    const data = { ...base.expected, intermediate: { ...base.expected.intermediate, logistics_source: source } };
    return buildCalculationSteps({
      platform: "wb", market: base.context.market, deliveryMode: base.context.delivery_mode,
      companyType: base.context.company_type, logisticsMode, inputs: input, data, labels
    });
  };
  const stepOf = (steps, key) => steps.find((step) => step.key === key);
  const layout = (steps) => steps.map((step) => [step.key, step.fields.join()].join(":"));

  const formula = stepsIn("formula", { outbound_logistics_rub: 250, return_logistics_rub: 120 });
  const actual = stepsIn("actual", { outbound_logistics_rub: 250, return_logistics_rub: 120 }, "actual");
  assert.deepEqual(layout(formula), layout(actual), "switching the mode must not add or remove a row or a field");

  const order = formula.map((step) => step.key);
  assert.deepEqual(order.slice(order.indexOf("return_rate"), order.indexOf("return_rate") + 3), ["return_rate", "delivered_rate", "logistics_mode"],
    "the delivered rate and then the switch sit right under the return rate");
  assert.ok(stepOf(formula, "logistics_mode").control);

  assert.deepEqual(stepOf(formula, "outbound_logistics").inactiveFields, ["outbound_logistics_rub"]);
  assert.deepEqual(stepOf(formula, "returns").inactiveFields, ["return_logistics_rub"]);

  assert.deepEqual(stepOf(actual, "outbound_logistics").inactiveFields, ["wb_logistics_base_rub", "wb_logistics_liter_rub", "logistics_coeff"],
    "the base fee, per-litre fee and coefficient are void on typed freight");
  assert.deepEqual(stepOf(actual, "returns").inactiveFields, ["wb_fixed_return_base_rub"]);
});

test("Ozon's fixed formula says what the freight is the average of", () => {
  const kase = cases.find((testCase) => testCase.name === "ozon_ru_standard");
  const stepsIn = (logisticsMode, formula, platformLogistics = "platform_logistics") => {
    const data = { ...kase.expected, logistics: { formula } };
    return buildCalculationSteps({
      platform: "ozon", market: kase.context.market, deliveryMode: kase.context.delivery_mode, companyType: kase.context.company_type,
      logisticsMode, inputs: { ...kase.inputs, length_cm: 52, width_cm: 5, height_cm: 85 }, data, labels
    }).find((step) => step.key === platformLogistics);
  };

  const top = { outbound_rub: 268.43, return_rub: 268.43, source: "ozon_route_average", route_count: 40, route_basis: "top_routes" };
  assert.equal(stepsIn("formula", top).note, "最常用 40 条路线 22.10 L 268.43");
  assert.equal(stepsIn("formula", { ...top, route_basis: "all_routes", route_count: 820 }).note, "所有路线 22.10 L 268.43");
  assert.equal(stepsIn("actual", top).note, null, "real figures are not worked out from the tariff");
  assert.equal(stepsIn("formula", { outbound_rub: null, source: null }).note, null, "no tariff figure, nothing to explain");
});

test("Ozon has the same total logistics row as WB: the freight with its handover fee, the returns share and, for FBO in Russia, cross-docking", () => {
  cases.filter((testCase) => testCase.platform === "ozon").forEach((testCase) => {
    const steps = stepsFor(testCase);
    const total = steps.find((step) => step.key === "total_logistics");
    const crossDocking = testCase.platform === "ozon" && testCase.context.market === "ru" && testCase.context.delivery_mode === "fbo";
    const costs = testCase.expected.cost_breakdown;
    const expectedCny = costs.logistics + costs.returns + (crossDocking ? Number(testCase.inputs.cross_docking_cny || 0) : 0);

    assert.equal(steps.map((step) => step.key).indexOf("total_logistics"), steps.map((step) => step.key).indexOf("return_amortized") + 1, `${testCase.name}: right under the returns share`);
    assert.ok(Math.abs(total.result - expectedCny * testCase.inputs.exchange_rate_rub_cny) < 1e-6, `${testCase.name}: ${total.result} vs ${expectedCny * testCase.inputs.exchange_rate_rub_cny}`);
    assert.equal(formulaLines(total.formula, format).named, crossDocking ? "平台物流费 + 退货分摊费用 + 越库费" : "平台物流费 + 退货分摊费用", testCase.name);
  });
});
