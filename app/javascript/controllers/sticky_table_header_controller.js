import { Controller } from "@hotwired/stimulus";

export function shouldFloatHeader(tableRect, headerHeight, topOffset, bottomOffset = Infinity) {
  return tableRect.top < topOffset &&
    tableRect.bottom > topOffset + headerHeight &&
    topOffset + headerHeight <= bottomOffset;
}

export function findVerticalScrollContainer(element, styleFor = (node) => getComputedStyle(node), fallback = window) {
  let parent = element?.parentElement;

  while (parent) {
    const overflowY = styleFor(parent).overflowY;
    if (["auto", "scroll", "overlay"].includes(overflowY) && parent.scrollHeight > parent.clientHeight) {
      return parent;
    }
    parent = parent.parentElement;
  }

  return fallback;
}

export function stickyColumnPlacements(rows, stickyColumnCount) {
  const count = Math.max(0, Number(stickyColumnCount) || 0);
  if (count === 0) return [];

  const occupiedUntilRow = [];
  const placements = [];

  Array.from(rows).forEach((row, rowIndex) => {
    let columnIndex = 0;

    Array.from(row.cells || []).forEach((cell) => {
      const columnSpan = Math.max(1, Number(cell.colSpan) || 1);
      const rowSpan = Math.max(1, Number(cell.rowSpan) || 1);

      while (Array.from({ length: columnSpan }, (_value, offset) => columnIndex + offset)
        .some((index) => (occupiedUntilRow[index] || 0) > rowIndex)) {
        columnIndex += 1;
      }

      const start = columnIndex;
      const end = start + columnSpan;
      if (end <= count) placements.push({ cell, start, end });

      if (rowSpan > 1) {
        for (let index = start; index < end; index += 1) {
          occupiedUntilRow[index] = Math.max(occupiedUntilRow[index] || 0, rowIndex + rowSpan);
        }
      }
      columnIndex = end;
    });
  });

  return placements;
}

export default class extends Controller {
  static values = {
    floatingHeader: Boolean,
    stickyColumns: Number,
  };

  connect() {
    this.table = this.element.querySelector(":scope > table");
    this.thead = this.table?.tHead;
    if (!this.thead) return;

    this.floatingHeaderEnabled = !this.hasFloatingHeaderValue || this.floatingHeaderValue;

    this.boundSchedulePosition = () => this.schedulePosition();
    this.boundMeasure = () => this.measure();
    this.boundBeforeCache = () => this.destroyEnhancements();
    this.boundTableScroll = () => this.syncHorizontalScroll(this.element, this.horizontalScrollbar);
    this.boundTopScroll = () => this.syncHorizontalScroll(this.horizontalScrollbar, this.element);
    this.scrollContainer = findVerticalScrollContainer(this.element);

    this.createHorizontalScrollbar();
    if (this.floatingHeaderEnabled) this.createFloatingHeader();
    this.resizeObserver = new ResizeObserver(this.boundMeasure);
    this.resizeObserver.observe(this.element);
    this.resizeObserver.observe(this.table);
    this.scrollContainer.addEventListener("scroll", this.boundSchedulePosition, { passive: true });
    window.addEventListener("resize", this.boundMeasure, { passive: true });
    this.element.addEventListener("scroll", this.boundTableScroll, { passive: true });
    this.horizontalScrollbar.addEventListener("scroll", this.boundTopScroll, { passive: true });
    document.addEventListener("turbo:before-cache", this.boundBeforeCache);

    this.measure();
  }

  disconnect() {
    this.resizeObserver?.disconnect();
    this.scrollContainer?.removeEventListener("scroll", this.boundSchedulePosition);
    window.removeEventListener("resize", this.boundMeasure);
    this.element.removeEventListener("scroll", this.boundTableScroll);
    this.horizontalScrollbar?.removeEventListener("scroll", this.boundTopScroll);
    document.removeEventListener("turbo:before-cache", this.boundBeforeCache);
    cancelAnimationFrame(this.frameRequest);
    this.destroyEnhancements();
  }

  createHorizontalScrollbar() {
    this.horizontalScrollbar = document.createElement("div");
    this.horizontalScrollbar.className = "table-horizontal-scrollbar";
    this.horizontalScrollbar.setAttribute("aria-hidden", "true");
    this.horizontalScrollbarSpacer = document.createElement("div");
    this.horizontalScrollbarSpacer.className = "table-horizontal-scrollbar__spacer";
    this.horizontalScrollbar.append(this.horizontalScrollbarSpacer);
    this.element.before(this.horizontalScrollbar);
  }

  createFloatingHeader() {
    this.floatingHeader = document.createElement("div");
    this.floatingHeader.className = "sticky-table-header";
    if (this.scrollContainer !== window) {
      this.floatingHeader.classList.add("sticky-table-header--nested");
    }
    this.floatingHeader.hidden = true;

    this.floatingTable = this.table.cloneNode(false);
    this.floatingTable.removeAttribute("id");
    this.floatingTable.removeAttribute("data-controller");
    this.floatingTable.classList.add("sticky-table-header__table");

    this.floatingThead = this.thead.cloneNode(true);
    this.floatingThead.querySelectorAll("[id]").forEach((node) => node.removeAttribute("id"));
    this.floatingTable.append(this.floatingThead);
    this.floatingHeader.append(this.floatingTable);
    document.body.append(this.floatingHeader);
  }

