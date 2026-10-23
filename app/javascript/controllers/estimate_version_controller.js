import { Controller } from "@hotwired/stimulus";

// Fills the estimated profit of a SKU (the SKU workbench list) with what the server rendered for one profit version:
// the two figures and their per-unit averages, the hint on the rows, and the marked entry of the version menu.
// `option` is { hint, bases: { orders: { value, average }, conversions: { value, average } } }.
export function renderEstimate({ values, averages, rows, options }, option, selectedId) {
  values.forEach((element) => { element.textContent = option.bases[element.dataset.basis].value; });
  averages.forEach((element) => { element.textContent = option.bases[element.dataset.basis].average; });
  rows.forEach((element) => { element.title = option.hint; });
  options.forEach((button) => {
    const selected = button.dataset.versionId === String(selectedId);
    button.classList.toggle("is-selected", selected);
    button.setAttribute("aria-checked", String(selected));
  });
}

// The icon beside a SKU's estimated profit opens the SKU's versions; one pick decides the orders and the completed figure
// together. Nothing is saved: the page shows the default version again on reload.
export default class extends Controller {
  static targets = ["trigger", "menu", "option", "value", "average", "row"];
  static values = { options: Object, selected: String };

  connect() {
    this.hide = this.hide.bind(this);
    this.handleOutsideClick = this.handleOutsideClick.bind(this);
    this.handleOtherMenu = this.handleOtherMenu.bind(this);
    document.addEventListener("estimate-version:open", this.handleOtherMenu);
  }

  disconnect() {
    document.removeEventListener("estimate-version:open", this.handleOtherMenu);
    this.removeOpenListeners();
  }

  toggle(event) {
    event.stopPropagation();
    this.menuTarget.hidden ? this.open() : this.close();
  }

  open() {
    document.dispatchEvent(new CustomEvent("estimate-version:open", { detail: { source: this.element } }));
    this.menuTarget.hidden = false;
    this.position();
    this.triggerTarget.setAttribute("aria-expanded", "true");
    document.addEventListener("click", this.handleOutsideClick);
    window.addEventListener("resize", this.hide);
    window.addEventListener("scroll", this.hide, true);
  }

  close() {
    this.hide();
    this.triggerTarget.focus();
  }

  hide() {
    this.menuTarget.hidden = true;
    this.triggerTarget.setAttribute("aria-expanded", "false");
    this.removeOpenListeners();
  }

  closeOnEscape(event) {
    if (event.key === "Escape" && !this.menuTarget.hidden) this.close();
  }

  select(event) {
    const id = event.currentTarget.dataset.versionId;
    const option = this.optionsValue[id];
    if (!option) return;

    this.selectedValue = id;
    renderEstimate(
      { values: this.valueTargets, averages: this.averageTargets, rows: this.rowTargets, options: this.optionTargets },
      option,
      id,
    );
    this.close();
  }

  handleOutsideClick(event) {
    if (!this.element.contains(event.target)) this.hide();
  }

  handleOtherMenu(event) {
    if (event.detail.source !== this.element && !this.menuTarget.hidden) this.hide();
  }

  removeOpenListeners() {
    document.removeEventListener("click", this.handleOutsideClick);
    window.removeEventListener("resize", this.hide);
    window.removeEventListener("scroll", this.hide, true);
  }

  // Fixed to the viewport, right edge under the icon, so the table's own scrolling cannot clip it.
  position() {
    const margin = 16;
    const gap = 6;
    const triggerRect = this.triggerTarget.getBoundingClientRect();
    const menuRect = this.menuTarget.getBoundingClientRect();
    const left = Math.min(
      Math.max(margin, triggerRect.right - menuRect.width),
      window.innerWidth - menuRect.width - margin,
    );
    const spaceBelow = window.innerHeight - triggerRect.bottom - gap;
    const top = spaceBelow >= menuRect.height
      ? triggerRect.bottom + gap
      : Math.max(margin, triggerRect.top - menuRect.height - gap);

    this.menuTarget.style.left = `${left}px`;
    this.menuTarget.style.top = `${top}px`;
  }
}
