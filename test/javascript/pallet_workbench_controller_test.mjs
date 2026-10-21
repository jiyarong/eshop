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
    messagesValue: { changed: "Pending validation", empty: "Select SKUs", calculating: "Calculating", validated: "Validation passed", invalid_items: "Check quantities and packaging", filled: "Cartons added", fill_unchanged: "No cartons added; see limits", shipping_pending: "Checking delivery options", shipping_empty: "Add products to check delivery options", shipping_failed: "Delivery validation failed", maximizing: "Calculating MAX for %{sku}", maximized: "%{sku}: %{boxes} cartons maximum" },
    hasShippingAdviceTarget: true,
    shippingAdviceTarget: {
      innerHTML: "Previous delivery recommendation",
      buttons: [{ disabled: false }],
      set textContent(value) { this.innerHTML = value; this.buttons = []; },
      querySelectorAll() { return this.buttons; },
    },
    resultsTarget: {
      innerHTML: "Previous validated layout",
      style: { minHeight: "" },
      getBoundingClientRect() { return { height: Math.max(this.innerHTML === "Previous validated layout" ? 1200 : this.innerHTML ? 800 : 0, parseFloat(this.style.minHeight) || 0) }; },
      replaceChildren() { this.innerHTML = ""; },
    },
    capacityTarget: { hidden: false },
    manifestTarget: { querySelectorAll: () => [] },
    saveButtonTarget: { disabled: false },
    calculateButtonTarget: {},
    recommendButtonTarget: {},
    modeTarget: { value: "single" },
    maxButtonTargets: [],
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
  assert.equal(controller.shippingAdviceTarget.innerHTML, "Checking delivery options");
  assert.equal(controller.shippingAdviceTarget.buttons.length, 0);

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
  assert.equal(controller.shippingAdviceTarget.innerHTML, "Delivery validation failed");
  assert.deepEqual(controller.status, { message: "Pallet capacity exceeded", error: true });
});

test("a shorter replacement layout keeps the scroll space while enabling saving", async (t) => {
  const controller = controllerFor(t);
  for (const target of ["heightMeter", "heightLabel", "weightMeter", "weightLabel"]) controller[`${target}Target`] = {};
  controller.renderAllocations = () => {};
  controller.request = async () => ({
    html: "Updated layout",
    shipping_advice_html: "Box delivery is available",
    result: {
      items: controller.items,
      pallets: [{ zones: [{ item_index: 0, count: 2 }], height: 100, weight: 80 }],
      settings: { height: 220, weight: 800 },
    },
  });
  controller.invalidate();

  await controller.calculate(true);

  assert.equal(controller.resultsTarget.innerHTML, "Updated layout");
  assert.equal(controller.shippingAdviceTarget.innerHTML, "Box delivery is available");
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
  assert.equal(controller.shippingAdviceTarget.innerHTML, "Add products to check delivery options");
  assert.equal(controller.saveButtonTarget.disabled, true);
});

test("fill with no additions displays the outcome and keeps the current manifest", async (t) => {
  const controller = controllerFor(t);
  controller.renderAllocations = () => {};
  let request;
  controller.request = async (_url, body) => {
    request = body.pallet_plan;
    return { html: "Capacity limit explanation", result: {
      shipping_mode: "pallet", items: controller.items, pallets: [], fill: { changes: [] },
    } };
  };

  await controller.fillFreeSpace();

  assert.equal(request.apply_fill, true);
  assert.equal(request.shipping_mode, "pallet");
  assert.equal(controller.status.message, "No cartons added; see limits");
  assert.equal(controller.resultsTarget.innerHTML, "Capacity limit explanation");
  assert.equal(controller.items[0].quantity, 2);
  assert.equal(controller.saveButtonTarget.disabled, false);
});

