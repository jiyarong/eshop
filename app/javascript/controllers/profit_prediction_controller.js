import { Controller } from "@hotwired/stimulus";
import { Turbo } from "@hotwired/turbo-rails";
import {
  dualCurrencyAmounts,
  priceVariableCostRate,
  profitInputValue,
  ratioToPercentString,
  sellingPriceShortcuts,
  shortcutInputValue,
  targetPriceForMargin,
  withoutCoefficient
} from "./profit_prediction_values";
import { buildCalculationSteps, formulaTokenName, formulaTokenText, isOperator } from "./profit_prediction_formula";
import {
  fill, hiddenScenarios, missedScenarios, missedSummary, scenarioShownIn, scenarioWarning, soldScenarios, soldSummary
} from "./profit_prediction_scenarios";

const PREVIEW_DEBOUNCE_MS = 350;

// The freight figures a scenario on the fixed formula does not take from the inputs (see Ec::LogisticsFormula).
const LOGISTICS_FIGURE_FIELDS = ["outbound_logistics_rub", "return_logistics_rub"];

// The actual-data shortcuts that can still be platform-wide for a scenario (see actuals_pending in
// config/sku_profit_scenarios.yml).
const PENDING_KIND_BY_SOURCE = { actual_storage: "storage", actual_advertising: "advertising" };

const VIEW_MODE_STORAGE_KEY = "profit_prediction_view_mode";
const VIEW_MODES = ["calculator", "table"];
const DEFAULT_VIEW_MODE = "calculator";

