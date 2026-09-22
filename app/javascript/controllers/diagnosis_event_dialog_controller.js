import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["backdrop", "trigger"];

  connect() {
    this.handleOtherDialog = this.handleOtherDialog.bind(this);
    document.addEventListener("diagnosis-event-dialog:open", this.handleOtherDialog);
  }

  disconnect() {
    document.removeEventListener("diagnosis-event-dialog:open", this.handleOtherDialog);
    this.unlockScroll();
  }

  toggle(event) {
    event.stopPropagation();
    this.backdropTarget.hidden ? this.open() : this.close();
  }

  open() {
    document.dispatchEvent(new CustomEvent("diagnosis-event-dialog:open", { detail: { source: this.element } }));
    this.backdropTarget.hidden = false;
    this.triggerTarget.setAttribute("aria-expanded", "true");
    this.lockScroll();
  }

  close() {
    if (this.backdropTarget.hidden) return;

    this.backdropTarget.hidden = true;
    this.triggerTarget.setAttribute("aria-expanded", "false");
    this.unlockScroll();
    this.triggerTarget.focus();
  }

  closeOnEscape(event) {
    if (event.key === "Escape" && !this.backdropTarget.hidden) this.close();
  }

  closeOnBackdrop(event) {
    if (event.target === this.backdropTarget) this.close();
  }

  handleOtherDialog(event) {
    if (event.detail.source !== this.element && !this.backdropTarget.hidden) this.close();
  }

  lockScroll() {
    document.body.style.overflow = "hidden";
  }

  unlockScroll() {
    document.body.style.overflow = "";
  }
}