test("an outdated preview cannot restore a stale delivery recommendation", async (t) => {
  const controller = controllerFor(t);
  let resolve;
  controller.request = () => new Promise((done) => { resolve = done; });

  const calculating = controller.calculate(true);
  assert.equal(controller.shippingAdviceTarget.buttons[0].disabled, true);
  controller.items[0].quantity = 4;
  controller.invalidate();
  resolve({ html: "Outdated layout", shipping_advice_html: "Outdated delivery suggestion", result: {} });
  await calculating;

  assert.equal(controller.resultsTarget.innerHTML, "");
  assert.equal(controller.shippingAdviceTarget.innerHTML, "Checking delivery options");
  assert.equal(controller.saveButtonTarget.disabled, true);
});

test("choosing box delivery preserves quantities, revalidates and can be undone", async (t) => {
  const controller = controllerFor(t);
  controller.hasShippingModeTarget = true;
  controller.shippingModeTarget = { value: "pallet" };
  controller.undoButtonTarget = { hidden: true };
  controller.allocations = [{ items: [{ sku_code: "TEST-SKU", quantity: 2 }] }];
  const originalAllocations = structuredClone(controller.allocations);
  controller.renderAllocations = () => {};
  controller.renderItems = () => {};

  controller.useShippingMode({ currentTarget: { dataset: { mode: "box" } } });

  assert.equal(controller.shippingModeTarget.value, "box");
  assert.deepEqual(controller.items, [{ sku_code: "TEST-SKU", quantity: 2 }]);
  assert.deepEqual(controller.allocations, []);
  assert.equal(controller.saveButtonTarget.disabled, true);
  assert.equal(controller.undoButtonTarget.hidden, false);
  assert.equal(globalThis.setTimeout.mock.calls.at(-1).arguments[1], 650);

  controller.request = async () => ({ html: "Validated box delivery", shipping_advice_html: "Current: box delivery", result: {
    shipping_mode: "box", items: controller.items, pallets: [],
  } });
  await globalThis.setTimeout.mock.calls.at(-1).arguments[0]();
  assert.equal(controller.saveButtonTarget.disabled, false);
  assert.equal(controller.shippingAdviceTarget.innerHTML, "Current: box delivery");

  controller.undo();
  assert.equal(controller.shippingModeTarget.value, "pallet");
  assert.deepEqual(controller.allocations, originalAllocations);
  assert.deepEqual(controller.items, [{ sku_code: "TEST-SKU", quantity: 2 }]);
  assert.equal(controller.saveButtonTarget.disabled, true);
  assert.equal(controller.undoButtonTarget.hidden, true);
});

test("successful fill applies the returned quantities and keeps one undo snapshot", async (t) => {
  const controller = controllerFor(t);
  controller.undoButtonTarget = { hidden: true };
  controller.renderAllocations = () => {};
  controller.renderItems = () => {};
  controller.request = async () => ({ html: "Filled layout", result: {
    shipping_mode: "pallet", items: [{ sku_code: "TEST-SKU", quantity: 3 }], pallets: [],
    fill: { changes: [{ sku_code: "TEST-SKU", from_boxes: 2, to_boxes: 3 }] },
  } });

  await controller.fillFreeSpace();

  assert.equal(controller.items[0].quantity, 3);
  assert.equal(controller.previous.items[0].quantity, 2);
  assert.equal(controller.undoButtonTarget.hidden, false);
  assert.equal(controller.status.message, "Cartons added");
  assert.equal(controller.saveButtonTarget.disabled, false);
});

