import assert from "node:assert/strict";
import { test } from "node:test";
import { build } from "esbuild";

const bundle = await build({
  entryPoints: ["app/javascript/controllers/input_number_controller.js"],
  bundle: true,
  format: "esm",
  platform: "browser",
  write: false,
});

const [{ default: InputNumberController }] = await Promise.all(
  bundle.outputFiles.map((file) => import(`data:text/javascript;base64,${Buffer.from(file.text).toString("base64")}`)),
);

function buildController(value, { magnitudeStep, minimumStep }) {
  const input = {
    value: String(value),
    min: "",
    max: "",
    focus() {},
    dispatchEvent() {},
  };
  const controller = Object.create(InputNumberController.prototype);
  controller.inputTarget = input;
  controller.hasMagnitudeStepValue = magnitudeStep === true;
  controller.hasMinimumStepValue = minimumStep !== undefined;
  controller.minimumStepValue = minimumStep;
  controller.hasStepValue = false;
  return { controller, input };
}

test("uses a stable magnitude step for amount values", () => {
  const first = buildController(100, { magnitudeStep: true, minimumStep: 1 });
  assert.equal(first.controller.stepAmount(), 10);
  first.controller.changeBy(first.controller.stepAmount());
  assert.equal(first.input.value, "110");

  const second = buildController(10000, { magnitudeStep: true, minimumStep: 1 });
  assert.equal(second.controller.stepAmount(), 100);
  second.controller.changeBy(second.controller.stepAmount());
  assert.equal(second.input.value, "10100");

  const third = buildController(750, { magnitudeStep: true, minimumStep: 1 });
  assert.equal(third.controller.stepAmount(), 10);
});

test("keeps precision when a high-precision amount is adjusted", () => {
  const { controller, input } = buildController(0.075, { magnitudeStep: true, minimumStep: 0.01 });
  controller.changeBy(controller.stepAmount());
  assert.equal(input.value, "0.085");
});
