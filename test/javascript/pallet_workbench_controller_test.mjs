import assert from "node:assert/strict";
import { test } from "node:test";
import { build } from "esbuild";

const bundle = await build({
  entryPoints: ["app/javascript/controllers/pallet_workbench_controller.js"],
  bundle: true,
  format: "esm",
  platform: "browser",
  write: false,
});
const { default: PalletWorkbenchController } = await import(`data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString("base64")}`);

function controllerFor(t) {
  const controller = Object.create(PalletWorkbenchController.prototype);
  Object.defineProperty(controller, "element", { value: { isConnected: true } });
  Object.assign(controller, {
    revision: 1,
    validated: true,
    items: [{ sku_code: "TEST-SKU", quantity: 2 }],
    messagesValue: { changed: "Pending validation", empty: "Select SKUs", calculating: "Calculating", validated: "Validation passed" },
    resultsTarget: {
      innerHTML: "Previous validated layout",
      style: { minHeight: "" },
      getBoundingClientRect() { return { height: Math.max(this.innerHTML === "Previous validated layout" ? 1200 : this.innerHTML ? 800 : 0, parseFloat(this.style.minHeight) || 0) }; },
      replaceChildren() { this.innerHTML = ""; },
    },
    capacityTarget: { hidden: false },
    manifestTarget: { querySelector: () => null },
    saveButtonTarget: { disabled: false },
    calculateButtonTarget: {},
    recommendButtonTarget: {},
    modeTarget: { value: "single" },
    catalogueValue: [],
    setStatus(message, error = false) { this.status = { message, error }; },
    persist() {},
    payload() { return {}; },
  });
  t.mock.method(globalThis, "setTimeout", () => 1);
  t.mock.method(globalThis, "clearTimeout", () => {});
  return controller;
}

test("quantity changes clear stale results and disable saving without collapsing their scroll space", (t) => {
  const controller = controllerFor(t);

  controller.invalidate();

  assert.equal(controller.resultsTarget.innerHTML, "");
  assert.equal(controller.resultsTarget.getBoundingClientRect().height, 1200);
  assert.equal(controller.capacityTarget.hidden, true);
  assert.equal(controller.saveButtonTarget.disabled, true);

  controller.items[0].quantity = 3;
  controller.invalidate();

  assert.equal(controller.resultsTarget.getBoundingClientRect().height, 1200);
  assert.equal(controller.status.message, "Pending validation");
});

test("failed validation keeps the reserved scroll space and saving disabled", async (t) => {
  const controller = controllerFor(t);
  controller.request = async () => { throw new Error("Pallet capacity exceeded"); };
  controller.invalidate();

  await controller.calculate(true);

  assert.equal(controller.resultsTarget.getBoundingClientRect().height, 1200);
  assert.equal(controller.resultsTarget.innerHTML, "");
  assert.equal(controller.saveButtonTarget.disabled, true);
  assert.deepEqual(controller.status, { message: "Pallet capacity exceeded", error: true });
});

test("a shorter replacement layout keeps the scroll space while enabling saving", async (t) => {
  const controller = controllerFor(t);
  for (const target of ["heightMeter", "heightLabel", "weightMeter", "weightLabel"]) controller[`${target}Target`] = {};
  controller.renderAllocations = () => {};
  controller.request = async () => ({
    html: "Updated layout",
    result: {
      items: controller.items,
      pallets: [{ zones: [{ item_index: 0, count: 2 }], height: 100, weight: 80 }],
      settings: { height: 220, weight: 800 },
    },
  });
  controller.invalidate();

  await controller.calculate(true);

  assert.equal(controller.resultsTarget.innerHTML, "Updated layout");
  assert.equal(controller.resultsTarget.getBoundingClientRect().height, 1200);
  assert.equal(controller.saveButtonTarget.disabled, false);
  assert.equal(controller.status.message, "Validation passed");
});

test("clearing the manifest releases the space reserved for the previous layout", (t) => {
  const controller = controllerFor(t);
  controller.invalidate();

  controller.items = [];
  controller.invalidate();

  assert.equal(controller.resultsTarget.getBoundingClientRect().height, 0);
  assert.equal(controller.status.message, "Select SKUs");
  assert.equal(controller.saveButtonTarget.disabled, true);
});
