import assert from "node:assert/strict";
import { test } from "node:test";

import { build } from "esbuild";

const bundle = await build({
  entryPoints: ["app/javascript/controllers/weekly_profit_filter_controller.js"],
  bundle: true,
  format: "esm",
  platform: "browser",
  write: false,
});

const [{ selectReportType, selectStore }] = await Promise.all(
  bundle.outputFiles.map((file) => import(`data:text/javascript;base64,${Buffer.from(file.text).toString("base64")}`)),
);

function buildButton(value, { disabled = false } = {}) {
  const classes = new Set();
  const attributes = new Map();

  return {
    dataset: { value },
    disabled,
    classList: {
      toggle(name, active) {
        if (active) {
          classes.add(name);
        } else {
          classes.delete(name);
        }
      },
      contains(name) {
        return classes.has(name);
      },
    },
    setAttribute(name, attributeValue) {
      attributes.set(name, String(attributeValue));
    },
    getAttribute(name) {
      return attributes.get(name);
    },
    removeAttribute(name) {
      attributes.delete(name);
    },
  };
}

function buildStoreField() {
  const classes = new Set();
  const attributes = new Map();

  return {
    classList: {
      toggle(name, active) {
        if (active) {
          classes.add(name);
        } else {
          classes.delete(name);
        }
      },
      contains(name) {
        return classes.has(name);
      },
    },
    setAttribute(name, attributeValue) {
      attributes.set(name, String(attributeValue));
    },
    getAttribute(name) {
      return attributes.get(name);
    },
  };
}

test("selectReportType enables wr store selection and auto submits the form", () => {
  const form = {
    submits: 0,
    requestSubmit() {
      this.submits += 1;
    },
  };
  const reportTypeInput = { value: "wsu" };
  const storeInput = { value: "wb:1" };
  const reportButtons = [buildButton("wr"), buildButton("wsu"), buildButton("wsu_deep")];
  const storeButtons = [buildButton("wb:1", { disabled: true }), buildButton("ozon:2", { disabled: true })];
  const storeField = buildStoreField();

  selectReportType({
    value: "wr",
    reportTypeInput,
    reportButtons,
    storeInput,
    storeButtons,
    storeField,
    form,
  });

  assert.equal(reportTypeInput.value, "wr");
  assert.equal(reportButtons[0].classList.contains("is-active"), true);
  assert.equal(reportButtons[0].getAttribute("aria-pressed"), "true");
  assert.equal(storeField.classList.contains("is-disabled"), false);
  assert.equal(storeField.getAttribute("aria-disabled"), "false");
  assert.equal(storeButtons[0].disabled, false);
  assert.equal(storeButtons[0].getAttribute("tabindex"), undefined);
  assert.equal(form.submits, 1);
  assert.equal(storeInput.value, "wb:1");
});

test("selectStore updates active store and auto submits the form", () => {
  const form = {
    submits: 0,
    requestSubmit() {
      this.submits += 1;
    },
  };
  const storeInput = { value: "wb:1" };
  const storeButtons = [buildButton("wb:1"), buildButton("ozon:2")];

  selectStore({
    value: "ozon:2",
    storeInput,
    storeButtons,
    form,
  });

  assert.equal(storeInput.value, "ozon:2");
  assert.equal(storeButtons[0].classList.contains("is-active"), false);
  assert.equal(storeButtons[1].classList.contains("is-active"), true);
  assert.equal(storeButtons[1].getAttribute("aria-pressed"), "true");
  assert.equal(form.submits, 1);
});
