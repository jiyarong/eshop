import { Controller } from "@hotwired/stimulus";
import { Turbo } from "@hotwired/turbo-rails";

export default class extends Controller {
  static values = { url: String };

  connect() {
    this.scheduleRefresh();
  }

  disconnect() {
    window.clearTimeout(this.refreshTimer);
  }

  scheduleRefresh() {
    this.refreshTimer = window.setTimeout(() => this.refresh(), 2000);
  }

  async refresh() {
    try {
      const response = await fetch(this.urlValue, {
        headers: { Accept: "text/vnd.turbo-stream.html" },
      });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);

      Turbo.renderStreamMessage(await response.text());
    } catch (_error) {
      this.scheduleRefresh();
    }
  }
}
