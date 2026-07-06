import { Controller } from "@hotwired/stimulus";

export function setToggleIcon(button, expanded) {
  const icon = button.querySelector("i");
  if (!icon) return;

  icon.classList.toggle("bi-chevron-right", !expanded);
  icon.classList.toggle("bi-chevron-down", expanded);
}

export default class extends Controller {
  connect() {
    this.boundPersistState = this.persistState.bind(this);
    window.addEventListener("pagehide", this.boundPersistState);
    document.addEventListener("turbo:before-cache", this.boundPersistState);
    this.restoreState();
  }

  disconnect() {
    window.removeEventListener("pagehide", this.boundPersistState);
    document.removeEventListener("turbo:before-cache", this.boundPersistState);
  }

  toggleMaster(event) {
    const button = event.currentTarget;
    const row = event.currentTarget.closest("tr.master");
    const detailRow = row?.nextElementSibling;
    if (!row || !this.isDetailRow(detailRow)) return;

    const expanded = row.classList.toggle("open");
    this.updateButton(button, expanded);
    detailRow.hidden = !expanded;
    this.persistState();
  }

  toggleSku(event) {
    const button = event.currentTarget;
    const row = event.currentTarget.closest("tr.sku-row");
    const detailRow = row?.nextElementSibling;
    if (!row || !detailRow?.classList.contains("batch-row")) return;

    const expanded = row.classList.toggle("open");
    this.updateButton(button, expanded);
    detailRow.hidden = !expanded;
    this.persistState();
  }

  isDetailRow(row) {
    return row.classList.contains("sub-row") || row.classList.contains("batch-row");
  }

  updateButton(button, expanded) {
    button.setAttribute("aria-expanded", expanded ? "true" : "false");
    setToggleIcon(button, expanded);
    const label = button.dataset.label || "详情";
    button.setAttribute("aria-label", `${expanded ? "收起" : "展开"} ${label}`);
  }

  persistState() {
    if (!this.storageAvailable()) return;

    window.sessionStorage.setItem(this.storageKey(), JSON.stringify({
      expandedKeys: this.expandedKeys(),
      scrollY: window.scrollY || window.pageYOffset || 0
    }));
  }

  restoreState() {
    if (!this.storageAvailable()) return;

    const rawState = window.sessionStorage.getItem(this.storageKey());
    if (!rawState) return;

    let state;

    try {
      state = JSON.parse(rawState);
    } catch (_error) {
      window.sessionStorage.removeItem(this.storageKey());
      return;
    }

    const expandedKeys = new Set(Array.isArray(state.expandedKeys) ? state.expandedKeys : []);

    this.element.querySelectorAll("button.product-tree-toggle[data-tree-key]").forEach((button) => {
      if (!expandedKeys.has(button.dataset.treeKey)) return;

      const row = button.closest("tr");
      const detailRow = row?.nextElementSibling;
      if (!row || !this.isDetailRow(detailRow)) return;

      row.classList.add("open");
      this.updateButton(button, true);
      detailRow.hidden = false;
    });

    const scrollY = Number(state.scrollY);
    if (Number.isFinite(scrollY)) {
      window.requestAnimationFrame(() => window.scrollTo(0, scrollY));
    }
  }

  expandedKeys() {
    return Array.from(
      this.element.querySelectorAll("button.product-tree-toggle[data-tree-key][aria-expanded='true']")
    ).map((button) => button.dataset.treeKey);
  }

  storageKey() {
    return `product-tree:${window.location.pathname}${window.location.search}`;
  }

  storageAvailable() {
    return typeof window !== "undefined" && Boolean(window.sessionStorage);
  }
}
