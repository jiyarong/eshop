import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  connect() {
    this.boundPersist = this.persist.bind(this);
    this.element.addEventListener("scroll", this.boundPersist, { passive: true });
    document.addEventListener("turbo:before-cache", this.boundPersist);
    this.restore();
  }

  disconnect() {
    this.persist();
    this.element.removeEventListener("scroll", this.boundPersist);
    document.removeEventListener("turbo:before-cache", this.boundPersist);
  }

  persist() {
    if (!this.storageAvailable()) return;

    window.sessionStorage.setItem(this.storageKey(), String(this.element.scrollTop));
  }

  restore() {
    if (!this.storageAvailable()) return;

    const scrollTop = Number(window.sessionStorage.getItem(this.storageKey()));
    if (!Number.isFinite(scrollTop) || scrollTop <= 0) return;

    window.requestAnimationFrame(() => {
      this.element.scrollTop = scrollTop;
    });
  }

  storageKey() {
    const params = new URLSearchParams(window.location.search);
    params.delete("chat_id");
    params.delete("message_page");
    params.sort();
    return `ozon-chat-inbox:${window.location.pathname}?${params.toString()}`;
  }

  storageAvailable() {
    return typeof window !== "undefined" && Boolean(window.sessionStorage);
  }
}
