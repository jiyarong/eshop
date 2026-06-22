import { Controller } from "@hotwired/stimulus";

export function formatLongText(text, limit = 100) {
  const normalizedText = text || "";
  if (normalizedText.length <= limit) {
    return { displayText: normalizedText, tooltipText: null };
  }

  return {
    displayText: normalizedText.slice(0, limit),
    tooltipText: normalizedText,
  };
}

export default class extends Controller {
  static values = {
    limit: { type: Number, default: 100 },
  };

  connect() {
    if (!this.hasOriginalTextValue()) this.element.dataset.longTextOriginalText = this.element.textContent.trim();

    const { displayText, tooltipText } = formatLongText(this.originalTextValue(), this.limitValue);
    this.element.textContent = displayText;
    this.tooltipText = tooltipText;

    if (!tooltipText) return;

    this.element.classList.add("long-text");
    this.element.tabIndex = this.element.tabIndex >= 0 ? this.element.tabIndex : 0;
    this.element.addEventListener("mouseenter", this.show);
    this.element.addEventListener("mouseleave", this.hide);
    this.element.addEventListener("focus", this.show);
    this.element.addEventListener("blur", this.hide);
  }

  disconnect() {
    this.hide();
    this.element.removeEventListener("mouseenter", this.show);
    this.element.removeEventListener("mouseleave", this.hide);
    this.element.removeEventListener("focus", this.show);
    this.element.removeEventListener("blur", this.hide);
  }

  hasOriginalTextValue() {
    return Object.prototype.hasOwnProperty.call(this.element.dataset, "longTextOriginalText");
  }

  originalTextValue() {
    return this.element.dataset.longTextOriginalText || "";
  }

  show = () => {
    if (!this.tooltipText) return;

    this.hide();

    this.tooltip = document.createElement("div");
    this.tooltip.className = "long-text-tooltip";
    this.tooltip.id = `long-text-tooltip-${Date.now()}-${Math.random().toString(36).slice(2)}`;
    this.tooltip.textContent = this.tooltipText;
    document.body.appendChild(this.tooltip);
    this.element.setAttribute("aria-describedby", this.tooltip.id);
    this.placeTooltip();
  };

  hide = () => {
    if (this.tooltip) {
      this.tooltip.remove();
      this.tooltip = null;
    }

    this.element.removeAttribute("aria-describedby");
  };

  placeTooltip() {
    const elementRect = this.element.getBoundingClientRect();
    const tooltipRect = this.tooltip.getBoundingClientRect();
    const gap = 8;
    const viewportPadding = 12;
    const preferredTop = elementRect.top - tooltipRect.height - gap;
    const top = preferredTop > viewportPadding ? preferredTop : elementRect.bottom + gap;
    const left = Math.min(
      Math.max(elementRect.left, viewportPadding),
      window.innerWidth - tooltipRect.width - viewportPadding,
    );

    this.tooltip.style.top = `${top}px`;
    this.tooltip.style.left = `${left}px`;
  }
}
