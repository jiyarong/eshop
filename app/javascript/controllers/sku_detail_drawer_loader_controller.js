import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["template"];

  connect() {
    this.handleClick = this.handleClick.bind(this);
    document.addEventListener("click", this.handleClick);
  }

  disconnect() {
    document.removeEventListener("click", this.handleClick);
  }

  handleClick(event) {
    const link = event.target.closest("a[data-turbo-frame='sku_detail_drawer']");
    if (!link || event.defaultPrevented || event.button !== 0) return;
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;

    const frame = document.getElementById("sku_detail_drawer");
    if (!frame || !this.hasTemplateTarget) return;

    frame.replaceChildren(this.templateTarget.content.cloneNode(true));
  }
}
