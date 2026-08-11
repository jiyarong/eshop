import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["link"];

  select(event) {
    this.markSelected(event.currentTarget);
  }

  sync(event) {
    if (event.target.id !== "sku_detail_tab" || !event.target.src) return;

    const loadedUrl = new URL(event.target.src, window.location.origin);
    const activeTab = loadedUrl.searchParams.get("tab") || "operation";
    const selectedLink = this.linkTargets.find((link) => {
      const linkUrl = new URL(link.href, window.location.origin);
      return (linkUrl.searchParams.get("tab") || "operation") === activeTab;
    });

    if (selectedLink) this.markSelected(selectedLink);
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
