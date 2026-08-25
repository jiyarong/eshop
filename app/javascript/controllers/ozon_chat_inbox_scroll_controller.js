import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static values = { key: String };
  static positions = new Map();

  connect() {
    this.boundPersist = this.persist.bind(this);
    this.boundRememberClick = this.rememberClick.bind(this);
    this.element.addEventListener("scroll", this.boundPersist, { passive: true });
    this.element.addEventListener("click", this.boundRememberClick, true);
    document.addEventListener("turbo:before-cache", this.boundPersist);
    this.restore();
  }

  disconnect() {
    this.element.removeEventListener("scroll", this.boundPersist);
    this.element.removeEventListener("click", this.boundRememberClick, true);
    document.removeEventListener("turbo:before-cache", this.boundPersist);
  }

  persist() {
    const scrollTop = this.element.scrollTop;
    this.constructor.positions.set(this.storageKey(), scrollTop);
    if (!this.storageAvailable()) return;

    window.sessionStorage.setItem(this.storageKey(), String(scrollTop));
  }

  rememberClick(event) {
    if (event.target.closest("a.ozon-chat-thread")) this.persist();
  }

  restore() {
    const memoryValue = this.constructor.positions.get(this.storageKey());
    const storedValue = this.storageAvailable() ? window.sessionStorage.getItem(this.storageKey()) : null;
    const scrollTop = Number(memoryValue ?? storedValue);
    if (!Number.isFinite(scrollTop) || scrollTop <= 0) return;

    window.requestAnimationFrame(() => {
      window.requestAnimationFrame(() => {
        this.element.scrollTop = scrollTop;
      });
    });
  }

  storageKey() {
    return `ozon-chat-inbox:${this.keyValue}`;
  }

  storageAvailable() {
    return typeof window !== "undefined" && Boolean(window.sessionStorage);
  }
}