const BULK_LOAD_ACTION_SELECTOR =
  "[data-action^='profit-prediction#loadActual'], [data-action='profit-prediction#loadOfficialCommission']";

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
    actualAcquiringUrl: String,
    switchUrl: String,
    createUrl: String,
    deleteUrl: String,
    today: String,
    versionId: Number,
    setCurrentUrl: String,
    incompleteCount: Number,
    scenarioState: Object,
    scenarioVisibilityUrl: String,
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
    "scenarioTabItem",
    "scenarioModeTab",
    "scenarioModeNote",
    "scenarioBanner",
    "scenarioNote",
    "scenarioRestore",
    "scenarioMenu",
    "tableHiddenNote",
    "viewTab",
    "tableView",
    "calculatorView",
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
    "deleteDialog",
    "deleteDialogMessage",
    "deleteDialogError",
    "deleteDialogConfirm",
    "logisticsModeCurrent",
    "versionDialog",
    "versionDialogTitle",
    "versionDialogName",
    "versionDialogError",
    "versionDialogConfirm",
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
    "bulkActualButton",
    "detailCommissionBasePrice",
    "detailBuyerPaidPrice",
    "detailPlatformSubsidy",
    "targetMargin",
    "detailTotalCost",
    "detailProfit",
    "detailMargin"
  ];

  connect() {
    this.previewTimers = new Map();
    this.previewControllers = new Map();
    this.previewData = new Map();
    this.actualLogisticsData = new Map();
    this.actualSellingPriceData = new Map();
    this.actualReturnRateData = new Map();
    this.actualStorageData = new Map();
    this.actualAdvertisingData = new Map();
    this.actualAcquiringData = new Map();
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
    this.scenarios = this.hasScenarioStateValue && this.scenarioStateValue.scenarios
      ? JSON.parse(JSON.stringify(this.scenarioStateValue))
      : null;
    // "custom": the scenarios this SKU chose to show (hide / restore work). "actual": the ones it
    // really sold in the window, read-only. Always starts on custom.
    this.scenarioMode = "custom";
    this.closeScenarioMenuHandler = (event) => this.closeScenarioMenuOnOutsideEvent(event);
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
    // A scenario on the formula shows the formula's figures: ask for them (quietly) even when it is up to date.
    this.rowTargets
      .filter((row) => this.logisticsMode(row) === "formula" && row.dataset.calculationStatus === "valid" && !this.newRecordValue)
      .forEach((row) => this.previewRow(row, { detailOnly: true }));
    this.applyPlatformFilter();
    this.renderScenarios();
    this.setViewMode(this.storedViewMode());

    if (!this.selectedRow && this.visibleRows()[0]) this.setSelectedRow(this.visibleRows()[0]);
    this.updateControls();
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
    this.actualAcquiringRequestController?.abort();
    this.officialCommissionRequestController?.abort();
    this.targetMarginRequestController?.abort();
    window.removeEventListener("beforeunload", this.beforeUnloadHandler);
    document.removeEventListener("turbo:before-visit", this.beforeVisitHandler);
    this.closeScenarioMenu();
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
    if (this.selectedRow === row && ["commission_base_price_rub", "buyer_paid_price_rub"].includes(event.target.dataset.field)) {
      this.renderPriceSummary(row);
    }
    this.dirtyRows.add(row.dataset.rowKey);
    this.previewData.delete(row.dataset.rowKey);
    row.classList.add("is-dirty");
    this.updateControls();

    if (event.type === "input") this.schedulePreview(row);
  }

  versionChanged() {
    if (!this.calculationMode) return;

    this.versionDirty = true;
    this.updateControls();
  }

  // Switching version reloads only the frame this tab lives in (the drawer's or the page's), so
  // the drawer and the other tabs stay put. It must not build the URL from window.location: in
  // the drawer that is the host page, not the SKU detail.
  changeVersion(event) {
    const select = event.target;
    if (!select.value) return;

    if (!this.confirmDiscardChanges()) {
      select.value = select.querySelector("option[selected]")?.value || "";
      return;
    }

    const url = new URL(this.switchUrlValue || window.location.href, window.location.origin);
    url.searchParams.set("tab", "profit_prediction");
    url.searchParams.set("version_id", select.value);
    url.searchParams.delete("copy_version_id");
    url.searchParams.delete("new_profit_version");
    this.navigateWithinFrame(url);
  }

  // Marks this saved version as the SKU's current one, then reloads the tab so the badge, the
  // switcher order and the lock version are fresh.
  async setCurrent(event) {
    const messages = this.messagesValue.current_version;
    if (this.hasUnsavedChanges()) {
      this.showModeMessage(messages.needs_save);
      return;
    }
    if (this.incompleteCountValue > 0 &&
        !window.confirm(messages.incomplete_confirm.replace("__COUNT__", this.incompleteCountValue))) return;

    const button = event.currentTarget;
    button.disabled = true;
    try {
      const response = await fetch(this.setCurrentUrlValue, { method: "PATCH", headers: this.jsonHeaders() });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);

      const url = new URL(this.switchUrlValue, window.location.origin);
      url.searchParams.set("tab", "profit_prediction");
      url.searchParams.set("version_id", this.versionIdValue);
      this.navigateWithinFrame(url);
    } catch (error) {
      button.disabled = false;
      this.showModeMessage(messages.failed);
    }
  }

  showModeMessage(text) {
    if (this.hasModeStatusTarget) this.modeStatusTarget.textContent = text;
  }

  // Copy and New ask for a name first and create the version at once; the page then opens it. A
  // copy is taken from what is stored, so unsaved edits would be left behind: ask before that.
  openVersionDialog(event) {
    if (!this.hasVersionDialogTarget || !this.confirmDiscardChanges()) return;

    const button = event.currentTarget;
    this.versionDialogAction = button.dataset.versionAction === "copy" ? "copy" : "new";
    const messages = this.messagesValue.version_dialog || {};
    this.versionDialogTitleTarget.textContent = this.versionDialogAction === "copy" ? messages.title_copy : messages.title_new;
    this.versionDialogNameTarget.value = button.dataset.defaultName || "";
    this.versionDialogErrorTarget.hidden = true;
    this.versionDialogConfirmTarget.disabled = false;
    if (!this.versionDialogTarget.open) this.versionDialogTarget.showModal();
    this.versionDialogNameTarget.focus();
    this.versionDialogNameTarget.select();
  }

  closeVersionDialog() {
    if (this.hasVersionDialogTarget && this.versionDialogTarget.open) this.versionDialogTarget.close();
  }

  closeVersionDialogOnBackdrop(event) {
    if (event.target === this.versionDialogTarget) this.closeVersionDialog();
  }

  async submitVersionDialog(event) {
    event.preventDefault();
    const messages = this.messagesValue.version_dialog || {};
    const name = this.versionDialogNameTarget.value.trim();
    if (!name) {
      this.showVersionDialogError(messages.name_required);
      return;
    }

    this.versionDialogConfirmTarget.disabled = true;
    this.versionDialogErrorTarget.hidden = true;
    try {
      const body = { version: { name, status: "draft", effective_from: this.todayValue } };
      if (this.versionDialogAction === "copy") body.copy_from_version_id = this.versionIdValue;
      const response = await fetch(this.createUrlValue, { method: "POST", headers: this.jsonHeaders(), body: JSON.stringify(body) });
      const data = await response.json().catch(() => ({}));
      if (!response.ok) {
        this.showVersionDialogError(data.errors?.effective_from ? messages.overlap : messages.failed);
        this.versionDialogConfirmTarget.disabled = false;
        return;
      }

      this.closeVersionDialog();
      // Nothing is unsaved any more (it was confirmed before the dialog opened): go straight there.
      this.dirtyRows.clear();
      this.versionDirty = false;
      const url = new URL(this.switchUrlValue, window.location.origin);
      url.searchParams.set("tab", "profit_prediction");
      url.searchParams.set("version_id", data.id);
      this.navigateWithinFrame(url);
    } catch (_error) {
      this.showVersionDialogError(messages.failed);
      this.versionDialogConfirmTarget.disabled = false;
    }
  }

  showVersionDialogError(text) {
    this.versionDialogErrorTarget.textContent = text || "";
    this.versionDialogErrorTarget.hidden = !text;
  }

  // Delete asks first, in a dialog that names the version. The current version cannot go (the button
  // is disabled and the server refuses): another version has to be made current first.
  openDeleteDialog(event) {
    if (!this.hasDeleteDialogTarget || !this.hasDeleteUrlValue) return;

    const messages = this.messagesValue.delete_dialog || {};
    this.deleteDialogMessageTarget.textContent = fill(messages.message || "", { name: event.currentTarget.dataset.versionName || "" });
    this.deleteDialogErrorTarget.hidden = true;
    this.deleteDialogConfirmTarget.disabled = false;
    if (!this.deleteDialogTarget.open) this.deleteDialogTarget.showModal();
    this.deleteDialogConfirmTarget.blur();
  }

  closeDeleteDialog() {
    if (this.hasDeleteDialogTarget && this.deleteDialogTarget.open) this.deleteDialogTarget.close();
  }

  closeDeleteDialogOnBackdrop(event) {
    if (event.target === this.deleteDialogTarget) this.closeDeleteDialog();
  }

  async submitDeleteDialog() {
    const messages = this.messagesValue.delete_dialog || {};
    this.deleteDialogConfirmTarget.disabled = true;
    this.deleteDialogErrorTarget.hidden = true;
    try {
      const response = await fetch(this.deleteUrlValue, { method: "DELETE", headers: this.jsonHeaders() });
      const data = await response.json().catch(() => ({}));
      if (!response.ok) {
        this.showDeleteDialogError(data.errors?.base?.includes("current_version") ? messages.current_blocked : messages.failed);
        this.deleteDialogConfirmTarget.disabled = false;
        return;
      }

      this.closeDeleteDialog();
      // The version is gone, so nothing in it is unsaved any more. Land on whichever version the
      // tab resolves to (the current one).
      this.dirtyRows.clear();
      this.versionDirty = false;
      const url = new URL(this.switchUrlValue, window.location.origin);
      url.searchParams.set("tab", "profit_prediction");
      this.navigateWithinFrame(url);
    } catch (_error) {
      this.showDeleteDialogError(messages.failed);
      this.deleteDialogConfirmTarget.disabled = false;
    }
  }

  showDeleteDialogError(text) {
    this.deleteDialogErrorTarget.textContent = text || "";
    this.deleteDialogErrorTarget.hidden = !text;
  }

  // ── Logistics mode ─────────────────────────────────────────────────────────────────────────
  // "formula": the fixed formula decides the freight (WB base rate x coefficient and a flat 50 RUB return,
  // Ozon the route tariff average), so the same SKU always costs the same; real figures are only a reference.
  // "actual": the typed or applied real figures count. Chosen per scenario, saved with it.
  logisticsMode(row) {
    return row?.dataset.logisticsMode === "actual" ? "actual" : "formula";
  }

  logisticsInputLocked(input) {
    return LOGISTICS_FIGURE_FIELDS.includes(input.dataset.field) && this.logisticsMode(input.closest("tr")) === "formula";
  }

  selectLogisticsMode(event) {
    const row = this.selectedRow;
    if (!row || this.readonlyValue) return;

    const mode = event.currentTarget.dataset.logisticsModeOption === "actual" ? "actual" : "formula";
    if (this.logisticsMode(row) === mode) return;

    row.dataset.logisticsMode = mode;
    if (mode === "actual") this.restoreRealFigures(row);
    this.applyLogisticsLock(row);
    this.dirtyRows.add(row.dataset.rowKey);
    this.previewData.delete(row.dataset.rowKey);
    row.classList.add("is-dirty");
    this.updateControls();
    this.renderLogisticsModePanel(row);
    this.schedulePreview(row);
  }

  applyLogisticsLock(row) {
    const messages = this.messagesValue.logistics_mode || {};
    row.querySelectorAll("[data-profit-prediction-target~='input']").forEach((input) => {
      if (!LOGISTICS_FIGURE_FIELDS.includes(input.dataset.field)) return;

      const locked = this.logisticsInputLocked(input);
      input.disabled = !this.calculationMode || input.dataset.editable === "false" || locked;
      input.title = locked ? messages.locked_title || "" : "";
    });
  }

  // On Ozon's formula the two freight inputs show the formula's figures (read-only); the real figures that were
  // there are kept aside and go back when the scenario returns to the real figures, and are what gets saved.
  showFormulaFigures(row, data) {
    if (this.logisticsMode(row) !== "formula") return;

    // WB's formula is made of its tariff parameters, shown on their own fields; the two freight fields are
    // then only the greyed-out real figures, and the formula's own result stays out of them (it would sit
    // there as an unexplained number). Ozon's route average has no parameter fields, so it is shown here.
    if (row.dataset.platform === "wb") {
      this.restoreRealFigures(row);
      return;
    }

    const formula = data.logistics?.formula || {};
    [["outbound_logistics_rub", formula.outbound_rub], ["return_logistics_rub", formula.return_rub]].forEach(([field, value]) => {
      const input = row.querySelector(`[data-field='${field}']`);
      if (!input) return;

      // Without a figure from the formula (WB works from the tariff parameters) the typed one stays in
      // view, greyed out, so it is clear it is not in use.
      if (value === null || value === undefined) {
        this.restoreRealFigure(input);
        return;
      }

      if (input.dataset.stashedValue === undefined) {
        input.dataset.stashedValue = profitInputValue(input);
        input.dataset.stashedDisplay = input.value;
      }
      input.value = Number(value).toFixed(2);
    });
  }

  restoreRealFigures(row) {
    LOGISTICS_FIGURE_FIELDS.forEach((field) => {
      const input = row.querySelector(`[data-field='${field}']`);
      if (input) this.restoreRealFigure(input);
    });
  }

  restoreRealFigure(input) {
    if (input.dataset.stashedValue === undefined) return;

    input.value = input.dataset.stashedDisplay ?? "";
    delete input.dataset.stashedValue;
    delete input.dataset.stashedDisplay;
  }

  // The quiet "current mode" line at the top of the panel, and the switch on the platform logistics row.
  renderLogisticsModePanel(row) {
    const messages = this.messagesValue.logistics_mode || {};
    if (this.hasLogisticsModeCurrentTarget) this.logisticsModeCurrentTarget.textContent = messages[this.logisticsMode(row)] || "";
    const control = this.hasDetailBodyTarget && this.detailBodyTarget.querySelector("[data-logistics-mode-control]");
    if (control) this.fillLogisticsModeControl(control, row);
  }

  // The switch itself: a radio pair, what the current mode means, and what the other mode would give.
  fillLogisticsModeControl(container, row) {
    const messages = this.messagesValue.logistics_mode || {};
    const mode = this.logisticsMode(row);
    const group = document.createElement("div");
    group.className = "profit-prediction-process__logistics-mode-options";
    group.setAttribute("role", "radiogroup");
    group.setAttribute("aria-label", messages.label || "");
    ["formula", "actual"].forEach((option) => {
      const label = document.createElement("label");
      label.className = "profit-prediction-process__logistics-mode-option";
      const radio = document.createElement("input");
      radio.type = "radio";
      radio.name = `logistics-mode-${row.dataset.rowKey}`;
      radio.value = option;
      radio.checked = option === mode;
      radio.dataset.logisticsModeOption = option;
      radio.dataset.action = "change->profit-prediction#selectLogisticsMode";
      radio.disabled = this.readonlyValue;
      label.append(radio, document.createTextNode(messages[option] || option));
      group.append(label);
    });
    const hint = document.createElement("small");
    hint.className = "profit-prediction-process__logistics-mode-hint";
    hint.textContent = mode === "formula" ? messages.formula_hint : messages.actual_hint;
    const children = [group, hint];

    const alternative = this.previewData.get(row?.dataset.rowKey)?.logistics?.alternative;
    const difference = Number(alternative?.profit_difference_cny);
    if (alternative && Number.isFinite(difference) && Math.abs(difference) >= 0.005) {
      const line = document.createElement("small");
      line.className = "profit-prediction-process__logistics-mode-alternative";
      line.textContent = fill(mode === "formula" ? messages.alternative_actual : messages.alternative_formula, {
        profit: this.number(Number(alternative.profit_cny)), difference: `${difference > 0 ? "+" : ""}${this.number(difference)}`
      });
      children.push(line);
    }
    container.replaceChildren(...children);
  }

  // Frame links that would throw away unsaved edits ask first.
  confirmLeave(event) {
    if (!this.confirmDiscardChanges()) event.preventDefault();
  }

  confirmDiscardChanges() {
    return !this.hasUnsavedChanges() || window.confirm(this.messagesValue.confirm_leave);
  }

  navigateWithinFrame(url) {
    const frame = this.element.closest("turbo-frame");
    if (frame?.id) {
      Turbo.visit(url.toString(), { frame: frame.id });
      return;
    }

    // Already confirmed above: do not ask again on the top-level visit.
    this.allowNavigation = true;
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
          parameter_context: this.parameterContext(row),
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
      this.showFormulaFigures(row, data);
      if (this.selectedRow === row) {
        this.renderLogisticsModePanel(row);
        this.renderCalculationProcess(row, data);
      }
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
    const tabs = this.scenarioTabTargets.filter((tab) => !tab.closest("[data-scenario-key]")?.hidden);
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

  // ── Scenario visibility ────────────────────────────────────────────────────────────────────
  // A scenario can be hidden per SKU (shared by everybody, saved at once, not part of the
  // version). The marks, the missed-scenario banner and the restore list are drawn from
  // `this.scenarios`, so they follow every change without asking the server.
  renderScenarios() {
    const state = this.scenarios;
    if (!state) return;

    const messages = this.messagesValue.scenarios || {};
    state.scenarios.forEach((scenario) => {
      const item = this.scenarioTabItemTargets.find((candidate) => candidate.dataset.scenarioKey === scenario.key);
      if (!item) return;

      item.hidden = !this.scenarioShown(scenario);
      const gear = item.querySelector(".profit-prediction-process__scenario-menu-button");
      if (gear) gear.hidden = this.actualScenarioMode();
      const warning = item.querySelector("[data-scenario-warning]");
      if (!warning) return;
      // A scenario shown only because it sold is not "hidden", whatever the SKU chose.
      const warn = scenarioWarning(state, { ...scenario, hidden: !this.scenarioShown(scenario) });
      warning.hidden = !warn;
      const text = !warn ? ""
        : Number(scenario.units || 0) === 0
          ? fill(messages.warning_none, { weeks: state.weeks })
          : fill(messages.warning, { weeks: state.weeks, units: scenario.units, min: state.min_units });
      warning.dataset.message = text;
      warning.setAttribute("aria-label", text);
    });

    const hidden = hiddenScenarios(state);
    if (this.hasScenarioRestoreTarget) {
      this.scenarioRestoreTarget.hidden = hidden.length === 0 || this.actualScenarioMode();
      const count = this.scenarioRestoreTarget.querySelector("[data-scenario-restore-count]");
      if (count) count.textContent = hidden.length ? String(hidden.length) : "";
    }
    if (this.hasTableHiddenNoteTarget) {
      this.tableHiddenNoteTarget.hidden = hidden.length === 0 || this.actualScenarioMode();
      const button = this.tableHiddenNoteTarget.querySelector("button");
      if (button) button.textContent = fill(messages.table_hidden || "", { count: hidden.length });
    }
    this.renderScenarioBanner(state, messages);
    this.renderScenarioModeNote(state, messages);
  }

  actualScenarioMode() {
    return this.scenarioMode === "actual";
  }

  // What the scenario bar shows: in custom mode the ones not hidden, in actual mode the ones
  // with signed units (hiding does not apply there).
  scenarioShown(scenario) {
    return scenarioShownIn(this.scenarioMode, scenario);
  }

  renderScenarioModeNote(state, messages) {
    if (!this.hasScenarioModeNoteTarget) return;

    const sold = soldScenarios(state);
    const show = this.actualScenarioMode();
    this.scenarioModeNoteTarget.hidden = !show;
    if (!show) {
      this.scenarioModeNoteTarget.textContent = "";
      return;
    }
    this.scenarioModeNoteTarget.textContent = sold.length === 0
      ? fill(messages.mode_actual_empty || "", { weeks: state.weeks })
      : fill(messages.mode_actual_note || "", { weeks: state.weeks, ...soldSummary(state) });
  }

  selectScenarioMode(event) {
    const mode = event.currentTarget.dataset.scenarioMode === "actual" ? "actual" : "custom";
    if (!this.scenarios || this.scenarioMode === mode) return;
    if (mode === "actual" && !this.scenarios.measured) return;

    this.closeScenarioMenu();
    this.scenarioMode = mode;
    this.scenarioModeTabTargets.forEach((tab) => {
      const active = tab.dataset.scenarioMode === mode;
      tab.classList.toggle("is-active", active);
      tab.setAttribute("aria-selected", active ? "true" : "false");
    });
    this.applyScenarioVisibility();
  }

  renderScenarioBanner(state, messages) {
    if (this.hasScenarioBannerTarget) {
      const summary = this.actualScenarioMode() ? { count: 0 } : missedSummary(state);
      this.scenarioBannerTarget.hidden = summary.count === 0;
      if (summary.count > 0) {
        const text = document.createElement("span");
        text.textContent = fill(messages.missed, {
          count: summary.count, weeks: state.weeks, units: summary.units, share: summary.share, labels: summary.labels
        });
        const button = document.createElement("button");
        button.type = "button";
        button.className = "btn btn-ghost btn-sm";
        button.dataset.action = "profit-prediction#restoreMissedScenarios";
        button.textContent = messages.restore_one;
        this.scenarioBannerTarget.replaceChildren(text, button);
      } else {
        this.scenarioBannerTarget.replaceChildren();
      }
    }

    if (this.hasScenarioNoteTarget) {
      const outside = Number(state.outside_units || 0);
      const show = Boolean(state.measured) && outside > 0;
      this.scenarioNoteTarget.hidden = !show;
      this.scenarioNoteTarget.textContent = show ? fill(messages.outside, { units: outside }) : "";
    }
  }

  // Marks the rows and tabs, re-applies the platform filter (which also moves the selection off a
  // hidden scenario) and refreshes what depends on the visible set.
  applyScenarioVisibility() {
    const state = this.scenarios;
    if (!state) return;

    this.rowTargets.forEach((row) => {
      const scenario = state.scenarios.find((candidate) => candidate.key === row.dataset.scenarioKey);
      row.dataset.scenarioHidden = scenario?.hidden ? "true" : "false";
      row.dataset.scenarioUnsold = scenario && Number(scenario.units || 0) > 0 ? "false" : "true";
    });
    this.applyPlatformFilter();
    this.renderScenarios();
    this.syncIncompleteCount();
  }

  // The "not finished" count behind the set-as-current confirmation ignores hidden scenarios.
  syncIncompleteCount() {
    if (!this.versionIdValue) return;

    this.incompleteCountValue = this.rowTargets.filter((row) => (
      row.dataset.scenarioHidden !== "true" && row.dataset.calculationStatus !== "valid"
    )).length;
  }

  async setScenarioHidden(key, hidden) {
    if (this.actualScenarioMode()) return;

    const scenario = this.scenarios?.scenarios.find((candidate) => candidate.key === key);
    if (!scenario || Boolean(scenario.hidden) === hidden) return;

    scenario.hidden = hidden;
    this.applyScenarioVisibility();
    try {
      const response = await fetch(this.scenarioVisibilityUrlValue, {
        method: "PATCH",
        headers: this.jsonHeaders(),
        body: JSON.stringify({ ...scenario.identity, hidden })
      });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
    } catch (error) {
      scenario.hidden = !hidden;
      this.applyScenarioVisibility();
      this.showModeMessage(this.messagesValue.scenarios?.save_failed || "");
    }
  }

  restoreMissedScenarios() {
    if (!this.scenarios) return;

    missedScenarios(this.scenarios).forEach((scenario) => this.setScenarioHidden(scenario.key, false));
  }

  toggleScenarioMenu(event) {
    event.stopPropagation();
    if (this.actualScenarioMode()) return;
    const key = event.currentTarget.closest("[data-scenario-key]")?.dataset.scenarioKey;
    const scenario = this.scenarios?.scenarios.find((candidate) => candidate.key === key);
    if (!scenario) return;

    if (this.openScenarioMenuFor === event.currentTarget) {
      this.closeScenarioMenu();
      return;
    }

    const messages = this.messagesValue.scenarios || {};
    this.openScenarioMenu(event.currentTarget, [
      { info: this.scenarioSalesLine(scenario) },
      { text: messages.hide, action: () => this.setScenarioHidden(key, true) }
    ]);
  }

  // The yellow mark explains itself at once (hover, keyboard focus or tap) in the same popover as
  // the menu; a native title would take a second to appear and show a help cursor meanwhile.
  showScenarioWarning(event) {
    const anchor = event.currentTarget;
    if (!anchor.dataset.message) return;
    if (this.openScenarioMenuFor && !this.openScenarioMenuFor.hasAttribute("data-scenario-warning")) return;
    if (this.openScenarioMenuFor === anchor) return;

    this.openScenarioMenu(anchor, [{ info: anchor.dataset.message }]);
  }

  hideScenarioWarning(event) {
    if (this.openScenarioMenuFor === event.currentTarget) this.closeScenarioMenu();
  }

  toggleRestoreMenu(event) {
    event.stopPropagation();
    if (this.actualScenarioMode()) return;
    if (!this.scenarios) return;

    if (this.openScenarioMenuFor === event.currentTarget) {
      this.closeScenarioMenu();
      return;
    }

    const messages = this.messagesValue.scenarios || {};
    const hidden = hiddenScenarios(this.scenarios);
    const entries = hidden.map((scenario) => ({
      text: `${scenario.label} · ${this.scenarioSalesLine(scenario)}`,
      action: () => this.setScenarioHidden(scenario.key, false)
    }));
    if (hidden.length > 1) {
      entries.push({ text: messages.restore_all, action: () => hidden.forEach((scenario) => this.setScenarioHidden(scenario.key, false)) });
    }
    this.openScenarioMenu(event.currentTarget, entries);
  }

  scenarioSalesLine(scenario) {
    const messages = this.messagesValue.scenarios || {};
    const state = this.scenarios;
    if (!state.measured) return messages.unmeasured;
    if (!Number(scenario.units)) return fill(messages.sales_none, { weeks: state.weeks });

    return fill(messages.sales_line, {
      weeks: state.weeks, units: scenario.units, orders: scenario.orders ?? 0, date: scenario.last_date || "-"
    });
  }

  openScenarioMenu(anchor, entries) {
    if (!this.hasScenarioMenuTarget || entries.length === 0) return;

    const menu = this.scenarioMenuTarget;
    menu.replaceChildren(...entries.map((entry) => {
      if (entry.info !== undefined) {
        const info = document.createElement("div");
        info.className = "profit-prediction-scenario-menu__info";
        info.textContent = entry.info;
        return info;
      }
      const button = document.createElement("button");
      button.type = "button";
      button.setAttribute("role", "menuitem");
      button.className = "profit-prediction-scenario-menu__item";
      button.textContent = entry.text;
      button.addEventListener("click", () => {
        this.closeScenarioMenu();
        entry.action();
      });
      return button;
    }));
    menu.hidden = false;
    // Open under the button, with the menu's right edge on the button's right edge: the ⋯ sits at
    // the right of its tab, so the menu stays under that tab instead of the next one.
    const box = anchor.getBoundingClientRect();
    const top = Math.round(box.bottom + 4);
    // Not further left than the scenario bar, so the popover never slides under the sidebar.
    const minLeft = Math.max(8, anchor.closest("nav")?.getBoundingClientRect().left ?? 8);
    const left = Math.round(Math.max(minLeft, Math.min(box.right - menu.offsetWidth, window.innerWidth - menu.offsetWidth - 8)));
    menu.style.top = `${top}px`;
    menu.style.left = `${left}px`;
    // `position: fixed` is relative to the viewport unless an ancestor (a transform, filter or
    // contain) becomes its containing block; measure where it really landed and shift it back.
    const placed = menu.getBoundingClientRect();
    if (Math.abs(placed.left - left) > 1 || Math.abs(placed.top - top) > 1) {
      menu.style.top = `${Math.round(top - (placed.top - top))}px`;
      menu.style.left = `${Math.round(left - (placed.left - left))}px`;
    }
    this.openScenarioMenuFor = anchor;
    anchor.setAttribute("aria-expanded", "true");
    document.addEventListener("click", this.closeScenarioMenuHandler, true);
    document.addEventListener("keydown", this.closeScenarioMenuHandler, true);
    window.addEventListener("resize", this.closeScenarioMenuHandler);
    window.addEventListener("scroll", this.closeScenarioMenuHandler, true);
  }

  closeScenarioMenu() {
    if (this.hasScenarioMenuTarget) this.scenarioMenuTarget.hidden = true;
    this.openScenarioMenuFor?.setAttribute("aria-expanded", "false");
    this.openScenarioMenuFor = null;
    document.removeEventListener("click", this.closeScenarioMenuHandler, true);
    document.removeEventListener("keydown", this.closeScenarioMenuHandler, true);
    window.removeEventListener("resize", this.closeScenarioMenuHandler);
    window.removeEventListener("scroll", this.closeScenarioMenuHandler, true);
  }

  closeScenarioMenuOnOutsideEvent(event) {
    if (event.type === "keydown" && event.key !== "Escape") return;
    // A click on the button that opened the menu is its own toggle; a click inside the menu is a choice.
    if (event.type === "click" && (this.scenarioMenuTarget.contains(event.target) || this.openScenarioMenuFor?.contains(event.target))) return;

    this.closeScenarioMenu();
  }

  // Two mutually exclusive views over the same scenario rows: the calculator (default) and the
  // six-row table. The table's inputs stay in the DOM in both, because the calculator reads them.
  selectViewMode(event) {
    const mode = event.currentTarget.dataset.viewMode;
    this.setViewMode(mode);
    this.storeViewMode(mode);
  }

  setViewMode(mode) {
    this.viewMode = VIEW_MODES.includes(mode) ? mode : DEFAULT_VIEW_MODE;
    this.element.dataset.viewMode = this.viewMode;
    if (this.hasTableViewTarget) this.tableViewTarget.hidden = this.viewMode !== "table";
    if (this.hasCalculatorViewTarget) this.calculatorViewTarget.hidden = this.viewMode !== "calculator";
    this.viewTabTargets.forEach((tab) => {
      const active = tab.dataset.viewMode === this.viewMode;
      tab.classList.toggle("is-active", active);
      tab.setAttribute("aria-selected", active ? "true" : "false");
    });
    // The platform filter belongs to the table: do not carry it into the calculator, where it
    // would silently narrow the table the next time it is opened.
    if (this.viewMode === "calculator" && this.platformFilter) this.resetPlatformFilter();
  }

  resetPlatformFilter() {
    this.platformFilter = "";
    this.platformFilterTargets.forEach((tab) => {
      const active = !tab.dataset.platformValue;
      tab.classList.toggle("is-active", active);
      tab.setAttribute("aria-selected", active ? "true" : "false");
    });
    this.applyPlatformFilter();
  }

  storedViewMode() {
    try {
      const stored = window.localStorage.getItem(VIEW_MODE_STORAGE_KEY);
      return VIEW_MODES.includes(stored) ? stored : DEFAULT_VIEW_MODE;
    } catch (error) {
      return DEFAULT_VIEW_MODE;
    }
  }

  storeViewMode(mode) {
    try {
      window.localStorage.setItem(VIEW_MODE_STORAGE_KEY, mode);
    } catch (error) {
      // Private windows and blocked storage: the choice just is not remembered.
    }
  }

  activateScenarioTab(tab) {
    const rowKey = tab.dataset.rowKey;
    const row = this.rowTargets.find((candidate) => candidate.dataset.rowKey === rowKey);
    if (!row) return;

    if (row.hidden && this.viewMode === "table") {
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
      row.hidden = this.scenarioRowOutOfScope(row) || (Boolean(filter) && row.dataset.platform !== filter);
    });

    const tables = [
      this.element.querySelector(".profit-prediction-table"),
      ...document.querySelectorAll(".sticky-table-header__table.profit-prediction-table")
    ].filter(Boolean);
    tables.forEach((table) => this.applyColumnFilter(table, filter));

    const visibleRows = this.visibleRows();
    if (!visibleRows.includes(this.selectedRow)) this.setSelectedRow(visibleRows[0]);
    if (this.hasContextCountTarget) {
      // The page sends its messages with snake_case keys (profit_messages in the ERB).
      const template = (filter ? this.messagesValue.filtered_context_count : this.messagesValue.context_count) || "";
      this.contextCountTarget.textContent = template
        .replace("__VISIBLE__", visibleRows.length)
        .replace("__TOTAL__", this.rowTargets.filter((row) => !this.scenarioRowOutOfScope(row)).length)
        .replace("__COUNT__", visibleRows.length)
        .replace("%{count}", visibleRows.length);
    }
  }

  // True for a row the current scenario scope leaves out (hidden by the SKU, or unsold in actual mode).
  scenarioRowOutOfScope(row) {
    return this.actualScenarioMode() ? row.dataset.scenarioUnsold === "true" : row.dataset.scenarioHidden === "true";
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
    this.renderLogisticsModePanel(row);
    this.renderPriceSummary(row);

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
    const process = this.messagesValue.process;
    const inputs = this.numericInputs(row);
    this.processExchangeRate = inputs.exchange_rate_rub_cny;
    this.processCurrencyUnits = process.units;

    buildCalculationSteps({
      platform: row.dataset.platform,
      market: row.dataset.market,
      deliveryMode: row.dataset.deliveryMode,
      companyType: row.dataset.companyType,
      logisticsMode: this.logisticsMode(row),
      inputs,
      data,
      labels: {
        fields: process.parameter_labels,
        steps: process.steps,
        formula: process.formula_labels,
        sumCosts: process.sum_costs,
        crossDockingNotApplicable: process.cross_docking_not_applicable,
        crossDockingInOther: process.cross_docking_in_other
      }
    }).forEach((step) => {
      this.appendProcessStep(step.label, step.formula, step.result, process.units[step.unit], step.fields, step.source, {
        key: step.key,
        note: step.note,
        inactive: step.inactive,
        inactiveFields: step.inactiveFields,
        control: step.control
      });
    });
  }

  renderIncompleteCalculationProcess(row, errors = []) {
    if (!this.hasDetailBodyTarget) return;

    this.prepareCalculationProcess(row);
    this.renderedProcessParameters = new Set();
    this.clearProcessSummary();
    const invalidFields = this.processInputFields(row, errors);
    const invalidLabels = invalidFields.map((field) => this.messagesValue.process.parameter_labels?.[field] || field);
    const incompleteMessage = errors.includes("missing_commission_base_price_rub")
      ? this.messagesValue.process.missing_commission_base_price
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

  appendProcessStep(label, formula, result, unit, parameterFields = [], sourceKey = null, { key = null, note = null, inactive = false, inactiveFields = [], control = false } = {}) {
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
    this.renderProcessParameters(parameterCell, this.selectedRow, newFields, inactive ? parameterFields : inactiveFields).forEach((field) => {
      this.renderedProcessParameters.add(field);
    });
    // The mode switch has a row of its own, under the return rate; a row reused by another step drops it.
    parameterCell.querySelector("[data-logistics-mode-control]")?.remove();
    if (key === "logistics_mode" && this.selectedRow) {
      const control = document.createElement("div");
      control.className = "profit-prediction-process__logistics-mode";
      control.dataset.logisticsModeControl = "";
      this.fillLogisticsModeControl(control, this.selectedRow);
      parameterCell.append(control);
    }
    this.renderProcessSource(sourceCell, sourceKey);
    calculationCell.className = "profit-prediction-process__calculation";
    this.renderProcessFormula(formulaElement, formula);
    resultElement.textContent = control ? "" : this.formatProcessResult(result, unit);
    this.renderProcessNote(calculationCell, note);
    if (key) row.dataset.processStepKey = key;
    else delete row.dataset.processStepKey;
    row.classList.toggle("is-inactive", inactive);
    row.classList.toggle("is-incomplete", !inactive && parameterFields.some((field) => !inactiveFields.includes(field) && this.processInvalidFields?.has(field)));
  }

  // A formula is either a plain string or a token list (see profit_prediction_formula.js): the
  // token list renders as a line of parameter names above the same line with the numbers in.
  renderProcessFormula(formulaElement, formula) {
    if (!Array.isArray(formula)) {
      formulaElement.textContent = formula;
      return;
    }

    const format = { number: (value) => this.number(value), percent: (value) => this.percent(value) };
    const named = document.createElement("span");
    const values = document.createElement("span");
    named.className = "profit-prediction-process__formula-named";
    values.className = "profit-prediction-process__formula-values";
    formula.forEach((token, index) => {
      if (index > 0) {
        named.append(" ");
        values.append(" ");
      }
      named.append(this.formulaTokenElement(token, formulaTokenName(token), formulaTokenText(token, format)));
      values.append(this.formulaTokenElement(token, formulaTokenText(token, format), formulaTokenName(token)));
    });
    formulaElement.replaceChildren(named, values);
  }

  formulaTokenElement(token, text, title) {
    const element = document.createElement("span");
    element.textContent = text;
    if (isOperator(token) || token.type === "const") {
      element.className = "profit-prediction-process__token profit-prediction-process__token--plain";
      return element;
    }

    element.className = "profit-prediction-process__token";
    element.title = `${formulaTokenName(token)} = ${formulaTokenText(token, { number: (value) => this.number(value), percent: (value) => this.percent(value) })}`;
    if (token.field) element.dataset.formulaField = token.field;
    if (token.key) element.dataset.formulaStep = token.key;
    if (token.field || token.key) {
      element.dataset.action = "mouseover->profit-prediction#highlightFormulaToken mouseout->profit-prediction#clearFormulaHighlight";
    }
    return element;
  }

  // Hovering a name or a number lights up the same token everywhere in the table, plus the
  // input it stands for (or the row of the step it quotes), so the formula reads back to the form.
  highlightFormulaToken(event) {
    this.clearFormulaHighlight();
    if (!this.hasDetailBodyTarget) return;

    const { formulaField: field, formulaStep: step } = event.currentTarget.dataset;
    const linked = [];
    if (field) {
      linked.push(...this.detailBodyTarget.querySelectorAll("[data-process-parameter-field]"));
      linked.push(...this.detailBodyTarget.querySelectorAll("[data-formula-field]"));
    }
    if (step) {
      linked.push(...this.detailBodyTarget.querySelectorAll("[data-process-step-key]"));
      linked.push(...this.detailBodyTarget.querySelectorAll("[data-formula-step]"));
    }
    this.linkedFormulaElements = linked.filter((element) => (
      (field && (element.dataset.processParameterField === field || element.dataset.formulaField === field))
      || (step && (element.dataset.processStepKey === step || element.dataset.formulaStep === step))
    ));
    this.linkedFormulaElements.forEach((element) => element.classList.add("is-formula-linked"));
  }

  clearFormulaHighlight() {
    (this.linkedFormulaElements || []).forEach((element) => element.classList.remove("is-formula-linked"));
    this.linkedFormulaElements = [];
  }

  renderProcessNote(calculationCell, note) {
    let element = calculationCell.querySelector(".profit-prediction-process__note");
    if (!note) {
      element?.remove();
      return;
    }
    if (!element) {
      element = document.createElement("span");
      element.className = "profit-prediction-process__note";
      calculationCell.append(element);
    }
    element.textContent = note;
  }

  renderProcessSource(cell, sourceKey) {
    this.renderProcessSourceControls(cell, sourceKey);

    // A scenario whose actual-data queries still cover the whole platform says so next to every
    // shortcut, so a figure taken from them is not mistaken for that market's or mode's own.
    cell.querySelector(":scope > .profit-prediction-process__source-note")?.remove();
    const pending = (this.selectedRow?.dataset.actualsPending || "").split(" ").filter(Boolean);
    if (sourceKey && cell.childElementCount > 0 && pending.includes(PENDING_KIND_BY_SOURCE[sourceKey])) {
      const note = document.createElement("div");
      note.className = "profit-prediction-process__source-note";
      note.textContent = this.messagesValue.process.sources.actuals_not_split || "";
      cell.append(note);
    }
  }

  renderProcessSourceControls(cell, sourceKey) {
    cell.className = "profit-prediction-process__source";
    if (!sourceKey) {
      cell.replaceChildren();
      delete cell.dataset.sourceKey;
      return;
    }
    const sourceRowKey = this.selectedRow?.dataset.rowKey || "";
    if (cell.dataset.sourceKey === sourceKey && cell.dataset.sourceRowKey === sourceRowKey) {
      if (sourceKey === "actual_storage") {
        const data = this.actualStorageData.get(this.actualStorageKey(this.selectedRow));
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
    if (sourceKey === "actual_acquiring") {
      this.renderActualAcquiringSource(cell);
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
    const data = this.actualLogisticsData.get(this.actualLogisticsKey(this.selectedRow));
    if (data) this.renderActualLogisticsResult(cell, data);
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
    const data = this.actualReturnRateData.get(this.actualLogisticsKey(this.selectedRow));
    if (data) this.renderActualReturnRateResult(cell, data);
  }

  renderActualAcquiringSource(cell) {
    const actions = document.createElement("div");
    actions.className = "profit-prediction-process__source-actions";
    actions.append(
      this.sourceButton("bi-credit-card", this.messagesValue.process.sources.actual_acquiring.action, "profit-prediction#loadActualAcquiring")
    );
    const result = document.createElement("div");
    result.className = "profit-prediction-process__source-result";
    result.dataset.actualAcquiringResult = "";
    cell.replaceChildren(actions, result);

    const data = this.actualAcquiringData.get(this.actualLogisticsKey(this.selectedRow));
    if (data) this.renderActualAcquiringResult(cell, data);
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
    const actions = document.createElement("div");
    actions.className = "profit-prediction-process__source-actions";
    actions.append(
      this.sourceButton(
        "bi-truck",
        this.messagesValue.process.sources.wb_logistics_tariffs.action,
        "profit-prediction#openWbLogisticsTariffs"
      ),
      this.sourceButton(
        "bi-clock-history",
        this.messagesValue.process.sources.actual_logistics.action,
        "profit-prediction#loadActualLogistics"
      )
    );
    const result = document.createElement("div");
    result.className = "profit-prediction-process__source-result";
    result.dataset.actualLogisticsResult = "";
    cell.replaceChildren(actions, result);

    const data = this.actualLogisticsData.get(this.actualLogisticsKey(this.selectedRow));
    if (data) this.renderActualLogisticsResult(cell, data);
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
    const data = this.actualStorageData.get(this.actualStorageKey(this.selectedRow));
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

  // Runs every loader of the process table (actual data and the official commission rate)
  // from top to bottom, one at a time, exactly as if each button below were clicked.
  async loadAllActuals() {
    await this.runAllActuals({ apply: false });
  }

  async loadAndApplyAllActuals() {
    await this.runAllActuals({ apply: true });
  }

  async runAllActuals({ apply }) {
    const row = this.selectedRow;
    if (!row || !this.hasDetailBodyTarget || this.bulkActualsRunning) return;
    if (apply && this.readonlyValue) return;

    this.bulkActualsRunning = true;
    this.setBulkActualButtonsDisabled(true);
    try {
      const sourceKeys = Array.from(this.detailBodyTarget.querySelectorAll(".profit-prediction-process__source[data-source-key]"))
        .map((cell) => cell.dataset.sourceKey);
      for (const sourceKey of sourceKeys) {
        if (this.selectedRow !== row) break;

        const button = this.processSourceCell(sourceKey)?.querySelector(BULK_LOAD_ACTION_SELECTOR);
        if (!button) continue;

        const method = button.dataset.action.split("#").pop();
        await this[method]({ currentTarget: button });
        if (apply && this.selectedRow === row) this.applyLoadedActual(sourceKey);
      }
    } finally {
      this.bulkActualsRunning = false;
      this.setBulkActualButtonsDisabled(false);
    }
  }

  setBulkActualButtonsDisabled(disabled) {
    if (!this.hasBulkActualButtonTarget) return;

    this.bulkActualButtonTargets.forEach((button) => { button.disabled = disabled; });
  }

  processSourceCell(sourceKey) {
    return Array.from(this.detailBodyTarget.querySelectorAll(".profit-prediction-process__source[data-source-key]"))
      .find((cell) => cell.dataset.sourceKey === sourceKey);
  }

  // Clicks the result links the loader just rendered, i.e. the same "click to fill" the
  // user would do. The process table may have been re-rendered while the request was in
  // flight, so re-render the cell from the loaded data first when its result is missing.
  applyLoadedActual(sourceKey) {
    const cell = this.processSourceCell(sourceKey);
    if (!cell) return;

    const selector = ".profit-prediction-process__source-result .profit-prediction-process__source-link";
    if (!cell.querySelector(selector)) {
      delete cell.dataset.sourceKey;
      this.renderProcessSource(cell, sourceKey);
    }
    const links = Array.from(cell.querySelectorAll(selector)).filter((link) => !link.disabled);
    // A SKU bound to products with different official rates gets one link per rate: there is
    // no way to tell which one is meant, so leave that choice to the user.
    if (sourceKey === "official_commission" && links.length > 1) return;

    links.forEach((link) => link.click());
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

  actualStorageKey(row) {
    if (!row) return "";

    return row.dataset.platform === "ozon" ? `ozon:${row.dataset.deliveryMode || "fbo"}` : row.dataset.platform;
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
      // Ozon storage is an FBO fee: the per-unit figure divides by the FBO postings only.
      if (platform === "ozon") url.searchParams.set("delivery_mode", row.dataset.deliveryMode || "fbo");
      const response = await fetch(url, { headers: { Accept: "application/json" }, signal: controller.signal });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);

      const data = await response.json();
      this.actualStorageData.set(this.actualStorageKey(row), data);
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

  async loadActualAcquiring(event) {
    if (!this.selectedRow) return;

    const row = this.selectedRow;
    const platform = row.dataset.platform;
    const key = this.actualLogisticsKey(row);
    const cell = event.currentTarget.closest(".profit-prediction-process__source");
    const result = cell?.querySelector("[data-actual-acquiring-result]");
    const messages = this.messagesValue.process.sources.actual_acquiring;
    this.actualAcquiringRequestController?.abort();
    const controller = new AbortController();
    this.actualAcquiringRequestController = controller;
    event.currentTarget.disabled = true;
    if (result) result.textContent = messages.loading;

    try {
      const url = new URL(this.actualAcquiringUrlValue, window.location.origin);
      url.searchParams.set("platform", platform);
      if (platform === "ozon") url.searchParams.set("delivery_mode", row.dataset.deliveryMode || "fbo");
      if (platform === "wb") url.searchParams.set("market", row.dataset.market);
      const response = await fetch(url, {
        headers: { Accept: "application/json" },
        signal: controller.signal
      });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);

      const data = await response.json();
      this.actualAcquiringData.set(key, data);
      if (this.actualLogisticsKey(this.selectedRow) === key) this.renderActualAcquiringResult(cell, data);
    } catch (error) {
      if (error.name !== "AbortError" && result) {
        result.className = "profit-prediction-process__source-result is-error";
        result.textContent = messages.load_failed;
      }
    } finally {
      if (this.actualAcquiringRequestController === controller) this.actualAcquiringRequestController = null;
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

    this.assignShortcutValue(input, rate);
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
    // WB's tariff base and per-litre fee are already multiplied by the coefficient (71.3 / 21.7 = 46 / 14 x 1.55), and
    // the calculator multiplies by the coefficient itself, so the fees go in with the coefficient taken back out.
    const values = {
      logistics_coeff: rate.logistics_coeff,
      wb_logistics_base_rub: withoutCoefficient(rate.base_rub, rate.logistics_coeff),
      wb_logistics_liter_rub: withoutCoefficient(rate.liter_rub, rate.logistics_coeff)
    };
    Object.entries(values).forEach(([field, value]) => {
      const input = this.selectedRow.querySelector(`[data-field='${field}']`);
      if (!input || value === undefined || value === null) return;
      this.assignShortcutValue(input, value);
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
      url.searchParams.set("delivery_mode", row.dataset.deliveryMode || "fbo");
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
    return row ? `${row.dataset.platform}:${row.dataset.market}:${row.dataset.deliveryMode || ""}` : "";
  }

  renderActualSellingPriceResult(cell, data) {
    const container = cell?.querySelector("[data-actual-selling-price-result]");
    if (!container) return;

    const commissionBase = data.commission_base_price || {};
    const buyerPaid = data.buyer_paid_price || {};
    const messages = this.messagesValue.process.sources.actual_selling_price;
    const shortcuts = sellingPriceShortcuts(this.selectedRow?.dataset.platform, data);
    const labels = {
      commission_base: { result: messages.commission_base_result, apply: messages.apply_commission_base },
      buyer_paid: { result: messages.buyer_result, apply: messages.apply_buyer }
    };
    const links = shortcuts.map(({ kind, field, priceRub }) => this.actualSellingPriceLink({
      field,
      priceRub,
      label: labels[kind].result,
      title: field ? labels[kind].apply : messages.buyer_reference_only
    }));
    if (links.length === 0) {
      const missingRate = (commissionBase.missing_exchange_rate_item_count || 0) + (buyerPaid.missing_exchange_rate_item_count || 0) > 0;
      container.className = missingRate
        ? "profit-prediction-process__source-result is-error"
        : "profit-prediction-process__source-result is-empty";
      container.textContent = missingRate ? messages.missing_rate : messages.empty;
      return;
    }

    const sources = [];
    [
      [commissionBase, messages.commission_base_converted_source],
      [buyerPaid, messages.converted_source]
    ].forEach(([price, template]) => {
      const sourceCurrency = price?.source_currency || "RUB";
      const sourceAverage = Number(price?.average_source);
      if (sourceCurrency === "RUB" || !Number.isFinite(sourceAverage) || !template) return;

      const source = document.createElement("small");
      source.textContent = template
        .replace("__SOURCE_PRICE__", this.number(sourceAverage))
        .replace("__SOURCE_CURRENCY__", sourceCurrency)
        .replace("__RUB_PRICE__", this.number(price.average_rub));
      sources.push(source);
    });

    const counted = commissionBase.item_count ? commissionBase : buyerPaid;
    const meta = document.createElement("small");
    meta.textContent = messages.meta
      .replace("__ITEMS__", counted.item_count ?? 0)
      .replace("__UNITS__", counted.unit_count ?? 0)
      .replace("__FROM__", data.period?.from_date || "-")
      .replace("__TO__", data.period?.to_date || "-")
      .replace("__DATA_THROUGH__", data.period?.data_through || "-");
    container.className = "profit-prediction-process__source-result";
    container.replaceChildren(...links, ...sources, meta);
  }

  // `field` is null for prices that are shown for reference only (no matching input).
  actualSellingPriceLink({ field, priceRub, label, title }) {
    const link = document.createElement("button");
    link.type = "button";
    link.className = "profit-prediction-process__source-link";
    link.dataset.action = "profit-prediction#applyActualSellingPrice";
    link.dataset.field = field || "";
    link.dataset.priceRub = priceRub;
    link.title = title;
    link.textContent = label.replace("__PRICE__", `${this.number(priceRub)} RUB`);
    link.disabled = this.readonlyValue || !field;
    return link;
  }

  applyActualSellingPrice(event) {
    if (!this.selectedRow || this.readonlyValue) return;

    const field = event.currentTarget.dataset.field;
    if (!field) return;

    const input = this.selectedRow.querySelector(`[data-field='${field}']`);
    const price = event.currentTarget.dataset.priceRub;
    if (!input || price === undefined || price === "") return;

    this.assignShortcutValue(input, price);
    input.dataset.valueChanged = "true";
    this.inputChanged({ target: input, type: "actual-selling-price" });
    this.schedulePreview(this.selectedRow);
  }

  async loadActualMetrics(event, kind) {
    if (!this.selectedRow) return;

    const platform = this.selectedRow.dataset.platform;
    const deliveryMode = this.selectedRow.dataset.deliveryMode || "";
    const logisticsKey = this.actualLogisticsKey(this.selectedRow);
    if (kind === "cross-dock" && platform !== "ozon") return;

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
      if (kind === "return-rate" || kind === "logistics") url.searchParams.set("platform", platform);
      // Both platforms narrow to the scenario: FBO/FBS, and for WB the market (Belarus-local or
      // export-to-Russia part of the ledger).
      if (kind === "logistics" || kind === "return-rate") {
        url.searchParams.set("delivery_mode", deliveryMode || "fbo");
        if (platform === "wb") url.searchParams.set("market", this.selectedRow.dataset.market);
      }
      const response = await fetch(url, {
        headers: { Accept: "application/json" },
        signal: controller.signal
      });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);

      const data = await response.json();
      if (kind === "return-rate") {
        this.actualReturnRateData.set(logisticsKey, data);
        if (this.actualLogisticsKey(this.selectedRow) === logisticsKey) this.renderActualReturnRateResult(cell, data);
      } else if (kind === "cross-dock") {
        this.actualMetricsData = data;
        this.actualCrossDockLoaded = true;
        if (this.selectedRow?.dataset.platform === "ozon") this.renderActualCrossDockResult(cell, this.actualMetricsData);
      } else {
        this.actualLogisticsData.set(logisticsKey, data);
        if (this.actualLogisticsKey(this.selectedRow) === logisticsKey) this.renderActualLogisticsResult(cell, data);
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
    const handoverValue = data.handover?.average_rub;
    const handover = handoverValue === null || handoverValue === undefined || handoverValue === "" ? NaN : Number(handoverValue);
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
    if (Number.isFinite(handover)) link.dataset.handoverRate = handover;
    const formulaMode = this.logisticsMode(this.selectedRow) === "formula";
    link.title = formulaMode ? this.messagesValue.logistics_mode?.reference_only || messages.apply : messages.apply;
    const outboundLine = document.createElement("span");
    outboundLine.textContent = `${messages.outbound} ${this.number(outbound)} RUB`;
    link.append(outboundLine);
    if (Number.isFinite(returnRate)) {
      const returnLine = document.createElement("span");
      returnLine.textContent = `${messages.return} ${this.number(returnRate)} RUB`;
      link.append(returnLine);
    }
    if (Number.isFinite(handover)) {
      const handoverLine = document.createElement("span");
      handoverLine.textContent = `${messages.handover} ${this.number(handover)} RUB`;
      link.append(handoverLine);
    }
    link.disabled = this.readonlyValue || formulaMode;

    const formula = this.previewData.get(this.selectedRow?.dataset.rowKey)?.logistics?.formula;
    const reference = document.createElement("small");
    const modeMessages = this.messagesValue.logistics_mode || {};
    reference.textContent = formula && formula.outbound_rub !== null && formula.outbound_rub !== undefined
      ? fill(modeMessages.compare || "", { outbound: this.number(Number(formula.outbound_rub)), return: this.number(Number(formula.return_rub)) })
      : modeMessages.no_formula || "";
    const meta = document.createElement("small");
    meta.textContent = messages.meta
      .replace("__FROM__", data.period?.from_date || "-")
      .replace("__TO__", data.period?.to_date || "-")
      .replace("__OUTBOUND_COUNT__", data.outbound?.sample_count ?? 0)
      .replace("__RETURN_COUNT__", data.return?.sample_count ?? 0)
      .replace("__DATA_THROUGH__", data.period?.data_through || "-");
    container.className = "profit-prediction-process__source-result";
    container.replaceChildren(link, meta, reference);
  }

  actualLogisticsKey(row) {
    if (!row) return "";

    return `${row.dataset.platform}:${row.dataset.deliveryMode || ""}:${row.dataset.market || ""}`;
  }

  applyActualLogistics(event) {
    if (!this.selectedRow || this.readonlyValue || this.logisticsMode(this.selectedRow) === "formula") return;

    const values = {
      outbound_logistics_rub: event.currentTarget.dataset.outboundRate,
      return_logistics_rub: event.currentTarget.dataset.returnRate,
      fbs_handover_rub: event.currentTarget.dataset.handoverRate
    };
    Object.entries(values).forEach(([field, value]) => {
      if (value === undefined || value === "") return;

      const input = this.selectedRow.querySelector(`[data-field='${field}']`);
      if (!input) return;

      this.assignShortcutValue(input, value);
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
    // Both platforms use the ledger definition: return legs billed per outbound leg billed. It
    // includes undelivered returns (which book no revenue) and is the ratio the return
    // amortization formula needs; the buyer-side rate from orders is only shown for reference.
    meta.textContent = messages.meta
      .replace("__ORDERS__", data.return_rate?.order_count ?? 0)
      .replace("__RETURNS__", data.return_rate?.return_count ?? 0)
      .replace("__FROM__", data.period?.from_date || "-")
      .replace("__TO__", data.period?.to_date || "-")
      .replace("__DATA_THROUGH__", data.period?.data_through || "-");
    const basis = document.createElement("small");
    basis.textContent = messages.basis;
    const lines = [link, meta, basis];
    const buyerRate = data.buyer_return_rate?.rate;
    if (buyerRate !== null && buyerRate !== undefined && buyerRate !== "" && Number.isFinite(Number(buyerRate))) {
      const reference = document.createElement("small");
      reference.textContent = messages.buyer_reference
        .replace("__RATE__", this.percent(buyerRate))
        .replace("__RETURNS__", data.buyer_return_rate.return_count ?? 0)
        .replace("__ORDERS__", data.buyer_return_rate.order_count ?? 0);
      lines.push(reference);
    }
    container.className = "profit-prediction-process__source-result";
    container.replaceChildren(...lines);
  }

  applyActualReturnRate(event) {
    if (!this.selectedRow || this.readonlyValue) return;

    const input = this.selectedRow.querySelector("[data-field='return_rate']");
    const rate = event.currentTarget.dataset.returnRate;
    if (!input || rate === undefined || rate === "") return;

    this.assignShortcutValue(input, rate);
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

    // The window is the cross-dock query's own (12 weeks of supplies), not the 4-week one.
    const crossDock = data.cross_dock || {};
    const meta = document.createElement("small");
    meta.textContent = messages.meta
      .replace("__UNITS__", crossDock.unit_count ?? 0)
      .replace("__SUPPLIES__", crossDock.sample_count ?? 0)
      .replace("__FROM__", crossDock.from_date || "-")
      .replace("__TO__", crossDock.to_date || "-")
      .replace("__DATA_THROUGH__", crossDock.data_through || "-");
    const notes = [];
    if (Number(crossDock.direct_unit_count) > 0) notes.push(messages.direct.replace("__COUNT__", crossDock.direct_unit_count));
    if (crossDock.expanded_to_all_history) notes.push(messages.expanded);
    if (Number(crossDock.unmatched_supply_count) > 0) {
      notes.push(messages.unmatched
        .replace("__COUNT__", crossDock.unmatched_supply_count)
        .replace("__FEE__", this.number(crossDock.unmatched_fee_rub)));
    }
    const details = notes.map((note) => {
      const element = document.createElement("small");
      element.textContent = note;
      return element;
    });
    container.className = "profit-prediction-process__source-result";
    container.replaceChildren(link, meta, ...details);
  }

  applyActualCrossDock(event) {
    if (!this.selectedRow || this.readonlyValue) return;

    const amountRub = Number(event.currentTarget.dataset.amountRub);
    const exchange = Number(this.numericInputs(this.selectedRow).exchange_rate_rub_cny);
    const input = this.selectedRow.querySelector("[data-field='cross_docking_cny']");
    if (!input || !Number.isFinite(amountRub) || !Number.isFinite(exchange) || exchange <= 0) return;

    this.assignShortcutValue(input, amountRub / exchange);
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

    this.assignShortcutValue(input, amountRub / exchange);
    input.dataset.valueChanged = "true";
    this.inputChanged({ target: input, type: "actual-storage" });
    this.schedulePreview(this.selectedRow);
  }

  renderActualAcquiringResult(cell, data) {
    const container = cell?.querySelector("[data-actual-acquiring-result]");
    if (!container) return;

    const rawRate = data.acquiring?.rate;
    const rate = rawRate === null || rawRate === undefined || rawRate === "" ? NaN : Number(rawRate);
    const messages = this.messagesValue.process.sources.actual_acquiring;
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
    link.dataset.action = "profit-prediction#applyActualAcquiring";
    link.dataset.acquiringRate = rate;
    link.title = messages.apply;
    link.textContent = messages.result.replace("__RATE__", this.percent(rate));
    link.disabled = this.readonlyValue;

    const meta = document.createElement("small");
    meta.textContent = messages.meta
      .replace("__FEE__", this.number(data.acquiring?.fee || 0))
      .replace("__BASE__", this.number(data.acquiring?.base || 0))
      .replace("__COUNT__", data.acquiring?.sample_count ?? 0)
      .replace("__FROM__", data.period?.from_date || "-")
      .replace("__TO__", data.period?.to_date || "-")
      .replace("__DATA_THROUGH__", data.period?.data_through || "-");
    container.className = "profit-prediction-process__source-result";
    container.replaceChildren(link, meta);
  }

  applyActualAcquiring(event) {
    if (!this.selectedRow || this.readonlyValue) return;

    const input = this.selectedRow.querySelector("[data-field='acquiring_rate']");
    const rate = event.currentTarget.dataset.acquiringRate;
    if (!input || rate === undefined || rate === "") return;

    this.assignShortcutValue(input, rate);
    input.dataset.valueChanged = "true";
    this.inputChanged({ target: input, type: "actual-acquiring" });
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

    this.assignShortcutValue(input, rate);
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
    this.tariffAverageRate = filter[`average_${this.tariffRateColumn()}`];
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

  // Which price of the Ozon route table applies to the scenario being priced: FBO has one, FBS
  // charges less for an item under 300 RUB.
  tariffRateColumn() {
    const row = this.selectedRow;
    if (row?.dataset.platform !== "ozon" || row.dataset.deliveryMode !== "fbs") return "fbo_rub";

    const price = this.numericInputs(row).commission_base_price_rub;
    return price !== null && price !== undefined && price < 300 ? "fbs_under_300_rub" : "fbs_over_300_rub";
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
    const rateValue = route[this.tariffRateColumn()];
    rate.textContent = `${this.number(rateValue)} RUB`;
    const button = document.createElement("button");
    button.type = "button";
    button.className = "btn btn-outline btn-sm";
    button.dataset.rate = rateValue;
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
    if (this.logisticsMode(this.selectedRow) === "formula") {
      this.renderTariffActionMessage(this.messagesValue.logistics_mode?.tariff_locked || "", true);
      return;
    }

    ["outbound_logistics_rub", "return_logistics_rub"].forEach((field) => {
      const input = this.selectedRow.querySelector(`[data-field='${field}']`);
      if (!input) return;

      this.assignShortcutValue(input, numericRate);
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

    this.assignShortcutValue(input, numericAmount / exchange);
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

      // The platform's own currency first: a step worked out in roubles reads rouble first, yuan as the reference.
      const cny = `${this.number(amounts.cny)}${this.processCurrencyUnits.cny}`;
      const rub = `${this.number(amounts.rub)}${this.processCurrencyUnits.rub}`;
      return sourceCurrency === "rub" ? `${rub} / ${cny}` : `${cny} / ${rub}`;
    }

    const formattedResult = this.number(result);
    return formattedResult === "-" ? "-" : `${formattedResult} ${unit}`.trim();
  }

  renderProcessSummary(row, data) {
    this.renderPriceSummary(row);
    if (this.hasDetailPlatformSubsidyTarget) this.detailPlatformSubsidyTarget.textContent = this.number(data.intermediate?.platform_subsidy_rub);
    if (this.hasDetailTotalCostTarget) this.detailTotalCostTarget.textContent = this.number(data.total_cost_cny);
    if (this.hasDetailProfitTarget) this.detailProfitTarget.textContent = this.number(data.profit_cny);
    if (this.hasDetailMarginTarget) this.detailMarginTarget.textContent = `${this.number(Number(data.margin) * 100)}%`;
    this.syncTargetMargin(row, data.margin);
  }

  renderPriceSummary(row) {
    const inputs = row ? this.numericInputs(row) : {};
    if (this.hasDetailCommissionBasePriceTarget) {
      this.detailCommissionBasePriceTarget.textContent = this.number(inputs.commission_base_price_rub);
    }
    if (this.hasDetailBuyerPaidPriceTarget) {
      this.detailBuyerPaidPriceTarget.textContent = this.number(inputs.buyer_paid_price_rub);
    }
  }

  // VAT embedded in the buyer price when the row has no explicit value:
  // Russian buyers (Ozon RU) 22%, Belarusian buyers (Ozon BY) and WB 20%.
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
    const priceInput = row.querySelector("[data-field='commission_base_price_rub']");
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
    // Ozon's target margin is based on the seller/list price (and commission
    // base), while the buyer-paid price is an independent subsidy input.
    const priceInput = row.querySelector("[data-field='commission_base_price_rub']");
    if (!priceInput || priceRub === null) {
      this.markTargetMarginInvalid(input, true);
      return;
    }

    this.markTargetMarginInvalid(input, false);
    this.assignShortcutValue(priceInput, priceRub);
    priceInput.dataset.valueChanged = "true";
    this.inputChanged({ target: priceInput, type: "target-margin" });
    this.schedulePreview(row);
  }

  async previewTargetMarginBaseData(row) {
    const controller = new AbortController();
    this.targetMarginRequestController = controller;
    const inputs = this.rowInputs(row);
    const probePrice = Number(inputs.commission_base_price_rub);

    // The calculator needs a positive commission base price to produce a preview. A
    // temporary 1 RUB probe is enough because target-price solving removes
    // all price-variable costs from the returned total.
    if (!Number.isFinite(probePrice) || probePrice <= 0) inputs.commission_base_price_rub = "1";

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: this.jsonHeaders(),
        body: JSON.stringify({
          platform: row.dataset.platform,
          parameter_context: this.parameterContext(row),
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
    if (this.hasDetailCommissionBasePriceTarget) this.detailCommissionBasePriceTarget.textContent = "-";
    if (this.hasDetailBuyerPaidPriceTarget) this.detailBuyerPaidPriceTarget.textContent = "-";
    if (this.hasDetailPlatformSubsidyTarget) this.detailPlatformSubsidyTarget.textContent = "-";
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

  // inactiveFields are shown greyed out and cannot be edited: they do not count in the calculation right now.
  renderProcessParameters(cell, row, fields, inactiveFields = []) {
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
      const inactive = inactiveFields.includes(field);
      input.disabled = field === "target_margin" ? this.readonlyValue : source.disabled || source.dataset.editable === "false" || inactive;
      wrapper?.classList.toggle("is-inactive", inactive);
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

    const label = this.messagesValue.process.parameter_labels?.[field] || field;
    const percent = row.querySelector(`[data-field='${field}']`)?.dataset.percent === "true";
    return percent ? `${label} (%)` : label;
  }

  processInputStep(field) {
    return this.processInputNumberOptions(field).step;
  }

  processInputNumberOptions(field) {
    const rateFields = [
      "duty_rate", "import_vat_rate", "commission_rate", "acquiring_rate",
      "advertising_rate", "tax_rate", "sales_vat_rate", "return_rate",
      "logistics_tax_rate", "damage_rate", "buyer_price_vat_rate"
    ];
    if (field === "target_margin") return { step: "1", min: "0", max: "100" };
    // Rates are stored as ratios (15% = 0.15) but typed and shown as percentages, so the
    // stepper moves one percentage point (15 -> 16). Manual input accepts more precision,
    // e.g. 7.5 for a 7.5% commission rate.
    if (rateFields.includes(field)) return { step: "1", min: "0", max: "100" };
    if (["length_cm", "width_cm", "height_cm"].includes(field)) {
      return { step: "0.1", min: "0" };
    }
    if (["commission_base_price_rub", "buyer_paid_price_rub"].includes(field)) {
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
          // A figure the fixed formula shows is what the formula says, not the stored real figure behind it.
          const value = this.logisticsInputLocked(input) ? input.value : profitInputValue(input);
          return [input.dataset.field, value === "" ? null : Number(value)];
        })
    );

    return inputs;
  }

  // Shortcuts (official commission, actual return rate, ...) compute ratios; a percent input
  // (data-percent) must be given the percentage, everything else the plain value.
  assignShortcutValue(input, value) {
    const plain = shortcutInputValue(value);
    input.value = input.dataset.percent === "true" ? ratioToPercentString(plain) : plain;
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
      : this.rowTargets.filter((row) => this.dirtyRows.has(row.dataset.rowKey) || !row.dataset.contextId);

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
      input.disabled = !this.calculationMode || input.dataset.editable === "false" || this.logisticsInputLocked(input);
      if (this.logisticsInputLocked(input)) input.title = this.messagesValue.logistics_mode?.locked_title || "";
    });
    this.targetMarginTargets.forEach((input) => { input.disabled = !this.calculationMode; });
    this.versionInputTargets.forEach((input) => { input.disabled = !this.calculationMode; });
    if (this.hasNavigationControlTarget) {
      this.navigationControlTarget.disabled = this.navigationWasDisabled;
    }
    if (this.hasSaveButtonTarget) this.saveButtonTarget.hidden = !this.calculationMode;
    this.updateControls();
  }

  // Rows of a saved version that have no record yet: scenarios added after the version was made.
  // They are not unsaved edits (leaving the page loses nothing), but saving writes them.
  unsavedNewRows() {
    return this.newRecordValue ? [] : this.rowTargets.filter((row) => !row.dataset.contextId);
  }

  updateControls() {
    const dirty = this.dirtyRows.size > 0 || this.versionDirty;
    if (this.hasSaveButtonTarget) this.saveButtonTarget.disabled = !(dirty || this.unsavedNewRows().length > 0) || this.saving;
    if (this.hasNavigationControlTarget) {
      // Unsaved edits do not lock the switcher: changeVersion asks before throwing them away.
      this.navigationControlTarget.disabled = this.navigationWasDisabled || this.saving;
    }
    if (!this.hasModeStatusTarget) return;

    // The yellow state only appears once something differs from what is stored: an untouched
    // saved version reads "saved", not "measuring".
    const showDirty = this.calculationMode && dirty;
    this.modeStatusTarget.classList.toggle("is-dirty", showDirty);
    this.modeStatusTarget.textContent = showDirty
      ? this.messagesValue.dirty.replace("__COUNT__", Math.max(this.dirtyRows.size, 1))
      : this.messagesValue.saved;
  }

  contextPayload(row) {
    return {
      id: row.dataset.contextId || undefined,
      context: this.contextAttributes(row),
      logistics_mode: this.logisticsMode(row),
      inputs: this.rowInputs(row)
    };
  }

  // What the calculator is asked about a scenario: its identity and how its freight is decided.
  parameterContext(row) {
    return { ...this.contextAttributes(row), logistics_mode: this.logisticsMode(row) };
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
        .map((input) => [input.dataset.field, this.logisticsInputLocked(input) && input.dataset.stashedValue !== undefined
          ? input.dataset.stashedValue
          : profitInputValue(input)])
    );

    return inputs;
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
