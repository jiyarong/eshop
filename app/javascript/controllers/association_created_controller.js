import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static values = { pickerId: String, recordId: Number, label: String };

  connect() {
    window.dispatchEvent(new CustomEvent("association-picker:selected", {
      detail: { pickerId: this.pickerIdValue, id: this.recordIdValue, label: this.labelValue }
    }));
  }
}
