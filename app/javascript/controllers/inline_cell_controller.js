import { Controller } from "@hotwired/stimulus";
import { Turbo } from "@hotwired/turbo-rails";

export default class extends Controller {
  static targets = ["input"];
  static values = { editUrl: String };

  connect() {
    this.submitting = false;
    this.cancelled = false;

    if (this.hasInputTarget) {
      this.focusInput();
    }
  }

  activate() {
    if (!this.hasEditUrlValue) return;

    const frame = this.element.closest("turbo-frame");
    if (!frame?.id) return;

    Turbo.visit(this.editUrlValue, { frame: frame.id });
  }

  handleKeydown(event) {
    if (event.key === "Escape") {
      event.preventDefault();
      this.cancel();
      return;
    }

    if (event.key === "Enter" && event.target.tagName !== "SELECT") {
      event.preventDefault();
      this.submit();
    }
  }

  submit() {
    if (!this.hasInputTarget || this.submitting || this.cancelled) return;

    const form = this.inputTarget.form;
    if (!form) return;

    this.submitting = true;
    form.requestSubmit();
  }

  cancel() {
    this.cancelled = true;
    this.element.closest("turbo-frame")?.reload();
  }

  focusInput() {
    const input = this.inputTarget;
    input.focus();

    if (typeof input.select === "function" && input.tagName !== "SELECT" && input.type !== "date") {
      input.select();
    }
  }
}
