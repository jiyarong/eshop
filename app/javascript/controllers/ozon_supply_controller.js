import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["store", "cluster", "type", "dropOff", "submit", "content", "workflow", "binding", "handoff", "submissionPanel", "planStatus", "platformStatus", "syncedAt", "orderNumber", "syncError", "pollError"];
  static values = { clusters: Object, statusUrl: String, state: String, planState: String, orderId: String, pollError: String, empty: String };

  connect() {
    if (this.hasStoreTarget) this.storeChanged();
    if (this.hasTypeTarget) this.typeChanged();
    if (this.statusUrlValue) this.timer = setTimeout(() => this.poll(), 1500);
  }

  disconnect() {
    clearTimeout(this.timer);
    this.request?.abort();
  }

  storeChanged() {
    this.clusterTarget.replaceChildren();
    (this.clustersValue[this.storeTarget.value] || []).forEach((cluster) => {
      this.clusterTarget.add(new Option(cluster.name || String(cluster.id), cluster.id));
    });
    const picker = this.dropOffTarget.querySelector("[data-controller='association-picker']");
    const url = new URL(picker.dataset.associationPickerSearchUrlValue, window.location.origin);
    url.searchParams.set("store_id", this.storeTarget.value);
    picker.dataset.associationPickerSearchUrlValue = url.toString();
    picker.querySelector("input[type=hidden]").value = "";
    picker.querySelector("input[type=search]").value = "";
  }

  typeChanged() {
    this.dropOffTarget.hidden = this.typeTarget.value !== "CROSSDOCK";
    this.dropOffTarget.querySelectorAll("input").forEach((input) => { input.disabled = this.dropOffTarget.hidden; });
  }

  submit() {
    this.submitTargets.forEach((button) => { button.disabled = true; });
    clearTimeout(this.timer);
  }

  async poll() {
    this.request = new AbortController();
    try {
      const response = await fetch(this.statusUrlValue, { headers: { Accept: "application/json" }, signal: this.request.signal });
      if (!response.ok) {
        if ([403, 404].includes(response.status)) return;
        throw new Error("Status request failed");
      }
      const result = await response.json();
      const state = result.state || "";
      const orderId = result.order_id || "";
      const changed = state !== this.stateValue || result.plan_state !== this.planStateValue || orderId !== this.orderIdValue;
      if (changed) {
        this.workflowTarget.innerHTML = result.workflow_html;
        this.bindingTarget.innerHTML = result.binding_html;
        this.handoffTarget.innerHTML = result.handoff_html;
      }
      if (state !== this.stateValue || result.running) this.contentTarget.innerHTML = result.html;
      this.submissionPanelTarget.hidden = !state;
      this.stateValue = state;
      this.planStateValue = result.plan_state;
      this.orderIdValue = orderId;
      this.planStatusTarget.innerHTML = result.status;
      this.platformStatusTarget.textContent = result.platform_status || this.emptyValue;
      this.syncedAtTarget.textContent = result.platform_synced_at;
      this.orderNumberTarget.textContent = result.order_number || this.emptyValue;
      this.syncErrorTarget.textContent = result.sync_error || "";
      this.syncErrorTarget.hidden = !result.sync_error;
      this.pollErrorTarget.textContent = "";
      if ((result.active || result.running) && this.element.isConnected) this.timer = setTimeout(() => this.poll(), result.running ? 3000 : 30000);
    } catch (error) {
      if (error.name !== "AbortError" && this.element.isConnected) {
        this.pollErrorTarget.textContent = this.pollErrorValue;
        this.timer = setTimeout(() => this.poll(), 10000);
      }
    }
  }
}
