import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["trigger", "panel", "search", "summary", "option", "empty"];

  connect() {
    this.boundCloseOnOutsideClick = this.closeOnOutsideClick.bind(this);
    document.addEventListener("click", this.boundCloseOnOutsideClick);
    this.optionTargets.forEach((option) => this.syncOption(option));
    this.filter();
    this.updateSummary();
  }

  disconnect() {
    document.removeEventListener("click", this.boundCloseOnOutsideClick);
  }

  toggle() {
    this.panelTarget.hidden ? this.open() : this.close();
  }

  open() {
    this.panelTarget.hidden = false;
    this.triggerTarget.setAttribute("aria-expanded", "true");
    this.searchTarget.focus();
  }

  close() {
    this.panelTarget.hidden = true;
    this.triggerTarget.setAttribute("aria-expanded", "false");
  }

  closeOnOutsideClick(event) {
    if (this.element.contains(event.target)) return;

    this.close();
  }

  closeOnEscape(event) {
    if (event.key === "Escape") this.close();
  }

  filter() {
    const query = this.searchTarget.value.trim().toLowerCase();
    let visibleCount = 0;

    this.optionTargets.forEach((option) => {
      const visible = option.dataset.categoryMultiselectLabel.includes(query);
      option.hidden = !visible;
      if (visible) visibleCount += 1;
    });

    if (this.hasEmptyTarget) this.emptyTarget.hidden = visibleCount > 0;
  }

  sync(event) {
    this.syncOption(event.currentTarget.closest(".category-multiselect__option"));
    this.updateSummary();
  }

  preventSubmit(event) {
    event.preventDefault();
  }

  syncOption(option) {
    const input = option.querySelector("input[type='checkbox']");
    const checked = Boolean(input?.checked);

    option.classList.toggle("is-selected", checked);
    option.setAttribute("aria-selected", checked ? "true" : "false");
  }

  updateSummary() {
    const selectedOptions = this.optionTargets.filter((option) => {
      return option.querySelector("input[type='checkbox']")?.checked;
    });

    if (selectedOptions.length === 0) {
      this.summaryTarget.textContent = this.element.dataset.allLabel;
      return;
    }

    if (selectedOptions.length === 1) {
      this.summaryTarget.textContent = selectedOptions[0].querySelector(".category-multiselect__label").textContent.trim();
      return;
    }

    this.summaryTarget.textContent = this.element.dataset.selectedCountLabel.replace("%{count}", selectedOptions.length);
  }
}
