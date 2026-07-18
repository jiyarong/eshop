import { Controller } from "@hotwired/stimulus";

const LIST_FIELDS = new Set(["aliases", "tags", "region_scope", "category_scope"]);

export function classificationFieldValues(payload) {
  if (!payload?.page || typeof payload.page !== "object" || Array.isArray(payload.page)) {
    throw new Error("Classification response must include a page object");
  }

  return Object.fromEntries(
    Object.entries(payload.page).map(([key, value]) => {
      const field = LIST_FIELDS.has(key) ? `${key}_text` : key;
      const normalizedValue = LIST_FIELDS.has(key) ? arrayValue(value).join("\n") : value ?? "";
      return [field, String(normalizedValue)];
    }),
  );
}

export function simpleModeRequiresClassification(mode, classificationIsFresh) {
  return mode === "simple" && !classificationIsFresh;
}

function arrayValue(value) {
  return Array.isArray(value) ? value : [];
}

export default class extends Controller {
  static targets = [
    "advanced",
    "classifyButton",
    "content",
    "modeButton",
    "result",
    "resultSummary",
    "resultTags",
    "resultTitle",
    "resultType",
    "saveButton",
    "simpleTools",
    "status",
  ];

  static values = {
    classifyUrl: String,
    emptyLabel: String,
    errorLabel: String,
    initialMode: String,
    loadingLabel: String,
    staleLabel: String,
    successLabel: String,
  };

  connect() {
    this.classificationIsFresh = false;
    this.setMode(this.initialModeValue || "simple");
  }

  switchMode(event) {
    this.setMode(event.currentTarget.dataset.mode);
  }

  async classify() {
    const content = this.contentTarget.value.trim();
    if (!content) {
      this.setStatus(this.emptyLabelValue, "error");
      this.contentTarget.focus();
      return;
    }

    this.setBusy(true);
    this.setStatus(this.loadingLabelValue, "loading");

    try {
      const response = await fetch(this.classifyUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content,
        },
        body: JSON.stringify({ content }),
      });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.error || this.errorLabelValue);

      let values;
      try {
        values = classificationFieldValues(payload);
      } catch (_) {
        throw new Error(this.errorLabelValue);
      }
      this.applyFieldValues(values);
      this.renderResult(values);
      this.classificationIsFresh = true;
      this.resultTarget.hidden = false;
      this.setStatus(this.successLabelValue, "success");
    } catch (error) {
      this.classificationIsFresh = false;
      this.setStatus(error.message || this.errorLabelValue, "error");
    } finally {
      this.setBusy(false);
      this.updateSaveButton();
    }
  }

  contentChanged() {
    if (!this.classificationIsFresh) return;

    this.classificationIsFresh = false;
    this.setStatus(this.staleLabelValue, "stale");
    this.updateSaveButton();
  }

  guardSubmit(event) {
    if (simpleModeRequiresClassification(this.mode, this.classificationIsFresh)) {
      event.preventDefault();
      this.setStatus(this.contentTarget.value.trim() ? this.staleLabelValue : this.emptyLabelValue, "error");
      this.contentTarget.focus();
    }
  }

  setMode(mode) {
    this.mode = mode === "complex" ? "complex" : "simple";
    const simpleMode = this.mode === "simple";

    this.element.dataset.editorMode = this.mode;
    this.advancedTarget.hidden = simpleMode;
    this.simpleToolsTarget.hidden = !simpleMode;
    this.modeButtonTargets.forEach((button) => {
      const active = button.dataset.mode === this.mode;
      button.classList.toggle("is-active", active);
      button.setAttribute("aria-pressed", String(active));
    });
    this.updateSaveButton();
  }

  applyFieldValues(values) {
    Object.entries(values).forEach(([attribute, value]) => {
      const field = this.element.elements.namedItem(`gbrain_page[${attribute}]`);
      if (field) field.value = value;
    });
  }

  renderResult(values) {
    this.resultTitleTarget.textContent = values.title;
    this.resultSummaryTarget.textContent = values.summary;
    this.resultTagsTarget.textContent = values.tags_text.split("\n").filter(Boolean).join(" · ");

    const typeField = this.element.elements.namedItem("gbrain_page[page_type]");
    this.resultTypeTarget.textContent = typeField?.selectedOptions?.[0]?.textContent || values.page_type;
  }

  setBusy(busy) {
    this.classifyButtonTarget.disabled = busy;
    this.classifyButtonTarget.setAttribute("aria-busy", String(busy));
    this.contentTarget.readOnly = busy;
  }

  setStatus(message, state) {
    this.statusTarget.textContent = message || "";
    this.statusTarget.dataset.state = state;
  }

  updateSaveButton() {
    this.saveButtonTarget.disabled = simpleModeRequiresClassification(this.mode, this.classificationIsFresh);
  }
}
