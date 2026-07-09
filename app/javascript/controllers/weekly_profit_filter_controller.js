import { Controller } from "@hotwired/stimulus";

export function syncActiveState(buttons, value) {
  buttons.forEach((button) => {
    const active = button.dataset.value === value;
    button.classList.toggle("is-active", active);
    button.setAttribute("aria-pressed", active ? "true" : "false");
  });
}

export function syncStoreState({ reportTypeInput, storeField, storeButtons }) {
  const enabled = reportTypeInput.value === "wr";

  storeField.classList.toggle("is-disabled", !enabled);
  storeField.setAttribute("aria-disabled", enabled ? "false" : "true");

  storeButtons.forEach((button) => {
    button.disabled = !enabled;
    if (enabled) {
      button.removeAttribute("tabindex");
    } else {
      button.setAttribute("tabindex", "-1");
    }
  });
}

export function selectReportType({ value, reportTypeInput, reportButtons, storeField, storeButtons, form }) {
  reportTypeInput.value = value;
  syncActiveState(reportButtons, reportTypeInput.value);
  syncStoreState({ reportTypeInput, storeField, storeButtons });
  form?.requestSubmit();
}

export function selectStore({ value, storeInput, storeButtons, form }) {
  const selectedButton = storeButtons.find((button) => button.dataset.value === value);
  if (!selectedButton || selectedButton.disabled) return;

  storeInput.value = value;
  syncActiveState(storeButtons, storeInput.value);
  form?.requestSubmit();
}

export default class extends Controller {
  static targets = ["reportTypeInput", "storeInput", "storeField", "reportButton", "storeButton"];

  connect() {
    syncActiveState(this.reportButtonTargets, this.reportTypeInputTarget.value);
    syncActiveState(this.storeButtonTargets, this.storeInputTarget.value);
    syncStoreState({
      reportTypeInput: this.reportTypeInputTarget,
      storeField: this.storeFieldTarget,
      storeButtons: this.storeButtonTargets,
    });
  }

  selectReportType(event) {
    selectReportType({
      value: event.currentTarget.dataset.value,
      reportTypeInput: this.reportTypeInputTarget,
      reportButtons: this.reportButtonTargets,
      storeField: this.storeFieldTarget,
      storeButtons: this.storeButtonTargets,
      form: this.element,
    });
  }

  selectStore(event) {
    selectStore({
      value: event.currentTarget.dataset.value,
      storeInput: this.storeInputTarget,
      storeButtons: this.storeButtonTargets,
      form: this.element,
    });
  }
}
