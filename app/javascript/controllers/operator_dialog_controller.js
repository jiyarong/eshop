import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  open(event) {
    const dialog = document.getElementById(event.currentTarget.dataset.operatorDialogId);
    if (dialog && !dialog.open) dialog.showModal();
  }

  close() {
    this.dialog?.close();
  }

  closeOnBackdrop(event) {
    if (event.target === this.dialog) this.close();
  }

  get dialog() {
    return this.element.closest("dialog");
  }
}
