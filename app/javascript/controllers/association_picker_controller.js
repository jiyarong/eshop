import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["input", "query", "results", "status", "createUrl", "emptyTemplate"];
  static values = { id: String, searchUrl: String, emptyLabel: String };

  connect() {
    this.selectedLabel = this.queryTarget.value;
    this.activeIndex = -1;
  }

  disconnect() {
    window.clearTimeout(this.searchTimer);
    window.clearTimeout(this.closeTimer);
    this.abortController?.abort();
  }

  search() {
    this.inputTarget.value = "";
    this.selectedLabel = "";
    window.clearTimeout(this.searchTimer);
    const query = this.queryTarget.value.trim();
    if (!query) return this.close();

    this.searchTimer = window.setTimeout(() => this.load(query), 180);
  }

  async load(query) {
    this.abortController?.abort();
    this.abortController = new AbortController();
    const url = new URL(this.searchUrlValue, window.location.origin);
    url.searchParams.set("q", query);

    try {
      const response = await fetch(url, { headers: { Accept: "application/json" }, signal: this.abortController.signal });
      if (!response.ok) throw new Error("search failed");
      this.render(await response.json());
    } catch (error) {
      if (error.name !== "AbortError") this.close();
    }
  }

  render(items) {
    this.resultsTarget.replaceChildren();
    this.activeIndex = -1;
    if (!items.length) {
      this.resultsTarget.append(this.emptyTemplateTarget.content.cloneNode(true));
    } else {
      items.forEach((item, index) => {
        const button = document.createElement("button");
        button.type = "button";
        button.className = "association-picker__option";
        button.role = "option";
        button.dataset.index = index;
        button.dataset.id = item.id;
        button.dataset.label = item.label;
        button.textContent = item.label;
        button.addEventListener("mousedown", event => event.preventDefault());
        button.addEventListener("click", () => this.choose(item.id, item.label));
        this.resultsTarget.append(button);
      });
    }
    this.resultsTarget.hidden = false;
    this.queryTarget.setAttribute("aria-expanded", "true");
  }

  navigate(event) {
    const options = [...this.resultsTarget.querySelectorAll("[role='option']")];
    if (event.key === "Escape") return this.close();
    if (!options.length || !["ArrowDown", "ArrowUp", "Enter"].includes(event.key)) return;
    event.preventDefault();

    if (event.key === "Enter" && this.activeIndex >= 0) {
      const option = options[this.activeIndex];
      return this.choose(option.dataset.id, option.dataset.label);
    }

    const direction = event.key === "ArrowUp" ? -1 : 1;
    this.activeIndex = (this.activeIndex + direction + options.length) % options.length;
    options.forEach((option, index) => option.setAttribute("aria-selected", index === this.activeIndex ? "true" : "false"));
  }

  choose(id, label) {
    this.inputTarget.value = id;
    this.queryTarget.value = label;
    this.selectedLabel = label;
    this.statusTarget.textContent = label;
    this.close();
  }

  selectCreated(event) {
    if (event.detail?.pickerId !== this.idValue) return;
    this.choose(event.detail.id, event.detail.label);
    document.getElementById("association_create_modal")?.replaceChildren();
  }

  openCreate() {
    const url = new URL(this.createUrlTarget.textContent.trim(), window.location.origin);
    url.searchParams.set("association_dom_id", this.idValue);
    url.searchParams.set("suggested_name", this.queryTarget.value.trim());
    document.getElementById("association_create_modal").src = url.toString();
  }

  closeSoon() {
    window.clearTimeout(this.closeTimer);
    this.closeTimer = window.setTimeout(() => {
      if (!this.inputTarget.value) this.queryTarget.value = this.selectedLabel;
      this.close();
    }, 150);
  }

  close() {
    this.resultsTarget.hidden = true;
    this.queryTarget.setAttribute("aria-expanded", "false");
  }
}
