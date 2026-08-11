import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["link"];

  select(event) {
    const selectedLink = event.currentTarget;
    const frame = document.getElementById(selectedLink.dataset.turboFrame);

    this.show(selectedLink.dataset.skuDetailTab);
    this.markSelected(selectedLink);

    if (frame?.dataset.skuDetailTabLoaded === "true") event.preventDefault();
  }

  sync(event) {
    if (!event.target.id.startsWith("sku_detail_tab_")) return;

    const activeTab = event.target.id.replace("sku_detail_tab_", "");
    const selectedLink = this.linkTargets.find((link) => link.dataset.skuDetailTab === activeTab);

    event.target.dataset.skuDetailTabLoaded = "true";
    this.show(activeTab);
    if (selectedLink) this.markSelected(selectedLink);
  }

  show(activeTab) {
    this.linkTargets.forEach((link) => {
      const frame = document.getElementById(link.dataset.turboFrame);
      if (frame) frame.hidden = link.dataset.skuDetailTab !== activeTab;
    });
  }

  markSelected(selectedLink) {
    this.linkTargets.forEach((link) => {
      if (link === selectedLink) {
        link.setAttribute("aria-current", "page");
      } else {
        link.removeAttribute("aria-current");
      }
    });
  }
}
