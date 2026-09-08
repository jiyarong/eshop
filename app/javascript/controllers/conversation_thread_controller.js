import { Controller } from "@hotwired/stimulus";

export function findToolExchangeRuns(elements) {
  const runs = [];

  for (let index = 0; index < elements.length; index += 1) {
    if (elements[index].dataset.toolRequest !== "true") continue;

    const run = [elements[index]];
    while (elements[index + 1]?.dataset.toolResponse === "true") {
      index += 1;
      run.push(elements[index]);
    }

    if (run.length > 1) runs.push(run);
  }

  return runs;
}

export function mergeToolExchanges(container, label, createElement = (tagName) => document.createElement(tagName)) {
  container.querySelectorAll(":scope > .ai-tool-exchange").forEach((exchange) => {
    exchange.replaceWith(...exchange.children);
  });

  findToolExchangeRuns(Array.from(container.children)).forEach((messages) => {
    const exchange = createElement("section");
    exchange.className = "ai-tool-exchange";
    exchange.setAttribute("aria-label", label);
    messages[0].before(exchange);
    messages.forEach((message) => exchange.append(message));
  });
}

export default class extends Controller {
  static values = { toolExchangeLabel: String };

  connect() {
    this.followLatest = true;
    this.reconcileToolExchanges();
    this.scrollToLatest();
    this.handleScroll = this.handleScroll.bind(this);
    window.addEventListener("scroll", this.handleScroll, { passive: true });
    this.observer = new MutationObserver(() => {
      this.observer.disconnect();
      this.reconcileToolExchanges();
      if (this.followLatest) this.scrollToLatest();
      this.observeMessages();
    });
    this.observeMessages();
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

  reconcileToolExchanges() {
    mergeToolExchanges(this.element, this.toolExchangeLabelValue);
  }

  observeMessages() {
    this.observer.observe(this.element, { childList: true, subtree: true });
  }
}
