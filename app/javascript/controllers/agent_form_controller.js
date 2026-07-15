import { Controller } from "@hotwired/stimulus";

export function syncSkillAvailability({ agentType, skillPanel, skillInputs }) {
  const enabled = agentType === "client";

  skillPanel.classList.toggle("is-disabled", !enabled);
  skillPanel.setAttribute("aria-disabled", enabled ? "false" : "true");
  skillInputs.forEach((input) => {
    input.disabled = !enabled;
    if (!enabled) input.checked = false;
  });
}

export default class extends Controller {
  static targets = ["typeInput", "skillPanel", "skillInput"];

  connect() {
    this.syncSkills();
  }

  syncSkills() {
    syncSkillAvailability({
      agentType: this.typeInputTargets.find((input) => input.checked)?.value || "web",
      skillPanel: this.skillPanelTarget,
      skillInputs: this.skillInputTargets,
    });
  }
}
