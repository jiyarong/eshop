import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  select(event) {
    const thread = event.target.closest("a.ozon-chat-thread");
    if (!thread) return;

    this.element.querySelectorAll("a.ozon-chat-thread.is-active").forEach((item) => {
      item.classList.remove("is-active");
      item.removeAttribute("aria-current");
    });
    thread.classList.add("is-active");
    thread.setAttribute("aria-current", "page");
    this.element.closest(".ozon-chat-page")?.classList.add("has-explicit-chat");
  }
}
