export function profitInputValue(input) {
  if (input.dataset.valueChanged === "true") return input.value;

  return Object.prototype.hasOwnProperty.call(input.dataset, "sourceValue")
    ? input.dataset.sourceValue
    : input.value;
}

export function shortcutInputValue(value) {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) return String(value ?? "");

  const normalized = Object.is(numeric, -0) ? 0 : numeric;
  return normalized.toFixed(4).replace(/\.?0+$/, "");
}

export function dualCurrencyAmounts(value, sourceCurrency, exchangeRate) {
  const amount = Number(value);
  const rate = Number(exchangeRate);
  if (!Number.isFinite(amount) || !Number.isFinite(rate) || rate <= 0) return null;

  if (sourceCurrency === "cny") return { cny: amount, rub: amount * rate };
  if (sourceCurrency === "rub") return { cny: amount / rate, rub: amount };

  return null;
}

export function priceVariableCostRate({ platform, market, companyType, inputs }) {
  const rate = (key, fallback = 0) => {
    const rawValue = inputs?.[key];
    if (rawValue === null || rawValue === undefined || rawValue === "") return fallback;

    const value = Number(rawValue);
    return Number.isFinite(value) ? value : fallback;
  };
  const vatShare = (key, fallback = 0) => {
    const value = rate(key, fallback);
    return value > -1 ? value / (1 + value) : NaN;
  };

  if (platform === "wb") {
    let result = rate("commission_rate");
    result += rate("acquiring_rate") + rate("advertising_rate");
    result += companyType === "general" ? vatShare("sales_vat_rate", 0.2) : rate("tax_rate", 0.06);
    return result;
  } else if (platform === "ozon") {
    // Ozon target margin follows the seller/list price. Buyer-paid price is
    // only an audit input for the Belarus platform subsidy.
    let result = rate("commission_rate") + rate("acquiring_rate") + rate("advertising_rate");
    result += market === "by" ? vatShare("sales_vat_rate", 0.2) : rate("tax_rate");
    return result;
  }

  return 0;
}

export function targetPriceForMargin({ revenueCny, totalCostCny, variableCostRate, targetMargin, exchangeRate }) {
  const revenue = Number(revenueCny);
  const totalCost = Number(totalCostCny);
  const variableRate = Number(variableCostRate);
  const margin = Number(targetMargin);
  const exchange = Number(exchangeRate);
  if (![revenue, totalCost, variableRate, margin, exchange].every(Number.isFinite) || revenue <= 0 || exchange <= 0) return null;

  const fixedCost = totalCost - revenue * variableRate;
  const denominator = 1 - variableRate - margin;
  if (fixedCost <= 0 || denominator <= 1e-12) return null;

  const priceRub = fixedCost / denominator * exchange;
  return Number.isFinite(priceRub) && priceRub > 0 ? priceRub : null;
}

// Which actual price fills which input, with the same meaning on every platform:
//   commission base price -> the input the platform's commission is charged on
//                            (Ozon rf_price_rub, WB price_rub)
//   buyer paid price      -> Ozon price_rub (Belarus subsidy audit only); WB has no
//                            such input, so it is shown but cannot be applied.
export function sellingPriceShortcuts(platform, data) {
  const positive = (value) => {
    if (value === null || value === undefined || value === "") return null;

    const number = Number(value);
    return Number.isFinite(number) && number > 0 ? number : null;
  };
  const commissionBase = positive(data?.commission_base_price?.average_rub);
  const buyerPaid = positive(data?.buyer_paid_price?.average_rub);
  const shortcuts = [];

  if (commissionBase !== null) {
    shortcuts.push({
      kind: "commission_base",
      field: platform === "ozon" ? "rf_price_rub" : "price_rub",
      priceRub: commissionBase
    });
  }
  if (buyerPaid !== null) {
    shortcuts.push({ kind: "buyer_paid", field: platform === "ozon" ? "price_rub" : null, priceRub: buyerPaid });
  }

  return shortcuts;
}
