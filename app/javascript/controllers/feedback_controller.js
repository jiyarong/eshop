import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["start", "modal", "form"];

  connect() {
    this.selecting = false;
    this.highlighted = null;
    this.selected = null;
  }

  start() {
    this.selecting = true;
    this.selected = null;
    this.startTarget.textContent = this.startTarget.dataset.selectingLabel || "选择页面元素";
  }

  hover(event) {
    if (!this.selecting || this.ignoredTarget(event.target)) return;

    this.clearHighlight();
    this.highlighted = event.target;
    this.highlighted.classList.add("feedback-highlight");
  }

  choose(event) {
    if (!this.selecting || this.ignoredTarget(event.target)) return;

    event.preventDefault();
    event.stopPropagation();
    this.selected = event.target;
    this.selecting = false;
    this.resetStartLabel();
    this.openModal();
  }

  cancel() {
    this.selecting = false;
    this.selected = null;
    this.resetStartLabel();
    this.clearHighlight();
    this.closeModal();
    this.formTarget.reset();
  }

  async submit(event) {
    event.preventDefault();
    if (!this.selected) return;

    const rect = this.selected.getBoundingClientRect();
    const payload = {
      feedback_task: {
        page_url: window.location.pathname + window.location.search + window.location.hash,
        page_title: document.title,
        issue_type: this.formTarget.issue_type.value,
        description: this.formTarget.description.value,
        suggestion: this.formTarget.suggestion.value,
        selector: this.cssPath(this.selected),
        element_text: this.selected.innerText.trim().slice(0, 500),
        element_rect: {
          x: Math.round(rect.x),
          y: Math.round(rect.y),
          width: Math.round(rect.width),
          height: Math.round(rect.height)
        },
        scroll_x: Math.round(window.scrollX),
        scroll_y: Math.round(window.scrollY),
        viewport_width: window.innerWidth,
        viewport_height: window.innerHeight
      }
    };

    const response = await fetch("/feedback_tasks", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content
      },
      body: JSON.stringify(payload)
    });

    if (response.ok) {
      this.clearHighlight();
      this.closeModal();
      this.formTarget.reset();
      this.selected = null;
    }
  }

  ignoredTarget(target) {
    return target.closest("[data-feedback-target='modal']") || target.closest("[data-feedback-target='start']");
  }

  openModal() {
    this.modalTarget.classList.add("is-open");
  }

  closeModal() {
    this.modalTarget.classList.remove("is-open");
  }

  resetStartLabel() {
    this.startTarget.textContent = this.startTarget.dataset.defaultLabel || "反馈";
  }

  clearHighlight() {
    if (this.highlighted) this.highlighted.classList.remove("feedback-highlight");
    this.highlighted = null;
  }

  cssPath(element) {
    const parts = [];
    let node = element;

    while (node && node.nodeType === Node.ELEMENT_NODE && node !== document.body) {
      let part = node.tagName.toLowerCase();

      if (node.id) {
        part += `#${CSS.escape(node.id)}`;
        parts.unshift(part);
        break;
      }

      const siblings = Array.from(node.parentElement.children).filter((child) => child.tagName === node.tagName);
      if (siblings.length > 1) part += `:nth-of-type(${siblings.indexOf(node) + 1})`;
      parts.unshift(part);
      node = node.parentElement;
    }

    return parts.join(" > ");
  }
}
