import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["source", "field"];
  static values = { visibleWhen: String };

  connect() {
    this.sync();
  }

  sync() {
    const visible = this.sourceTarget.value === this.visibleWhenValue;
    this.fieldTarget.hidden = !visible;
    this.fieldTarget.querySelectorAll("input, select, textarea").forEach(input => {
      input.disabled = !visible;
    });
  }
}
