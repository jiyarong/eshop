import assert from "node:assert/strict";
import { test } from "node:test";

import { build } from "esbuild";

const bundle = await build({
  entryPoints: ["app/javascript/controllers/estimate_version_controller.js"],
  bundle: true,
  format: "esm",
  platform: "browser",
  write: false,
});

const [{ renderEstimate }] = await Promise.all(
  bundle.outputFiles.map((file) => import(`data:text/javascript;base64,${Buffer.from(file.text).toString("base64")}`)),
);

function element(dataset = {}) {
  const attributes = {};
  const classes = new Set();
  return {
    dataset,
    textContent: "",
    title: "",
    attributes,
    classes,
    setAttribute(name, value) { attributes[name] = value; },
    classList: { toggle(name, on) { on ? classes.add(name) : classes.delete(name); } },
  };
}

test("swaps both figures, the per-unit averages and the hint to the chosen version, and marks its menu entry", () => {
  const parts = {
    values: [element({ basis: "orders" }), element({ basis: "conversions" })],
    averages: [element({ basis: "orders" }), element({ basis: "conversions" })],
    rows: [element(), element()],
    options: [element({ versionId: "7" }), element({ versionId: "9" })],
  };
  const option = {
    hint: "按定价版本「2026-10」（自动）",
    bases: {
      orders: { value: "53 单 / 1,234.50", average: "单件均 24.69" },
      conversions: { value: "41 单 / 900.00", average: "" },
    },
  };

  renderEstimate(parts, option, 9);

  assert.deepEqual(parts.values.map((node) => node.textContent), ["53 单 / 1,234.50", "41 单 / 900.00"]);
  assert.deepEqual(parts.averages.map((node) => node.textContent), ["单件均 24.69", ""]);
  assert.deepEqual(parts.rows.map((node) => node.title), [option.hint, option.hint]);
  assert.equal(parts.options[0].classes.has("is-selected"), false);
  assert.equal(parts.options[0].attributes["aria-checked"], "false");
  assert.equal(parts.options[1].classes.has("is-selected"), true);
  assert.equal(parts.options[1].attributes["aria-checked"], "true");
});
