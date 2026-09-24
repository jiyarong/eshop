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

  let result = rate("commission_rate");
  if (platform === "wb") {
    result += rate("acquiring_rate") + rate("advertising_rate");
    result += companyType === "general" ? vatShare("sales_vat_rate", 0.2) : rate("tax_rate", 0.06);
  } else if (platform === "ozon" && market === "by") {
    result += vatShare("sales_vat_rate", 0.2);
  } else if (platform === "ozon") {
    result += rate("acquiring_rate", 0.02) + rate("advertising_rate") + rate("tax_rate");
  }

  return result;
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
