import assert from "node:assert/strict";
import { test } from "node:test";

import { build } from "esbuild";

const bundle = await build({
  entryPoints: ["app/javascript/controllers/product_tree_controller.js"],
  bundle: true,
  format: "esm",
  platform: "browser",
  write: false,
});

const [{ setToggleIcon }] = await Promise.all(
  bundle.outputFiles.map((file) => import(`data:text/javascript;base64,${Buffer.from(file.text).toString("base64")}`)),
);

function createButtonWithIcon(classes) {
  const classNames = new Set(classes);

  return {
    querySelector(selector) {
      if (selector !== "i") return null;

      return {
        classList: {
          contains(className) {
            return classNames.has(className);
          },
          toggle(className, enabled) {
            if (enabled) {
              classNames.add(className);
            } else {
              classNames.delete(className);
            }
          },
        },
      };
    },
  };
}

test("setToggleIcon shows right chevron when collapsed", () => {
  const button = createButtonWithIcon(["bi", "bi-chevron-down"]);

  setToggleIcon(button, false);

  const icon = button.querySelector("i");
  assert.equal(icon.classList.contains("bi-chevron-right"), true);
  assert.equal(icon.classList.contains("bi-chevron-down"), false);
});

test("setToggleIcon shows down chevron when expanded", () => {
  const button = createButtonWithIcon(["bi", "bi-chevron-right"]);

  setToggleIcon(button, true);

  const icon = button.querySelector("i");
  assert.equal(icon.classList.contains("bi-chevron-right"), false);
  assert.equal(icon.classList.contains("bi-chevron-down"), true);
});
