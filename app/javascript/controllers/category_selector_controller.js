import { Controller } from "@hotwired/stimulus";

export function categoryOptionsFromResponse(payload) {
  if (!payload || !Array.isArray(payload.categories)) return [];

  return payload.categories.map((category) => ({
    id: String(category.id),
    name: category.name || String(category.id),
    parentId: category.parent_id ? String(category.parent_id) : "",
    parentName: category.parent_name || "",
  }));
}

export function selectedCategoryId(parentId, childId) {
  return childId || parentId || "";
}

export default class extends Controller {
  static targets = ["trigger", "panel", "search", "selected", "display", "parentList", "childList"];
  static values = {
    childrenUrl: String,
    selectedCategoryId: String,
  };

  connect() {
    this.originalParentOptions = Array.from(
      this.parentListTarget.querySelectorAll("[data-original-option='true']"),
    ).map((button) => ({
      id: button.dataset.categoryId,
      name: button.dataset.categoryName,
      parentId: "",
      parentName: "",
    }));
    this.boundCloseOnOutsideClick = this.closeOnOutsideClick.bind(this);
    document.addEventListener("click", this.boundCloseOnOutsideClick);
  }

  disconnect() {
    this.abortActiveRequest();
    window.clearTimeout(this.searchTimer);
    document.removeEventListener("click", this.boundCloseOnOutsideClick);
  }

  toggle() {
    this.panelTarget.hidden ? this.open() : this.close();
  }

  open() {
    this.panelTarget.hidden = false;
    this.triggerTarget.setAttribute("aria-expanded", "true");
    this.searchTarget.focus();
  }

  close() {
    this.panelTarget.hidden = true;
    this.triggerTarget.setAttribute("aria-expanded", "false");
  }

  closeOnOutsideClick(event) {
    if (this.element.contains(event.target)) return;

    this.close();
  }

  stopClick(event) {
    event.stopPropagation();
  }

  closeOnEscape(event) {
    if (event.key === "Escape") this.close();
  }

  searchChanged() {
    window.clearTimeout(this.searchTimer);

    this.searchTimer = window.setTimeout(() => {
      const query = this.searchTarget.value.trim();

      if (query) {
        this.search(query);
      } else {
        this.resetSearch();
      }
    }, 180);
  }

  selectParent(event) {
    const button = event.currentTarget;
    const parentId = button.dataset.categoryId;
    const parentName = button.dataset.categoryName;

    this.resetSearchInput();
    this.setSelectedCategory(parentId);
    this.setDisplay(parentName);
    this.setActiveParent(parentId);
    this.loadChildren(parentId);
  }

  selectChild(event) {
    const button = event.currentTarget;
    const parentId = button.dataset.parentId;
    const parentName = button.dataset.parentName;
    const childId = button.dataset.categoryId;
    const childName = button.dataset.categoryName;

    this.resetSearchInput();
    this.setSelectedCategory(selectedCategoryId(parentId, childId));
    this.setDisplay([parentName, childName].filter(Boolean).join(" / "));
    this.setActiveParent(parentId);
    this.loadChildren(parentId, childId);
    this.close();
  }

  async loadChildren(parentId, selectedId = "") {
    this.abortActiveRequest();
    this.abortController = new AbortController();
    this.setListMessage(this.childListTarget, this.childListTarget.dataset.loadingLabel);

    try {
      const url = new URL(this.childrenUrlValue, window.location.origin);
      url.searchParams.set("parent_id", parentId);

      const response = await fetch(url.toString(), {
        headers: { Accept: "application/json" },
        signal: this.abortController.signal,
      });

      if (!response.ok) throw new Error(`HTTP ${response.status}`);

      const options = categoryOptionsFromResponse(await response.json());
      this.populateChildren(options, selectedId);
    } catch (error) {
      if (error.name === "AbortError") return;

      this.setListMessage(this.childListTarget, this.childListTarget.dataset.errorLabel);
    }
  }

