import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["button", "content"];
  static values = { showLabel: String, hideLabel: String };

  toggle() {
    const hidden = !this.contentTarget.hidden;
    this.contentTarget.hidden = hidden;
    this.buttonTarget.setAttribute("aria-expanded", hidden ? "false" : "true");
    this.buttonTarget.textContent = hidden ? this.showLabelValue : this.hideLabelValue;
  }
}
