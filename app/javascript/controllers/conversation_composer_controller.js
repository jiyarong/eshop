import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["content", "images", "previews", "submit", "error"];
  static values = {
    maxImages: Number,
    emptyError: String,
    tooManyError: String,
    removeImageLabel: String,
  };

  connect() {
    this.previewUrls = [];
    this.resize();
  }

  disconnect() {
    this.revokePreviewUrls();
  }

  chooseImages() {
    this.imagesTarget.click();
  }

  imagesChanged() {
    if (this.imagesTarget.files.length > this.maxImagesValue) {
      this.showError(this.tooManyErrorValue);
      this.imagesTarget.value = "";
    } else {
      this.clearError();
    }
    this.renderPreviews();
  }

  removeImage(event) {
    const removeIndex = Number(event.currentTarget.dataset.index);
    const transfer = new DataTransfer();

    Array.from(this.imagesTarget.files).forEach((file, index) => {
      if (index !== removeIndex) transfer.items.add(file);
    });

    this.imagesTarget.files = transfer.files;
    this.renderPreviews();
  }

  keydown(event) {
    if (event.key !== "Enter" || event.shiftKey || event.isComposing) return;

    event.preventDefault();
    this.element.requestSubmit();
  }

  resize() {
    this.contentTarget.style.height = "auto";
    this.contentTarget.style.height = `${Math.min(this.contentTarget.scrollHeight, 180)}px`;
  }

  validate(event) {
    if (!this.contentTarget.value.trim() && this.imagesTarget.files.length === 0) {
      event.preventDefault();
      this.showError(this.emptyErrorValue);
      this.contentTarget.focus();
    }
  }

  submitStart() {
    this.submitTarget.disabled = true;
  }

  submitEnd(event) {
    if (!event.detail.success) this.submitTarget.disabled = false;
  }

  renderPreviews() {
    this.revokePreviewUrls();
    this.previewsTarget.replaceChildren();

    Array.from(this.imagesTarget.files).forEach((file, index) => {
      const url = URL.createObjectURL(file);
      this.previewUrls.push(url);

      const item = document.createElement("div");
      item.className = "ai-conversation-composer__preview";

      const image = document.createElement("img");
      image.src = url;
      image.alt = file.name;

      const button = document.createElement("button");
      button.type = "button";
      button.dataset.index = index;
      button.dataset.action = "conversation-composer#removeImage";
      button.setAttribute("aria-label", `${this.removeImageLabelValue}: ${file.name}`);
      button.title = this.removeImageLabelValue;
      button.innerHTML = '<i class="bi bi-x" aria-hidden="true"></i>';

      item.append(image, button);
      this.previewsTarget.append(item);
    });

    this.previewsTarget.hidden = this.imagesTarget.files.length === 0;
  }

  showError(message) {
    if (!this.hasErrorTarget) return;

    this.errorTarget.textContent = message;
    this.errorTarget.hidden = false;
  }

  clearError() {
    if (!this.hasErrorTarget) return;

    this.errorTarget.textContent = "";
    this.errorTarget.hidden = true;
  }

  revokePreviewUrls() {
    (this.previewUrls || []).forEach((url) => URL.revokeObjectURL(url));
    this.previewUrls = [];
  }
}
