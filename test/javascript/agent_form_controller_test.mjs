import assert from "node:assert/strict";
import { test } from "node:test";

import { build } from "esbuild";

const bundle = await build({
  entryPoints: ["app/javascript/controllers/agent_form_controller.js"],
  bundle: true,
  format: "esm",
  platform: "browser",
  write: false,
});

const [{ syncSkillAvailability }] = await Promise.all(
  bundle.outputFiles.map((file) => import(`data:text/javascript;base64,${Buffer.from(file.text).toString("base64")}`)),
);

function buildPanel() {
  const classes = new Set();
  const attributes = new Map();

  return {
    classList: {
      toggle(name, active) {
        active ? classes.add(name) : classes.delete(name);
      },
      contains(name) {
        return classes.has(name);
      },
    },
    setAttribute(name, value) {
      attributes.set(name, String(value));
    },
    getAttribute(name) {
      return attributes.get(name);
    },
  };
}

test("web agents disable and clear skill selections", () => {
  const skillPanel = buildPanel();
  const skillInputs = [ { checked: true, disabled: false }, { checked: false, disabled: false } ];

  syncSkillAvailability({ agentType: "web", skillPanel, skillInputs });

  assert.equal(skillPanel.classList.contains("is-disabled"), true);
  assert.equal(skillPanel.getAttribute("aria-disabled"), "true");
  assert.deepEqual(skillInputs, [
    { checked: false, disabled: true },
    { checked: false, disabled: true },
  ]);
});

test("client agents enable skill selections", () => {
  const skillPanel = buildPanel();
  const skillInputs = [ { checked: false, disabled: true } ];

  syncSkillAvailability({ agentType: "client", skillPanel, skillInputs });

  assert.equal(skillPanel.classList.contains("is-disabled"), false);
  assert.equal(skillPanel.getAttribute("aria-disabled"), "false");
  assert.equal(skillInputs[0].disabled, false);
});
