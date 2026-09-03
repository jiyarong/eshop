import { Controller } from "@hotwired/stimulus";

export function shouldFloatHeader(tableRect, headerHeight, topOffset) {
  return tableRect.top < topOffset && tableRect.bottom > topOffset + headerHeight;
}

export default class extends Controller {
  connect() {
    this.table = this.element.querySelector(":scope > table");
    this.thead = this.table?.tHead;
    if (!this.thead) return;

    this.boundSchedulePosition = () => this.schedulePosition();
    this.boundMeasure = () => this.measure();
    this.boundBeforeCache = () => this.destroyEnhancements();
    this.boundTableScroll = () => this.syncHorizontalScroll(this.element, this.horizontalScrollbar);
    this.boundTopScroll = () => this.syncHorizontalScroll(this.horizontalScrollbar, this.element);

    this.createHorizontalScrollbar();
    this.createFloatingHeader();
    this.resizeObserver = new ResizeObserver(this.boundMeasure);
    this.resizeObserver.observe(this.element);
    this.resizeObserver.observe(this.table);
    window.addEventListener("scroll", this.boundSchedulePosition, { passive: true });
    window.addEventListener("resize", this.boundMeasure, { passive: true });
    this.element.addEventListener("scroll", this.boundTableScroll, { passive: true });
    this.horizontalScrollbar.addEventListener("scroll", this.boundTopScroll, { passive: true });
    document.addEventListener("turbo:before-cache", this.boundBeforeCache);

    this.measure();
  }

  disconnect() {
    this.resizeObserver?.disconnect();
    window.removeEventListener("scroll", this.boundSchedulePosition);
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
    this.destroyFloatingHeader();
    this.horizontalScrollbar?.remove();
    this.horizontalScrollbar = null;
    this.horizontalScrollbarSpacer = null;
  }

  measure() {
    if (!this.floatingHeader?.isConnected) return;

    const tableWidth = this.table.getBoundingClientRect().width;
    this.horizontalScrollbarSpacer.style.width = `${tableWidth}px`;
    this.horizontalScrollbar.hidden = tableWidth <= this.element.clientWidth + 1;
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

    this.headerHeight = this.thead.getBoundingClientRect().height;
    this.schedulePosition();
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
    const topOffset = this.topOffset();
    const visible = shouldFloatHeader(tableRect, this.headerHeight, topOffset) &&
      viewportRect.right > 0 && viewportRect.left < window.innerWidth;

    this.floatingHeader.hidden = !visible;
    if (!visible) return;

    this.floatingHeader.style.top = `${topOffset}px`;
    this.floatingHeader.style.left = `${Math.max(0, viewportRect.left)}px`;
    this.floatingHeader.style.width = `${Math.min(viewportRect.width, window.innerWidth - Math.max(0, viewportRect.left))}px`;
    this.floatingTable.style.transform = `translateX(${-this.element.scrollLeft}px)`;
  }

  topOffset() {
    const value = getComputedStyle(document.documentElement).getPropertyValue("--erp-topbar-height");
    return Number.parseFloat(value) || 0;
  }
}
