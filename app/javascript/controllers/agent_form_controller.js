import { Controller } from "@hotwired/stimulus";

export function syncSkillAvailability({ agentType, skillPanel, skillInputs }) {
  const enabled = agentType === "client";

  skillPanel.hidden = !enabled;
  skillPanel.classList.toggle("is-disabled", !enabled);
  skillPanel.setAttribute("aria-disabled", enabled ? "false" : "true");
  skillInputs.forEach((input) => {
    input.disabled = !enabled;
    if (!enabled) input.checked = false;
  });
}

export function syncToolAvailability({ agentType, toolPanel, toolInputs }) {
  const enabled = agentType === "web";

  toolPanel.hidden = !enabled;
  toolPanel.classList.toggle("is-disabled", !enabled);
  toolPanel.setAttribute("aria-disabled", enabled ? "false" : "true");
  toolInputs.forEach((input) => {
    input.disabled = !enabled;
    if (!enabled) input.checked = false;
  });
}

export default class extends Controller {
  static targets = ["typeInput", "skillPanel", "skillInput", "toolPanel", "toolInput"];

  connect() {
    this.syncCapabilities();
  }

  syncCapabilities() {
    const agentType = this.typeInputTargets.find((input) => input.checked)?.value || "web";

    syncSkillAvailability({
      agentType,
      skillPanel: this.skillPanelTarget,
      skillInputs: this.skillInputTargets,
    });
    syncToolAvailability({
      agentType,
      toolPanel: this.toolPanelTarget,
      toolInputs: this.toolInputTargets,
    });
  }
}
