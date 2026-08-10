import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  prepare() {
    this.element.classList.toggle(
      "drawer-transition--without-entry",
      this.element.querySelector(".inventory-drawer") !== null
    );
  }
}
