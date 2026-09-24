import { Controller } from "@hotwired/stimulus";
import { Turbo } from "@hotwired/turbo-rails";
import {
  dualCurrencyAmounts,
  priceVariableCostRate,
  profitInputValue,
  shortcutInputValue,
  targetPriceForMargin
} from "./profit_prediction_values";

const PREVIEW_DEBOUNCE_MS = 350;

const COST_FORMULA_STEPS = [
  ["goods", "goods"],
  ["import_vat", "import_vat"],
  ["duty", "duty"],
  ["logistics", "platform_logistics"],
  ["returns", "returns"],
  ["storage", "storage"],
  ["commission", "commission"],
  ["acquiring", "acquiring"],
  ["advertising", "advertising"],
  ["tax", "tax"],
  ["other", "other"]
];

const RESULT_PATHS = {
  revenue_cny: ["revenue_cny"],
  goods_cost_cny: ["cost_breakdown", "goods"],
  import_vat_cny: ["cost_breakdown", "import_vat"],
  duty_cny: ["cost_breakdown", "duty"],
  logistics_cny: ["cost_breakdown", "logistics"],
  returns_cny: ["cost_breakdown", "returns"],
  storage_cost_cny: ["cost_breakdown", "storage"],
  commission_cny: ["cost_breakdown", "commission"],
  acquiring_cny: ["cost_breakdown", "acquiring"],
  advertising_cny: ["cost_breakdown", "advertising"],
  tax_cny: ["cost_breakdown", "tax"],
  other_cost_cny: ["cost_breakdown", "other"],
  total_cost_cny: ["total_cost_cny"],
  profit_cny: ["profit_cny"],
  margin: ["margin"]
};

export default class extends Controller {
  static values = {
    url: String,
    tariffUrl: String,
    crossDockTariffUrl: String,
    wbLogisticsTariffUrl: String,
    actualLogisticsUrl: String,
    actualReturnRateUrl: String,
    actualStorageUrl: String,
    actualSellingPriceUrl: String,
    actualAdvertisingUrl: String,
    officialCommissionUrl: String,
    messages: Object,
    newRecord: Boolean,
    status: String,
    readonly: Boolean
  };

  static targets = [
    "row",
    "input",
    "platformFilter",
    "scenarioTab",
    "versionInput",
    "navigationControl",
    "modeStatus",
    "saveButton",
    "detailTitle",
    "detailStatus",
    "detailCostFormula",
    "detailProfitFormula",
    "detailMarginFormula",
    "detailBody",
    "tariffDialog",
    "tariffVolume",
    "tariffVolumeBand",
    "tariffSnapshot",
    "tariffMatchedCount",
    "tariffAverage",
    "tariffUseAverage",
    "tariffActionMessage",
    "tariffBody",
    "tariffPrevious",
    "tariffNext",
    "tariffPage",
    "crossDockDialog",
    "crossDockVolume",
    "crossDockSnapshot",
    "crossDockMatchedCount",
    "crossDockAveragePallet",
    "crossDockAverageBox",
    "crossDockUseAveragePallet",
    "crossDockUseAverageBox",
    "crossDockBody",
    "crossDockPrevious",
    "crossDockNext",
    "crossDockPage",
    "wbLogisticsDialog",
    "wbLogisticsMode",
    "wbLogisticsSnapshot",
    "wbLogisticsWarehouse",
    "wbLogisticsGeo",
    "wbLogisticsMatched",
    "wbLogisticsAverageBase",
    "wbLogisticsAverageCoeff",
    "wbLogisticsAverageLiter",
    "wbLogisticsUseAverage",
    "wbLogisticsActionMessage",
    "wbLogisticsBody",
    "contextCount",
    "detailPrice",
    "targetMargin",
    "detailTotalCost",
    "detailProfit",
    "detailMargin"
  ];

  connect() {
    this.previewTimers = new Map();
    this.previewControllers = new Map();
    this.previewData = new Map();
    this.actualSellingPriceData = new Map();
    this.actualReturnRateData = new Map();
    this.actualStorageData = new Map();
    this.actualAdvertisingData = new Map();
    this.officialCommissionData = new Map();
    this.targetMarginRequestController = null;
    this.targetMarginRequestToken = 0;
    this.dirtyRows = new Set();
    this.versionDirty = false;
    this.allowNavigation = false;
    this.navigationWasDisabled = this.hasNavigationControlTarget && this.navigationControlTarget.disabled;
    this.numberFormatter = new Intl.NumberFormat(document.documentElement.lang || undefined, {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2
    });
    this.platformFilter = "";
    this.targetMarginBaseData = null;
    this.captureSnapshot();
    this.beforeUnloadHandler = (event) => this.handleBeforeUnload(event);
    this.beforeVisitHandler = (event) => this.handleBeforeVisit(event);
    window.addEventListener("beforeunload", this.beforeUnloadHandler);
    document.addEventListener("turbo:before-visit", this.beforeVisitHandler);

    if (this.newRecordValue) {
      this.rowTargets.forEach((row) => {
        this.dirtyRows.add(row.dataset.rowKey);
        row.classList.add("is-dirty");
        this.schedulePreview(row);
      });
      this.versionDirty = true;
    } else {
      // Existing drafts can contain stale incomplete results (for example, a
      // Belarus Ozon row whose reference price is derived from its own price).
      // Refresh those rows in the browser so the table does not keep showing
      // empty result columns until the user edits a field.
      this.rowTargets
        .filter((row) => row.dataset.calculationStatus !== "valid")
        .forEach((row) => this.schedulePreview(row));
    }
    this.setCalculationMode(true);
    this.applyPlatformFilter();

    if (!this.selectedRow && this.visibleRows()[0]) this.setSelectedRow(this.visibleRows()[0]);
  }

  disconnect() {
    this.previewTimers.forEach((timer) => window.clearTimeout(timer));
    this.previewControllers.forEach((controller) => controller.abort());
    this.tariffRequestController?.abort();
    this.crossDockRequestController?.abort();
    this.wbLogisticsRequestController?.abort();
    this.actualMetricsRequestController?.abort();
    this.actualStorageRequestController?.abort();
    this.actualSellingPriceRequestController?.abort();
    this.actualAdvertisingRequestController?.abort();
    this.officialCommissionRequestController?.abort();
    this.targetMarginRequestController?.abort();
    window.removeEventListener("beforeunload", this.beforeUnloadHandler);
    document.removeEventListener("turbo:before-visit", this.beforeVisitHandler);
  }

  inputChanged(event) {
    if (!this.calculationMode) return;

    const row = event.target.closest("[data-profit-prediction-target~='row']");
    if (!row) return;

    if (event.type !== "target-margin") {
      this.targetMarginBaseData = null;
    }

    event.target.dataset.valueChanged = "true";
    this.syncProcessInput(row, event.target.dataset.field);
    if (this.selectedRow === row && event.target.dataset.field === "price_rub" && this.hasDetailPriceTarget) {
      this.detailPriceTarget.textContent = this.number(this.numericInputs(row).price_rub);
    }
    this.dirtyRows.add(row.dataset.rowKey);
    this.previewData.delete(row.dataset.rowKey);
    row.classList.add("is-dirty");
    this.updateControls();

    if (event.type === "input") this.schedulePreview(row);
    if (event.type === "input" && row.dataset.platform === "ozon" && row.dataset.market === "ru" && event.target.dataset.field === "price_rub") {
      this.rowTargets
        .filter((candidate) => candidate.dataset.platform === "ozon" && candidate.dataset.market === "by")
        .forEach((candidate) => this.schedulePreview(candidate));
    }
  }

  versionChanged() {
    if (!this.calculationMode) return;

    this.versionDirty = true;
    this.updateControls();
  }

  changeVersion(event) {
    if (!event.target.value) return;

    const url = new URL(window.location.href);
    url.searchParams.set("tab", "profit_prediction");
    url.searchParams.set("version_id", event.target.value);
    url.searchParams.delete("copy_version_id");
    url.searchParams.delete("new_profit_version");
    Turbo.visit(url.toString(), { action: "replace" });
  }

  save() {
    this.saveVersion(this.statusValue || "draft", false);
  }

  schedulePreview(row) {
    const key = row.dataset.rowKey;
    window.clearTimeout(this.previewTimers.get(key));
    this.previewControllers.get(key)?.abort();
    this.previewControllers.delete(key);
    this.setRowStatus(row, this.messagesValue.calculating, "calculating");
    this.previewTimers.set(key, window.setTimeout(() => this.previewRow(row), PREVIEW_DEBOUNCE_MS));
  }

