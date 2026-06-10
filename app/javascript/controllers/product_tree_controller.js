import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  toggleMaster(event) {
    const button = event.currentTarget;
    const row = event.currentTarget.closest("tr.master");
    const detailRow = row?.nextElementSibling;
    if (!row || !this.isDetailRow(detailRow)) return;

    const expanded = row.classList.toggle("open");
    this.updateButton(button, expanded);
    detailRow.hidden = !expanded;
  }

  toggleSku(event) {
    const button = event.currentTarget;
    const row = event.currentTarget.closest("tr.sku-row");
    const detailRow = row?.nextElementSibling;
    if (!row || !detailRow?.classList.contains("batch-row")) return;

    const expanded = row.classList.toggle("open");
    this.updateButton(button, expanded);
    detailRow.hidden = !expanded;
  }

  isDetailRow(row) {
    return row.classList.contains("sub-row") || row.classList.contains("batch-row");
  }

  updateButton(button, expanded) {
    button.setAttribute("aria-expanded", expanded ? "true" : "false");
    const label = button.dataset.label || "详情";
    button.setAttribute("aria-label", `${expanded ? "收起" : "展开"} ${label}`);
  }
}