  destroyFloatingHeader() {
    this.floatingHeader?.remove();
    this.floatingHeader = null;
    this.floatingTable = null;
    this.floatingThead = null;
  }

  destroyEnhancements() {
    this.clearStickyColumns(this.table);
    this.destroyFloatingHeader();
    this.horizontalScrollbar?.remove();
    this.horizontalScrollbar = null;
    this.horizontalScrollbarSpacer = null;
  }

  measure() {
    if (!this.table?.isConnected || !this.horizontalScrollbarSpacer) return;

    const tableWidth = this.table.getBoundingClientRect().width;
    this.horizontalScrollbarSpacer.style.width = `${tableWidth}px`;
    this.horizontalScrollbar.hidden = tableWidth <= this.element.clientWidth + 1;

    if (this.floatingHeader?.isConnected) {
      this.floatingTable.style.width = `${tableWidth}px`;
      this.floatingTable.style.minWidth = `${tableWidth}px`;

      const sourceCells = this.thead.querySelectorAll("th, td");
      const floatingCells = this.floatingThead.querySelectorAll("th, td");
      sourceCells.forEach((cell, index) => {
        const width = cell.getBoundingClientRect().width;
        if (floatingCells[index]) {
          floatingCells[index].style.width = `${width}px`;
          floatingCells[index].style.minWidth = `${width}px`;
          floatingCells[index].style.maxWidth = `${width}px`;
        }
      });
    }

    this.applyStickyColumns(this.table);
    if (this.floatingTable) this.applyStickyColumns(this.floatingTable);

    this.headerHeight = this.thead.getBoundingClientRect().height;
    this.schedulePosition();
  }

  applyStickyColumns(table) {
    const count = this.hasStickyColumnsValue ? this.stickyColumnsValue : 0;
    this.clearStickyColumns(table);
    if (count <= 0) return;

    const tableLeft = table.getBoundingClientRect().left;
    const sections = [table.tHead, ...Array.from(table.tBodies), table.tFoot].filter(Boolean);
    sections.forEach((section) => {
      stickyColumnPlacements(section.rows, count).forEach(({ cell, end }) => {
        const left = cell.getBoundingClientRect().left - tableLeft;
        cell.classList.add("table-sticky-column");
        cell.classList.toggle("table-sticky-column--edge", end === count);
        cell.style.setProperty("--table-sticky-column-left", `${left}px`);
      });
    });
  }

  clearStickyColumns(table) {
    if (!table) return;

    table.querySelectorAll(".table-sticky-column").forEach((cell) => {
      cell.classList.remove("table-sticky-column", "table-sticky-column--edge");
      cell.style.removeProperty("--table-sticky-column-left");
    });
  }

  syncHorizontalScroll(source, destination) {
    if (!source || !destination || this.syncingScroll) return;

    this.syncingScroll = true;
    destination.scrollLeft = source.scrollLeft;
    this.syncingScroll = false;
    this.schedulePosition();
  }

  schedulePosition() {
    if (!this.floatingHeader || this.frameRequest) return;

    this.frameRequest = requestAnimationFrame(() => {
      this.frameRequest = null;
      this.position();
    });
  }

  position() {
    if (!this.floatingHeader?.isConnected) return;

    const viewportRect = this.element.getBoundingClientRect();
    const tableRect = this.table.getBoundingClientRect();
    const { top, bottom } = this.verticalBounds();
    const visible = shouldFloatHeader(tableRect, this.headerHeight, top, bottom) &&
      viewportRect.right > 0 && viewportRect.left < window.innerWidth;

    this.floatingHeader.hidden = !visible;
    if (!visible) return;

    this.floatingHeader.style.top = `${top}px`;
    this.floatingHeader.style.left = `${Math.max(0, viewportRect.left)}px`;
    this.floatingHeader.style.width = `${Math.min(viewportRect.width, window.innerWidth - Math.max(0, viewportRect.left))}px`;
    this.floatingHeader.style.setProperty("--table-sticky-scroll-offset", `${this.element.scrollLeft}px`);
    this.floatingTable.style.transform = `translateX(${-this.element.scrollLeft}px)`;
  }

  verticalBounds() {
    if (this.scrollContainer === window) {
      const value = getComputedStyle(document.documentElement).getPropertyValue("--erp-topbar-height");
      return { top: Number.parseFloat(value) || 0, bottom: window.innerHeight };
    }

    const rect = this.scrollContainer.getBoundingClientRect();
    return {
      top: Math.max(0, rect.top),
      bottom: Math.min(window.innerHeight, rect.bottom),
    };
  }
}
