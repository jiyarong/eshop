import assert from "node:assert/strict";
import { test } from "node:test";
import { build } from "esbuild";

const bundle = await build({
  entryPoints: ["app/javascript/controllers/ozon_supply_controller.js"],
  bundle: true,
  format: "esm",
  platform: "browser",
  write: false,
});
const { default: OzonSupplyController } = await import(`data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString("base64")}`);

function controllerFor(t, result, values = {}) {
  const controller = Object.create(OzonSupplyController.prototype);
  Object.assign(controller, {
    statusUrlValue: "/plans/1/status.json",
    stateValue: "",
    planStateValue: "packed",
    orderIdValue: "",
    emptyValue: "—",
    pollErrorValue: "Retrying status read",
    ...values,
  });
  Object.defineProperty(controller, "element", { value: { isConnected: true } });
  for (const target of ["workflow", "binding", "handoff", "content", "submissionPanel", "planStatus", "platformStatus", "syncedAt", "orderNumber", "syncError", "pollError"]) {
    controller[`${target}Target`] = { innerHTML: "user input", textContent: "", hidden: false };
  }
  const timers = [];
  t.mock.method(globalThis, "setTimeout", (_callback, delay) => { timers.push(delay); });
  t.mock.method(globalThis, "fetch", async () => ({ ok: true, json: async () => result }));
  return { controller, timers };
}

function status(overrides = {}) {
  return {
    state: null, plan_state: "packed", order_id: null, order_number: null,
    running: false, active: true, platform_status: "READY_TO_SUPPLY", platform_synced_at: "2026-10-20 10:00",
    status: "Packed", sync_error: null,
    workflow_html: "new workflow", binding_html: "new binding", handoff_html: "", html: "",
    ...overrides,
  };
}

test("manual plans keep in-progress forms intact while unchanged status polls update metadata", async (t) => {
  const { controller, timers } = controllerFor(t, status({ order_number: "OZON-1" }));

  await controller.poll();

  assert.equal(controller.workflowTarget.innerHTML, "user input");
  assert.equal(controller.bindingTarget.innerHTML, "user input");
  assert.equal(controller.handoffTarget.innerHTML, "user input");
  assert.equal(controller.stateValue, "");
  assert.equal(controller.submissionPanelTarget.hidden, true);
  assert.equal(controller.orderNumberTarget.textContent, "OZON-1");
  assert.equal(controller.platformStatusTarget.textContent, "READY_TO_SUPPLY");
  assert.equal(controller.syncedAtTarget.textContent, "2026-10-20 10:00");
  assert.deepEqual(timers, [30000]);
});

test("new order binding refreshes actions even when the plan status stays packed", async (t) => {
  const { controller } = controllerFor(t, status({ order_id: "123", order_number: "OZON-123" }));

  await controller.poll();

  assert.equal(controller.workflowTarget.innerHTML, "new workflow");
  assert.equal(controller.bindingTarget.innerHTML, "new binding");
  assert.equal(controller.handoffTarget.innerHTML, "");
  assert.equal(controller.orderIdValue, "123");
  assert.equal(controller.orderNumberTarget.textContent, "OZON-123");
});

test("automatic completion reveals the submission results and keeps watching platform status", async (t) => {
  const { controller, timers } = controllerFor(t, status({
    state: "completed", order_id: "123", order_number: "OZON-123", html: "cargo IDs",
  }), { stateValue: "finalizing", orderIdValue: "123" });

  await controller.poll();

  assert.equal(controller.contentTarget.innerHTML, "cargo IDs");
  assert.equal(controller.submissionPanelTarget.hidden, false);
  assert.equal(controller.bindingTarget.innerHTML, "new binding");
  assert.deepEqual(timers, [30000]);
});

test("platform completion replaces manual actions and stops polling a closed plan", async (t) => {
  const { controller, timers } = controllerFor(t, status({ plan_state: "closed", active: false, status: "Closed" }));

  await controller.poll();

  assert.equal(controller.workflowTarget.innerHTML, "new workflow");
  assert.equal(controller.planStatusTarget.innerHTML, "Closed");
  assert.equal(controller.planStateValue, "closed");
  assert.deepEqual(timers, []);
});

test("running submission readback continues after platform completion closes the plan", async (t) => {
  const { controller, timers } = controllerFor(t, status({ state: "finalizing", running: true, active: false, plan_state: "closed", html: "checking cargoes" }));

  await controller.poll();

  assert.equal(controller.contentTarget.innerHTML, "checking cargoes");
  assert.deepEqual(timers, [3000]);
});
