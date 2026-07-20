import { Controller } from "@hotwired/stimulus";
import { calculatePopoverOffset, isInsideComponentClick } from "./time_range_selector_controller";

export default class extends Controller {
  static targets = ["empty", "input", "option", "popover", "search", "summary", "trigger"];

  static values = {
    placeholder: { type: String, default: "" },
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

  select(event) {
    const option = event.currentTarget;

    this.inputTarget.value = option.dataset.value || "";
    this.summaryTarget.textContent = option.dataset.label || this.placeholderValue;
    this.syncSelectedState();
    this.close({ restoreFocus: true });
  }

  filter() {
    const query = this.searchTarget.value.trim().toLowerCase();
    let visibleCount = 0;

    this.optionTargets.forEach((option) => {
      if (option.classList.contains("responsible-user-filter__option--shortcut")) return;

      const visible = option.dataset.searchLabel.includes(query);
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
    const selectedValue = this.inputTarget.value;
    this.triggerTarget.classList.toggle("is-placeholder", selectedValue === "");

    this.optionTargets.forEach((option) => {
      const selected = (option.dataset.value || "") === selectedValue;

      option.classList.toggle("is-selected", selected);
      option.setAttribute("aria-selected", selected ? "true" : "false");
    });
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
