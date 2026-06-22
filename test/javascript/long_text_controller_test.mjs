import assert from "node:assert/strict";
import { test } from "node:test";

import { build } from "esbuild";

const bundle = await build({
  entryPoints: ["app/javascript/controllers/long_text_controller.js"],
  bundle: true,
  format: "esm",
  platform: "browser",
  write: false,
});

const [{ formatLongText }] = await Promise.all(
  bundle.outputFiles.map((file) => import(`data:text/javascript;base64,${Buffer.from(file.text).toString("base64")}`)),
);

test("formatLongText truncates text longer than the limit and keeps custom tooltip text", () => {
  const text = "a".repeat(101);

  assert.deepEqual(formatLongText(text, 100), {
    displayText: "a".repeat(100),
    tooltipText: text,
  });
});

test("formatLongText leaves text at the limit unchanged without custom tooltip text", () => {
  const text = "a".repeat(100);

  assert.deepEqual(formatLongText(text, 100), {
    displayText: text,
    tooltipText: null,
  });
});

test("formatLongText leaves short text unchanged without custom tooltip text", () => {
  assert.deepEqual(formatLongText("short", 100), {
    displayText: "short",
    tooltipText: null,
  });
});
