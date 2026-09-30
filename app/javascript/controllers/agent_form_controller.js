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

export function syncThinkingAvailability({ model, enabled, select, profiles }) {
  const profile = profiles.find((candidate) => new RegExp(candidate.pattern).test(model));
  const levels = profile?.levels || [];

  Array.from(select.options).forEach((option) => {
    const supported = option.value === "" || levels.includes(option.value);
    option.hidden = !supported;
    option.disabled = !supported;
  });
  if (!levels.includes(select.value)) select.value = "";
  select.disabled = !enabled || levels.length === 0;
}

export default class extends Controller {
  static targets = ["typeInput", "skillPanel", "skillInput", "toolPanel", "toolInput", "modelInput", "thinkingEnabled", "thinkingLevel", "thinkingLevelValue"];
  static values = { thinkingProfiles: Array };

  connect() {
    this.syncCapabilities();
    this.syncThinking();
  }

  syncThinking() {
    syncThinkingAvailability({
      model: this.modelInputTarget.value,
      enabled: this.thinkingEnabledTarget.checked,
      select: this.thinkingLevelTarget,
      profiles: this.thinkingProfilesValue,
    });
    this.thinkingLevelValueTarget.value = this.thinkingLevelTarget.value;
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
