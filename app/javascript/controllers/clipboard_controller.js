import { Controller } from "@hotwired/stimulus";

export async function writeClipboardText(text, clipboard = globalThis.navigator?.clipboard, documentObject = globalThis.document) {
  if (clipboard?.writeText) {
    try {
      await clipboard.writeText(text);
      return;
    } catch (_error) {
      // Fall through for browsers that expose the API but deny access to it.
    }
  }

  const textarea = documentObject.createElement("textarea");
  textarea.value = text;
  textarea.setAttribute("readonly", "");
  textarea.style.position = "fixed";
  textarea.style.opacity = "0";
  documentObject.body.append(textarea);
  textarea.select();

  try {
    if (!documentObject.execCommand("copy")) throw new Error("Clipboard copy failed");
  } finally {
    textarea.remove();
  }
}

export default class extends Controller {
  static targets = ["source", "button", "icon", "status"];

  static values = {
    text: String,
    copiedLabel: String
  };

  disconnect() {
    window.clearTimeout(this.restoreTimer);
  }

  async copy(event) {
    event?.preventDefault();
    event?.stopPropagation();
    const text = this.hasTextValue ? this.textValue : (this.hasSourceTarget ? this.sourceTarget.textContent : "");
    if (!text) return;

    try {
      await writeClipboardText(text);
      this.showCopiedState();
    } catch (_error) {
      // Leave the button unchanged when the browser blocks both copy methods.
    }
  }

  showCopiedState() {
    if (!this.hasButtonTarget || !this.hasCopiedLabelValue) return;

    window.clearTimeout(this.restoreTimer);
    const button = this.buttonTarget;
    this.originalLabel ||= button.getAttribute("aria-label");
    button.setAttribute("aria-label", this.copiedLabelValue);
    button.setAttribute("title", this.copiedLabelValue);
    button.classList.add("is-copied");
    if (this.hasIconTarget) this.iconTarget.classList.replace("bi-copy", "bi-check2");
    if (this.hasStatusTarget) this.statusTarget.textContent = this.copiedLabelValue;

    this.restoreTimer = window.setTimeout(() => this.restoreButton(), 1600);
  }

  restoreButton() {
    if (!this.hasButtonTarget || !this.originalLabel) return;

    const button = this.buttonTarget;
    button.setAttribute("aria-label", this.originalLabel);
    button.setAttribute("title", this.originalLabel);
    button.classList.remove("is-copied");
    if (this.hasIconTarget) this.iconTarget.classList.replace("bi-check2", "bi-copy");
    if (this.hasStatusTarget) this.statusTarget.textContent = "";
  }
}
