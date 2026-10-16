// Formulas of the "calculation process" table in the pricing workbench.
//
// Every step is a list of tokens instead of a finished string, so the same data renders
// twice: once with the parameter names ("base fee + (billed volume - 1) * fee per liter")
// and once with the numbers substituted. A token is
//   "+", "-", "×", "÷", "(", ")", "ceil"             an operator
//   { type: "field", field, name, value, percent }   a left-form parameter
//   { type: "calc", key, name, value }               the result of another step
//   { type: "const", value }                         a constant of the formula
// `evaluateFormula` computes the tokens, which is how the specs keep the page in step with
// the Ruby calculators in app/services/ec/profit_calculators.

const OPERATORS = new Set(["+", "−", "×", "÷", "(", ")", "ceil"]);

// "WB 基础物流费 RUB" -> "WB 基础物流费": the unit is the table's job, not the name's.
export function formulaFieldName(label) {
  return String(label).replace(/\s*[（(][^）)]*[）)]$/, "").replace(/\s+(CNY|RUB\/L|RUB|cm)$/, "");
}

export function isOperator(token) {
  return typeof token === "string" && OPERATORS.has(token);
}

export function formulaTokenText(token, format) {
  if (isOperator(token)) return token === "ceil" ? "ceil" : token;
  if (token.type === "const") return format.number(token.value);
  return token.percent ? format.percent(token.value) : format.number(token.value);
}

export function formulaTokenName(token) {
  if (isOperator(token)) return token;
  return token.type === "const" ? formulaTokenText(token, { number: String }) : token.name;
}

// Plain-text rendering of both lines, used by the specs and as the tooltip fallback.
export function formulaLines(tokens, format) {
  if (!Array.isArray(tokens)) return { named: String(tokens), values: String(tokens) };

  return {
    named: tokens.map((token) => formulaTokenName(token)).join(" "),
    values: tokens.map((token) => formulaTokenText(token, format)).join(" ")
  };
}

export function evaluateFormula(tokens) {
  const expression = tokens.map((token) => {
    if (isOperator(token)) {
      return { "−": "-", "×": "*", "÷": "/", ceil: "Math.ceil" }[token] || token;
    }
    return `(${Number(token.type === "const" ? token.value : token.value ?? 0)})`;
  }).join(" ");

  return Function(`"use strict"; return (${expression});`)();
}

