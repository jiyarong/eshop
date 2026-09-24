import { Controller } from "@hotwired/stimulus";

// A small, framework-neutral number input wrapper. The input stays text-based
// so users can type decimal intermediate states (".", "0.", ".5"), while the
// stepper buttons always write a normalized numeric value.
export default class extends Controller {
  static targets = ["input"];
  static values = {
    step: Number,
    min: Number,
    max: Number,
    size: String,
    magnitudeStep: Boolean,
    minimumStep: Number
  };

  connect() {
    this.inputTarget.addEventListener("keydown", this.handleKeydown);
    if (this.hasSizeValue) this.element.classList.toggle("input-number--large", this.sizeValue === "large");
    this.syncDisabledState();
  }

  disconnect() {
    this.inputTarget.removeEventListener("keydown", this.handleKeydown);
  }

  increment() {
    this.changeBy(this.stepAmount());
  }

  decrement() {
    this.changeBy(-this.stepAmount());
  }

  syncDisabledState() {
    this.element.querySelectorAll(".input-number__button").forEach((button) => {
      button.disabled = this.inputTarget.disabled;
    });
  }

  handleKeydown = (event) => {
    if (event.key === "ArrowUp") {
      event.preventDefault();
      this.increment();
    } else if (event.key === "ArrowDown") {
      event.preventDefault();
      this.decrement();
    }
  };

  changeBy(delta) {
    const current = Number(this.inputTarget.value);
    const base = Number.isFinite(current) ? current : this.boundValue("min", 0);
    const precision = Math.max(this.decimalPlaces(base), this.decimalPlaces(delta));
    const next = this.clamp(this.round(base + delta, precision));

    this.inputTarget.value = this.format(next);
    this.inputTarget.dispatchEvent(new Event("input", { bubbles: true }));
    this.inputTarget.focus();
  }

  stepAmount() {
    if (this.hasMagnitudeStepValue) {
      const current = Number(this.inputTarget.value);
      const minimum = this.hasMinimumStepValue ? this.minimumStepValue : 0;
      if (Number.isFinite(current) && current !== 0) {
        return this.magnitudeStepAmount(Math.abs(current), minimum);
      }
      return minimum || 1;
    }

    const step = this.hasStepValue ? this.stepValue : Number(this.inputTarget.step);
    return Number.isFinite(step) && step > 0 ? step : 1;
  }

  magnitudeStepAmount(current, minimum) {
    // Keep one stable step within a practical order-of-magnitude bucket:
    // 100, 500 and 750 all use 10; 10,000 uses 100.
    const unit = current >= 1000 ? 100 : current >= 100 ? 10 : current >= 10 ? 1 : current >= 1 ? 0.1 : 0.01;
    return Math.max(minimum, unit);
  }

  boundValue(name, fallback) {
    if (name === "min" && this.hasMinValue) return this.minValue;
    if (name === "max" && this.hasMaxValue) return this.maxValue;

    const rawValue = this.inputTarget[name];
    if (rawValue === "" || rawValue === null || rawValue === undefined) return fallback;

    const value = Number(rawValue);
    return Number.isFinite(value) ? value : fallback;
  }

  clamp(value) {
    return Math.min(this.boundValue("max", Number.POSITIVE_INFINITY), Math.max(this.boundValue("min", Number.NEGATIVE_INFINITY), value));
  }

  round(value, precision = this.decimalPlaces(this.stepAmount())) {
    const factor = 10 ** precision;
    return Math.round((value + Number.EPSILON) * factor) / factor;
  }

  decimalPlaces(value) {
    const text = String(value);
    return text.includes(".") ? text.split(".")[1].length : 0;
  }

  format(value) {
    return String(value);
  }
}
