import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["form", "platform", "profile", "rule", "ruleTemplate", "rows", "rowTemplate", "empty", "count", "status", "submit", "results"];
  static values = { catalogue: Array, rules: Object, defaults: Object, messages: Object };

  connect() {
    this.rowCache = new Map();
    this.version = 0;
    this.applyProfile();
    this.syncSelection();
  }

  disconnect() {
    clearTimeout(this.timer);
    this.request?.abort();
  }

  input(event) {
    if (event.target.matches("input[type=number]")) this.schedule();
  }

  pickerClick(event) {
    if (!event.target.closest(".spu-sku-filter__clear")) return;
    this.syncSelection();
    this.schedule();
  }

  change(event) {
    if (event.target === this.platformTarget) {
      const option = Array.from(this.profileTarget.options).find((item) => item.dataset.platform === this.platformTarget.value);
      this.profileTarget.value = option.value;
      this.applyProfile();
    } else if (event.target === this.profileTarget) {
      this.applyProfile();
    } else if (event.target.closest(".spu-sku-filter")) {
      this.syncSelection();
    }
    this.schedule();
  }

  applyProfile() {
    const profile = this.profileTarget.value;
    const rule = this.rulesValue[profile];
    this.platformTarget.value = rule.platform;
    Array.from(this.profileTarget.options).forEach((option) => {
      option.hidden = option.disabled = option.dataset.platform !== rule.platform;
    });
    this.formTarget.querySelectorAll("[data-setting]").forEach((input) => {
      const value = this.defaultsValue[profile][input.dataset.setting];
      if (input.type === "checkbox") input.checked = Boolean(value);
      else input.value = value ?? "";
      if (["height", "weight", "overhang"].includes(input.dataset.setting)) input.max = rule[input.dataset.setting];
    });
    this.ruleTarget.textContent = this.ruleTemplateTarget.content.querySelector(`[data-profile="${profile}"]`).textContent;
    this.syncVisibility();
  }

  syncVisibility() {
    this.formTarget.querySelectorAll("[data-profile-only]").forEach((element) => {
      element.hidden = !element.dataset.profileOnly.split(" ").includes(this.profileTarget.value);
      element.querySelectorAll("input, select").forEach((input) => { input.disabled = element.hidden; });
    });
  }

  syncSelection() {
    const form = new FormData(this.formTarget);
    const codes = new Set(form.getAll("sku_codes[]"));
    const masters = new Set(form.getAll("master_sku_ids[]").map(String));
    const selected = this.catalogueValue.filter((item) => codes.has(item.sku_code) || masters.has(String(item.master_sku_id)));
    this.selectionCount = selected.length;
    this.countTarget.textContent = `${selected.length} / 5`;
    this.emptyTarget.hidden = selected.length > 0;
    this.rowsTarget.replaceChildren();
    // Preserve edits when selecting or deselecting another SKU.
    selected.slice(0, 5).forEach((item, index) => {
      let row = this.rowCache.get(item.sku_code);
      if (!row) {
        row = this.rowTemplateTarget.content.firstElementChild.cloneNode(true);
        row.querySelector("[data-sku-code]").textContent = item.sku_code;
        row.querySelector("[data-sku-name]").textContent = item.name || "";
        row.querySelectorAll("[data-field]").forEach((input) => {
          if (input.type !== "checkbox") input.value = item[input.dataset.field] ?? "";
          input.setAttribute("aria-label", `${item.sku_code} ${input.dataset.label || ""}`);
        });
        this.rowCache.set(item.sku_code, row);
      }
      row.querySelector(".pallet-calculator__swatch").style.setProperty("--sku-color", ["#2563eb", "#d97706", "#059669", "#9333ea", "#db2777"][index]);
      this.rowsTarget.append(row);
    });
    this.syncVisibility();
  }

  schedule() {
    clearTimeout(this.timer);
    this.request?.abort();
    this.version += 1;
    this.resultsTarget.hidden = true;
    this.statusTarget.textContent = this.messagesValue.changed;
    this.timer = setTimeout(() => this.calculate(), 450);
  }

  async calculate(event) {
    event?.preventDefault();
    clearTimeout(this.timer);
    this.request?.abort();
    const version = ++this.version;
    this.resultsTarget.hidden = true;
    this.submitTarget.disabled = false;
    if (!this.selectionCount || this.selectionCount > 5) {
      this.statusTarget.textContent = this.messagesValue.sku_count;
      return;
    }
    if (!this.formTarget.checkValidity()) {
      this.statusTarget.textContent = this.messagesValue.complete_fields;
      this.formTarget.classList.add("pallet-calculator__validate");
      if (event) {
        const details = this.formTarget.querySelector(":invalid")?.closest("details");
        if (details) details.open = true;
        this.formTarget.reportValidity();
      }
      return;
    }
    this.request = new AbortController();
    this.submitTarget.disabled = true;
    this.statusTarget.textContent = this.messagesValue.calculating;
    this.resultsTarget.setAttribute("aria-busy", "true");
    try {
      const response = await fetch(this.formTarget.action, {
        method: "POST", body: new FormData(this.formTarget), signal: this.request.signal,
        headers: { Accept: "text/html", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content },
      });
      if (version !== this.version) return;
      if (!response.ok && response.status !== 422) throw new Error("Calculation request failed");
      const html = await response.text();
      if (version !== this.version) return;
      this.resultsTarget.innerHTML = html;
      this.resultsTarget.hidden = false;
      this.statusTarget.textContent = response.ok ? this.messagesValue.updated : this.messagesValue.invalid;
    } catch (error) {
      if (error.name !== "AbortError" && version === this.version) this.statusTarget.textContent = this.messagesValue.request_error;
    } finally {
      if (version === this.version) {
        this.submitTarget.disabled = false;
        this.resultsTarget.removeAttribute("aria-busy");
      }
    }
  }

  selectPallet(event) {
    this.resultsTarget.querySelectorAll("[data-pallet-panel]").forEach((panel) => {
      panel.hidden = panel.dataset.palletPanel !== event.target.value;
    });
  }
}