test("MAX applies the server layout, preserves other SKUs and supports undo", async (t) => {
  const controller = controllerFor(t);
  controller.items.push({ sku_code: "OTHER", quantity: 4 });
  const original = structuredClone(controller.items);
  controller.allocations = [];
  controller.undoButtonTarget = { hidden: true };
  controller.renderAllocations = () => {};
  controller.renderItems = () => {};
  let request;
  controller.request = async (_url, body) => {
    request = body.pallet_plan;
    assert.equal(controller.status.message, "Calculating MAX for TEST-SKU");
    return { html: "Maximum layout", result: {
      shipping_mode: "pallet", items: [{ sku_code: "TEST-SKU", quantity: 14 }, { sku_code: "OTHER", quantity: 4 }],
      pallets: [], maximized: { sku_code: "TEST-SKU", from_boxes: 2, to_boxes: 14 },
    } };
  };

  await controller.maximizeItem({ currentTarget: { closest: () => ({ dataset: { sku: "TEST-SKU" } }) } });

  assert.equal(request.maximize_sku_code, "TEST-SKU");
  assert.equal(request.shipping_mode, "pallet");
  assert.deepEqual(request.allocations, []);
  assert.deepEqual(controller.items.map((item) => item.quantity), [14, 4]);
  assert.equal(controller.status.message, "TEST-SKU: 14 cartons maximum");
  assert.equal(controller.saveButtonTarget.disabled, false);
  controller.undo();
  assert.deepEqual(controller.items, original);
  assert.equal(controller.saveButtonTarget.disabled, true);
});

test("MAX buttons reflect busy state and are hidden for box delivery", (t) => {
  const controller = controllerFor(t);
  const button = { attributes: {}, setAttribute(key, value) { this.attributes[key] = value; }, closest: () => ({ dataset: { sku: "TEST-SKU" } }) };
  controller.maxButtonTargets = [button];
  controller.busy = true;
  controller.maximizingSku = "TEST-SKU";
  controller.updateButtons();
  assert.equal(button.disabled, true);
  assert.equal(button.attributes["aria-busy"], "true");

  controller.busy = false;
  controller.hasShippingModeTarget = true;
  controller.shippingModeTarget = { value: "box" };
  controller.updateButtons();
  assert.equal(button.hidden, true);
  assert.equal(button.attributes["aria-busy"], "false");
});

test("a stale MAX result cannot overwrite edited quantities or undo history", async (t) => {
  const controller = controllerFor(t);
  let resolve;
  controller.request = () => new Promise((done) => { resolve = done; });
  const calculating = controller.calculate(false, null, false, "TEST-SKU");
  controller.items[0].quantity = 4;
  controller.invalidate();
  resolve({ result: { maximized: { from_boxes: 2, to_boxes: 18 } } });
  await calculating;
  assert.equal(controller.items[0].quantity, 4);
  assert.equal(controller.previous, undefined);
  assert.equal(controller.saveButtonTarget.disabled, true);
});

test("single-pallet MAX can correct its own quantity beyond the stock input limit", async (t) => {
  const controller = controllerFor(t);
  controller.manifestTarget.querySelectorAll = () => [{ dataset: { field: "quantity" }, closest: () => ({ dataset: { sku: "TEST-SKU" } }) }];
  controller.renderAllocations = () => {};
  let requested = false;
  controller.request = async () => {
    requested = true;
    return { result: { items: controller.items, pallets: [], maximized: { from_boxes: 2, to_boxes: 2 } } };
  };

  await controller.calculate(false, null, false, "TEST-SKU");

  assert.equal(requested, true);
  assert.equal(controller.status.message, "TEST-SKU: 2 cartons maximum");
});

for (const [mode, field, sku] of [["single", "quantity", "OTHER"], ["single", "weight", "TEST-SKU"], ["multiple", "quantity", "TEST-SKU"]]) {
  test(`MAX rejects invalid ${field} for ${sku} in ${mode} mode`, async (t) => {
    const controller = controllerFor(t);
    controller.modeTarget.value = mode;
    controller.manifestTarget.querySelectorAll = () => [{ dataset: { field }, closest: () => ({ dataset: { sku } }) }];
    controller.request = () => assert.fail("Invalid inputs must be corrected before requesting MAX");

    await controller.calculate(false, null, false, "TEST-SKU");

    assert.deepEqual(controller.status, { message: "Check quantities and packaging", error: true });
  });
}
