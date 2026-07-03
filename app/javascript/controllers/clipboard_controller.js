import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static values = {
    text: String
  };

  copy() {
    if (!this.textValue) return;

    navigator.clipboard?.writeText(this.textValue);
  }
}
