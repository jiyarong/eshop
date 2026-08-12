import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["input", "dropzone", "list", "empty"];
  static values = {
    removeLabel: String,
    fileSizeLabel: String
  };

  connect() {
    this.files = [];
    this.render();
  }

  select(event) {
    this.addFiles(event.target.files);
  }

  dragover(event) {
    event.preventDefault();
    this.dropzoneTarget.classList.add("is-dragging");
  }

  dragleave(event) {
    if (event.relatedTarget && this.dropzoneTarget.contains(event.relatedTarget)) return;
    this.dropzoneTarget.classList.remove("is-dragging");
  }

  drop(event) {
    event.preventDefault();
    this.dropzoneTarget.classList.remove("is-dragging");
    this.addFiles(event.dataTransfer.files);
  }

  remove(event) {
    const index = Number(event.currentTarget.dataset.index);
    this.files.splice(index, 1);
    this.syncInput();
    this.render();
  }

  addFiles(fileList) {
    Array.from(fileList).forEach((file) => {
      const duplicate = this.files.some((current) =>
        current.name === file.name && current.size === file.size && current.lastModified === file.lastModified
      );
      if (!duplicate) this.files.push(file);
    });
    this.syncInput();
    this.render();
  }

  syncInput() {
    if (typeof DataTransfer === "undefined") return;

    const transfer = new DataTransfer();
    this.files.forEach((file) => transfer.items.add(file));
    this.inputTarget.files = transfer.files;
  }

  render() {
    this.listTarget.replaceChildren();
    this.emptyTarget.hidden = this.files.length > 0;

    this.files.forEach((file, index) => {
      const item = document.createElement("li");
      item.className = "attachment-pending-list__item";

      const icon = document.createElement("i");
      icon.className = `bi ${this.iconClass(file.name)} attachment-file-icon attachment-file-icon--${this.kind(file.name)}`;
      icon.setAttribute("aria-hidden", "true");

      const details = document.createElement("div");
      details.className = "attachment-pending-list__details";
      const name = document.createElement("span");
      name.className = "attachment-pending-list__name";
      name.textContent = file.name;
      const size = document.createElement("span");
      size.className = "attachment-pending-list__size";
      size.textContent = `${this.fileSizeLabelValue}: ${this.formatBytes(file.size)}`;
      details.append(name, size);

      const remove = document.createElement("button");
      remove.type = "button";
      remove.className = "icon-button";
      remove.dataset.index = index;
      remove.dataset.action = "attachment-upload#remove";
      remove.setAttribute("aria-label", this.removeLabelValue);
      remove.innerHTML = '<i class="bi bi-x-lg" aria-hidden="true"></i>';

      item.append(icon, details, remove);
      this.listTarget.append(item);
    });
  }

  kind(filename) {
    const extension = filename.split(".").pop().toLowerCase();
    if (["png", "jpg", "jpeg", "gif", "webp", "bmp", "svg"].includes(extension)) return "image";
    if (extension === "pdf") return "pdf";
    if (["xls", "xlsx", "csv"].includes(extension)) return "spreadsheet";
    if (["doc", "docx"].includes(extension)) return "document";
    if (["ppt", "pptx"].includes(extension)) return "presentation";
    if (["zip", "rar", "7z", "tar", "gz"].includes(extension)) return "archive";
    return "unknown";
  }

  iconClass(filename) {
    return {
      image: "bi-file-earmark-image",
      pdf: "bi-file-earmark-pdf",
      spreadsheet: "bi-file-earmark-spreadsheet",
      document: "bi-file-earmark-word",
      presentation: "bi-file-earmark-slides",
      archive: "bi-file-earmark-zip",
      unknown: "bi-file-earmark"
    }[this.kind(filename)];
  }

  formatBytes(bytes) {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  }
}