  async search(query) {
    this.abortActiveRequest();
    this.abortController = new AbortController();
    this.setListMessage(this.parentListTarget, this.parentListTarget.dataset.loadingLabel);
    this.setListMessage(this.childListTarget, this.childListTarget.dataset.loadingLabel);

    try {
      const url = new URL(this.childrenUrlValue, window.location.origin);
      url.searchParams.set("q", query);

      const response = await fetch(url.toString(), {
        headers: { Accept: "application/json" },
        signal: this.abortController.signal,
      });

      if (!response.ok) throw new Error(`HTTP ${response.status}`);

      this.populateSearchResults(categoryOptionsFromResponse(await response.json()));
    } catch (error) {
      if (error.name === "AbortError") return;

      this.setListMessage(this.parentListTarget, this.parentListTarget.dataset.errorLabel);
      this.setListMessage(this.childListTarget, this.childListTarget.dataset.errorLabel);
    }
  }

  populateChildren(options, selectedId = "") {
    this.childListTarget.replaceChildren();

    options.forEach((option) => {
      this.childListTarget.appendChild(
        this.optionButton({
          option,
          action: "category-selector#selectChild",
          active: option.id === String(selectedId),
        }),
      );
    });

    if (options.length === 0) {
      this.setListMessage(this.childListTarget, this.childListTarget.dataset.emptyLabel);
    }
  }

  populateSearchResults(options) {
    const parentOptions = options.filter((option) => !option.parentId);
    const childOptions = options.filter((option) => option.parentId);

    this.parentListTarget.replaceChildren();
    this.childListTarget.replaceChildren();

    parentOptions.forEach((option) => {
      this.parentListTarget.appendChild(
        this.optionButton({
          option,
          action: "category-selector#selectParent",
          active: option.id === this.selectedTarget.value,
        }),
      );
    });

    childOptions.forEach((option) => {
      this.childListTarget.appendChild(
        this.optionButton({
          option,
          action: "category-selector#selectChild",
          active: option.id === this.selectedTarget.value,
          meta: option.parentName,
        }),
      );
    });

    if (parentOptions.length === 0) this.setListMessage(this.parentListTarget, this.parentListTarget.dataset.noResultsLabel);
    if (childOptions.length === 0) this.setListMessage(this.childListTarget, this.childListTarget.dataset.noResultsLabel);
  }

  resetSearch() {
    this.abortActiveRequest();
    this.renderOriginalParentOptions();

    const activeParent = this.parentListTarget.querySelector(".category-selector__option[aria-selected='true']");
    if (activeParent) {
      this.loadChildren(activeParent.dataset.categoryId);
    } else {
      this.setListMessage(this.childListTarget, this.childListTarget.dataset.emptyLabel);
    }
  }

  resetSearchInput() {
    this.searchTarget.value = "";
    this.renderOriginalParentOptions();
  }

  renderOriginalParentOptions() {
    this.parentListTarget.replaceChildren();
    this.originalParentOptions.forEach((option) => {
      this.parentListTarget.appendChild(
        this.optionButton({
          option,
          action: "category-selector#selectParent",
          active: option.id === this.parentListTarget.dataset.activeParentId,
          original: true,
        }),
      );
    });
  }

  optionButton({ option, action, active = false, meta = "", original = false }) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "category-selector__option";
    button.dataset.action = action;
    button.dataset.categoryId = option.id;
    button.dataset.categoryName = option.name;
    button.dataset.parentId = option.parentId;
    button.dataset.parentName = option.parentName;
    if (original) button.dataset.originalOption = "true";
    if (!original) button.dataset.searchResult = "true";
    button.setAttribute("aria-selected", active ? "true" : "false");

    const label = document.createElement("span");
    label.textContent = option.name;
    button.appendChild(label);

    if (meta) {
      const metaLabel = document.createElement("small");
      metaLabel.textContent = meta;
      button.appendChild(metaLabel);
    }

    return button;
  }

  setActiveParent(parentId) {
    this.parentListTarget.dataset.activeParentId = String(parentId || "");
    this.parentListTarget.querySelectorAll(".category-selector__option").forEach((button) => {
      button.setAttribute("aria-selected", button.dataset.categoryId === String(parentId) ? "true" : "false");
    });
  }

  setListMessage(list, message) {
    list.replaceChildren();
    const item = document.createElement("div");
    item.className = "category-selector__empty";
    item.textContent = message || "";
    list.appendChild(item);
  }

  abortActiveRequest() {
    if (this.abortController) this.abortController.abort();
  }

  setSelectedCategory(categoryId) {
    this.selectedTarget.value = categoryId || "";
  }

  setDisplay(label) {
    this.displayTarget.textContent = label || this.displayTarget.dataset.placeholder;
    this.displayTarget.classList.toggle("category-selector__placeholder", !label);
  }
}
