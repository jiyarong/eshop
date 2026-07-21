import { Controller } from "@hotwired/stimulus";
import { calculatePopoverOffset, isInsideComponentClick } from "./time_range_selector_controller";

export default class extends Controller {
  static targets = ["checkbox", "empty", "option", "popover", "search", "summary", "trigger"];

  static values = {
    allLabel: { type: String, default: "" },
    selectedCountLabel: { type: String, default: "" },
  };

  connect() {
    this.boundDocumentClick = this.handleDocumentClick.bind(this);
    this.boundDocumentKeydown = this.handleDocumentKeydown.bind(this);
    this.boundWindowResize = this.handleWindowResize.bind(this);

    document.addEventListener("click", this.boundDocumentClick);
    document.addEventListener("keydown", this.boundDocumentKeydown);
    window.addEventListener("resize", this.boundWindowResize);

    this.isOpen = false;
    this.syncSelectedState();
    this.filter();
  }

  disconnect() {
    document.removeEventListener("click", this.boundDocumentClick);
    document.removeEventListener("keydown", this.boundDocumentKeydown);
    window.removeEventListener("resize", this.boundWindowResize);
  }

  toggle(event) {
    event.preventDefault();

    this.isOpen ? this.close() : this.open();
  }

  open() {
    this.isOpen = true;
    this.popoverTarget.hidden = false;
    this.triggerTarget.setAttribute("aria-expanded", "true");
    this.searchTarget.value = "";
    this.filter();
    this.positionPopover();
    this.searchTarget.focus();
  }

  close({ restoreFocus = false } = {}) {
    this.isOpen = false;
    this.popoverTarget.hidden = true;
    this.triggerTarget.setAttribute("aria-expanded", "false");
    this.popoverTarget.style.transform = "";

    if (restoreFocus) {
      this.triggerTarget.focus();
    }
  }

  sync(event) {
    this.syncOption(event.currentTarget.closest(".popover-multiselect__option"));
    this.updateSummary();
  }

  clear(event) {
    event.preventDefault();
    this.checkboxTargets.forEach((checkbox) => {
      checkbox.checked = false;
    });
    this.syncSelectedState();
  }

  filter() {
    const query = this.searchTarget.value.trim().toLowerCase();
    let visibleCount = 0;

    this.optionTargets.forEach((option) => {
      const visible = (option.dataset.searchLabel || "").includes(query);

      option.hidden = !visible;
      if (visible) visibleCount += 1;
    });

    if (this.hasEmptyTarget) {
      this.emptyTarget.hidden = visibleCount > 0;
    }
  }

  preventSubmit(event) {
    event.preventDefault();
  }

  closeOnEscape(event) {
    if (event.key !== "Escape") return;

    event.preventDefault();
    this.close({ restoreFocus: true });
  }

  handleDocumentClick(event) {
    if (!this.isOpen) return;
    if (isInsideComponentClick(event, this.element)) return;

    this.close();
  }

  handleDocumentKeydown(event) {
    if (!this.isOpen) return;
    if (event.key !== "Escape") return;

    event.preventDefault();
    this.close({ restoreFocus: true });
  }

  handleWindowResize() {
    if (!this.isOpen) return;

    this.positionPopover();
  }

  syncSelectedState() {
    this.optionTargets.forEach((option) => this.syncOption(option));
    this.updateSummary();
  }

  syncOption(option) {
    const checkbox = option?.querySelector("input[type='checkbox']");
    const selected = Boolean(checkbox?.checked);

    option?.classList.toggle("is-selected", selected);
    option?.setAttribute("aria-selected", selected ? "true" : "false");
  }

  updateSummary() {
    const selectedOptions = this.optionTargets.filter((option) => {
      return option.querySelector("input[type='checkbox']")?.checked;
    });

    this.triggerTarget.classList.toggle("is-placeholder", selectedOptions.length === 0);

    if (selectedOptions.length === 0) {
      this.summaryTarget.textContent = this.allLabelValue;
      return;
    }

    if (selectedOptions.length === 1) {
      this.summaryTarget.textContent = selectedOptions[0].dataset.label || this.allLabelValue;
      return;
    }

    this.summaryTarget.textContent = this.selectedCountLabelValue.replace("%{count}", selectedOptions.length);
  }

  positionPopover() {
    const margin = window.innerWidth <= 980 ? 20 : 28;
    const offset = calculatePopoverOffset({
      popoverRect: this.popoverTarget.getBoundingClientRect(),
      viewportWidth: window.innerWidth,
      margin,
    });

    this.popoverTarget.style.transform = offset === 0 ? "" : `translateX(${offset}px)`;
  }
}
