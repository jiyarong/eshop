import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  toggle(event) {
    const button = event.currentTarget;
    const row = button.closest("tr");
    const detailRow = row?.nextElementSibling;
    if (!detailRow?.classList.contains("wb-ads-product-detail-row")) return;

    const expanded = button.getAttribute("aria-expanded") !== "true";
    button.setAttribute("aria-expanded", expanded ? "true" : "false");
    button.setAttribute("aria-label", expanded ? button.dataset.collapseLabel : button.dataset.expandLabel);
    detailRow.hidden = !expanded;

    const icon = button.querySelector("i");
    icon?.classList.toggle("bi-chevron-right", !expanded);
    icon?.classList.toggle("bi-chevron-down", expanded);

    const frame = detailRow.querySelector("turbo-frame[data-lazy-src]");
    if (expanded && frame && !frame.hasAttribute("src")) {
      frame.setAttribute("src", frame.dataset.lazySrc);
    }
  }
}
