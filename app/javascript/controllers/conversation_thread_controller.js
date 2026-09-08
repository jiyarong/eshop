import { Controller } from "@hotwired/stimulus";

export function findToolExchangePairs(elements) {
  const pendingRequests = new Map();
  const pairs = [];

  elements.forEach((element) => {
    const toolCallId = element.dataset.toolCallId;
    if (!toolCallId) return;

    if (element.dataset.toolRequest === "true") {
      const requests = pendingRequests.get(toolCallId) || [];
      requests.push(element);
      pendingRequests.set(toolCallId, requests);
      return;
    }

    if (element.dataset.toolResponse !== "true") return;

    const requests = pendingRequests.get(toolCallId);
    if (!requests?.length) return;

    pairs.push([requests.shift(), element]);
  });

  return pairs;
}

export function mergeToolExchanges(container, label, createElement = (tagName) => document.createElement(tagName)) {
  findToolExchangePairs(Array.from(container.children)).forEach(([request, response]) => {
    const exchange = createElement("section");
    exchange.className = "ai-tool-exchange";
    exchange.setAttribute("aria-label", label);
    exchange.dataset.toolCallId = request.dataset.toolCallId;
    request.before(exchange);
    exchange.append(request, response);
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
