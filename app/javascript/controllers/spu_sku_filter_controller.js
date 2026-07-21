import { Controller } from "@hotwired/stimulus";
import { calculatePopoverOffset, isInsideComponentClick } from "./time_range_selector_controller";

export default class extends Controller {
  static targets = [
    "checkbox",
    "empty",
    "groupButton",
    "groupRow",
    "option",
    "paneEmpty",
    "popover",
    "search",
    "skuPane",
    "summary",
    "trigger",
  ];

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
    this.activeGroupKey = this.activePane?.dataset.groupKey || this.groupRowTargets[0]?.dataset.groupKey || null;
    this.syncSelectedState();
    this.activateGroup(this.activeGroupKey);
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

  selectGroup(event) {
    event.preventDefault();

    this.activateGroup(event.currentTarget.dataset.groupKey);
  }

  sync(event) {
    this.syncControl(event.currentTarget);
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
    let firstVisibleGroupKey = null;
    let visibleGroupCount = 0;

    this.groupRowTargets.forEach((row) => {
      const groupKey = row.dataset.groupKey;
      const pane = this.paneFor(groupKey);
      const groupMatches = (row.dataset.searchLabel || "").includes(query);
      let visibleOptionCount = 0;

      this.optionsForPane(pane).forEach((option) => {
        const optionMatches = (option.dataset.searchLabel || "").includes(query);
        const visible = query === "" || groupMatches || optionMatches;

        option.hidden = !visible;
        if (visible) visibleOptionCount += 1;
      });

      const visible = query === "" || groupMatches || visibleOptionCount > 0;
      row.hidden = !visible;
      this.syncPaneEmpty(pane, visibleOptionCount);

      if (visible) {
        visibleGroupCount += 1;
        firstVisibleGroupKey ||= groupKey;
      }
    });

    if (firstVisibleGroupKey && this.rowFor(this.activeGroupKey)?.hidden) {
      this.activateGroup(firstVisibleGroupKey);
    }

    if (this.hasEmptyTarget) {
      this.emptyTarget.hidden = visibleGroupCount > 0;
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
    this.checkboxTargets.forEach((checkbox) => this.syncControl(checkbox));
    this.updateSummary();
  }

  syncControl(checkbox) {
    const selected = Boolean(checkbox?.checked);
    const row = checkbox?.closest(".spu-sku-filter__spu-row");
    const option = checkbox?.closest(".spu-sku-filter__sku-option");

    row?.classList.toggle("is-selected", selected);
    option?.classList.toggle("is-selected", selected);
    option?.setAttribute("aria-selected", selected ? "true" : "false");
  }

  updateSummary() {
    const checkedOptions = this.checkboxTargets
      .filter((checkbox) => checkbox.checked)
      .map((checkbox) => checkbox.closest(".spu-sku-filter__spu-row, .spu-sku-filter__sku-option"))
      .filter(Boolean);

    this.triggerTarget.classList.toggle("is-placeholder", checkedOptions.length === 0);

    if (checkedOptions.length === 0) {
      this.summaryTarget.textContent = this.allLabelValue;
      return;
    }

    if (checkedOptions.length === 1) {
      this.summaryTarget.textContent = checkedOptions[0].querySelector(".spu-sku-filter__name")?.textContent.trim() || this.allLabelValue;
      return;
    }

    this.summaryTarget.textContent = this.selectedCountLabelValue.replace("%{count}", checkedOptions.length);
  }

  activateGroup(groupKey) {
    if (!groupKey) return;

    this.activeGroupKey = groupKey;
    this.groupRowTargets.forEach((row) => {
      const active = row.dataset.groupKey === groupKey;
      row.classList.toggle("is-active", active);
      row.querySelector(".spu-sku-filter__spu-button")?.setAttribute("aria-selected", active ? "true" : "false");
    });
    this.skuPaneTargets.forEach((pane) => {
      pane.hidden = pane.dataset.groupKey !== groupKey;
    });
  }

  get activePane() {
    return this.skuPaneTargets.find((pane) => !pane.hidden);
  }

  rowFor(groupKey) {
    return this.groupRowTargets.find((row) => row.dataset.groupKey === groupKey);
  }

  paneFor(groupKey) {
    return this.skuPaneTargets.find((pane) => pane.dataset.groupKey === groupKey);
  }

  optionsForPane(pane) {
    if (!pane) return [];

    return Array.from(pane.querySelectorAll(".spu-sku-filter__sku-option"));
  }

  syncPaneEmpty(pane, visibleOptionCount) {
    const empty = pane?.querySelector(".spu-sku-filter__pane-empty");
    if (empty) {
      empty.hidden = visibleOptionCount > 0;
    }
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
