// Which pricing scenarios the workbench shows for an SKU, and what it says about them.
//
// `state` comes from the page (SkuProfitPredictionHelper#profit_prediction_scenario_state):
//   { min_units, missed_share_percent, weeks, measured, total_units, outside_units,
//     scenarios: [{ key, row_key, label, hidden, units, orders, last_date }] }
// The rules live here so that hiding or restoring a scenario re-draws the marks, the banner and
// the restore list without a round trip.

// A scenario that is shown but has fewer signed units than the minimum: it hardly exists.
export function scenarioWarning(state, scenario) {
  return Boolean(state.measured) && !scenario.hidden && Number(scenario.units || 0) < state.min_units;
}

// Hidden scenarios that carry real sales: enough units, and a share of the SKU's signed units
// that is not negligible. These are the ones somebody should not have hidden.
export function missedScenarios(state) {
  const total = Number(state.total_units || 0);
  if (!state.measured || total <= 0) return [];

  return state.scenarios.filter((scenario) => (
    scenario.hidden
    && Number(scenario.units || 0) >= state.min_units
    && (Number(scenario.units) / total) * 100 >= state.missed_share_percent
  ));
}

export function missedSummary(state) {
  const missed = missedScenarios(state);
  const units = missed.reduce((sum, scenario) => sum + Number(scenario.units), 0);
  const total = Number(state.total_units || 0);
  return {
    scenarios: missed,
    count: missed.length,
    units,
    share: total > 0 ? Math.round((units / total) * 100) : 0,
    labels: missed.map((scenario) => scenario.label).join("、")
  };
}

export function hiddenScenarios(state) {
  return state.scenarios.filter((scenario) => scenario.hidden);
}

export function visibleScenarios(state) {
  return state.scenarios.filter((scenario) => !scenario.hidden);
}

export function fill(template, values) {
  return Object.entries(values).reduce(
    (text, [name, value]) => text.replaceAll(`__${name.toUpperCase()}__`, String(value ?? "")),
    template
  );
}
