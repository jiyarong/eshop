import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  close() {
    this.element.closest("turbo-frame").innerHTML = "";
  }

  closeOnBackdrop(event) {
    if (event.target === this.element) this.close();
  }
}
