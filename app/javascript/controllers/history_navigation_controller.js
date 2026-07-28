import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  back(event) {
    if (window.history.length <= 1) return;

    event.preventDefault();
    window.history.back();
  }
}