// The steps of the calculation process for one scenario row, in display order.
//   context: { platform, market, companyType,
//              inputs      the numeric left-form values (null when blank),
//              data        the preview response ({ revenue_cny, cost_breakdown, intermediate, ... }),
//              labels      { fields, steps, formula }  (the translated names) }
// Each step is { key, label, formula, result, unit, fields, source, note }, where
// `fields` are the parameters whose inputs are shown on that row, `unit` is "cny", "rub",
// "liter" or "percent" and a string `formula` is shown as is.
export function buildCalculationSteps({ platform, market, companyType, inputs, data, labels }) {
  const costs = data.cost_breakdown || {};
  const intermediate = data.intermediate || {};
  const exchange = inputs.exchange_rate_rub_cny;
  const numberOr = (value, fallback) => (value === null || value === undefined || Number.isNaN(Number(value)) ? fallback : Number(value));
  const hasValue = (value) => value !== null && value !== undefined && value !== "" && Number.isFinite(Number(value));

  const fieldLabel = (field) => labels.fields?.[field] ?? labels.formula?.[field] ?? field;
  const F = (field, value = inputs[field], percent = false) => ({
    type: "field", field, name: formulaFieldName(fieldLabel(field)), value, percent
  });
  const P = (field, value) => F(field, value === undefined ? inputs[field] : value, true);
  const C = (key, value) => ({ type: "calc", key, name: labels.steps[key], value });
  // A value the backend applies but the page has no input for (legacy sheet parameters).
  const N = (value) => ({ type: "const", value });
  const H = (field, value, percent = false) => ({ type: "field", field: null, name: formulaFieldName(labels.formula?.[field] ?? field), value, percent });

  const steps = [];
  const step = (key, formula, result, unit, fields = [], extra = {}) => {
    steps.push({ key, label: labels.steps[key], formula, result, unit, fields, source: null, note: null, ...extra });
  };

  const wb = platform === "wb";
  const commissionRate = P("commission_rate");
  const dutyRate = numberOr(inputs.duty_rate, 0.1);
  const importVatRate = numberOr(inputs.import_vat_rate, 0.2);
  const returnRate = wb ? inputs.return_rate : numberOr(inputs.return_rate, 0.1);
  const returnAmortization = (rate) => [P("return_rate", rate), "÷", "(", N(1), "−", P("return_rate", rate), ")"];

  // Revenue is the commission base price on every platform; the buyer-paid price never enters
  // it (it only feeds the platform subsidy step).
  step("revenue", [F("commission_base_price_rub"), "÷", F("exchange_rate_rub_cny", exchange)],
    data.revenue_cny, "cny", ["commission_base_price_rub", "target_margin", "exchange_rate_rub_cny"],
    { source: "actual_selling_price" });

  // Audit only: what the platform effectively pays on top of what the buyer paid. A WB general
  // company issues a VAT invoice the platform deducts, so that VAT is not part of the due amount.
  const buyerVatRate = numberOr(inputs.buyer_price_vat_rate, wb ? 0.2 : (market === "by" ? 0.2 : 0.22));
  const invoiceVatRate = wb && companyType === "general" ? numberOr(inputs.sales_vat_rate, 0.2) : null;
  step("platform_subsidy", [
    F("commission_base_price_rub"), "×", "(", N(1), "−", commissionRate, ")",
    ...(invoiceVatRate === null ? [] : ["÷", "(", N(1), "+", P("sales_vat_rate", invoiceVatRate), ")"]),
    "−", F("buyer_paid_price_rub"), "÷", "(", N(1), "+", P("buyer_price_vat_rate", buyerVatRate), ")"
  ], intermediate.platform_subsidy_rub, "rub", ["buyer_paid_price_rub", "buyer_price_vat_rate"]);

  step("goods", [F("purchase_price_cny"), "+", F("freight_cny", inputs.freight_cny || 0), "+", F("customs_misc_cny", inputs.customs_misc_cny || 0)],
    costs.goods, "cny", ["purchase_price_cny", "freight_cny", "customs_misc_cny"]);
  step("duty", [F("purchase_price_cny"), "×", P("duty_rate", dutyRate)],
    costs.duty, "cny", ["purchase_price_cny", "duty_rate"]);

  // Ozon Russia books the import VAT only by the share of it that is a cost (normally none).
  const importVatCostRate = numberOr(intermediate.import_vat_cost_rate, 0);
  if (wb || market === "by") {
    step("import_vat", ["(", F("purchase_price_cny"), "+", C("duty", costs.duty), ")", "×", P("import_vat_rate", importVatRate)],
      costs.import_vat, "cny", ["purchase_price_cny", "duty_rate", "import_vat_rate"]);
  } else if (importVatCostRate !== 0) {
    step("import_vat", ["(", F("purchase_price_cny"), "+", C("duty", costs.duty), ")", "×", P("import_vat_rate", importVatRate), "×", H("ozon_import_vat_cost_rate", importVatCostRate, true)],
      costs.import_vat, "cny", ["purchase_price_cny", "duty_rate", "import_vat_rate"]);
  }

  step("volume", [F("length_cm"), "×", F("width_cm"), "×", F("height_cm"), "÷", N(1000)],
    intermediate.volume_l, "liter", ["length_cm", "width_cm", "height_cm"]);
  step("billed_volume", ["ceil", "(", C("volume", intermediate.volume_l), ")"],
    intermediate.billed_volume_l, "liter", ["length_cm", "width_cm", "height_cm"]);
  step("return_rate", [P("return_rate", returnRate)], returnRate * 100, "percent", ["return_rate"],
    { source: "actual_return_rate" });

  if (wb) {
    const baseFee = numberOr(inputs.wb_logistics_base_rub, companyType === "general" ? 60 : 46);
    const literFee = numberOr(inputs.wb_logistics_liter_rub, 14);
    const hasActualReturn = hasValue(inputs.return_logistics_rub);
    const logisticsSource = intermediate.logistics_source || (hasValue(inputs.outbound_logistics_rub) ? "actual" : "coefficient");
    const fbo = F("fbo_delivery_cny", inputs.fbo_delivery_cny || 0);

    step("base_logistics", [F("wb_logistics_base_rub", baseFee), "+", "(", C("billed_volume", intermediate.billed_volume_l), "−", N(1), ")", "×", F("wb_logistics_liter_rub", literFee)],
      intermediate.base_logistics_rub, "rub", ["wb_logistics_base_rub", "wb_logistics_liter_rub"], { source: "wb_logistics_tariffs" });

    const outbound = {
      actual: [F("outbound_logistics_rub"), "÷", F("exchange_rate_rub_cny", exchange)],
      override: [H("wb_logistics_override_cny", intermediate.platform_logistics_cny)],
      coefficient: [C("base_logistics", intermediate.base_logistics_rub), "×", F("logistics_coeff"), "÷", F("exchange_rate_rub_cny", exchange)]
    }[logisticsSource];
    step("platform_logistics", [fbo, "+", ...outbound], costs.logistics, "cny",
      ["fbo_delivery_cny", "logistics_coeff", "outbound_logistics_rub", "exchange_rate_rub_cny"]);

    const returnBase = hasActualReturn
      ? F("return_logistics_rub")
      : F("wb_fixed_return_base_rub", numberOr(inputs.wb_fixed_return_base_rub, 50));
    step("returns", [
      "(", H("logistics_ex_fbo", intermediate.platform_logistics_cny), "+", returnBase, "÷", F("exchange_rate_rub_cny", exchange), ")",
      "×", ...returnAmortization(returnRate)
    ], costs.returns, "cny", ["return_rate", "wb_fixed_return_base_rub", "return_logistics_rub", "exchange_rate_rub_cny"]);
  } else {
    const factorOverride = inputs.return_amortization_factor_override;
    const hasOverride = intermediate.return_amortization_factor_overridden === true
      || (factorOverride !== undefined && factorOverride !== null && factorOverride !== "");
    const warehouseRate = numberOr(intermediate.warehouse_rate, 0.25);
    const warehouse = F("warehouse_operation_rub");

    step("platform_logistics", [
      "(", F("outbound_logistics_rub"), "+", warehouse, "+", warehouse, "×", N(2), "×", H("ozon_warehouse_rate", warehouseRate, true), ")",
      "÷", F("exchange_rate_rub_cny", exchange)
    ], costs.logistics, "cny", ["outbound_logistics_rub", "warehouse_operation_rub", "exchange_rate_rub_cny"],
    { source: "ozon_logistics_tariffs" });

    // Cross-docking is charged inside "other costs"; this row only shows where it comes from.
    const crossDocking = market === "ru";
    step("cross_docking",
      crossDocking ? [F("cross_docking_cny", inputs.cross_docking_cny || 0)] : labels.crossDockingNotApplicable,
      crossDocking ? inputs.cross_docking_cny || 0 : 0, "cny", crossDocking ? ["cross_docking_cny"] : [],
      { source: crossDocking ? "ozon_cross_dock_tariffs" : null, note: crossDocking ? labels.crossDockingInOther : null });

    step("return_amortized", [
      "(", F("outbound_logistics_rub"), "+", F("return_logistics_rub"), ")", "×",
      ...(hasOverride
        ? [F("return_amortization_factor_override", numberOr(intermediate.return_amortization_factor, factorOverride))]
        : ["(", ...returnAmortization(returnRate), ")"]),
      "÷", F("exchange_rate_rub_cny", exchange)
    ], costs.returns, "cny", ["outbound_logistics_rub", "return_logistics_rub", "return_amortization_factor_override", "return_rate", "exchange_rate_rub_cny"]);
  }

  const revenue = data.revenue_cny;
  step("storage", [F("storage_cny", inputs.storage_cny || 0)], costs.storage, "cny", ["storage_cny"], { source: "actual_storage" });
  step("commission", [C("revenue", revenue), "×", commissionRate], costs.commission, "cny", ["commission_rate"], { source: "official_commission" });
  step("acquiring", [C("revenue", revenue), "×", P("acquiring_rate", numberOr(inputs.acquiring_rate, wb ? 0 : 0.02))],
    costs.acquiring, "cny", ["acquiring_rate"], { source: "actual_acquiring" });

  const advertisingFixed = numberOr(intermediate.advertising_fixed_rub, 0);
  step("advertising", [
    C("revenue", revenue), "×", P("advertising_rate", inputs.advertising_rate || 0),
    ...(advertisingFixed === 0 ? [] : ["+", H("advertising_fixed_rub", advertisingFixed), "÷", F("exchange_rate_rub_cny", exchange)])
  ], costs.advertising, "cny", ["advertising_rate"], { source: "actual_advertising" });

  step("tax", taxFormula({ wb, market, companyType, inputs, intermediate, revenue, costs, F, P, C, N, numberOr }),
    costs.tax, "cny", ["tax_rate", "sales_vat_rate"]);

  const damage = [ "(", C("goods", costs.goods), "+", C("import_vat", costs.import_vat), "+", C("duty", costs.duty), ")", "×", P("damage_rate", inputs.damage_rate || 0), "+", F("misc_cny", inputs.misc_cny || 0), "+" ];
  const otherCost = wb
    ? [...damage, F("other_cny", inputs.other_cny || 0)]
    : [...(market === "ru" ? [F("cross_docking_cny", inputs.cross_docking_cny || 0), "+"] : []), F("other_cny", inputs.other_cny || 0)];
  step("other", otherCost, costs.other, "cny", wb ? ["damage_rate", "misc_cny", "other_cny"] : ["other_cny"]);

  step("total_cost", labels.sumCosts, data.total_cost_cny, "cny");
  step("profit", [C("revenue", revenue), "−", C("total_cost", data.total_cost_cny)], data.profit_cny, "cny");
  step("margin", [C("profit", data.profit_cny), "÷", C("revenue", revenue)], Number(data.margin) * 100, "percent");

  return steps;
}

function taxFormula({ wb, market, companyType, inputs, intermediate, revenue, costs, F, P, C, N, numberOr }) {
  if (!wb && market !== "by") return [C("revenue", revenue), "×", P("tax_rate", numberOr(intermediate.sales_tax_rate, 0))];
  if (companyType === "small") return [C("revenue", revenue), "×", P("tax_rate", numberOr(inputs.tax_rate, 0.06))];

  const rate = numberOr(inputs.sales_vat_rate, 0.2);
  return [C("revenue", revenue), "×", P("sales_vat_rate", rate), "÷", "(", N(1), "+", P("sales_vat_rate", rate), ")", "−", C("import_vat", costs.import_vat)];
}
