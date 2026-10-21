import assert from "node:assert/strict";
import { test } from "node:test";
import { build } from "esbuild";

const bundle = await build({ entryPoints: ["app/javascript/controllers/delivery_workbench_controller.js"], bundle: true, format: "esm", platform: "browser", write: false });
const { default: DeliveryWorkbenchController } = await import(`data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString("base64")}`);

test("selecting a SKU leaves the estimate empty even when a suggested quantity exists", () => {
  const controller = Object.create(DeliveryWorkbenchController.prototype);
  controller.items = [];
  controller.catalogueValue = [{ sku_code: "SKU", suggested_units: 100 }];
  controller.render = () => {};

  controller.pick({ target: { dataset: { sku: "SKU" }, checked: true } });

  assert.deepEqual(controller.items, [{ sku_code: "SKU", units: null }]);
});

test("suggested demand includes more than five SKUs without requiring packaging or replacing manual quantities", () => {
  const controller = Object.create(DeliveryWorkbenchController.prototype);
  controller.items = [{ sku_code: "SKU-0", units: 7 }];
  controller.catalogueValue = Array.from({ length: 8 }, (_, i) => ({ sku_code: `SKU-${i}`, suggested_units: 100 + i, packaging_complete: false }));
  controller.render = () => {};

  controller.selectSuggested();

  assert.equal(controller.items.length, 8);
  assert.equal(controller.items[0].units, 7);
  assert.equal(controller.items[7].units, 107);
});

test("changing stores clears the destination cluster and reloads the SKU catalogue", () => {
  const controller = Object.create(DeliveryWorkbenchController.prototype);
  const cluster = { value: "3" };
  let submitted = false;
  const form = { elements: { namedItem: () => cluster }, requestSubmit: () => { submitted = true; } };

  controller.changeStore({ target: { form } });

  assert.equal(cluster.value, "");
  assert.equal(submitted, true);
});

test("server version changes discard saved local quantities and the delivery week", () => {
  const controller = Object.create(DeliveryWorkbenchController.prototype);
  Object.assign(controller, { hasManifestTarget: true, contextValue: { id: 12, store_id: 2, cluster_id: 3, lock_version: 4 },
    initialValue: [{ sku_code: "SKU", units: 10 }], weekTarget: { value: "2026-10-19" }, render() {} });
  const original = globalThis.sessionStorage;
  globalThis.sessionStorage = { getItem: () => JSON.stringify({ lockVersion: 3, items: [{ sku_code: "SKU", units: 99 }], week: "2026-11-02" }) };
  try {
    controller.connect();
    assert.deepEqual(controller.items, [{ sku_code: "SKU", units: 10 }]);
    assert.equal(controller.weekTarget.value, "2026-10-19");
    assert.equal(controller.storageKey, "delivery-workbench:12:2");
  } finally { globalThis.sessionStorage = original; }
});

test("page reload restores selected units and week for the same server version", () => {
  const controller = Object.create(DeliveryWorkbenchController.prototype);
  Object.assign(controller, { hasManifestTarget: true, contextValue: { id: 13, store_id: 2, cluster_id: 3, lock_version: 4 },
    initialValue: [], weekTarget: { value: "2026-10-19" }, render() {} });
  const original = globalThis.sessionStorage;
  globalThis.sessionStorage = { getItem: () => JSON.stringify({ lockVersion: 4, items: [{ sku_code: "SKU", units: 99 }], week: "2026-11-02" }) };
  try {
    controller.connect();
    assert.deepEqual(controller.items, [{ sku_code: "SKU", units: 99 }]);
    assert.equal(controller.weekTarget.value, "2026-11-02");
  } finally { globalThis.sessionStorage = original; }
});
