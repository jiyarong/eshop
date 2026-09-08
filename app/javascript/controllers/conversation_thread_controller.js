import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  connect() {
    this.followLatest = true;
    this.scrollToLatest();
    this.handleScroll = this.handleScroll.bind(this);
    window.addEventListener("scroll", this.handleScroll, { passive: true });
    this.observer = new MutationObserver(() => {
      if (this.followLatest) this.scrollToLatest();
    });
    this.observer.observe(this.element, { childList: true, subtree: true });
  }

  disconnect() {
    this.observer?.disconnect();
    window.removeEventListener("scroll", this.handleScroll);
  }

  handleScroll() {
    const documentBottom = document.documentElement.scrollHeight;
    this.followLatest = window.scrollY + window.innerHeight >= documentBottom - 160;
  }

  scrollToLatest() {
    window.requestAnimationFrame(() => {
      this.element.lastElementChild?.scrollIntoView({ block: "nearest", behavior: "auto" });
    });
  }
}
