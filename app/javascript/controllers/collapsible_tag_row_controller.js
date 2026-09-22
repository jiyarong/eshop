import { Controller } from "@hotwired/stimulus";

export function contentOverflows(scrollHeight, clientHeight) {
  return scrollHeight > clientHeight + 1;
}

export default class extends Controller {
  static targets = ["content", "toggle"];
  static values = {
    expandLabel: String,
    collapseLabel: String
  };

  connect() {
    this.expanded = false;
    this.refresh();
  }

  refresh() {
    const overflowing = contentOverflows(this.contentTarget.scrollHeight, this.contentTarget.clientHeight);
    this.toggleTarget.hidden = !overflowing && !this.expanded;
    this.toggleTarget.textContent = this.expanded ? this.collapseLabelValue : this.expandLabelValue;
  }

  toggle() {
    this.expanded = !this.expanded;
    this.element.classList.toggle("is-expanded", this.expanded);
    this.refresh();
  }
}
