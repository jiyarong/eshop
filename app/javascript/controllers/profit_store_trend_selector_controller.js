import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["panel"];

  select(event) {
    const storeRef = event.currentTarget.value;
    this.panelTargets.forEach((panel) => {
      panel.hidden = panel.dataset.storeRef !== storeRef;
    });
  }
}
