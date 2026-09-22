import assert from "node:assert/strict";
import { test } from "node:test";

import { build } from "esbuild";

const bundle = await build({
  entryPoints: ["app/javascript/controllers/collapsible_tag_row_controller.js"],
  bundle: true,
  format: "esm",
  platform: "browser",
  write: false,
});

const [{ contentOverflows }] = await Promise.all(
  bundle.outputFiles.map((file) => import(`data:text/javascript;base64,${Buffer.from(file.text).toString("base64")}`)),
);

test("does not overflow when scroll height matches the visible height", () => {
  assert.equal(contentOverflows(16, 16), false);
});

test("overflows when scroll height exceeds the collapsed height", () => {
  assert.equal(contentOverflows(48, 16), true);
});

test("tolerates sub-pixel rounding differences", () => {
  assert.equal(contentOverflows(16.4, 16), false);
});
