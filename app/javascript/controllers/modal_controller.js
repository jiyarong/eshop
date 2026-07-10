import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static values = {
    closePath: String
  };

  static openCount = 0;
  static scrollTop = 0;

  connect() {
    this.lockScroll();
  }

  disconnect() {
    this.unlockScroll();
  }

  close() {
    if (this.hasClosePathValue) {
      const currentUrl = new URL(window.location.href);
      const closeUrl = new URL(this.closePathValue, window.location.origin);

      if (currentUrl.pathname !== closeUrl.pathname || currentUrl.search !== closeUrl.search) {
        if (window.Turbo?.visit) {
          window.Turbo.visit(closeUrl.toString(), { action: "replace" });
        } else {
          window.location.assign(closeUrl.toString());
        }
        return;
      }

      if (window.history?.replaceState) {
        window.history.replaceState(window.history.state, "", closeUrl.toString());
      }
    }

    const frame = this.element.closest("turbo-frame");
    if (frame) frame.innerHTML = "";
  }

  closeOnBackdrop(event) {
    if (event.target === this.element) this.close();
  }

  lockScroll() {
    if (this.scrollLocked) return;

    this.scrollLocked = true;
    if (this.constructor.openCount === 0) {
      this.constructor.scrollTop = window.scrollY || window.pageYOffset || 0;

      document.documentElement.style.overflow = "hidden";
      document.body.style.overflow = "hidden";
      document.body.style.position = "fixed";
      document.body.style.top = `-${this.constructor.scrollTop}px`;
      document.body.style.width = "100%";
    }

    this.constructor.openCount += 1;
  }

  unlockScroll() {
    if (!this.scrollLocked) return;

    this.scrollLocked = false;
    this.constructor.openCount = Math.max(this.constructor.openCount - 1, 0);

    if (this.constructor.openCount > 0) return;

    const scrollTop = this.constructor.scrollTop || 0;

    document.documentElement.style.overflow = "";
    document.body.style.overflow = "";
    document.body.style.position = "";
    document.body.style.top = "";
    document.body.style.width = "";
    window.scrollTo(0, scrollTop);
  }
}
