import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["popover", "trigger"];

  connect() {
    this.handleOutsideClick = this.handleOutsideClick.bind(this);
    this.handleOtherPopover = this.handleOtherPopover.bind(this);
    this.hide = this.hide.bind(this);
    document.addEventListener("diagnosis-event-popover:open", this.handleOtherPopover);
  }

  disconnect() {
    document.removeEventListener("click", this.handleOutsideClick);
    document.removeEventListener("diagnosis-event-popover:open", this.handleOtherPopover);
    window.removeEventListener("resize", this.hide);
    window.removeEventListener("scroll", this.hide, true);
  }

  toggle(event) {
    event.stopPropagation();
    this.popoverTarget.hidden ? this.open() : this.close();
  }

  open() {
    document.dispatchEvent(new CustomEvent("diagnosis-event-popover:open", { detail: { source: this.element } }));
    this.popoverTarget.hidden = false;
    this.positionPopover();
    this.triggerTarget.setAttribute("aria-expanded", "true");
    document.addEventListener("click", this.handleOutsideClick);
    window.addEventListener("resize", this.hide);
    window.addEventListener("scroll", this.hide, true);
  }

  close() {
    this.popoverTarget.hidden = true;
    this.triggerTarget.setAttribute("aria-expanded", "false");
    document.removeEventListener("click", this.handleOutsideClick);
    window.removeEventListener("resize", this.hide);
    window.removeEventListener("scroll", this.hide, true);
    this.triggerTarget.focus();
  }

  closeOnEscape(event) {
    if (event.key === "Escape" && !this.popoverTarget.hidden) this.close();
  }

  handleOutsideClick(event) {
    if (!this.element.contains(event.target)) this.hide();
  }

  handleOtherPopover(event) {
    if (event.detail.source !== this.element && !this.popoverTarget.hidden) this.hide();
  }

  hide() {
    this.popoverTarget.hidden = true;
    this.triggerTarget.setAttribute("aria-expanded", "false");
    document.removeEventListener("click", this.handleOutsideClick);
    window.removeEventListener("resize", this.hide);
    window.removeEventListener("scroll", this.hide, true);
  }

  positionPopover() {
    const margin = 16;
    const gap = 6;
    const triggerRect = this.triggerTarget.getBoundingClientRect();
    const popoverRect = this.popoverTarget.getBoundingClientRect();
    const left = Math.min(
      Math.max(margin, triggerRect.right - popoverRect.width),
      window.innerWidth - popoverRect.width - margin
    );
    const spaceBelow = window.innerHeight - triggerRect.bottom - gap;
    const top = spaceBelow >= popoverRect.height
      ? triggerRect.bottom + gap
      : Math.max(margin, triggerRect.top - popoverRect.height - gap);

    this.popoverTarget.style.left = `${left}px`;
    this.popoverTarget.style.top = `${top}px`;
  }
}
