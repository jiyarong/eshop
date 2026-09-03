import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["template"];

  connect() {
    this.handleClick = this.handleClick.bind(this);
    this.prepareFrameRender = this.prepareFrameRender.bind(this);
    document.addEventListener("click", this.handleClick);
    document.addEventListener("turbo:before-frame-render", this.prepareFrameRender);
  }

  disconnect() {
    document.removeEventListener("click", this.handleClick);
    document.removeEventListener("turbo:before-frame-render", this.prepareFrameRender);
  }

  handleClick(event) {
    const link = event.target.closest("a[data-turbo-frame='sku_detail_drawer']");
    if (!link || event.defaultPrevented || event.button !== 0) return;
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;

    const frame = document.getElementById("sku_detail_drawer");
    if (!frame || !this.hasTemplateTarget) return;

    frame.replaceChildren(this.templateTarget.content.cloneNode(true));
  }

  prepareFrameRender(event) {
    if (event.target.id !== "sku_detail_drawer") return;
    if (!event.target.querySelector(".sku-detail-loading")) return;

    event.detail.newFrame
      .querySelector(".inventory-drawer-backdrop")
      ?.classList.add("inventory-drawer-backdrop--replace-without-animation");
    event.detail.newFrame
      .querySelector(".inventory-drawer")
      ?.classList.add("inventory-drawer--replace-without-animation");
  }
}
