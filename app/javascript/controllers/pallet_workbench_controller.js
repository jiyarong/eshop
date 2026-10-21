import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["pick", "catalogueRow", "manifest", "itemTemplate", "status", "results", "autoDialog", "mySkus", "threshold", "autoStatus", "autoPreviewButton", "autoApplyButton", "allocationPanel", "allocationRows", "allocationTemplate", "mode", "emptyManifest", "skuCount", "boxCount", "unitCount", "weightCount", "saveButton", "calculateButton", "recommendButton", "undoButton", "capacity", "heightMeter", "heightLabel", "weightMeter", "weightLabel", "shippingMode", "shippingAdvice", "fillButton", "cataloguePanel", "catalogueToggle", "catalogueCollapseLabel", "catalogueExpandLabel", "maxButton"];
  static values = { catalogue: Array, context: Object, initial: Array, allocations: Array, previewUrl: String, autoUrl: String, saveUrl: String, method: String, planId: String, messages: Object };

  connect() {
    if (!this.hasManifestTarget) return;
    this.revision = (this.revision || 0) + 1;
    this.storageKey = `pallet-workbench:${this.planIdValue || (this.contextValue.delivery_plan_id ? `delivery-${this.contextValue.delivery_plan_id}` : "new")}:${this.contextValue.store_id}:${this.contextValue.cluster_id}`;
    let stored;
    try { stored = JSON.parse(sessionStorage.getItem(this.storageKey)); } catch (_) { stored = null; }
    // An edited server plan may have changed in another tab since this local draft.
    if (stored?.lockVersion !== this.contextValue.lock_version) stored = null;
    this.items = stored?.items || this.initialValue || [];
    this.allocations = stored?.allocations || this.allocationsValue || [];
    this.modeTarget.value = stored?.mode || (this.allocations.length > 1 ? "multiple" : "single");
    if (this.hasShippingModeTarget && stored?.shippingMode) this.shippingModeTarget.value = stored.shippingMode;
    this.element.querySelectorAll("[data-shipping]").forEach((input) => {
      if (stored?.shipping && Object.hasOwn(stored.shipping, input.dataset.shipping)) input.value = stored.shipping[input.dataset.shipping];
    });
    this.element.querySelectorAll("[data-setting]").forEach((input) => {
      if (stored?.settings && Object.hasOwn(stored.settings, input.dataset.setting)) input.value = stored.settings[input.dataset.setting];
    });
    this.renderItems();
    this.renderAllocations();
    this.invalidate();
  }

  disconnect() { clearTimeout(this.timer); this.revision += 1; }

  changeStore(event) {
    event.target.form.querySelector("[name=cluster_id]").value = "";
    event.target.form.requestSubmit();
  }

  toggleCatalogue() {
    const collapsed = this.element.classList.toggle("pallet-workbench--catalogue-collapsed");
    this.cataloguePanelTargets.forEach((panel) => { panel.hidden = collapsed; });
    this.catalogueToggleTarget.setAttribute("aria-expanded", String(!collapsed));
    this.catalogueCollapseLabelTarget.hidden = collapsed;
    this.catalogueExpandLabelTarget.hidden = !collapsed;
    window.dispatchEvent(new Event("resize"));
  }

  toggleDetails(event) {
    // The shared sticky header clones this table into document.body.
    document.querySelectorAll("table.pallet-workbench__stock-table").forEach((table) => {
      table.classList.toggle("pallet-workbench__show-stock-details", event.target.checked);
    });
  }

  remember() {
    this.previous = JSON.parse(JSON.stringify({ items: this.items, allocations: this.allocations, mode: this.modeTarget.value, shippingMode: this.hasShippingModeTarget ? this.shippingModeTarget.value : "pallet" }));
    this.undoButtonTarget.hidden = false;
  }

  undo() {
    if (!this.previous) return;
    this.items = this.previous.items;
    this.allocations = this.previous.allocations;
    this.modeTarget.value = this.previous.mode;
    if (this.hasShippingModeTarget) this.shippingModeTarget.value = this.previous.shippingMode;
    this.previous = null;
    this.undoButtonTarget.hidden = true;
    this.renderItems(); this.renderAllocations(); this.invalidate();
  }

  pick(event) {
    const sku = event.target.dataset.sku;
    if (event.target.checked && (!this.hasShippingModeTarget || this.shippingModeTarget.value === "pallet") && this.modeTarget.value === "single" && this.items.length >= 5) {
      event.target.checked = false;
      this.setStatus(this.messagesValue.single_limit, true);
      return;
    }
    this.remember();
    if (event.target.checked) {
      if (!this.items.some((item) => item.sku_code === sku)) this.items.push(this.itemFor(sku));
    } else this.items = this.items.filter((item) => item.sku_code !== sku);
    this.allocations = [];
    this.renderItems(); this.renderAllocations(); this.invalidate();
  }

  itemFor(sku, quantity) {
    const row = this.catalogueValue.find((item) => item.sku_code === sku) || {};
    const packaging = row.packaging || row;
    const item = { sku_code: sku, quantity: quantity ?? Math.max(1, row.suggested_boxes || 1) };
    ["length", "width", "height", "weight", "pcs", "unit_volume_l", "rotatable"].forEach((key) => { item[key] = packaging[key] ?? row[key] ?? (key === "rotatable" ? false : ""); });
    return item;
  }

  renderItems() {
    this.manifestTarget.replaceChildren();
    this.items.forEach((item, index) => {
      const fragment = this.itemTemplateTarget.content.cloneNode(true);
      const card = fragment.querySelector("[data-item]");
      card.dataset.sku = item.sku_code;
      card.querySelector("[data-code]").textContent = item.sku_code;
      card.querySelector("[data-name]").textContent = this.catalogueValue.find((row) => row.sku_code === item.sku_code)?.product_name || "";
      card.querySelectorAll("[data-field]").forEach((input) => {
        if (input.type === "checkbox") input.checked = item[input.dataset.field] === true || item[input.dataset.field] === "1";
        else input.value = item[input.dataset.field] ?? "";
      });
      const quantity = card.querySelector('[data-field="quantity"]');
      quantity.id = `pallet-quantity-${index}`;
      card.querySelector("[data-quantity-label]").htmlFor = quantity.id;
      card.querySelector('[data-pallet-workbench-target="maxButton"]').setAttribute("aria-label", this.messagesValue.max_label.replace("%{sku}", item.sku_code));
      if (["length", "width", "height", "weight", "pcs"].some((key) => !Number(item[key]))) card.querySelector("details").open = true;
      this.manifestTarget.append(fragment);
    });
    this.pickTargets.forEach((input) => { input.checked = this.items.some((item) => item.sku_code === input.dataset.sku); });
    this.catalogueRowTargets.forEach((row) => { row.classList.toggle("is-selected", this.items.some((item) => item.sku_code === row.dataset.sku)); });
    this.updateSummary();
    this.persist();
  }

  updateSummary() {
    this.emptyManifestTarget.hidden = this.items.length > 0;
    this.skuCountTargets.forEach((target) => { target.textContent = this.items.length; });
    this.boxCountTarget.textContent = this.items.reduce((sum, item) => sum + Number(item.quantity || 0), 0);
    this.unitCountTarget.textContent = this.items.reduce((sum, item) => sum + Number(item.quantity || 0) * Number(item.pcs || 0), 0);
    this.weightCountTarget.textContent = this.items.reduce((sum, item) => sum + Number(item.quantity || 0) * Number(item.weight || 0), 0).toFixed(1);
    this.manifestTarget.querySelectorAll("[data-item]").forEach((card) => {
      const item = this.items.find((row) => row.sku_code === card.dataset.sku);
      const source = this.catalogueValue.find((row) => row.sku_code === item.sku_code);
      const max = source && Number(item.pcs) > 0 ? Math.floor(source.fbs_allocatable / Number(item.pcs)) : null;
      card.querySelector("[data-stock]").textContent = max === null ? "" : this.messagesValue.stock.replace("%{suggested}", source.suggested_boxes).replace("%{max}", Math.max(0, max));
      const input = card.querySelector('[data-field="quantity"]');
      if (max !== null) input.max = Math.max(0, max);
      input.setAttribute("aria-invalid", String(!input.checkValidity()));
    });
    this.updateButtons();
  }

  changeItem(event) {
    const input = event.target;
    this.remember();
    const item = this.items.find((row) => row.sku_code === input.closest("[data-item]").dataset.sku);
    item[input.dataset.field] = input.type === "checkbox" ? input.checked : input.value;
    this.allocations = [];
    this.renderAllocations(); this.updateSummary(); this.invalidate();
  }

  stepQuantity(event) {
    const input = event.currentTarget.closest("[data-item]").querySelector('[data-field="quantity"]');
    const next = Number(input.value) + Number(event.currentTarget.dataset.delta);
    if (next < 1 || (input.max !== "" && next > Number(input.max))) return;
    input.value = next;
    this.changeItem({ target: input });
  }

  removeItem(event) {
    this.remember();
    this.items = this.items.filter((item) => item.sku_code !== event.currentTarget.closest("[data-item]").dataset.sku);
    this.allocations = [];
    this.renderItems(); this.renderAllocations(); this.invalidate();
  }

  changeMode() {
    this.remember(); this.previous.mode = this.currentMode;
    this.allocations = []; this.renderAllocations(); this.invalidate();
  }

  changeShippingMode() {
    this.allocations = []; this.renderAllocations(); this.invalidate();
  }

  useShippingMode(event) {
    this.remember();
    this.shippingModeTarget.value = event.currentTarget.dataset.mode;
    this.changeShippingMode();
  }

  invalidate() {
    this.revision += 1;
    this.validated = false;
    // Keep the sticky editor and page scroll range stable while replacing stale results.
    this.resultsTarget.style.minHeight = this.items.length ? `${this.resultsTarget.getBoundingClientRect().height}px` : "";
    this.resultsTarget.replaceChildren();
    if (this.hasShippingAdviceTarget) this.shippingAdviceTarget.textContent = this.items.length ? this.messagesValue.shipping_pending : this.messagesValue.shipping_empty;
    this.capacityTarget.hidden = true;
    this.setStatus(this.items.length ? this.messagesValue.changed : this.messagesValue.empty);
    this.updateButtons(); this.persist();
    clearTimeout(this.timer);
    if (this.items.length) this.timer = setTimeout(() => this.calculate(true), 650);
  }

  setStatus(message, error = false) {
    this.statusTarget.textContent = message;
    this.statusTarget.classList.toggle("is-error", error);
  }

  updateButtons() {
    this.saveButtonTarget.disabled = this.busy || !this.validated;
    this.calculateButtonTarget.disabled = this.busy || !this.items.length;
    this.calculateButtonTarget.textContent = (!this.hasShippingModeTarget || this.shippingModeTarget.value === "pallet") && this.modeTarget.value === "single" ? this.messagesValue.fit : this.messagesValue.recalculate;
    if (this.hasFillButtonTarget) this.fillButtonTarget.disabled = this.busy || !this.items.length || this.contextValue.fill_free_space === false || (this.hasShippingModeTarget && this.shippingModeTarget.value === "box");
    this.maxButtonTargets.forEach((button) => {
      button.hidden = this.hasShippingModeTarget && this.shippingModeTarget.value === "box";
      button.disabled = this.busy;
      button.setAttribute("aria-busy", String(this.busy && button.closest("[data-item]").dataset.sku === this.maximizingSku));
    });
    if (this.hasShippingAdviceTarget) this.shippingAdviceTarget.querySelectorAll("button").forEach((button) => { button.disabled = this.busy; });
    this.recommendButtonTarget.disabled = this.busy || !this.catalogueValue.some((row) => row.packaging_complete && row.suggested_boxes > 0);
  }

  settings() {
    const settings = {};
    this.element.querySelectorAll("[data-setting]").forEach((input) => { settings[input.dataset.setting] = input.value; });
    return settings;
  }

  persist() {
    if (!this.storageKey) return;
    try { sessionStorage.setItem(this.storageKey, JSON.stringify({ items: this.items, allocations: this.allocations, mode: this.modeTarget.value, settings: this.settings(), shipping: this.shipping(), shippingMode: this.hasShippingModeTarget ? this.shippingModeTarget.value : "pallet", lockVersion: this.contextValue.lock_version })); } catch (_) { /* Storage is optional. */ }
  }

  shipping() {
    const shipping = {};
    this.element.querySelectorAll("[data-shipping]").forEach((input) => { shipping[input.dataset.shipping] = input.value; });
    return shipping;
  }

  payload(manual = true) {
    return { ...this.contextValue, items: this.items, settings: this.settings(), shipping: this.shipping(), shipping_mode: this.hasShippingModeTarget ? this.shippingModeTarget.value : "pallet", packing_mode: this.modeTarget.value, allocations: manual ? this.allocations : [] };
  }

  async request(url, body, method = "POST") {
    const response = await fetch(url, { method, credentials: "same-origin", headers: { "Content-Type": "application/json", "Accept": "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "" }, body: JSON.stringify(body) });
    const data = await response.json();
    if (!response.ok) throw new Error(data.error || this.messagesValue.failed);
    return data;
  }

  async preview() { await this.calculate(false, (!this.hasShippingModeTarget || this.shippingModeTarget.value === "pallet") && this.modeTarget.value === "single" ? this.items : null); }
  async validateAllocation() { await this.calculate(true); }
  async fillFreeSpace() { await this.calculate(false, null, true); }
  async maximizeItem(event) {
    const sku = event.currentTarget.closest("[data-item]").dataset.sku;
    await this.calculate(false, null, false, sku);
  }

  async recommendOne() {
    // Use all filtered pages and a stable urgency order, regardless of table sorting.
    const candidates = this.catalogueValue.filter((row) => row.packaging_complete && row.suggested_boxes > 0)
      .sort((a, b) => b.shortage - a.shortage || b.daily_sales - a.daily_sales || a.sku_code.localeCompare(b.sku_code)).slice(0, 5);
    if (!candidates.length) return;
    await this.calculate(false, candidates.map((row) => this.itemFor(row.sku_code, row.suggested_boxes)));
  }

  async calculate(manual, recommendation = null, fill = false, maximizeSku = null) {
    clearTimeout(this.timer);
    if (this.busy || (!recommendation && !this.items.length)) return;
    const invalidInputs = [...this.manifestTarget.querySelectorAll("input:invalid")];
    if (!recommendation && invalidInputs.some((input) => !(maximizeSku && this.modeTarget.value === "single" && input.dataset.field === "quantity" && input.closest("[data-item]").dataset.sku === maximizeSku))) {
      this.setStatus(this.messagesValue.invalid_items, true);
      if (this.hasShippingAdviceTarget) this.shippingAdviceTarget.textContent = this.messagesValue.shipping_failed;
      return;
    }
    const revision = this.revision;
    this.busy = true;
    this.maximizingSku = maximizeSku;
    this.setStatus(maximizeSku ? this.messagesValue.maximizing.replace("%{sku}", maximizeSku) : this.messagesValue.calculating); this.updateButtons();
    try {
      const payload = this.payload(manual);
      if (fill) Object.assign(payload, { apply_fill: true, shipping_mode: "pallet", allocations: [] });
      if (maximizeSku) Object.assign(payload, { maximize_sku_code: maximizeSku, shipping_mode: "pallet", allocations: [] });
      if (recommendation) Object.assign(payload, { items: recommendation, recommend_one: true, packing_mode: "single", allocations: [] });
      if (recommendation) payload.shipping_mode = "pallet";
      const data = await this.request(this.previewUrlValue, { pallet_plan: payload });
      if (revision !== this.revision || !this.element.isConnected) return;
      if (recommendation || data.result.fill?.changes?.length || (data.result.maximized && data.result.maximized.from_boxes !== data.result.maximized.to_boxes)) {
        this.remember();
        this.items = data.result.items;
        if (recommendation) this.modeTarget.value = "single";
        if (this.hasShippingModeTarget) this.shippingModeTarget.value = "pallet";
        this.renderItems();
      }
      this.resultsTarget.innerHTML = data.html;
      if (this.hasShippingAdviceTarget) this.shippingAdviceTarget.innerHTML = data.shipping_advice_html || "";
      this.allocations = data.result.pallets.map((pallet) => {
        const quantities = new Map();
        pallet.zones.forEach((zone) => {
          const sku = data.result.items[zone.item_index].sku_code;
          quantities.set(sku, (quantities.get(sku) || 0) + zone.count);
        });
        return { items: [...quantities].map(([sku_code, quantity]) => ({ sku_code, quantity })) };
      });
      this.renderAllocations();
      this.capacityTarget.hidden = data.result.shipping_mode === "box" || data.result.pallets.length !== 1;
      if (data.result.shipping_mode !== "box" && data.result.pallets.length === 1) {
        const pallet = data.result.pallets[0];
        this.heightMeterTarget.max = data.result.settings.height;
        this.heightMeterTarget.value = pallet.height;
        this.heightLabelTarget.textContent = `${pallet.height.toFixed(1)} / ${data.result.settings.height}`;
        this.weightMeterTarget.max = data.result.settings.weight;
        this.weightMeterTarget.value = pallet.weight;
        this.weightLabelTarget.textContent = `${pallet.weight.toFixed(1)} / ${data.result.settings.weight}`;
      }
      this.validated = true;
      if (maximizeSku) this.setStatus(this.messagesValue.maximized.replace("%{sku}", maximizeSku).replace("%{boxes}", data.result.maximized.to_boxes));
      else if (fill) this.setStatus(data.result.fill?.changes?.length ? this.messagesValue.filled : this.messagesValue.fill_unchanged);
      else this.setStatus(recommendation ? this.messagesValue.recommended : this.messagesValue.validated);
    } catch (error) {
      if (revision === this.revision) {
        this.validated = false; this.setStatus(error.message, true);
        if (this.hasShippingAdviceTarget) this.shippingAdviceTarget.textContent = this.messagesValue.shipping_failed;
      }
    } finally {
      this.busy = false; this.updateButtons();
      if (revision !== this.revision && this.element.isConnected && this.items.length) this.timer = setTimeout(() => this.calculate(true), 650);
    }
  }

  async save() {
    if (this.busy || !this.validated) return;
    this.busy = true;
    this.setStatus(this.messagesValue.saving); this.updateButtons();
    try {
      const data = await this.request(this.saveUrlValue, { pallet_plan: this.payload() }, this.methodValue);
      sessionStorage.removeItem(this.storageKey);
      window.location.assign(data.url);
    } catch (error) { this.setStatus(error.message, true); this.busy = false; this.updateButtons(); }
  }

  renderAllocations() {
    this.currentMode = this.modeTarget.value;
    this.allocationPanelTarget.hidden = (this.hasShippingModeTarget && this.shippingModeTarget.value === "box") || this.modeTarget.value === "single" || this.allocations.length === 0;
    this.allocationRowsTarget.replaceChildren();
    this.allocations.forEach((pallet, index) => {
      const fragment = this.allocationTemplateTarget.content.cloneNode(true);
      const fieldset = fragment.querySelector("fieldset");
      fieldset.dataset.index = index;
      fieldset.querySelector("[data-title]").textContent = this.messagesValue.pallet.replace("%{number}", index + 1);
      this.items.forEach((item) => {
        const label = document.createElement("label");
        label.className = "field";
        label.append(document.createTextNode(item.sku_code));
        const input = document.createElement("input");
        input.type = "number"; input.min = "0"; input.step = "1";
        input.value = pallet.items.find((row) => row.sku_code === item.sku_code)?.quantity || 0;
        input.dataset.sku = item.sku_code;
        input.dataset.action = "change->pallet-workbench#changeAllocation";
        label.append(input);
        fieldset.querySelector("[data-items]").append(label);
      });
      this.allocationRowsTarget.append(fragment);
    });
    this.persist();
  }

  changeAllocation(event) {
    this.remember();
    const pallet = this.allocations[Number(event.target.closest("fieldset").dataset.index)];
    const sku = event.target.dataset.sku;
    pallet.items = pallet.items.filter((item) => item.sku_code !== sku);
    if (Number(event.target.value) > 0) pallet.items.push({ sku_code: sku, quantity: event.target.value });
    this.invalidate();
  }

  addPallet() { this.remember(); this.allocations.push({ items: [] }); this.renderAllocations(); this.invalidate(); }
  removePallet(event) { this.remember(); this.allocations.splice(Number(event.currentTarget.closest("fieldset").dataset.index), 1); this.renderAllocations(); this.invalidate(); }
  openAuto() { this.pendingAuto = null; this.autoApplyButtonTarget.disabled = true; this.autoStatusTarget.textContent = ""; this.autoDialogTarget.showModal(); }
  closeAuto() { this.autoDialogTarget.close(); }

  async autoSelect() {
    this.pendingAuto = null;
    this.autoApplyButtonTarget.disabled = true;
    this.autoPreviewButtonTarget.disabled = true;
    this.autoStatusTarget.textContent = this.messagesValue.calculating;
    try {
      const data = await this.request(this.autoUrlValue, { ...this.contextValue, my_skus: this.mySkusTarget.checked, shortage_gt: this.thresholdTarget.value });
      this.pendingAuto = data.items;
      this.autoApplyButtonTarget.disabled = !data.items.length;
      this.autoStatusTarget.textContent = this.messagesValue.selection.replace("%{selected}", data.selected_count).replace("%{excluded}", data.excluded.length);
    } catch (error) { this.autoStatusTarget.textContent = error.message; }
    finally { this.autoPreviewButtonTarget.disabled = false; }
  }

  applyAuto() {
    if (!this.pendingAuto) return;
    this.remember();
    this.items = this.pendingAuto.map((item) => this.itemFor(item.sku_code, item.quantity));
    this.modeTarget.value = "multiple";
    this.allocations = [];
    this.renderItems(); this.renderAllocations(); this.invalidate(); this.closeAuto();
  }
}
