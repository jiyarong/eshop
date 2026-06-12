import { Controller } from "@hotwired/stimulus";
import flatpickr from "flatpickr";

export default class extends Controller {
  static targets = ["input"];
  static values = {
    dateFormat: { type: String, default: "Y-m-d" },
    enableTime: { type: Boolean, default: false },
    maxDate: String,
    minDate: String,
    mode: { type: String, default: "single" },
    time24hr: { type: Boolean, default: true }
  };

  connect() {
    this.picker = flatpickr(this.inputTarget, this.options);
  }

  disconnect() {
    this.picker?.destroy();
  }

  get options() {
    return {
      allowInput: true,
      dateFormat: this.dateFormatValue,
      enableTime: this.enableTimeValue,
      maxDate: this.optionalValue(this.maxDateValue),
      minDate: this.optionalValue(this.minDateValue),
      mode: this.modeValue,
      time_24hr: this.time24hrValue
    };
  }

  optionalValue(value) {
    return value || undefined;
  }
}
