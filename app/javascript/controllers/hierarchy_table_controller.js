import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  toggle(event) {
    const button = event.currentTarget;
    const { kind, key } = event.params;
    const expanded = button.getAttribute("aria-expanded") !== "true";

    button.setAttribute("aria-expanded", expanded ? "true" : "false");
    this.updateIcon(button, expanded);

    if (kind === "product") {
      this.productRows(key).forEach((row) => {
        if (row.classList.contains("ozon-warehouse-cluster-row")) row.hidden = !expanded;
        if (!expanded && row.classList.contains("ozon-warehouse-detail-row")) row.hidden = true;
      });
      if (!expanded) this.collapseClusterButtons(key);
      return;
    }

    this.clusterRows(key).forEach((row) => { row.hidden = !expanded; });
  }

  productRows(key) {
    return this.element.querySelectorAll(`[data-hierarchy-product="${CSS.escape(key)}"]`);
  }

  clusterRows(key) {
    return this.element.querySelectorAll(`[data-hierarchy-cluster="${CSS.escape(key)}"]`);
  }

  collapseClusterButtons(productKey) {
    this.element.querySelectorAll(`[data-hierarchy-product="${CSS.escape(productKey)}"] .ozon-warehouse-toggle`).forEach((button) => {
      button.setAttribute("aria-expanded", "false");
      this.updateIcon(button, false);
    });
  }

  updateIcon(button, expanded) {
    const icon = button.querySelector("i");
    icon?.classList.toggle("bi-chevron-right", !expanded);
    icon?.classList.toggle("bi-chevron-down", expanded);
  }
}
