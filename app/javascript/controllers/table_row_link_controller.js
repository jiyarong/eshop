import { Controller } from "@hotwired/stimulus";
import { Turbo } from "@hotwired/turbo-rails";

export default class extends Controller {
  static values = { url: String };

  visit(event) {
    if (event.defaultPrevented || event.target.closest("a, button, input, select, textarea, summary, dialog")) return;

    Turbo.visit(this.urlValue);
  }
}
