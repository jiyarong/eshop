import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["checkbox", "group", "row"];

  connect() {
    this.update();
  }

  update() {
    const selectedPeriods = new Set(
      this.checkboxTargets.filter((checkbox) => checkbox.checked).map((checkbox) => checkbox.value)
    );

    this.rowTargets.forEach((row) => {
      row.hidden = !selectedPeriods.has(row.dataset.period);
    });

    this.groupTargets.forEach((group) => {
      const visibleRows = Array.from(group.querySelectorAll("[data-profit-period-filter-target~='row']"))
        .filter((row) => !row.hidden);
      const storeCell = group.querySelector("[data-profit-period-filter-store-cell]");
      if (!storeCell || visibleRows.length === 0) return;

      visibleRows[0].prepend(storeCell);
      storeCell.rowSpan = visibleRows.length;
    });
  }
}