  async previewRow(row, { detailOnly = false } = {}) {
    const key = row.dataset.rowKey;
    window.clearTimeout(this.previewTimers.get(key));
    this.previewTimers.delete(key);
    this.previewControllers.get(key)?.abort();
    const controller = new AbortController();
    this.previewControllers.set(key, controller);

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: this.jsonHeaders(),
        body: JSON.stringify({
          platform: row.dataset.platform,
          parameter_context: this.contextAttributes(row),
          inputs: this.rowInputs(row)
        }),
        signal: controller.signal
      });
      const data = await response.json();
      if (!response.ok || data.errors?.length) {
        const errors = data.errors || [];
        this.previewData.delete(key);
        this.syncTargetMargin(row, null);
        this.clearRowResults(row);
        this.markInvalidInputs(row, errors);
        this.setRowStatus(row, this.messagesValue.statuses.incomplete, "incomplete");
        row.title = this.messagesValue.calculation_failed;
        if (this.selectedRow === row) this.renderIncompleteCalculationProcess(row, errors);
        return;
      }

      this.previewData.set(key, data);
      this.syncTargetMargin(row, data.margin);
      if (!detailOnly) {
        this.markInvalidInputs(row, []);
        Object.entries(RESULT_PATHS).forEach(([field, path]) => {
          this.setResultValue(row, field, this.valueAt(data, path));
        });
        this.setRowStatus(row, this.messagesValue.statuses.valid, "valid");
        row.title = Array(data.warnings)
          .map((warning) => this.messagesValue.warnings?.[warning])
          .filter(Boolean)
          .join("; ");
        row.classList.add("has-preview-results");
      }
      if (this.selectedRow === row) this.renderCalculationProcess(row, data);
    } catch (error) {
      if (error.name === "AbortError") return;

      this.clearRowResults(row);
      this.syncTargetMargin(row, null);
      this.markInvalidInputs(row, []);
      this.setRowStatus(row, this.messagesValue.calculation_failed, "incomplete");
      row.title = this.messagesValue.calculation_failed;
      if (this.selectedRow === row) this.renderIncompleteCalculationProcess(row);
    } finally {
      if (this.previewControllers.get(key) === controller) this.previewControllers.delete(key);
    }
  }

  selectRow(event) {
    this.setSelectedRow(event.currentTarget);
  }

  selectRowWithKeyboard(event) {
    if (event.target !== event.currentTarget || !["Enter", " "].includes(event.key)) return;

    event.preventDefault();
    this.setSelectedRow(event.currentTarget);
  }

  selectScenarioTab(event) {
    this.activateScenarioTab(event.currentTarget);
  }

  selectScenarioTabWithKeyboard(event) {
    const keys = ["ArrowLeft", "ArrowRight", "Home", "End"];
    if (!keys.includes(event.key)) return;

    event.preventDefault();
    const tabs = this.scenarioTabTargets;
    const currentIndex = tabs.indexOf(event.currentTarget);
    let nextIndex = currentIndex;
    if (event.key === "ArrowLeft") nextIndex = (currentIndex - 1 + tabs.length) % tabs.length;
    if (event.key === "ArrowRight") nextIndex = (currentIndex + 1) % tabs.length;
    if (event.key === "Home") nextIndex = 0;
    if (event.key === "End") nextIndex = tabs.length - 1;

    const tab = tabs[nextIndex];
    if (!tab) return;

    tab.focus();
    this.activateScenarioTab(tab);
  }

  activateScenarioTab(tab) {
    const rowKey = tab.dataset.rowKey;
    const row = this.rowTargets.find((candidate) => candidate.dataset.rowKey === rowKey);
    if (!row) return;

    if (row.hidden) {
      this.platformFilter = row.dataset.platform || "";
      this.platformFilterTargets.forEach((platformTab) => {
        const active = platformTab.dataset.platformValue === this.platformFilter;
        platformTab.classList.toggle("is-active", active);
        platformTab.setAttribute("aria-selected", active ? "true" : "false");
      });
      this.setSelectedRow(row);
      this.applyPlatformFilter();
      return;
    }

    this.setSelectedRow(row);
  }

  platformFilterChanged(event) {
    this.platformFilter = event.currentTarget.dataset.platformValue || "";
    this.platformFilterTargets.forEach((tab) => {
      const active = tab === event.currentTarget;
      tab.classList.toggle("is-active", active);
      tab.setAttribute("aria-selected", active ? "true" : "false");
    });
    this.applyPlatformFilter();
  }

  applyPlatformFilter() {
    const filter = this.platformFilter;
    this.rowTargets.forEach((row) => {
      row.hidden = Boolean(filter) && row.dataset.platform !== filter;
    });

    const tables = [
      this.element.querySelector(".profit-prediction-table"),
      ...document.querySelectorAll(".sticky-table-header__table.profit-prediction-table")
    ].filter(Boolean);
    tables.forEach((table) => this.applyColumnFilter(table, filter));

    const visibleRows = this.visibleRows();
    if (!visibleRows.includes(this.selectedRow)) this.setSelectedRow(visibleRows[0]);
    if (this.hasContextCountTarget) {
      const template = filter ? this.messagesValue.filteredContextCount : this.messagesValue.contextCount;
      this.contextCountTarget.textContent = template
        .replace("__VISIBLE__", visibleRows.length)
        .replace("__TOTAL__", this.rowTargets.length)
        .replace("__COUNT__", visibleRows.length)
        .replace("%{count}", visibleRows.length);
    }
  }

  applyColumnFilter(table, filter) {
    table.querySelectorAll("[data-platforms]").forEach((cell) => {
      const platforms = cell.dataset.platforms.split(" ").filter(Boolean);
      cell.hidden = Boolean(filter) && !platforms.includes(filter);
    });

    table.querySelectorAll("[data-platform-group]").forEach((groupHeader) => {
      const group = groupHeader.dataset.platformGroup;
      const visibleColumns = table.tHead?.querySelectorAll(
        `[data-platform-column-group='${group}']:not([hidden])`
      ).length || 0;
      groupHeader.colSpan = visibleColumns;
      groupHeader.hidden = visibleColumns === 0;
    });
  }

  visibleRows() {
    return this.rowTargets.filter((row) => !row.hidden);
  }

  setSelectedRow(row) {
    if (!row) return;

    this.rowTargets.forEach((candidate) => {
      const selected = candidate === row;
      candidate.classList.toggle("is-selected", selected);
      candidate.setAttribute("aria-selected", selected ? "true" : "false");
    });
    this.selectedRow = row;
    this.scenarioTabTargets.forEach((tab) => {
      const selected = tab.dataset.rowKey === row.dataset.rowKey;
      tab.classList.toggle("is-active", selected);
      tab.setAttribute("aria-selected", selected ? "true" : "false");
      tab.tabIndex = selected ? 0 : -1;
    });
    if (this.hasDetailTitleTarget) this.detailTitleTarget.textContent = row.dataset.contextLabel || "";
    if (this.hasDetailPriceTarget) this.detailPriceTarget.textContent = this.number(this.numericInputs(row).price_rub);

    const data = this.previewData.get(row.dataset.rowKey);
    if (data) {
      this.renderCalculationProcess(row, data);
    } else if (this.previewControllers.has(row.dataset.rowKey) || this.previewTimers.has(row.dataset.rowKey)) {
      this.renderPendingCalculationProcess(row);
    } else {
      this.renderPendingCalculationProcess(row);
      this.previewRow(row, { detailOnly: true });
    }
  }

  renderCalculationProcess(row, data) {
    if (!this.hasDetailBodyTarget) return;

    this.prepareCalculationProcess(row);
    this.setProcessStatus("", "valid");
    this.renderedProcessParameters = new Set();
    this.processInvalidFields = new Set();
    this.renderCalculationSteps(row, data);
    this.processInvalidFields = null;
    this.finishCalculationProcess();
    this.renderProcessSummary(row, data);
    this.renderProcessFormulaSummary(data);
  }

  prepareCalculationProcess(row) {
    this.renderedProcessRowKey = row.dataset.rowKey;
    this.processStepIndex = 0;
  }

  renderPendingCalculationProcess(row) {
    if (!this.hasDetailBodyTarget) return;

    this.prepareCalculationProcess(row);
    this.renderedProcessParameters = new Set();
    this.processInvalidFields = new Set();
    this.renderCalculationSteps(row, { cost_breakdown: {}, intermediate: {} });
    this.processInvalidFields = null;
    this.finishCalculationProcess();
    this.clearProcessSummary();
    this.setProcessStatus("", "pending");
  }

  finishCalculationProcess() {
    Array.from(this.detailBodyTarget.children).forEach((processRow) => {
      if (Number(processRow.dataset.processStepIndex) >= this.processStepIndex) processRow.remove();
    });
  }

  renderCalculationSteps(row, data) {
    const inputs = this.numericInputs(row);
    const costs = data.cost_breakdown || {};
    const intermediate = data.intermediate || {};
    const steps = this.messagesValue.process.steps;
    const units = this.messagesValue.process.units;
    const exchange = inputs.exchange_rate_rub_cny;
    this.processExchangeRate = exchange;
    this.processCurrencyUnits = units;
    const purchase = inputs.purchase_price_cny;
    const freight = inputs.freight_cny || 0;
    const customs = inputs.customs_misc_cny || 0;
    const dutyRate = this.numberOr(inputs.duty_rate, 0.1);
    const importVatRate = this.numberOr(inputs.import_vat_rate, 0.2);

    const isOzonBelarus = row.dataset.platform === "ozon" && row.dataset.market === "by";
    const russianPriceAvailable = isOzonBelarus && this.russianScenarioPrice(row) !== null;
    const revenueFormula = isOzonBelarus
      ? (russianPriceAvailable
        ? this.messagesValue.process.by_revenue_formula
        : this.messagesValue.process.by_revenue_formula_fallback)
        .replace("__BY_PRICE__", this.number(inputs.price_rub))
        .replace("__RF_PRICE__", this.number(inputs.rf_price_rub))
        .replaceAll("__EXCHANGE__", this.number(exchange))
      : `${this.number(inputs.price_rub)} / ${this.number(exchange)}`;
    const revenueFields = isOzonBelarus
      ? ["price_rub", "target_margin", "rf_price_rub", "exchange_rate_rub_cny"]
      : ["price_rub", "target_margin", "exchange_rate_rub_cny"];
    this.appendProcessStep(steps.revenue,
      revenueFormula,
      data.revenue_cny, units.cny, revenueFields, "actual_selling_price");
    this.appendProcessStep(steps.goods,
      `${this.number(purchase)} + ${this.number(freight)} + ${this.number(customs)}`,
      costs.goods, units.cny, ["purchase_price_cny", "freight_cny", "customs_misc_cny"]);
    this.appendProcessStep(steps.duty,
      `${this.number(purchase)} * ${this.percent(dutyRate)}`,
      costs.duty, units.cny, ["purchase_price_cny", "duty_rate"]);

    if (row.dataset.platform === "wb" || row.dataset.market === "by") {
      this.appendProcessStep(steps.import_vat,
        `(${this.number(purchase)} + ${this.number(costs.duty)}) * ${this.percent(importVatRate)}`,
        costs.import_vat, units.cny, ["purchase_price_cny", "duty_rate", "import_vat_rate"]);
    }

    if (row.dataset.platform === "wb") {
      this.appendWbProcessSteps(row, inputs, costs, intermediate, steps, units);
    } else {
      this.appendOzonProcessSteps(row, inputs, costs, intermediate, steps, units);
    }

    this.appendCommonCostSteps(row, inputs, costs, data, steps, units);
  }

  renderIncompleteCalculationProcess(row, errors = []) {
    if (!this.hasDetailBodyTarget) return;

    this.prepareCalculationProcess(row);
    this.renderedProcessParameters = new Set();
    this.clearProcessSummary();
    const invalidFields = this.processInputFields(row, errors);
    const invalidLabels = invalidFields.map((field) => this.messagesValue.process.parameter_labels?.[field] || field);
    const incompleteMessage = errors.includes("missing_rf_price_rub")
      ? this.messagesValue.process.missing_reference_price
      : invalidLabels.length > 0
      ? this.messagesValue.process.incomplete_fields.replace("__FIELDS__", invalidLabels.join(", "))
      : this.messagesValue.process.incomplete;
    this.setProcessStatus(incompleteMessage, "incomplete");

    this.processInvalidFields = new Set(invalidFields);
    this.renderCalculationSteps(row, { cost_breakdown: {}, intermediate: {} });
    this.processInvalidFields = null;
    this.finishCalculationProcess();
  }

  processInputFields(row, errors) {
    const inputFields = Array.from(row.querySelectorAll("[data-profit-prediction-target~='input']"))
      .filter((input) => input.type !== "hidden" && input.dataset.editable !== "false")
      .map((input) => input.dataset.field)
      .filter(Boolean);
    const invalidFields = inputFields.filter((field) => errors.some((error) => error.includes(field)));

    return invalidFields;
  }

  appendWbProcessSteps(row, inputs, costs, intermediate, steps, units) {
    const exchange = inputs.exchange_rate_rub_cny;
    const returnRate = inputs.return_rate;
    const baseFee = this.numberOr(inputs.wb_logistics_base_rub, row.dataset.companyType === "general" ? 60 : 46);
    const literFee = this.numberOr(inputs.wb_logistics_liter_rub, 14);

    this.appendProcessStep(steps.volume,
      `${this.number(inputs.length_cm)} * ${this.number(inputs.width_cm)} * ${this.number(inputs.height_cm)} / 1000`,
      intermediate.volume_l, units.liter, ["length_cm", "width_cm", "height_cm"]);
    this.appendProcessStep(steps.billed_volume,
      `ceil(${this.number(intermediate.volume_l)})`,
      intermediate.billed_volume_l, units.liter, ["length_cm", "width_cm", "height_cm"]);
    this.appendProcessStep(steps.return_rate,
      this.percent(returnRate),
      returnRate * 100, units.percent, ["return_rate"],
      "actual_return_rate");
    this.appendProcessStep(steps.base_logistics,
      `${this.number(baseFee)} + (${this.number(intermediate.billed_volume_l)} - 1) * ${this.number(literFee)}`,
      intermediate.base_logistics_rub, units.rub, ["wb_logistics_base_rub", "wb_logistics_liter_rub"], "wb_logistics_tariffs");
    this.appendProcessStep(steps.platform_logistics,
      `${this.number(inputs.fbo_delivery_cny || 0)} + ${this.number(intermediate.base_logistics_rub)} * ${this.number(inputs.logistics_coeff)} / ${this.number(exchange)}`,
      costs.logistics, units.cny, ["fbo_delivery_cny", "logistics_coeff", "exchange_rate_rub_cny"]);

    const fixedReturnFormula = row.dataset.companyType === "general"
      ? `${this.number(this.numberOr(inputs.wb_fixed_return_base_rub, 50))} / ${this.number(exchange)} * ${this.percent(returnRate)} / (1 - ${this.percent(returnRate)})`
      : `${this.number(intermediate.base_logistics_rub)} * (1 - ${this.percent(this.numberOr(inputs.logistics_tax_rate, 0.2))}) / ${this.number(exchange)}`;
    this.appendProcessStep(steps.returns,
      `${this.number(intermediate.platform_logistics_cny)} * ${this.percent(returnRate)} / (1 - ${this.percent(returnRate)}) + (${fixedReturnFormula})`,
      costs.returns, units.cny, ["return_rate", "wb_fixed_return_base_rub", "logistics_tax_rate", "exchange_rate_rub_cny"]);
  }

  appendOzonProcessSteps(row, inputs, costs, intermediate, steps, units) {
    const exchange = inputs.exchange_rate_rub_cny;
    const returnRate = this.numberOr(inputs.return_rate, 0.1);
    const factorOverride = inputs.return_amortization_factor_override;
    const factorFormula = factorOverride === undefined || factorOverride === null || factorOverride === ""
      ? `${this.percent(returnRate)} / (1 - ${this.percent(returnRate)})`
      : this.number(factorOverride);
    this.appendProcessStep(steps.volume,
      `${this.number(inputs.length_cm)} * ${this.number(inputs.width_cm)} * ${this.number(inputs.height_cm)} / 1000`,
      intermediate.volume_l, units.liter, ["length_cm", "width_cm", "height_cm"]);
    this.appendProcessStep(steps.billed_volume,
      `ceil(${this.number(intermediate.volume_l)})`,
      intermediate.billed_volume_l, units.liter, ["length_cm", "width_cm", "height_cm"]);
    this.appendProcessStep(steps.return_rate,
      this.percent(returnRate),
      returnRate * 100, units.percent, ["return_rate"],
      "actual_return_rate");
    this.appendProcessStep(steps.platform_logistics,
      `(${this.number(inputs.outbound_logistics_rub)} + ${this.number(inputs.warehouse_operation_rub)} + ${this.number(intermediate.warehouse_surcharge_rub)}) / ${this.number(exchange)}`,
      costs.logistics, units.cny, ["outbound_logistics_rub", "return_logistics_rub", "warehouse_operation_rub", "exchange_rate_rub_cny"],
      "ozon_logistics_tariffs");
    const crossDockingApplicable = row.dataset.market === "ru";
    this.appendProcessStep(
      steps.cross_docking,
      crossDockingApplicable
        ? this.number(inputs.cross_docking_cny || 0)
        : this.messagesValue.process.cross_docking_not_applicable,
      crossDockingApplicable ? inputs.cross_docking_cny || 0 : 0,
      units.cny,
      crossDockingApplicable ? ["cross_docking_cny"] : [],
      crossDockingApplicable ? "ozon_cross_dock_tariffs" : null
    );
    this.appendProcessStep(steps.return_amortized,
      `(${this.number(inputs.outbound_logistics_rub)} + ${this.number(inputs.return_logistics_rub)}) * (${factorFormula}) / ${this.number(exchange)}`,
      costs.returns, units.cny,
      ["outbound_logistics_rub", "return_logistics_rub", "return_amortization_factor_override", "return_rate", "exchange_rate_rub_cny"]);
  }

  appendCommonCostSteps(row, inputs, costs, data, steps, units) {
    const revenue = data.revenue_cny;
    const commissionBase = revenue;
    const rateBase = row.dataset.platform === "ozon" ? data.intermediate?.rf_revenue_cny : revenue;

    this.appendProcessStep(
      steps.storage,
      this.number(inputs.storage_cny || 0),
      costs.storage,
      units.cny,
      ["storage_cny"],
      "actual_storage"
    );
    this.appendProcessStep(steps.commission,
      `${this.number(commissionBase)} * ${this.percent(inputs.commission_rate)}`,
      costs.commission, units.cny, ["commission_rate"], "official_commission");
    this.appendProcessStep(steps.acquiring,
      `${this.number(rateBase)} * ${this.percent(this.numberOr(inputs.acquiring_rate, row.dataset.platform === "ozon" ? 0.02 : 0))}`,
      costs.acquiring, units.cny, ["acquiring_rate"]);
    this.appendProcessStep(steps.advertising,
      `${this.number(rateBase)} * ${this.percent(inputs.advertising_rate || 0)}`,
      costs.advertising, units.cny, ["advertising_rate"], "actual_advertising");

    const taxFormula = this.taxFormula(row, inputs, data);
    this.appendProcessStep(steps.tax, taxFormula, costs.tax, units.cny, ["tax_rate", "sales_vat_rate"]);
    this.appendProcessStep(steps.other, this.otherCostFormula(row, inputs, costs), costs.other, units.cny, ["damage_rate", "misc_cny", "other_cny", "cross_docking_cny"]);
    this.appendProcessStep(steps.total_cost, this.messagesValue.process.sum_costs, data.total_cost_cny, units.cny);
    this.appendProcessStep(steps.profit,
      `${this.number(revenue)} - ${this.number(data.total_cost_cny)}`,
      data.profit_cny, units.cny);
    this.appendProcessStep(steps.margin,
      `${this.number(data.profit_cny)} / ${this.number(revenue)}`,
      Number(data.margin) * 100, units.percent);
  }

  taxFormula(row, inputs, data) {
    if (row.dataset.platform === "ozon" && row.dataset.market !== "by") return "0";
    if (row.dataset.companyType === "small") {
      return `${this.number(data.revenue_cny)} * ${this.percent(this.numberOr(inputs.tax_rate, 0.06))}`;
    }

    const rate = this.numberOr(inputs.sales_vat_rate, 0.2);
    return `${this.number(data.revenue_cny)} * ${this.percent(rate)} / (1 + ${this.percent(rate)}) - ${this.number(data.cost_breakdown?.import_vat)}`;
  }

  otherCostFormula(row, inputs, costs) {
    if (row.dataset.platform === "ozon") {
      const crossDocking = row.dataset.market === "ru" ? inputs.cross_docking_cny || 0 : 0;
      return `${this.number(crossDocking)} + ${this.number(inputs.other_cny || 0)}`;
    }

    return `(${this.number(costs.goods)} + ${this.number(costs.import_vat)} + ${this.number(costs.duty)}) * ${this.percent(inputs.damage_rate || 0)} + ${this.number(inputs.misc_cny || 0)} + ${this.number(inputs.other_cny || 0)}`;
  }

  appendProcessStep(label, formula, result, unit, parameterFields = [], sourceKey = null) {
    const stepIndex = this.processStepIndex++;
    let row = this.detailBodyTarget.querySelector(`[data-process-step-index='${stepIndex}']`);
    if (!row) {
      row = document.createElement("tr");
      row.dataset.processStepIndex = stepIndex;
      row.append(document.createElement("td"), document.createElement("td"), document.createElement("td"), document.createElement("td"));
      this.detailBodyTarget.append(row);
    }
    const [itemCell, parameterCell, sourceCell, calculationCell] = row.children;
    let formulaElement = calculationCell.querySelector(".profit-prediction-process__formula");
    let resultElement = calculationCell.querySelector(".profit-prediction-process__result");
    if (!formulaElement || !resultElement) {
      calculationCell.replaceChildren();
      formulaElement = document.createElement("span");
      resultElement = document.createElement("strong");
      formulaElement.className = "profit-prediction-process__formula";
      resultElement.className = "profit-prediction-process__result";
      calculationCell.append(formulaElement, resultElement);
    }

    itemCell.textContent = label;
    parameterCell.className = "profit-prediction-process__parameters";
    const newFields = parameterFields.filter((field) => !this.renderedProcessParameters.has(field));
    this.renderProcessParameters(parameterCell, this.selectedRow, newFields).forEach((field) => {
      this.renderedProcessParameters.add(field);
    });
    this.renderProcessSource(sourceCell, sourceKey);
    calculationCell.className = "profit-prediction-process__calculation";
    formulaElement.textContent = formula;
    resultElement.textContent = this.formatProcessResult(result, unit);
    row.classList.toggle("is-incomplete", parameterFields.some((field) => this.processInvalidFields?.has(field)));
  }

  renderProcessSource(cell, sourceKey) {
    cell.className = "profit-prediction-process__source";
    if (!sourceKey) {
      cell.replaceChildren();
      delete cell.dataset.sourceKey;
      return;
    }
    const sourceRowKey = this.selectedRow?.dataset.rowKey || "";
    if (cell.dataset.sourceKey === sourceKey && cell.dataset.sourceRowKey === sourceRowKey) {
      if (sourceKey === "actual_storage") {
        const data = this.actualStorageData.get(this.selectedRow?.dataset.platform);
        if (data) this.renderActualStorageResult(cell, data);
      }
      return;
    }

    if (sourceKey === "ozon_logistics_tariffs") {
      this.renderOzonLogisticsSources(cell);
      cell.dataset.sourceKey = sourceKey;
      cell.dataset.sourceRowKey = sourceRowKey;
      return;
    }
    if (sourceKey === "actual_selling_price") {
      this.renderActualSellingPriceSource(cell);
      cell.dataset.sourceKey = sourceKey;
      cell.dataset.sourceRowKey = sourceRowKey;
      return;
    }
    if (sourceKey === "actual_return_rate") {
      this.renderActualReturnRateSource(cell);
      cell.dataset.sourceKey = sourceKey;
      cell.dataset.sourceRowKey = sourceRowKey;
      return;
    }
    if (sourceKey === "actual_advertising") {
      this.renderActualAdvertisingSource(cell);
      cell.dataset.sourceKey = sourceKey;
      cell.dataset.sourceRowKey = sourceRowKey;
      return;
    }
    if (sourceKey === "official_commission") {
      this.renderOfficialCommissionSource(cell);
      cell.dataset.sourceKey = sourceKey;
      cell.dataset.sourceRowKey = sourceRowKey;
      return;
    }
    if (sourceKey === "ozon_cross_dock_tariffs") {
      this.renderOzonCrossDockSource(cell);
      cell.dataset.sourceKey = sourceKey;
      cell.dataset.sourceRowKey = sourceRowKey;
      return;
    }
    if (sourceKey === "wb_logistics_tariffs") {
      this.renderWbLogisticsSource(cell);
      cell.dataset.sourceKey = sourceKey;
      cell.dataset.sourceRowKey = sourceRowKey;
      return;
    }
    if (sourceKey === "actual_storage") {
      this.renderActualStorageSource(cell);
      cell.dataset.sourceKey = sourceKey;
      cell.dataset.sourceRowKey = sourceRowKey;
      return;
    }

    cell.replaceChildren();
    cell.dataset.sourceKey = sourceKey;
    cell.dataset.sourceRowKey = sourceRowKey;
  }

  renderOzonLogisticsSources(cell) {
    const actions = document.createElement("div");
    actions.className = "profit-prediction-process__source-actions";

    actions.append(
      this.sourceButton("bi-table", this.messagesValue.process.sources.ozon_tariffs, "profit-prediction#openOzonTariffs"),
      this.sourceButton("bi-clock-history", this.messagesValue.process.sources.actual_logistics.action, "profit-prediction#loadActualLogistics")
    );
    const logisticsResult = document.createElement("div");
    logisticsResult.className = "profit-prediction-process__source-result";
    logisticsResult.dataset.actualLogisticsResult = "";
    cell.replaceChildren(actions, logisticsResult);
    if (this.actualLogisticsLoaded && this.actualMetricsData) this.renderActualLogisticsResult(cell, this.actualMetricsData);
  }

  renderActualSellingPriceSource(cell) {
    const actions = document.createElement("div");
    actions.className = "profit-prediction-process__source-actions";
    actions.append(
      this.sourceButton("bi-clock-history", this.messagesValue.process.sources.actual_selling_price.action, "profit-prediction#loadActualSellingPrice")
    );
    const result = document.createElement("div");
    result.className = "profit-prediction-process__source-result";
    result.dataset.actualSellingPriceResult = "";
    cell.replaceChildren(actions, result);

    const data = this.actualSellingPriceData.get(this.actualSellingPriceKey(this.selectedRow));
    if (data) this.renderActualSellingPriceResult(cell, data);
  }

  renderActualReturnRateSource(cell) {
    const actions = document.createElement("div");
    actions.className = "profit-prediction-process__source-actions";
    actions.append(
      this.sourceButton("bi-arrow-return-left", this.messagesValue.process.sources.actual_return_rate.action, "profit-prediction#loadActualReturnRate")
    );
    const result = document.createElement("div");
    result.className = "profit-prediction-process__source-result";
    result.dataset.actualReturnRateResult = "";
    cell.replaceChildren(actions, result);
    const data = this.actualReturnRateData.get(this.selectedRow?.dataset.platform);
    if (data) this.renderActualReturnRateResult(cell, data);
  }

  renderActualAdvertisingSource(cell) {
    const actions = document.createElement("div");
    actions.className = "profit-prediction-process__source-actions";
    actions.append(
      this.sourceButton("bi-megaphone", this.messagesValue.process.sources.actual_advertising.action, "profit-prediction#loadActualAdvertising")
    );
    const result = document.createElement("div");
    result.className = "profit-prediction-process__source-result";
    result.dataset.actualAdvertisingResult = "";
    cell.replaceChildren(actions, result);

    const platform = this.selectedRow?.dataset.platform;
    const data = this.actualAdvertisingData.get(platform);
    if (data) this.renderActualAdvertisingResult(cell, data);
  }

  renderOfficialCommissionSource(cell) {
    const actions = document.createElement("div");
    actions.className = "profit-prediction-process__source-actions";
    actions.append(
      this.sourceButton("bi-percent", this.messagesValue.process.sources.official_commission.action, "profit-prediction#loadOfficialCommission")
    );
    const result = document.createElement("div");
    result.className = "profit-prediction-process__source-result";
    result.dataset.officialCommissionResult = "";
    cell.replaceChildren(actions, result);

    const data = this.officialCommissionData.get(this.officialCommissionKey(this.selectedRow));
    if (data) this.renderOfficialCommissionResult(cell, data);
  }

  renderOzonCrossDockSource(cell) {
    const actions = document.createElement("div");
    actions.className = "profit-prediction-process__source-actions";
    actions.append(
      this.sourceButton("bi-table", this.messagesValue.process.sources.cross_dock_tariffs.action, "profit-prediction#openCrossDockTariffs"),
      this.sourceButton("bi-clock-history", this.messagesValue.process.sources.actual_cross_dock.action, "profit-prediction#loadActualCrossDock")
    );
    const result = document.createElement("div");
    result.className = "profit-prediction-process__source-result";
    result.dataset.actualCrossDockResult = "";
    cell.replaceChildren(actions, result);
    if (this.actualCrossDockLoaded && this.actualMetricsData) this.renderActualCrossDockResult(cell, this.actualMetricsData);
  }

  renderWbLogisticsSource(cell) {
    const button = this.sourceButton(
      "bi-truck",
      this.messagesValue.process.sources.wb_logistics_tariffs.action,
      "profit-prediction#openWbLogisticsTariffs"
    );
    cell.replaceChildren(button);
  }

  renderActualStorageSource(cell) {
    const actions = document.createElement("div");
    actions.className = "profit-prediction-process__source-actions";
    actions.append(
      this.sourceButton("bi-clock-history", this.messagesValue.process.sources.actual_storage.action, "profit-prediction#loadActualStorage")
    );
    const result = document.createElement("div");
    result.className = "profit-prediction-process__source-result";
    result.dataset.actualStorageResult = "";
    cell.replaceChildren(actions, result);
    const data = this.actualStorageData.get(this.selectedRow?.dataset.platform);
    if (data) this.renderActualStorageResult(cell, data);
  }

  sourceButton(iconClass, text, action) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "btn btn-outline btn-sm";
    button.dataset.action = action;
    const icon = document.createElement("i");
    icon.className = `bi ${iconClass}`;
    icon.setAttribute("aria-hidden", "true");
    const label = document.createElement("span");
    label.textContent = text;
    button.append(icon, label);
    return button;
  }

  async loadActualLogistics(event) {
    await this.loadActualMetrics(event, "logistics");
  }

  async loadActualReturnRate(event) {
    await this.loadActualMetrics(event, "return-rate");
  }

  async loadActualCrossDock(event) {
    await this.loadActualMetrics(event, "cross-dock");
  }

  async loadActualStorage(event) {
    if (!this.selectedRow) return;

    const row = this.selectedRow;
    const platform = row.dataset.platform;
    const cell = event.currentTarget.closest(".profit-prediction-process__source");
    const result = cell?.querySelector("[data-actual-storage-result]");
    const messages = this.messagesValue.process.sources.actual_storage;
    this.actualStorageRequestController?.abort();
    const controller = new AbortController();
    this.actualStorageRequestController = controller;
    event.currentTarget.disabled = true;
    if (result) result.textContent = messages.loading;

    try {
      const url = new URL(this.actualStorageUrlValue, window.location.origin);
      url.searchParams.set("platform", platform);
      const response = await fetch(url, { headers: { Accept: "application/json" }, signal: controller.signal });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);

      const data = await response.json();
      this.actualStorageData.set(platform, data);
      if (this.selectedRow === row && cell?.isConnected) this.renderActualStorageResult(cell, data);
    } catch (error) {
      if (error.name !== "AbortError" && result?.isConnected) {
        result.className = "profit-prediction-process__source-result is-error";
        result.textContent = messages.load_failed;
      }
    } finally {
      if (this.actualStorageRequestController === controller) this.actualStorageRequestController = null;
      if (event.currentTarget.isConnected) event.currentTarget.disabled = false;
    }
  }

  async loadActualAdvertising(event) {
    if (!this.selectedRow) return;

    const platform = this.selectedRow.dataset.platform;
    const cell = event.currentTarget.closest(".profit-prediction-process__source");
    const result = cell?.querySelector("[data-actual-advertising-result]");
    const messages = this.messagesValue.process.sources.actual_advertising;
    this.actualAdvertisingRequestController?.abort();
    const controller = new AbortController();
    this.actualAdvertisingRequestController = controller;
    event.currentTarget.disabled = true;
    if (result) result.textContent = messages.loading;

    try {
      const url = new URL(this.actualAdvertisingUrlValue, window.location.origin);
      url.searchParams.set("platform", platform);
      const response = await fetch(url, {
        headers: { Accept: "application/json" },
        signal: controller.signal
      });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);

      const data = await response.json();
      this.actualAdvertisingData.set(platform, data);
      if (this.selectedRow?.dataset.platform === platform) this.renderActualAdvertisingResult(cell, data);
    } catch (error) {
      if (error.name !== "AbortError" && result) {
        result.className = "profit-prediction-process__source-result is-error";
        result.textContent = messages.load_failed;
      }
    } finally {
      if (this.actualAdvertisingRequestController === controller) this.actualAdvertisingRequestController = null;
      if (event.currentTarget.isConnected) event.currentTarget.disabled = false;
    }
  }

  async loadOfficialCommission(event) {
    if (!this.selectedRow) return;

    const row = this.selectedRow;
    const key = this.officialCommissionKey(row);
    const cell = event.currentTarget.closest(".profit-prediction-process__source");
    const result = cell?.querySelector("[data-official-commission-result]");
    const messages = this.messagesValue.process.sources.official_commission;
    this.officialCommissionRequestController?.abort();
    const controller = new AbortController();
    this.officialCommissionRequestController = controller;
    event.currentTarget.disabled = true;
    if (result) result.textContent = messages.loading;

    try {
      const url = new URL(this.officialCommissionUrlValue, window.location.origin);
      url.searchParams.set("platform", row.dataset.platform);
      url.searchParams.set("delivery_mode", row.dataset.deliveryMode);
      const response = await fetch(url, {
        headers: { Accept: "application/json" },
        signal: controller.signal
      });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);

      const data = await response.json();
      this.officialCommissionData.set(key, data);
      if (this.officialCommissionKey(this.selectedRow) === key) this.renderOfficialCommissionResult(cell, data);
    } catch (error) {
      if (error.name !== "AbortError" && result) {
        result.className = "profit-prediction-process__source-result is-error";
        result.textContent = messages.load_failed;
      }
    } finally {
      if (this.officialCommissionRequestController === controller) this.officialCommissionRequestController = null;
      if (event.currentTarget.isConnected) event.currentTarget.disabled = false;
    }
  }

  officialCommissionKey(row) {
    return row ? `${row.dataset.platform}:${row.dataset.deliveryMode}` : "";
  }

  renderOfficialCommissionResult(cell, data) {
    const container = cell?.querySelector("[data-official-commission-result]");
    if (!container) return;

    const messages = this.messagesValue.process.sources.official_commission;
    const rates = Array.isArray(data.rates) ? data.rates : [];
    if (rates.length === 0) {
      container.className = "profit-prediction-process__source-result is-empty";
      container.textContent = messages.empty;
      return;
    }

    const multipleRates = rates.length > 1;
    const links = rates.map((entry) => {
      const rate = Number(entry.rate);
      const link = document.createElement("button");
      link.type = "button";
      link.className = "profit-prediction-process__source-link";
      link.dataset.action = "profit-prediction#applyOfficialCommission";
      link.dataset.commissionRate = entry.rate;
      link.title = messages.apply;
      link.textContent = (multipleRates ? messages.result_with_products : messages.result)
        .replace("__RATE__", this.percent(rate))
        .replace("__COUNT__", entry.product_count ?? 0);
      link.disabled = this.readonlyValue;
      return link;
    });

    const meta = document.createElement("small");
    meta.textContent = messages.meta
      .replace("__RESOLVED__", data.resolved_count ?? 0)
      .replace("__TOTAL__", data.binding_count ?? 0)
      .replace("__FIELD__", data.source?.field || "-")
      .replace("__SYNCED_AT__", this.localizedTimestamp(data.source?.synced_at));
    container.className = "profit-prediction-process__source-result";
    container.replaceChildren(...links, meta);
  }

  applyOfficialCommission(event) {
    if (!this.selectedRow || this.readonlyValue) return;

    const input = this.selectedRow.querySelector("[data-field='commission_rate']");
    const rate = event.currentTarget.dataset.commissionRate;
    if (!input || rate === undefined || rate === "") return;

    input.value = shortcutInputValue(rate);
    input.dataset.valueChanged = "true";
    this.inputChanged({ target: input, type: "official-commission" });
    this.schedulePreview(this.selectedRow);
  }

  openWbLogisticsTariffs() {
    if (!this.selectedRow || this.selectedRow.dataset.platform !== "wb" || !this.hasWbLogisticsDialogTarget) return;

    const mode = this.selectedRow.dataset.deliveryMode || "fbo";
    this.wbLogisticsModeTarget.textContent = mode.toUpperCase();
    this.wbLogisticsWarehouseTarget.value = "";
    this.wbLogisticsGeoTarget.value = "";
    if (!this.wbLogisticsDialogTarget.open) this.wbLogisticsDialogTarget.showModal();
    this.loadWbLogisticsTariffs();
  }

  closeWbLogisticsDialog() {
    this.wbLogisticsRequestController?.abort();
    if (this.hasWbLogisticsDialogTarget && this.wbLogisticsDialogTarget.open) this.wbLogisticsDialogTarget.close();
  }

  closeWbLogisticsDialogOnBackdrop(event) {
    if (event.target === this.wbLogisticsDialogTarget) this.closeWbLogisticsDialog();
  }

  applyWbLogisticsFilters() {
    this.loadWbLogisticsTariffs();
  }

  useWbLogisticsAverage() {
    const messages = this.messagesValue.process.sources.wb_logistics_tariffs;
    if (!this.selectedRow) {
      this.renderWbLogisticsActionMessage(messages.no_selected_row, true);
      return;
    }

    const filter = this.wbLogisticsFilter || {};
    if (![filter.average_logistics_coeff, filter.average_base_rub, filter.average_liter_rub].every((value) => Number.isFinite(Number(value)))) {
      this.renderWbLogisticsActionMessage(messages.no_average, true);
      return;
    }

    this.applyWbLogisticsRate(filter);
  }

  useWbLogisticsRate(event) {
    this.applyWbLogisticsRate({
      logistics_coeff: event.currentTarget.dataset.logisticsCoeff,
      base_rub: event.currentTarget.dataset.baseRub,
      liter_rub: event.currentTarget.dataset.literRub
    });
  }

  async loadWbLogisticsTariffs() {
    if (!this.selectedRow || this.selectedRow.dataset.platform !== "wb") return;

    const messages = this.messagesValue.process.sources.wb_logistics_tariffs;
    this.wbLogisticsRequestController?.abort();
    const controller = new AbortController();
    this.wbLogisticsRequestController = controller;
    if (this.hasWbLogisticsUseAverageTarget) this.wbLogisticsUseAverageTarget.disabled = true;
    this.renderWbLogisticsActionMessage("");
    this.renderWbLogisticsMessage(messages.loading);

    const url = new URL(this.wbLogisticsTariffUrlValue, window.location.origin);
    url.searchParams.set("delivery_mode", this.selectedRow.dataset.deliveryMode || "fbo");
    const warehouse = this.wbLogisticsWarehouseTarget.value.trim();
    const geo = this.wbLogisticsGeoTarget.value.trim();
    if (warehouse) url.searchParams.set("warehouse", warehouse);
    if (geo) url.searchParams.set("geo", geo);

    try {
      const response = await fetch(url, { headers: { Accept: "application/json" }, signal: controller.signal });
      const data = await response.json();
      if (!response.ok) {
        const error = new Error(`HTTP ${response.status}`);
        error.payload = data;
        throw error;
      }
      this.renderWbLogisticsTariffs(data);
    } catch (error) {
      if (error.name === "AbortError") return;
      const message = error.payload?.errors?.includes("wb_api_token_unavailable")
        ? messages.api_token_unavailable
        : error.payload?.errors?.includes("wb_logistics_tariff_snapshot_unavailable")
          ? messages.snapshot_unavailable
          : messages.load_failed;
      this.renderWbLogisticsMessage(message, true);
    } finally {
      if (this.wbLogisticsRequestController === controller) this.wbLogisticsRequestController = null;
    }
  }

  renderWbLogisticsTariffs(data) {
    const messages = this.messagesValue.process.sources.wb_logistics_tariffs;
    const filter = data.filter || {};
    this.wbLogisticsFilter = filter;
    this.wbLogisticsSnapshotTarget.textContent = [data.source?.effective_from, data.source?.effective_to].filter(Boolean).join(" — ") || "-";
    this.wbLogisticsMatchedTarget.textContent = String(filter.matched_count ?? 0);
    this.wbLogisticsAverageBaseTarget.textContent = this.number(filter.average_base_rub);
    this.wbLogisticsAverageCoeffTarget.textContent = this.number(filter.average_logistics_coeff);
    this.wbLogisticsAverageLiterTarget.textContent = this.number(filter.average_liter_rub);
    this.wbLogisticsUseAverageTarget.disabled = ![
      filter.average_logistics_coeff, filter.average_base_rub, filter.average_liter_rub
    ].every((value) => Number.isFinite(Number(value)));
    this.renderWbLogisticsActionMessage("");

    this.wbLogisticsBodyTarget.replaceChildren();
    if (!data.rows?.length) {
      this.renderWbLogisticsMessage(messages.empty);
      return;
    }

    data.rows.forEach((tariff) => {
      const row = document.createElement("tr");
      [tariff.warehouse_name, tariff.geo_name].forEach((value) => {
        const cell = document.createElement("td");
        cell.textContent = value || "-";
        row.append(cell);
      });
      [tariff.base_rub, tariff.logistics_coeff, tariff.liter_rub].forEach((value) => {
        const cell = document.createElement("td");
        cell.className = "numeric";
        cell.textContent = this.number(value);
        row.append(cell);
      });
      const operation = document.createElement("td");
      const button = document.createElement("button");
      button.type = "button";
      button.className = "btn btn-outline btn-sm";
      button.dataset.action = "profit-prediction#useWbLogisticsRate";
      button.dataset.baseRub = tariff.base_rub;
      button.dataset.logisticsCoeff = tariff.logistics_coeff;
      button.dataset.literRub = tariff.liter_rub;
      button.textContent = messages.use_rate;
      operation.append(button);
      row.append(operation);
      this.wbLogisticsBodyTarget.append(row);
    });
  }

  renderWbLogisticsMessage(message, error = false) {
    if (!this.hasWbLogisticsBodyTarget) return;
    const row = document.createElement("tr");
    const cell = document.createElement("td");
    cell.colSpan = 6;
    cell.className = error ? "empty-state is-error" : "empty-state";
    cell.textContent = message;
    row.append(cell);
    this.wbLogisticsBodyTarget.replaceChildren(row);
  }

  renderWbLogisticsActionMessage(message, error = false) {
    if (!this.hasWbLogisticsActionMessageTarget) return;
    this.wbLogisticsActionMessageTarget.textContent = message || "";
    this.wbLogisticsActionMessageTarget.classList.toggle("is-error", Boolean(error));
  }

  applyWbLogisticsRate(rate) {
    if (!this.selectedRow || this.readonlyValue) return;
    const values = {
      logistics_coeff: rate.logistics_coeff,
      wb_logistics_base_rub: rate.base_rub,
      wb_logistics_liter_rub: rate.liter_rub
    };
    Object.entries(values).forEach(([field, value]) => {
      const input = this.selectedRow.querySelector(`[data-field='${field}']`);
      if (!input || value === undefined || value === null) return;
      input.value = shortcutInputValue(value);
      input.dataset.valueChanged = "true";
      this.inputChanged({ target: input, type: "wb-logistics-tariff" });
    });
    this.schedulePreview(this.selectedRow);
    this.closeWbLogisticsDialog();
  }

  localizedTimestamp(value) {
    if (!value) return "-";

    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? value : date.toLocaleString(document.documentElement.lang || undefined);
  }

  async loadActualSellingPrice(event) {
    if (!this.selectedRow) return;

    const row = this.selectedRow;
    const key = this.actualSellingPriceKey(row);
    const cell = event.currentTarget.closest(".profit-prediction-process__source");
    const result = cell?.querySelector("[data-actual-selling-price-result]");
    const messages = this.messagesValue.process.sources.actual_selling_price;
    this.actualSellingPriceRequestController?.abort();
    const controller = new AbortController();
    this.actualSellingPriceRequestController = controller;
    event.currentTarget.disabled = true;
    if (result) result.textContent = messages.loading;

    try {
      const url = new URL(this.actualSellingPriceUrlValue, window.location.origin);
      url.searchParams.set("platform", row.dataset.platform);
      url.searchParams.set("market", row.dataset.market);
      const response = await fetch(url, {
        headers: { Accept: "application/json" },
        signal: controller.signal
      });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);

      const data = await response.json();
      this.actualSellingPriceData.set(key, data);
      if (this.actualSellingPriceKey(this.selectedRow) === key) this.renderActualSellingPriceResult(cell, data);
    } catch (error) {
      if (error.name !== "AbortError" && result) {
        result.className = "profit-prediction-process__source-result is-error";
        result.textContent = messages.load_failed;
      }
    } finally {
      if (this.actualSellingPriceRequestController === controller) this.actualSellingPriceRequestController = null;
      if (event.currentTarget.isConnected) event.currentTarget.disabled = false;
    }
  }

  actualSellingPriceKey(row) {
    return row ? `${row.dataset.platform}:${row.dataset.market}` : "";
  }

  renderActualSellingPriceResult(cell, data) {
    const container = cell?.querySelector("[data-actual-selling-price-result]");
    if (!container) return;

    const rawPrice = data.price?.average_rub;
    const priceRub = rawPrice === null || rawPrice === undefined || rawPrice === "" ? NaN : Number(rawPrice);
    const messages = this.messagesValue.process.sources.actual_selling_price;
    if (!Number.isFinite(priceRub)) {
      container.className = data.price?.missing_exchange_rate_item_count > 0
        ? "profit-prediction-process__source-result is-error"
        : "profit-prediction-process__source-result is-empty";
      container.textContent = data.price?.missing_exchange_rate_item_count > 0 ? messages.missing_rate : messages.empty;
      return;
    }

    const link = document.createElement("button");
    link.type = "button";
    link.className = "profit-prediction-process__source-link";
    link.dataset.action = "profit-prediction#applyActualSellingPrice";
    link.dataset.priceRub = priceRub;
    link.title = messages.apply;
    link.textContent = messages.result.replace("__PRICE__", `${this.number(priceRub)} RUB`);
    link.disabled = this.readonlyValue;

    const sourceCurrency = data.price?.source_currency || "RUB";
    const sourceAverage = Number(data.price?.average_source);
    const source = sourceCurrency !== "RUB" && Number.isFinite(sourceAverage) ? document.createElement("small") : null;
    if (source) {
      source.textContent = messages.converted_source
        .replace("__SOURCE_PRICE__", this.number(sourceAverage))
        .replace("__SOURCE_CURRENCY__", sourceCurrency)
        .replace("__RUB_PRICE__", this.number(priceRub));
    }

    const meta = document.createElement("small");
    meta.textContent = messages.meta
      .replace("__ITEMS__", data.price?.item_count ?? 0)
      .replace("__UNITS__", data.price?.unit_count ?? 0)
      .replace("__FROM__", data.period?.from_date || "-")
      .replace("__TO__", data.period?.to_date || "-")
      .replace("__DATA_THROUGH__", data.period?.data_through || "-");
    container.className = "profit-prediction-process__source-result";
    container.replaceChildren(link, ...[source, meta].filter(Boolean));
  }

  applyActualSellingPrice(event) {
    if (!this.selectedRow || this.readonlyValue) return;

    const input = this.selectedRow.querySelector("[data-field='price_rub']");
    const price = event.currentTarget.dataset.priceRub;
    if (!input || price === undefined || price === "") return;

    input.value = shortcutInputValue(price);
    input.dataset.valueChanged = "true";
    this.inputChanged({ target: input, type: "actual-selling-price" });
    this.schedulePreview(this.selectedRow);
  }

  async loadActualMetrics(event, kind) {
    if (!this.selectedRow) return;

    const platform = this.selectedRow.dataset.platform;
    if (kind !== "return-rate" && platform !== "ozon") return;

    this.actualMetricsRequestController?.abort();
    const controller = new AbortController();
    this.actualMetricsRequestController = controller;
    const cell = event.currentTarget.closest(".profit-prediction-process__source");
    const resultSelector = {
      "return-rate": "[data-actual-return-rate-result]",
      "cross-dock": "[data-actual-cross-dock-result]"
    }[kind] || "[data-actual-logistics-result]";
    const result = cell?.querySelector(resultSelector);
    const messages = {
      "return-rate": this.messagesValue.process.sources.actual_return_rate,
      "cross-dock": this.messagesValue.process.sources.actual_cross_dock
    }[kind] || this.messagesValue.process.sources.actual_logistics;
    event.currentTarget.disabled = true;
    if (result) result.textContent = messages.loading;

    try {
      const url = kind === "return-rate"
        ? new URL(this.actualReturnRateUrlValue, window.location.origin)
        : new URL(this.actualLogisticsUrlValue, window.location.origin);
      if (kind === "return-rate") url.searchParams.set("platform", platform);
      const response = await fetch(url, {
        headers: { Accept: "application/json" },
        signal: controller.signal
      });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);

      const data = await response.json();
      if (kind === "return-rate") {
        this.actualReturnRateData.set(platform, data);
        if (this.selectedRow?.dataset.platform === platform) this.renderActualReturnRateResult(cell, data);
      } else if (kind === "cross-dock") {
        this.actualMetricsData = data;
        this.actualCrossDockLoaded = true;
        if (this.selectedRow?.dataset.platform === "ozon") this.renderActualCrossDockResult(cell, this.actualMetricsData);
      } else {
        this.actualMetricsData = data;
        this.actualLogisticsLoaded = true;
        if (this.selectedRow?.dataset.platform === "ozon") this.renderActualLogisticsResult(cell, this.actualMetricsData);
      }
    } catch (error) {
      if (error.name !== "AbortError" && result) {
        result.className = "profit-prediction-process__source-result is-error";
        result.textContent = messages.load_failed;
      }
    } finally {
      if (this.actualMetricsRequestController === controller) this.actualMetricsRequestController = null;
      if (event.currentTarget.isConnected) event.currentTarget.disabled = false;
    }
  }

  renderActualLogisticsResult(cell, data) {
    const container = cell?.querySelector("[data-actual-logistics-result]");
    if (!container) return;

    const outboundValue = data.outbound?.average_rub;
    const returnValue = data.return?.average_rub;
    const outbound = outboundValue === null || outboundValue === undefined || outboundValue === "" ? NaN : Number(outboundValue);
    const returnRate = returnValue === null || returnValue === undefined || returnValue === "" ? NaN : Number(returnValue);
    if (!Number.isFinite(outbound)) {
      container.className = "profit-prediction-process__source-result is-empty";
      container.textContent = this.messagesValue.process.sources.actual_logistics.empty;
      return;
    }

    const messages = this.messagesValue.process.sources.actual_logistics;
    const link = document.createElement("button");
    link.type = "button";
    link.className = "profit-prediction-process__source-link";
    link.dataset.action = "profit-prediction#applyActualLogistics";
    link.dataset.outboundRate = outbound;
    if (Number.isFinite(returnRate)) link.dataset.returnRate = returnRate;
    link.title = messages.apply;
    const outboundLine = document.createElement("span");
    outboundLine.textContent = `${messages.outbound} ${this.number(outbound)} RUB`;
    link.append(outboundLine);
    if (Number.isFinite(returnRate)) {
      const returnLine = document.createElement("span");
      returnLine.textContent = `${messages.return} ${this.number(returnRate)} RUB`;
      link.append(returnLine);
    }
    link.disabled = this.readonlyValue;

    const meta = document.createElement("small");
    meta.textContent = messages.meta
      .replace("__FROM__", data.period?.from_date || "-")
      .replace("__TO__", data.period?.to_date || "-")
      .replace("__OUTBOUND_COUNT__", data.outbound?.sample_count ?? 0)
      .replace("__RETURN_COUNT__", data.return?.sample_count ?? 0)
      .replace("__DATA_THROUGH__", data.period?.data_through || "-");
    container.className = "profit-prediction-process__source-result";
    container.replaceChildren(link, meta);
  }

  applyActualLogistics(event) {
    if (!this.selectedRow || this.readonlyValue) return;

    const values = {
      outbound_logistics_rub: event.currentTarget.dataset.outboundRate,
      return_logistics_rub: event.currentTarget.dataset.returnRate
    };
    Object.entries(values).forEach(([field, value]) => {
      if (value === undefined || value === "") return;

      const input = this.selectedRow.querySelector(`[data-field='${field}']`);
      if (!input) return;

      input.value = shortcutInputValue(value);
      input.dataset.valueChanged = "true";
      this.inputChanged({ target: input, type: "actual-logistics" });
    });
    this.schedulePreview(this.selectedRow);
  }

  renderActualReturnRateResult(cell, data) {
    const container = cell?.querySelector("[data-actual-return-rate-result]");
    if (!container) return;

    const rawRate = data.return_rate?.rate;
    const rate = rawRate === null || rawRate === undefined || rawRate === "" ? NaN : Number(rawRate);
    const messages = this.messagesValue.process.sources.actual_return_rate;
    if (!Number.isFinite(rate)) {
      container.className = "profit-prediction-process__source-result is-empty";
      container.textContent = messages.empty;
      return;
    }
    if (rate < 0 || rate >= 1) {
      container.className = "profit-prediction-process__source-result is-error";
      container.textContent = messages.unusable.replace("__RATE__", this.percent(rate));
      return;
    }

    const link = document.createElement("button");
    link.type = "button";
    link.className = "profit-prediction-process__source-link";
    link.dataset.action = "profit-prediction#applyActualReturnRate";
    link.dataset.returnRate = rate;
    link.title = messages.apply;
    link.textContent = messages.result.replace("__RATE__", this.percent(rate));
    link.disabled = this.readonlyValue;

    const meta = document.createElement("small");
    meta.textContent = messages.meta
      .replace("__ORDERS__", data.return_rate?.order_count ?? 0)
      .replace("__RETURNS__", data.return_rate?.return_count ?? 0)
      .replace("__FROM__", data.period?.from_date || "-")
      .replace("__TO__", data.period?.to_date || "-")
      .replace("__DATA_THROUGH__", data.period?.data_through || "-");
    container.className = "profit-prediction-process__source-result";
    container.replaceChildren(link, meta);
  }

  applyActualReturnRate(event) {
    if (!this.selectedRow || this.readonlyValue) return;

    const input = this.selectedRow.querySelector("[data-field='return_rate']");
    const rate = event.currentTarget.dataset.returnRate;
    if (!input || rate === undefined || rate === "") return;

    input.value = shortcutInputValue(rate);
    input.dataset.valueChanged = "true";
    this.inputChanged({ target: input, type: "actual-return-rate" });
    this.schedulePreview(this.selectedRow);
  }

  renderActualCrossDockResult(cell, data) {
    const container = cell?.querySelector("[data-actual-cross-dock-result]");
    if (!container) return;

    const rawAmount = data.cross_dock?.average_rub;
    const amountRub = rawAmount === null || rawAmount === undefined || rawAmount === "" ? NaN : Number(rawAmount);
    const messages = this.messagesValue.process.sources.actual_cross_dock;
    if (!Number.isFinite(amountRub)) {
      container.className = "profit-prediction-process__source-result is-empty";
      container.textContent = messages.empty;
      return;
    }

    const link = document.createElement("button");
    link.type = "button";
    link.className = "profit-prediction-process__source-link";
    link.dataset.action = "profit-prediction#applyActualCrossDock";
    link.dataset.amountRub = amountRub;
    link.title = messages.apply;
    link.textContent = messages.result.replace("__AMOUNT__", this.crossDockAmountLabel(amountRub));
    link.disabled = this.readonlyValue;

    const meta = document.createElement("small");
    meta.textContent = messages.meta
      .replace("__COUNT__", data.cross_dock?.sample_count ?? 0)
      .replace("__FROM__", data.period?.from_date || "-")
      .replace("__TO__", data.period?.to_date || "-")
      .replace("__DATA_THROUGH__", data.period?.data_through || "-");
    container.className = "profit-prediction-process__source-result";
    container.replaceChildren(link, meta);
  }

  applyActualCrossDock(event) {
    if (!this.selectedRow || this.readonlyValue) return;

    const amountRub = Number(event.currentTarget.dataset.amountRub);
    const exchange = Number(this.numericInputs(this.selectedRow).exchange_rate_rub_cny);
    const input = this.selectedRow.querySelector("[data-field='cross_docking_cny']");
    if (!input || !Number.isFinite(amountRub) || !Number.isFinite(exchange) || exchange <= 0) return;

    input.value = shortcutInputValue(amountRub / exchange);
    input.dataset.valueChanged = "true";
    this.inputChanged({ target: input, type: "actual-cross-dock" });
    this.schedulePreview(this.selectedRow);
  }

  renderActualStorageResult(cell, data) {
    const container = cell?.querySelector("[data-actual-storage-result]");
    if (!container) return;

    const rawAmount = data.storage?.average_rub;
    const amountRub = rawAmount === null || rawAmount === undefined || rawAmount === "" ? NaN : Number(rawAmount);
    const messages = this.messagesValue.process.sources.actual_storage;
    if (!Number.isFinite(amountRub)) {
      container.className = "profit-prediction-process__source-result is-empty";
      container.textContent = messages.empty;
      return;
    }

    const exchange = Number(this.numericInputs(this.selectedRow).exchange_rate_rub_cny);
    if (!Number.isFinite(exchange) || exchange <= 0) {
      container.className = "profit-prediction-process__source-result is-empty";
      container.textContent = messages.empty;
      return;
    }

    const amountCny = amountRub / exchange;
    const link = document.createElement("button");
    link.type = "button";
    link.className = "profit-prediction-process__source-link";
    link.dataset.action = "profit-prediction#applyActualStorage";
    link.dataset.amountRub = amountRub;
    link.title = messages.apply;
    link.textContent = messages.result.replace("__AMOUNT__", `${this.number(amountCny)} CNY / ${this.number(amountRub)} RUB`);
    link.disabled = this.readonlyValue;

    const meta = document.createElement("small");
    meta.textContent = messages.meta
      .replace("__TOTAL__", `${this.number(data.storage?.total_rub || 0)} RUB`)
      .replace("__COUNT__", data.storage?.sample_count ?? 0)
      .replace("__SALES__", data.storage?.sale_count ?? 0)
      .replace("__FROM__", data.period?.from_date || "-")
      .replace("__TO__", data.period?.to_date || "-")
      .replace("__DATA_THROUGH__", data.period?.data_through || "-");
    container.className = "profit-prediction-process__source-result";
    container.replaceChildren(link, meta);
  }

  applyActualStorage(event) {
    if (!this.selectedRow || this.readonlyValue) return;

    const amountRub = Number(event.currentTarget.dataset.amountRub);
    const exchange = Number(this.numericInputs(this.selectedRow).exchange_rate_rub_cny);
    const input = this.selectedRow.querySelector("[data-field='storage_cny']");
    if (!input || !Number.isFinite(amountRub) || !Number.isFinite(exchange) || exchange <= 0) return;

    input.value = shortcutInputValue(amountRub / exchange);
    input.dataset.valueChanged = "true";
    this.inputChanged({ target: input, type: "actual-storage" });
    this.schedulePreview(this.selectedRow);
  }

  renderActualAdvertisingResult(cell, data) {
    const container = cell?.querySelector("[data-actual-advertising-result]");
    if (!container) return;

    const rawRate = data.rate;
    const rate = rawRate === null || rawRate === undefined || rawRate === "" ? NaN : Number(rawRate);
    const messages = this.messagesValue.process.sources.actual_advertising;
    if (!Number.isFinite(rate) || rate < 0) {
      container.className = "profit-prediction-process__source-result is-empty";
      container.textContent = messages.empty;
      return;
    }

    const link = document.createElement("button");
    link.type = "button";
    link.className = "profit-prediction-process__source-link";
    link.dataset.action = "profit-prediction#applyActualAdvertising";
    link.dataset.advertisingRate = rate;
    link.title = messages.apply;
    link.textContent = messages.result.replace("__RATE__", this.percent(rate));
    link.disabled = this.readonlyValue;

    const currency = data.advertising?.currency || data.sales?.currency || "RUB";
    const meta = document.createElement("small");
    meta.textContent = messages.meta
      .replace("__ADVERTISING__", this.number(data.advertising?.total || 0))
      .replace("__SALES__", this.number(data.sales?.total || 0))
      .replaceAll("__CURRENCY__", currency)
      .replace("__COVERED__", data.coverage?.covered_account_weeks ?? 0)
      .replace("__EXPECTED__", data.coverage?.expected_account_weeks ?? 0)
      .replace("__FROM__", data.period?.from_date || "-")
      .replace("__TO__", data.period?.to_date || "-")
      .replace("__DATA_THROUGH__", data.period?.data_through || "-");

    const quality = document.createElement("small");
    if (data.platform === "ozon") {
      const coverage = Number(data.coverage?.attribution_rate);
      quality.textContent = Number.isFinite(coverage)
        ? messages.ozon_attribution.replace("__COVERAGE__", this.percent(coverage))
        : messages.ozon_attribution.replace("__COVERAGE__", "-");
    } else {
      quality.textContent = data.coverage?.allocation_fallback ? messages.wb_fallback : messages.wb_exact;
      if (data.coverage?.currency_conversion_fallback) quality.textContent += ` · ${messages.currency_fallback}`;
    }

    container.className = "profit-prediction-process__source-result";
    container.replaceChildren(link, meta, quality);
  }

  applyActualAdvertising(event) {
    if (!this.selectedRow || this.readonlyValue) return;

    const input = this.selectedRow.querySelector("[data-field='advertising_rate']");
    const rate = event.currentTarget.dataset.advertisingRate;
    if (!input || rate === undefined || rate === "") return;

    input.value = shortcutInputValue(rate);
    input.dataset.valueChanged = "true";
    this.inputChanged({ target: input, type: "actual-advertising" });
    this.schedulePreview(this.selectedRow);
  }

  openOzonTariffs() {
    if (!this.selectedRow || this.selectedRow.dataset.platform !== "ozon" || !this.hasTariffDialogTarget) return;

    const inputs = this.numericInputs(this.selectedRow);
    const preview = this.previewData.get(this.selectedRow.dataset.rowKey);
    const dimensions = [inputs.length_cm, inputs.width_cm, inputs.height_cm];
    const calculatedVolume = dimensions.every((value) => Number.isFinite(value))
      ? dimensions.reduce((volume, value) => volume * value, 1) / 1000
      : NaN;
    this.tariffVolumeValue = Number(preview?.intermediate?.volume_l ?? calculatedVolume);
    this.tariffVolumeTarget.textContent = Number.isFinite(this.tariffVolumeValue)
      ? `${this.number(this.tariffVolumeValue)} ${this.messagesValue.process.units.liter}`
      : "-";
    if (!this.tariffDialogTarget.open) this.tariffDialogTarget.showModal();
    this.loadOzonTariffs(1);
  }

  closeTariffDialog() {
    this.tariffRequestController?.abort();
    if (this.hasTariffDialogTarget && this.tariffDialogTarget.open) this.tariffDialogTarget.close();
  }

  closeTariffDialogOnBackdrop(event) {
    if (event.target === this.tariffDialogTarget) this.closeTariffDialog();
  }

  applyTariffFilters() {
    this.loadOzonTariffs(1);
  }

  previousTariffPage() {
    if (this.tariffCurrentPage > 1) this.loadOzonTariffs(this.tariffCurrentPage - 1);
  }

  nextTariffPage() {
    if (this.tariffCurrentPage < this.tariffTotalPages) this.loadOzonTariffs(this.tariffCurrentPage + 1);
  }

  useTariffRate(event) {
    this.applyOzonTariffRate(event.currentTarget.dataset.rate);
  }

  useTariffAverage() {
    const messages = this.messagesValue.process.sources.ozon_tariff_feedback;
    if (!this.selectedRow) {
      this.renderTariffActionMessage(messages.no_selected_row, true);
      return;
    }

    const rate = Number(this.tariffAverageRate);
    if (!Number.isFinite(rate)) {
      this.renderTariffActionMessage(messages.no_average, true);
      return;
    }

    this.applyOzonTariffRate(rate);
  }

  async loadOzonTariffs(page) {
    if (this.hasTariffUseAverageTarget) this.tariffUseAverageTarget.disabled = true;
    this.renderTariffActionMessage("");
    if (!Number.isFinite(this.tariffVolumeValue) || this.tariffVolumeValue < 0) {
      this.renderTariffMessage(this.messagesValue.process.sources.missing_volume, true);
      return;
    }

    this.tariffRequestController?.abort();
    const controller = new AbortController();
    this.tariffRequestController = controller;
    this.renderTariffMessage(this.messagesValue.process.sources.loading);
    const originKeys = this.selectedTariffKeys("profit_prediction_ozon_origin_keys[]");
    const destinationKeys = this.selectedTariffKeys("profit_prediction_ozon_destination_keys[]");
    const url = new URL(this.tariffUrlValue, window.location.origin);
    url.searchParams.set("volume_l", this.tariffVolumeValue);
    url.searchParams.set("page", page);
    originKeys.forEach((key) => url.searchParams.append("origin_keys[]", key));
    destinationKeys.forEach((key) => url.searchParams.append("destination_keys[]", key));

    try {
      const response = await fetch(url, { headers: { Accept: "application/json" }, signal: controller.signal });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const data = await response.json();
      this.renderOzonTariffs(data, originKeys, destinationKeys);
    } catch (error) {
      if (error.name !== "AbortError") this.renderTariffMessage(this.messagesValue.process.sources.load_failed, true);
    } finally {
      if (this.tariffRequestController === controller) this.tariffRequestController = null;
    }
  }

  selectedTariffKeys(name) {
    if (!this.hasTariffDialogTarget) return [];

    return Array.from(this.tariffDialogTarget.querySelectorAll(`input[name='${name}']:checked`)).map((input) => input.value);
  }

  renderOzonTariffs(data, originKeys, destinationKeys) {
    const filter = data.route_filter || {};
    const pagination = data.pagination || {};
    this.tariffCurrentPage = Number(pagination.page) || 1;
    this.tariffTotalPages = Number(pagination.pages) || 1;
    this.tariffAverageRate = filter.average_fbo_rub;
    this.tariffVolumeBandTarget.textContent = filter.volume_band_label || "-";
    this.tariffSnapshotTarget.textContent = data.snapshot
      ? `${data.snapshot.effective_from} · ${data.snapshot.source_file_name}`
      : "-";
    this.tariffMatchedCountTarget.textContent = String(filter.matched_count ?? 0);
    this.tariffAverageTarget.textContent = this.tariffAverageRate === null || this.tariffAverageRate === undefined
      ? "-"
      : `${this.number(this.tariffAverageRate)} RUB`;
    // Keep the action clickable after loading so an empty or invalid filter
    // result can explain why nothing can be applied.
    this.tariffUseAverageTarget.disabled = false;
    this.renderTariffActionMessage("");
    this.tariffPreviousTarget.disabled = this.tariffCurrentPage <= 1;
    this.tariffNextTarget.disabled = this.tariffCurrentPage >= this.tariffTotalPages;
    this.tariffPageTarget.textContent = this.messagesValue.process.sources.page
      .replace("__CURRENT__", this.tariffCurrentPage)
      .replace("__TOTAL__", this.tariffTotalPages);

    this.tariffBodyTarget.replaceChildren();
    if (!data.rows?.length) {
      this.renderTariffMessage(this.messagesValue.process.sources.empty);
      return;
    }
    data.rows.forEach((route) => this.tariffBodyTarget.append(this.tariffRouteRow(route)));
  }

  tariffRouteRow(route) {
    const row = document.createElement("tr");
    const origin = document.createElement("td");
    const destination = document.createElement("td");
    const rate = document.createElement("td");
    const operation = document.createElement("td");
    origin.textContent = route.origin_cluster_name;
    destination.textContent = route.destination_cluster_name;
    rate.className = "numeric";
    rate.textContent = `${this.number(route.fbo_rub)} RUB`;
    const button = document.createElement("button");
    button.type = "button";
    button.className = "btn btn-outline btn-sm";
    button.dataset.rate = route.fbo_rub;
    button.dataset.action = "profit-prediction#useTariffRate";
    button.textContent = this.messagesValue.process.sources.use_rate;
    operation.append(button);
    row.append(origin, destination, rate, operation);
    return row;
  }

  renderTariffMessage(message, error = false) {
    if (!this.hasTariffBodyTarget) return;

    const row = document.createElement("tr");
    const cell = document.createElement("td");
    cell.colSpan = 4;
    cell.className = error ? "empty-state is-error" : "empty-state";
    cell.textContent = message;
    row.append(cell);
    this.tariffBodyTarget.replaceChildren(row);
  }

  renderTariffActionMessage(message, error = false) {
    if (!this.hasTariffActionMessageTarget) return;

    this.tariffActionMessageTarget.textContent = message || "";
    this.tariffActionMessageTarget.classList.toggle("is-error", Boolean(error));
  }

  applyOzonTariffRate(rate) {
    const numericRate = Number(rate);
    if (!this.selectedRow || !Number.isFinite(numericRate)) return;

    ["outbound_logistics_rub", "return_logistics_rub"].forEach((field) => {
      const input = this.selectedRow.querySelector(`[data-field='${field}']`);
      if (!input) return;

      input.value = shortcutInputValue(numericRate);
      input.dataset.valueChanged = "true";
      this.inputChanged({ target: input, type: "tariff" });
    });
    this.schedulePreview(this.selectedRow);
    this.closeTariffDialog();
  }

  openCrossDockTariffs() {
    if (!this.selectedRow || this.selectedRow.dataset.platform !== "ozon" || !this.hasCrossDockDialogTarget) return;

    const inputs = this.numericInputs(this.selectedRow);
    const preview = this.previewData.get(this.selectedRow.dataset.rowKey);
    const dimensions = [inputs.length_cm, inputs.width_cm, inputs.height_cm];
    const calculatedVolume = dimensions.every((value) => Number.isFinite(value))
      ? dimensions.reduce((volume, value) => volume * value, 1) / 1000
      : NaN;
    this.crossDockVolumeValue = Number(preview?.intermediate?.volume_l ?? calculatedVolume);
    this.crossDockVolumeTarget.textContent = Number.isFinite(this.crossDockVolumeValue)
      ? `${this.number(this.crossDockVolumeValue)} ${this.messagesValue.process.units.liter}`
      : "-";
    if (!this.crossDockDialogTarget.open) this.crossDockDialogTarget.showModal();
    this.loadCrossDockTariffs(1);
  }

  closeCrossDockDialog() {
    this.crossDockRequestController?.abort();
    if (this.hasCrossDockDialogTarget && this.crossDockDialogTarget.open) this.crossDockDialogTarget.close();
  }

  closeCrossDockDialogOnBackdrop(event) {
    if (event.target === this.crossDockDialogTarget) this.closeCrossDockDialog();
  }

  applyCrossDockFilters() {
    this.loadCrossDockTariffs(1);
  }

  previousCrossDockPage() {
    if (this.crossDockCurrentPage > 1) this.loadCrossDockTariffs(this.crossDockCurrentPage - 1);
  }

  nextCrossDockPage() {
    if (this.crossDockCurrentPage < this.crossDockTotalPages) this.loadCrossDockTariffs(this.crossDockCurrentPage + 1);
  }

  useCrossDockAmount(event) {
    this.applyCrossDockAmount(event.currentTarget.dataset.amountRub);
  }

  useCrossDockAveragePallet() {
    this.applyCrossDockAmount(this.crossDockAveragePalletAmount);
  }

  useCrossDockAverageBox() {
    this.applyCrossDockAmount(this.crossDockAverageBoxAmount);
  }

  async loadCrossDockTariffs(page) {
    const messages = this.messagesValue.process.sources.cross_dock_tariffs;
    if (!Number.isFinite(this.crossDockVolumeValue) || this.crossDockVolumeValue < 0) {
      this.renderCrossDockMessage(messages.missing_volume, true);
      return;
    }

    this.crossDockRequestController?.abort();
    const controller = new AbortController();
    this.crossDockRequestController = controller;
    this.renderCrossDockMessage(messages.loading);
    const supplyZoneKeys = this.selectedCrossDockKeys("profit_prediction_cross_dock_supply_zone_keys[]");
    const destinationKeys = this.selectedCrossDockKeys("profit_prediction_cross_dock_destination_keys[]");
    const url = new URL(this.crossDockTariffUrlValue, window.location.origin);
    url.searchParams.set("volume_l", this.crossDockVolumeValue);
    url.searchParams.set("page", page);
    supplyZoneKeys.forEach((key) => url.searchParams.append("supply_zone_keys[]", key));
    destinationKeys.forEach((key) => url.searchParams.append("destination_keys[]", key));

    try {
      const response = await fetch(url, { headers: { Accept: "application/json" }, signal: controller.signal });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const data = await response.json();
      this.renderCrossDockTariffs(data, supplyZoneKeys, destinationKeys);
    } catch (error) {
      if (error.name !== "AbortError") this.renderCrossDockMessage(messages.load_failed, true);
    } finally {
      if (this.crossDockRequestController === controller) this.crossDockRequestController = null;
    }
  }

  selectedCrossDockKeys(name) {
    if (!this.hasCrossDockDialogTarget) return [];

    return Array.from(this.crossDockDialogTarget.querySelectorAll(`input[name='${name}']:checked`)).map((input) => input.value);
  }

  renderCrossDockTariffs(data, supplyZoneKeys, destinationKeys) {
    const filter = data.cross_dock_filter || {};
    const pagination = data.pagination || {};
    this.crossDockCurrentPage = Number(pagination.page) || 1;
    this.crossDockTotalPages = Number(pagination.pages) || 1;
    this.crossDockAveragePalletAmount = filter.average_pallet_amount_rub;
    this.crossDockAverageBoxAmount = filter.average_box_amount_rub;
    this.crossDockSnapshotTarget.textContent = data.snapshot
      ? `${data.snapshot.effective_from} · ${data.snapshot.source_file_name}`
      : "-";
    this.crossDockMatchedCountTarget.textContent = String(filter.matched_count ?? 0);
    this.crossDockAveragePalletTarget.textContent = this.crossDockAmountLabel(this.crossDockAveragePalletAmount);
    this.crossDockAverageBoxTarget.textContent = this.crossDockAmountLabel(this.crossDockAverageBoxAmount);
    const hasMatchedRoutes = Number(filter.matched_count) > 0;
    this.crossDockUseAveragePalletTarget.disabled = !hasMatchedRoutes || !Number.isFinite(Number(this.crossDockAveragePalletAmount));
    this.crossDockUseAverageBoxTarget.disabled = !hasMatchedRoutes || !Number.isFinite(Number(this.crossDockAverageBoxAmount));
    this.crossDockPreviousTarget.disabled = this.crossDockCurrentPage <= 1;
    this.crossDockNextTarget.disabled = this.crossDockCurrentPage >= this.crossDockTotalPages;
    this.crossDockPageTarget.textContent = this.messagesValue.process.sources.cross_dock_tariffs.page
      .replace("__CURRENT__", this.crossDockCurrentPage)
      .replace("__TOTAL__", this.crossDockTotalPages);

    this.crossDockBodyTarget.replaceChildren();
    if (!data.rows?.length) {
      this.renderCrossDockMessage(this.messagesValue.process.sources.cross_dock_tariffs.empty);
      return;
    }
    data.rows.forEach((route) => this.crossDockBodyTarget.append(this.crossDockRouteRow(route)));
  }

  crossDockRouteRow(route) {
    const row = document.createElement("tr");
    const supplyZone = document.createElement("td");
    const destination = document.createElement("td");
    const pallet = document.createElement("td");
    const box = document.createElement("td");
    const operation = document.createElement("td");
    supplyZone.textContent = route.supply_receiving_zone_name;
    destination.textContent = route.destination_cluster_name;
    pallet.className = "numeric";
    pallet.textContent = `${this.number(route.pallet_rub_per_l)} RUB/L · ${this.crossDockAmountLabel(route.pallet_amount_rub)}`;
    box.className = "numeric";
    box.textContent = `${this.number(route.box_rub_per_l)} RUB/L · ${this.crossDockAmountLabel(route.box_amount_rub)}`;

    const messages = this.messagesValue.process.sources.cross_dock_tariffs;
    const palletButton = this.crossDockUseButton(messages.use_pallet, route.pallet_amount_rub);
    const boxButton = this.crossDockUseButton(messages.use_box, route.box_amount_rub);
    operation.className = "profit-prediction-tariff-dialog__row-actions";
    operation.append(palletButton, boxButton);
    row.append(supplyZone, destination, pallet, box, operation);
    return row;
  }

  crossDockUseButton(label, amountRub) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "btn btn-outline btn-sm";
    button.dataset.amountRub = amountRub;
    button.dataset.action = "profit-prediction#useCrossDockAmount";
    button.textContent = label;
    button.disabled = !Number.isFinite(Number(amountRub));
    return button;
  }

  crossDockAmountLabel(amountRub) {
    const numericAmount = Number(amountRub);
    if (!Number.isFinite(numericAmount)) return "-";

    const exchange = Number(this.numericInputs(this.selectedRow).exchange_rate_rub_cny);
    if (!Number.isFinite(exchange) || exchange <= 0) return `${this.number(numericAmount)} RUB`;

    return `${this.number(numericAmount)} RUB / ${this.number(numericAmount / exchange)} CNY`;
  }

  renderCrossDockMessage(message, error = false) {
    if (!this.hasCrossDockBodyTarget) return;

    const row = document.createElement("tr");
    const cell = document.createElement("td");
    cell.colSpan = 5;
    cell.className = error ? "empty-state is-error" : "empty-state";
    cell.textContent = message;
    row.append(cell);
    this.crossDockBodyTarget.replaceChildren(row);
  }

  applyCrossDockAmount(amountRub) {
    const numericAmount = Number(amountRub);
    if (!this.selectedRow || !Number.isFinite(numericAmount) || this.readonlyValue) return;

    const exchange = Number(this.numericInputs(this.selectedRow).exchange_rate_rub_cny);
    if (!Number.isFinite(exchange) || exchange <= 0) return;
    const input = this.selectedRow.querySelector("[data-field='cross_docking_cny']");
    if (!input) return;

    input.value = shortcutInputValue(numericAmount / exchange);
    input.dataset.valueChanged = "true";
    this.inputChanged({ target: input, type: "cross-dock-tariff" });
    this.schedulePreview(this.selectedRow);
    this.closeCrossDockDialog();
  }

  formatProcessResult(result, unit) {
    const sourceCurrency = unit === this.processCurrencyUnits?.cny
      ? "cny"
      : unit === this.processCurrencyUnits?.rub ? "rub" : null;
    if (sourceCurrency) {
      const amounts = dualCurrencyAmounts(result, sourceCurrency, this.processExchangeRate);
      if (!amounts) return "-";

      return `${this.number(amounts.cny)}${this.processCurrencyUnits.cny} / ${this.number(amounts.rub)}${this.processCurrencyUnits.rub}`;
    }

    const formattedResult = this.number(result);
    return formattedResult === "-" ? "-" : `${formattedResult} ${unit}`.trim();
  }

  renderProcessSummary(row, data) {
    if (this.hasDetailPriceTarget) this.detailPriceTarget.textContent = this.number(this.numericInputs(row).price_rub);
    if (this.hasDetailTotalCostTarget) this.detailTotalCostTarget.textContent = this.number(data.total_cost_cny);
    if (this.hasDetailProfitTarget) this.detailProfitTarget.textContent = this.number(data.profit_cny);
    if (this.hasDetailMarginTarget) this.detailMarginTarget.textContent = `${this.number(Number(data.margin) * 100)}%`;
    this.syncTargetMargin(row, data.margin);
  }

  syncTargetMargin(row, margin) {
    const input = this.targetMarginTargets.find(
      (candidate) => candidate.dataset.processRowKey === row?.dataset.rowKey
    );
    if (!input) return;

    const numericMargin = Number(margin);
    const available = margin !== null && margin !== undefined && Number.isFinite(numericMargin);
    this.markTargetMarginInvalid(input, false);
    if (document.activeElement === input) return;

    input.value = available ? (numericMargin * 100).toFixed(2) : "";
  }

  beginTargetMarginEdit(event) {
    const input = event.currentTarget;
    const row = this.rowTargets.find((candidate) => candidate.dataset.rowKey === input.dataset.processRowKey);
    if (!row) return;

    const rowKey = row.dataset.rowKey;
    const data = this.previewData.get(rowKey);
    this.targetMarginBaseData = data ? { rowKey, data } : null;
    const priceInput = row.querySelector("[data-field='price_rub']");
    if (!data && priceInput?.value && !this.previewControllers.has(rowKey) && !this.previewTimers.has(rowKey)) {
      this.previewRow(row, { detailOnly: true });
    }
  }

  async targetMarginChanged(event) {
    if (this.readonlyValue) return;

    const input = event.currentTarget;
    const row = this.rowTargets.find((candidate) => candidate.dataset.rowKey === input.dataset.processRowKey);
    if (!row) return;
    const rowKey = row.dataset.rowKey;
    let data = this.targetMarginBaseData?.rowKey === rowKey
      ? this.targetMarginBaseData.data
      : this.previewData.get(rowKey);
    if (["", ".", "-", "+", "-.", "+."].includes(input.value.trim())) {
      this.markTargetMarginInvalid(input, false);
      return;
    }
    const targetMargin = Number(input.value) / 100;
    const inputs = this.numericInputs(row);

    const requestToken = ++this.targetMarginRequestToken;
    this.targetMarginRequestController?.abort();
    if (!data) data = await this.previewTargetMarginBaseData(row);
    if (requestToken !== this.targetMarginRequestToken) return;

    const variableCostRate = priceVariableCostRate({
      platform: row.dataset.platform,
      market: row.dataset.market,
      companyType: row.dataset.companyType,
      inputs
    });
    const priceRub = targetPriceForMargin({
      revenueCny: data?.revenue_cny,
      totalCostCny: data?.total_cost_cny,
      variableCostRate,
      targetMargin,
      exchangeRate: inputs.exchange_rate_rub_cny
    });
    const priceInput = row.querySelector("[data-field='price_rub']");
    if (!priceInput || priceRub === null) {
      this.markTargetMarginInvalid(input, true);
      return;
    }

    this.markTargetMarginInvalid(input, false);
    priceInput.value = shortcutInputValue(priceRub);
    priceInput.dataset.valueChanged = "true";
    this.inputChanged({ target: priceInput, type: "target-margin" });
    this.schedulePreview(row);
    if (row.dataset.platform === "ozon" && row.dataset.market === "ru") {
      this.rowTargets
        .filter((candidate) => candidate.dataset.platform === "ozon" && candidate.dataset.market === "by")
        .forEach((candidate) => this.schedulePreview(candidate));
    }
  }

  async previewTargetMarginBaseData(row) {
    const controller = new AbortController();
    this.targetMarginRequestController = controller;
    const inputs = this.rowInputs(row);
    const probePrice = Number(inputs.price_rub);

    // The calculator needs a positive sale price to produce a preview. A
    // temporary 1 RUB probe is enough because target-price solving removes
    // all price-variable costs from the returned total.
    if (!Number.isFinite(probePrice) || probePrice <= 0) inputs.price_rub = "1";
    if (row.dataset.platform === "ozon" && row.dataset.market === "by") {
      const referencePrice = Number(inputs.rf_price_rub);
      if (!Number.isFinite(referencePrice) || referencePrice <= 0) inputs.rf_price_rub = "1";
    }

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: this.jsonHeaders(),
        body: JSON.stringify({
          platform: row.dataset.platform,
          parameter_context: this.contextAttributes(row),
          inputs
        }),
        signal: controller.signal
      });
      const data = await response.json();
      if (!response.ok || data.errors?.length) return null;
      return data;
    } catch (error) {
      if (error.name === "AbortError") return null;
      return null;
    } finally {
      if (this.targetMarginRequestController === controller) this.targetMarginRequestController = null;
    }
  }

  endTargetMarginEdit(event) {
    const row = this.rowTargets.find((candidate) => candidate.dataset.rowKey === event.currentTarget.dataset.processRowKey);
    if (!row) return;

    const rowKey = row.dataset.rowKey;
    this.targetMarginBaseData = null;
    const data = this.previewData.get(rowKey);
    this.syncTargetMargin(row, data?.margin);
  }

  markTargetMarginInvalid(input, invalid) {
    if (!input) return;

    input.classList.toggle("is-invalid", invalid);
    input.setAttribute("aria-invalid", invalid ? "true" : "false");
    input.title = invalid ? this.messagesValue.process.target_margin_invalid : "";
  }

  renderProcessFormulaSummary(data) {
    const templates = this.messagesValue.process.formula_summary;
    const steps = this.messagesValue.process.steps;
    const costs = data.cost_breakdown || {};
    const items = COST_FORMULA_STEPS.map(([costKey, stepKey]) => this.interpolate(
      templates.cost_term,
      { label: steps[stepKey], value: this.number(costs[costKey]) }
    )).join(" + ");
    const revenue = this.number(data.revenue_cny);
    const totalCost = this.number(data.total_cost_cny);
    const profit = this.number(data.profit_cny);
    const margin = Number.isFinite(Number(data.margin)) ? `${this.number(Number(data.margin) * 100)}%` : "-";

    if (this.hasDetailCostFormulaTarget) {
      this.detailCostFormulaTarget.textContent = this.interpolate(templates.total_cost, {
        items,
        total: totalCost
      });
    }
    if (this.hasDetailProfitFormulaTarget) {
      this.detailProfitFormulaTarget.textContent = this.interpolate(templates.profit, {
        revenue,
        total_cost: totalCost,
        profit
      });
    }
    if (this.hasDetailMarginFormulaTarget) {
      this.detailMarginFormulaTarget.textContent = this.interpolate(templates.margin, {
        profit,
        revenue,
        margin
      });
    }
  }

  clearProcessSummary() {
    if (this.hasDetailTotalCostTarget) this.detailTotalCostTarget.textContent = "-";
    if (this.hasDetailProfitTarget) this.detailProfitTarget.textContent = "-";
    if (this.hasDetailMarginTarget) this.detailMarginTarget.textContent = "-";
    this.targetMarginTargets.forEach((input) => {
      if (document.activeElement !== input) input.value = "";
      this.markTargetMarginInvalid(input, false);
    });
    this.renderProcessFormulaSummary({ cost_breakdown: {} });
  }

  interpolate(template, values) {
    return Object.entries(values).reduce(
      (text, [key, value]) => text.replaceAll(`__${key.toUpperCase()}__`, value),
      template
    );
  }

  setProcessStatus(message, status) {
    if (!this.hasDetailStatusTarget) return;

    this.detailStatusTarget.textContent = message;
    this.detailStatusTarget.dataset.status = status;
    this.detailStatusTarget.hidden = !message;
  }

  renderProcessParameters(cell, row, fields) {
    if (!row) return [];

    const renderedFields = [];
    const expectedFields = new Set(fields);
    cell.querySelectorAll("[data-process-parameter-field]").forEach((wrapper) => {
      if (!expectedFields.has(wrapper.dataset.processParameterField)) wrapper.remove();
    });

    fields.filter((field, index) => fields.indexOf(field) === index).forEach((field) => {
      const source = row.querySelector(`[data-field='${field}']`);
      if (field !== "target_margin" && (!source || source.type === "hidden")) return;

      let wrapper = Array.from(cell.querySelectorAll("[data-process-parameter-field]"))
        .find((candidate) => candidate.dataset.processParameterField === field);
      let input = wrapper?.querySelector("[data-process-field]");
      if (!wrapper || !input) {
        wrapper = document.createElement("label");
        wrapper.className = "profit-prediction-process__parameter";
        wrapper.dataset.processParameterField = field;
        const label = document.createElement("span");
        label.className = "profit-prediction-process__parameter-label";
        label.textContent = this.processParameterLabel(row, field);

        input = field === "target_margin" ? document.createElement("input") : source.cloneNode(false);
        if (field === "target_margin") {
          input.type = "text";
          input.step = "1";
          input.inputMode = "decimal";
          const margin = Number(this.previewData.get(row.dataset.rowKey)?.margin);
          input.value = Number.isFinite(margin) ? (margin * 100).toFixed(2) : "";
          input.setAttribute("aria-label", this.processParameterLabel(row, field));
          input.dataset.profitPredictionTarget = "targetMargin";
          input.dataset.action = "focus->profit-prediction#beginTargetMarginEdit input->profit-prediction#targetMarginChanged blur->profit-prediction#endTargetMarginEdit";
        }
        if (field !== "target_margin") {
          // Text inputs preserve decimal intermediate states such as "." and
          // "0." while the user is typing; the source table input remains the
          // normalized numeric value used for preview requests.
          input.type = "text";
          input.inputMode = "decimal";
        }
        input.removeAttribute("id");
        input.removeAttribute("name");
        if (field !== "target_margin") input.removeAttribute("data-profit-prediction-target");
        input.removeAttribute("data-source-value");
        input.dataset.processRowKey = row.dataset.rowKey;
        input.dataset.processField = field;
        if (field !== "target_margin") input.dataset.action = "input->profit-prediction#processInputChanged";
        input.className = "profit-prediction-process__input";

        const numberControl = document.createElement("span");
        numberControl.className = "input-number";
        numberControl.dataset.controller = "input-number";
        const inputNumberOptions = this.processInputNumberOptions(field);
        numberControl.dataset.inputNumberStepValue = inputNumberOptions.step;
        if (inputNumberOptions.magnitudeStep !== undefined) {
          numberControl.dataset.inputNumberMagnitudeStepValue = inputNumberOptions.magnitudeStep;
        }
        if (inputNumberOptions.minimumStep !== undefined) {
          numberControl.dataset.inputNumberMinimumStepValue = inputNumberOptions.minimumStep;
        }
        if (inputNumberOptions.min !== undefined) numberControl.dataset.inputNumberMinValue = inputNumberOptions.min;
        if (inputNumberOptions.max !== undefined) numberControl.dataset.inputNumberMaxValue = inputNumberOptions.max;
        const increment = document.createElement("button");
        increment.type = "button";
        increment.className = "input-number__button";
        increment.dataset.action = "input-number#increment";
        increment.title = this.messagesValue.process.input_number.increment;
        increment.setAttribute("aria-label", this.messagesValue.process.input_number.increment);
        increment.innerHTML = '<i class="bi bi-chevron-up" aria-hidden="true"></i>';
        const decrement = document.createElement("button");
        decrement.type = "button";
        decrement.className = "input-number__button";
        decrement.dataset.action = "input-number#decrement";
        decrement.title = this.messagesValue.process.input_number.decrement;
        decrement.setAttribute("aria-label", this.messagesValue.process.input_number.decrement);
        decrement.innerHTML = '<i class="bi bi-chevron-down" aria-hidden="true"></i>';
        input.dataset.inputNumberTarget = "input";
        numberControl.append(input, increment, decrement);
        wrapper.append(label, numberControl);
        cell.append(wrapper);
      }
      input.classList.toggle("is-invalid", source?.classList.contains("is-invalid") || false);
      input.dataset.processRowKey = row.dataset.rowKey;
      input.dataset.processField = field;
      if (field !== "target_margin" && document.activeElement !== input) input.value = source.value;
      input.disabled = field === "target_margin" ? this.readonlyValue : source.disabled || source.dataset.editable === "false";
      wrapper?.querySelectorAll(".input-number__button").forEach((button) => {
        button.disabled = input.disabled;
      });
      renderedFields.push(field);
    });

    return renderedFields;
  }

  processInputChanged(event) {
    const processInput = event.currentTarget;
    const row = this.rowTargets.find((candidate) => candidate.dataset.rowKey === processInput.dataset.processRowKey);
    const source = row?.querySelector(`[data-field='${processInput.dataset.processField}']`);
    if (!source) return;

    const rawValue = processInput.value;
    if (["", ".", "-", "+", "-.", "+."].includes(rawValue)) return;
    if (!/^[+-]?(?:\d+\.?\d*|\.\d+)$/.test(rawValue)) return;

    source.value = rawValue.endsWith(".") ? rawValue.slice(0, -1) : rawValue;
    source.dataset.valueChanged = "true";
    this.inputChanged({ target: source, type: "input" });
  }

  processParameterLabel(row, field) {
    if (field === "target_margin") return this.messagesValue.process.target_margin;
    if (field === "price_rub" && row.dataset.platform === "ozon" && row.dataset.market === "by") {
      return this.messagesValue.process.by_price_label;
    }

    return this.messagesValue.process.parameter_labels?.[field] || field;
  }

  processInputStep(field) {
    return this.processInputNumberOptions(field).step;
  }

  processInputNumberOptions(field) {
    const rateFields = [
      "duty_rate", "import_vat_rate", "commission_rate", "acquiring_rate",
      "advertising_rate", "tax_rate", "sales_vat_rate", "return_rate",
      "logistics_tax_rate", "damage_rate"
    ];
    if (field === "target_margin") return { step: "1", min: "0", max: "100" };
    // Rates are stored as ratios (15% = 0.15), but the stepper should move
    // by one percentage point at a time: 0.15 -> 0.16. Manual text input
    // still accepts more precision, e.g. 0.075 for a 7.5% commission rate.
    if (rateFields.includes(field)) return { step: "0.01", min: "0", max: "1" };
    if (["length_cm", "width_cm", "height_cm"].includes(field)) {
      return { step: "0.1", min: "0" };
    }
    if (["price_rub", "rf_price_rub"].includes(field)) {
      return { step: "1", magnitudeStep: "true", minimumStep: "1", min: "0" };
    }
    if (field === "exchange_rate_rub_cny") {
      return { step: "0.01", min: "0.0001" };
    }
    if (field === "logistics_coeff") {
      return { step: "0.01", min: "0" };
    }

    return { step: "0.01", magnitudeStep: "true", minimumStep: "0.01", min: "0" };
  }

  syncProcessInput(row, field) {
    if (!this.hasDetailBodyTarget || !field) return;

    const source = row.querySelector(`[data-field='${field}']`);
    if (!source) return;

    this.detailBodyTarget.querySelectorAll(
      `[data-process-row-key='${row.dataset.rowKey}'][data-process-field='${field}']`
    ).forEach((input) => {
      // Keep decimal intermediate states such as `0.` in the field the user
      // is actively editing. The normalized source value is still used for
      // calculation and copied to the other representations.
      if (document.activeElement !== input) input.value = source.value;
    });
  }

  numericInputs(row) {
    const inputs = Object.fromEntries(
      Array.from(row.querySelectorAll("[data-profit-prediction-target~='input']"))
        .map((input) => {
          const value = profitInputValue(input);
          return [input.dataset.field, value === "" ? null : Number(value)];
        })
    );

    if (row.dataset.platform === "ozon" && row.dataset.market === "by") {
      const value = this.russianScenarioPrice(row);
      inputs.rf_price_rub = value ?? inputs.price_rub ?? null;
    }

    return inputs;
  }

  numberOr(value, fallback) {
    return value === null || value === undefined || Number.isNaN(Number(value)) ? fallback : Number(value);
  }

  number(value) {
    const numeric = Number(value);
    return Number.isFinite(numeric) ? this.numberFormatter.format(numeric) : "-";
  }

  percent(value) {
    return `${this.number(Number(value || 0) * 100)}%`;
  }

  async saveVersion(status, includeAllRows) {
    if (this.readonlyValue || this.saving) return;

    let outcome = null;
    this.saving = true;
    this.setButtonsDisabled(true);
    this.modeStatusTarget.textContent = this.messagesValue.calculating;

    const rows = includeAllRows || this.newRecordValue
      ? this.rowTargets
      : this.rowTargets.filter((row) => this.dirtyRows.has(row.dataset.rowKey));

    try {
      const response = await fetch(this.element.dataset.saveUrl, {
        method: this.element.dataset.saveMethod,
        headers: this.jsonHeaders(),
        body: JSON.stringify({
          version: this.versionAttributes(status),
          contexts: rows.map((row) => this.contextPayload(row))
        })
      });
      const data = await response.json();
      if (!response.ok) {
        outcome = "failed";
        return;
      }

      this.applySavedVersion(data);
      this.dirtyRows.clear();
      this.versionDirty = false;
      this.allowNavigation = false;
      this.captureSnapshot();
      outcome = "saved";
    } catch (_error) {
      outcome = "failed";
    } finally {
      this.saving = false;
      this.updateControls();
      if (outcome === "saved") this.modeStatusTarget.textContent = this.messagesValue.saved;
      if (outcome === "failed") this.modeStatusTarget.textContent = this.messagesValue.save_failed;
    }
  }

  applySavedVersion(data) {
    this.previewTimers.forEach((timer) => window.clearTimeout(timer));
    this.previewTimers.clear();
    this.previewControllers.forEach((controller) => controller.abort());
    this.previewControllers.clear();

    const savedContexts = Array.isArray(data.contexts) ? data.contexts : [];
    const contextsById = new Map(savedContexts.map((context) => [String(context.id), context]));
    const contextsByIdentity = new Map(savedContexts.map((context) => [this.contextIdentity(context), context]));

    this.rowTargets.forEach((row) => {
      const oldKey = row.dataset.rowKey;
      const saved = contextsById.get(String(row.dataset.contextId || "")) ||
        contextsByIdentity.get(this.contextIdentity(this.contextAttributes(row)));
      if (!saved) return;

      const newKey = String(saved.id);
      row.dataset.contextId = newKey;
      row.dataset.rowKey = newKey;
      this.moveMapEntry(this.previewData, oldKey, newKey);
      this.syncProcessRowKey(oldKey, newKey);
      this.syncSavedRow(row, saved);
    });

    this.element.dataset.lockVersion = data.lock_version;
    this.element.dataset.saveUrl = this.persistedSaveUrl(data.id);
    this.element.dataset.saveMethod = "PATCH";
    this.newRecordValue = false;
    this.statusValue = data.status;
    this.syncVersionSelector(data);
  }

  syncSavedRow(row, saved) {
    this.inputTargets.filter((input) => input.closest("tr") === row).forEach((input) => {
      const savedValue = saved[input.dataset.field];
      if (savedValue === null || savedValue === undefined) {
        delete input.dataset.sourceValue;
      } else {
        input.dataset.sourceValue = String(savedValue);
      }
      delete input.dataset.valueChanged;
    });

    const status = saved.calculation_status || "pending";
    if (status === "valid") {
      Object.keys(RESULT_PATHS).forEach((field) => this.setResultValue(row, field, saved[field]));
    } else {
      this.clearRowResults(row);
    }
    this.setRowStatus(row, this.messagesValue.statuses[status] || status, status);
    this.syncTargetMargin(row, saved.margin);
    row.classList.remove("is-dirty");
  }

  contextIdentity(context) {
    return ["platform", "market", "delivery_mode", "warehouse_region", "company_type"]
      .map((field) => String(context[field] ?? "").toLowerCase())
      .join(":");
  }

  moveMapEntry(map, oldKey, newKey) {
    if (oldKey === newKey || !map.has(oldKey)) return;

    map.set(newKey, map.get(oldKey));
    map.delete(oldKey);
  }

  syncProcessRowKey(oldKey, newKey) {
    if (oldKey === newKey) return;

    this.element.querySelectorAll("[data-process-row-key]").forEach((element) => {
      if (element.dataset.processRowKey === oldKey) element.dataset.processRowKey = newKey;
    });
    this.element.querySelectorAll("[data-source-row-key]").forEach((element) => {
      if (element.dataset.sourceRowKey === oldKey) element.dataset.sourceRowKey = newKey;
    });
    if (this.renderedProcessRowKey === oldKey) this.renderedProcessRowKey = newKey;
  }

  persistedSaveUrl(versionId) {
    if (this.element.dataset.saveMethod === "PATCH") return this.element.dataset.saveUrl;

    const url = new URL(this.element.dataset.saveUrl, window.location.origin);
    url.pathname = `${url.pathname.replace(/\/$/, "")}/${versionId}`;
    return url.origin === window.location.origin ? `${url.pathname}${url.search}${url.hash}` : url.toString();
  }

  syncVersionSelector(data) {
    if (!this.hasNavigationControlTarget) return;

    let option = Array.from(this.navigationControlTarget.options)
      .find((candidate) => candidate.value === String(data.id));
    if (!option) {
      option = new Option(data.name, data.id);
      this.navigationControlTarget.add(option);
    }
    option.textContent = data.name;
    this.navigationControlTarget.value = String(data.id);
    this.navigationControlTarget.disabled = false;
    this.navigationWasDisabled = false;
  }

  setCalculationMode(active) {
    this.calculationMode = active && !this.readonlyValue;
    this.element.classList.toggle("is-calculating", this.calculationMode);
    this.inputTargets.forEach((input) => {
      input.disabled = !this.calculationMode || input.dataset.editable === "false";
    });
    this.targetMarginTargets.forEach((input) => { input.disabled = !this.calculationMode; });
    this.versionInputTargets.forEach((input) => { input.disabled = !this.calculationMode; });
    if (this.hasNavigationControlTarget) {
      this.navigationControlTarget.disabled = this.navigationWasDisabled || this.hasUnsavedChanges();
    }
    if (this.hasSaveButtonTarget) this.saveButtonTarget.hidden = !this.calculationMode;
    this.updateControls();
  }

  updateControls() {
    const dirty = this.dirtyRows.size > 0 || this.versionDirty;
    if (this.hasSaveButtonTarget) this.saveButtonTarget.disabled = !dirty || this.saving;
    if (this.hasNavigationControlTarget) {
      this.navigationControlTarget.disabled = this.navigationWasDisabled || dirty || this.saving;
    }
    if (!this.hasModeStatusTarget) return;

    if (this.calculationMode && dirty) {
      const count = Math.max(this.dirtyRows.size, 1);
      this.modeStatusTarget.textContent = this.messagesValue.dirty.replace("__COUNT__", count);
    } else if (this.calculationMode) {
      this.modeStatusTarget.textContent = this.messagesValue.measuring;
    } else {
      this.modeStatusTarget.textContent = this.messagesValue.saved;
    }
  }

  contextPayload(row) {
    return {
      id: row.dataset.contextId || undefined,
      context: this.contextAttributes(row),
      inputs: this.rowInputs(row)
    };
  }

  contextAttributes(row) {
    return {
      platform: row.dataset.platform,
      market: row.dataset.market,
      delivery_mode: row.dataset.deliveryMode,
      warehouse_region: row.dataset.warehouseRegion || null,
      company_type: row.dataset.companyType || null
    };
  }

  rowInputs(row) {
    const inputs = Object.fromEntries(
      Array.from(row.querySelectorAll("[data-profit-prediction-target~='input']"))
        .map((input) => [input.dataset.field, profitInputValue(input)])
    );

    if (row.dataset.platform === "ozon" && row.dataset.market === "by") {
      inputs.rf_price_rub = this.russianScenarioPrice(row) ?? inputs.price_rub ?? "";
    }

    return inputs;
  }

  russianScenarioPrice(row) {
    if (row.dataset.platform !== "ozon" || row.dataset.market !== "by") return null;

    const russianRow = this.rowTargets.find(
      (candidate) => candidate.dataset.platform === "ozon" && candidate.dataset.market === "ru"
    );
    const russianPrice = russianRow?.querySelector("[data-field='price_rub']");
    if (!russianPrice) return null;

    const value = profitInputValue(russianPrice);
    return value === "" || !Number.isFinite(Number(value)) ? null : Number(value);
  }

  versionAttributes(status) {
    const attributes = Object.fromEntries(
      this.versionInputTargets.map((input) => [input.dataset.versionField, input.value])
    );
    attributes.status = status;
    if (this.element.dataset.lockVersion) attributes.lock_version = this.element.dataset.lockVersion;
    return attributes;
  }

  setResultValue(row, field, value) {
    const cell = row.querySelector(`[data-result-field='${field}']`);
    if (!cell) return;

    const numericValue = Number(value);
    cell.textContent = field === "margin"
      ? `${this.numberFormatter.format(numericValue * 100)}%`
      : this.numberFormatter.format(numericValue);
    if (field === "profit_cny" || field === "margin") {
      cell.classList.toggle("is-negative", numericValue < 0);
      cell.classList.toggle("is-positive", numericValue >= 0);
    }
  }

  clearRowResults(row) {
    Object.keys(RESULT_PATHS).forEach((field) => {
      const cell = row.querySelector(`[data-result-field='${field}']`);
      if (cell) cell.textContent = "-";
    });
    row.classList.remove("has-preview-results");
  }

  markInvalidInputs(row, errors) {
    row.querySelectorAll("[data-profit-prediction-target~='input']").forEach((input) => {
      const invalid = errors.some((error) => error.includes(input.dataset.field));
      input.classList.toggle("is-invalid", invalid);
      if (invalid) {
        input.setAttribute("aria-invalid", "true");
      } else {
        input.removeAttribute("aria-invalid");
      }
    });
  }

  setRowStatus(row, text, status) {
    const cell = row.querySelector("[data-row-status]");
    if (!cell) return;

    cell.dataset.status = status;
    cell.title = text;
    row.dataset.calculationStatus = status;
    row.classList.toggle("is-incomplete", status === "incomplete");
    row.classList.toggle("is-calculating", status === "calculating");
    const label = cell.querySelector("[data-row-status-label]");
    if (label) label.textContent = text;
  }

  valueAt(object, path) {
    return path.reduce((value, key) => value?.[key], object);
  }

  captureSnapshot() {
    this.inputSnapshot = new Map(this.inputTargets.map((input) => [input, {
      value: input.value,
      sourceValue: input.dataset.sourceValue,
      valueChanged: input.dataset.valueChanged
    }]));
    this.versionSnapshot = new Map(this.versionInputTargets.map((input) => [input, input.value]));
    this.resultSnapshot = new Map(
      Array.from(this.element.querySelectorAll("[data-result-field]"))
        .map((cell) => [cell, { text: cell.textContent, className: cell.className, status: cell.dataset.status }])
    );
    this.rowSnapshot = new Map(this.rowTargets.map((row) => {
      const status = row.querySelector("[data-row-status]");
      return [row, {
        calculationStatus: row.dataset.calculationStatus,
        title: row.title,
        status: status?.dataset.status,
        statusTitle: status?.title,
        statusLabel: status?.querySelector("[data-row-status-label]")?.textContent
      }];
    }));
  }

  restoreSnapshot() {
    this.previewTimers.forEach((timer) => window.clearTimeout(timer));
    this.previewTimers.clear();
    this.previewControllers.forEach((controller) => controller.abort());
    this.previewControllers.clear();
    this.previewData.clear();
    this.inputSnapshot.forEach((snapshot, input) => {
      input.value = snapshot.value;
      if (snapshot.sourceValue === undefined) {
        delete input.dataset.sourceValue;
      } else {
        input.dataset.sourceValue = snapshot.sourceValue;
      }
      if (snapshot.valueChanged === undefined) {
        delete input.dataset.valueChanged;
      } else {
        input.dataset.valueChanged = snapshot.valueChanged;
      }
    });
    this.versionSnapshot.forEach((value, input) => { input.value = value; });
    this.resultSnapshot.forEach((snapshot, cell) => {
      cell.textContent = snapshot.text;
      cell.className = snapshot.className;
      cell.dataset.status = snapshot.status || "";
    });
    this.rowSnapshot.forEach((snapshot, row) => {
      row.dataset.calculationStatus = snapshot.calculationStatus || "";
      row.title = snapshot.title || "";
      const status = row.querySelector("[data-row-status]");
      if (!status) return;

      status.dataset.status = snapshot.status || "";
      status.title = snapshot.statusTitle || "";
      const label = status.querySelector("[data-row-status-label]");
      if (label) label.textContent = snapshot.statusLabel || "";
    });
    this.rowTargets.forEach((row) => row.classList.remove("is-dirty", "has-preview-results"));
    if (this.selectedRow) {
      this.renderedProcessRowKey = null;
      if (this.hasDetailBodyTarget) this.detailBodyTarget.replaceChildren();
      this.clearProcessSummary();
      this.setProcessStatus("", "pending");
      this.previewRow(this.selectedRow, { detailOnly: true });
    }
  }

  setButtonsDisabled(disabled) {
    if (this.hasSaveButtonTarget) this.saveButtonTarget.disabled = disabled;
  }

  jsonHeaders() {
    return {
      "Content-Type": "application/json",
      "Accept": "application/json",
      "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content || ""
    };
  }

  handleBeforeUnload(event) {
    if (!this.hasUnsavedChanges()) return;

    event.preventDefault();
    event.returnValue = "";
  }

  handleBeforeVisit(event) {
    if (this.allowNavigation || !this.hasUnsavedChanges()) return;
    if (window.confirm(this.messagesValue.confirm_leave)) return;

    event.preventDefault();
  }

  hasUnsavedChanges() {
    return this.calculationMode && (this.dirtyRows.size > 0 || this.versionDirty);
  }
}
