import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["manifest", "itemTemplate", "pick", "week", "status", "save"];
  static values = { context: Object, initial: Array, messages: Object };

  connect() {
    if (!this.hasManifestTarget) return;
    const context = this.contextValue;
    this.storageKey = `delivery-workbench:${context.id || "new"}:${context.store_id}`;
    let stored;
    try { stored = JSON.parse(sessionStorage.getItem(this.storageKey)); } catch (_) { stored = null; }
    if (stored?.lockVersion !== context.lock_version) stored = null;
    this.items = stored?.items || this.initialValue || [];
    if (stored?.week) this.weekTarget.value = stored.week;
    this.render();
  }

  changeStore(event) {
    event.target.form.elements.namedItem("cluster_id").value = "";
    event.target.form.requestSubmit();
  }

  changeCluster(event) {
    event.target.form.requestSubmit();
  }

  pick(event) {
    const code = event.target.dataset.sku;
    if (event.target.checked && !this.items.some((item) => item.sku_code === code)) {
      this.items.push({ sku_code: code, units: null });
    } else if (!event.target.checked) this.items = this.items.filter((item) => item.sku_code !== code);
    this.render();
  }

  render() {
    this.manifestTarget.replaceChildren();
    this.items.forEach((item) => {
      const fragment = this.itemTemplateTarget.content.cloneNode(true);
      fragment.querySelector("[data-item]").dataset.sku = item.sku_code;
      fragment.querySelector("[data-code]").textContent = item.sku_code;
      fragment.querySelector("input").value = item.units ?? "";
      this.manifestTarget.append(fragment);
    });
    this.pickTargets.forEach((input) => { input.checked = this.items.some((item) => item.sku_code === input.dataset.sku); });
    this.saveTarget.disabled = this.busy || !this.items.length || !this.contextValue.cluster_id;
    this.persist();
  }

  changeUnits(event) {
    const code = event.target.closest("[data-item]").dataset.sku;
    this.items.find((item) => item.sku_code === code).units = event.target.value;
    this.persist();
  }

  remove(event) {
    this.items = this.items.filter((item) => item.sku_code !== event.target.closest("[data-item]").dataset.sku);
    this.render();
  }

  persist() {
    if (!this.storageKey) return;
    try { sessionStorage.setItem(this.storageKey, JSON.stringify({ items: this.items, week: this.weekTarget.value, lockVersion: this.contextValue.lock_version })); } catch (_) { /* Storage is optional. */ }
  }

  async save(event) {
    event.preventDefault();
    if (this.busy || !this.items.length || !event.target.reportValidity()) return;
    this.busy = true;
    this.saveTarget.disabled = true;
    this.statusTarget.textContent = this.messagesValue.saving;
    try {
      const response = await fetch(event.target.action, { method: this.contextValue.id ? "PATCH" : "POST", credentials: "same-origin",
        headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "" },
        body: JSON.stringify({ delivery_plan: { ...this.contextValue, week_start: this.weekTarget.value, items: this.items } }) });
      const data = await response.json();
      if (!response.ok) throw new Error(data.error || this.messagesValue.failed);
      sessionStorage.removeItem(this.storageKey);
      window.location.assign(data.url);
    } catch (error) {
      this.statusTarget.textContent = error.message;
      this.busy = false;
      this.saveTarget.disabled = false;
    }
  }
}
