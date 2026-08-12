import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["dialog", "title", "frame", "fallback", "fallbackIcon"];

  open(event) {
    const button = event.currentTarget;
    const supported = button.dataset.previewKind !== "unsupported";

    this.titleTarget.textContent = button.dataset.filename;
    this.frameTarget.hidden = !supported;
    this.fallbackTarget.hidden = supported;
    this.fallbackIconTarget.className = `bi ${button.dataset.previewIcon || "bi-file-earmark"}`;
    this.frameTarget.src = supported ? button.dataset.previewUrl : "about:blank";
    this.dialogTarget.showModal();
  }

  close() {
    this.dialogTarget.close();
    this.frameTarget.src = "about:blank";
  }

  closeOnBackdrop(event) {
    if (event.target === this.dialogTarget) this.close();
  }

  closeOnCancel() {
    this.frameTarget.src = "about:blank";
  }
}
