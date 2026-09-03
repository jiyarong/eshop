import assert from "node:assert/strict";
import { test } from "node:test";

import { build } from "esbuild";

const bundle = await build({
  entryPoints: ["app/javascript/controllers/sticky_table_header_controller.js"],
  bundle: true,
  format: "esm",
  platform: "browser",
  write: false,
});

const [{ shouldFloatHeader }] = await Promise.all(
  bundle.outputFiles.map((file) => import(`data:text/javascript;base64,${Buffer.from(file.text).toString("base64")}`)),
);

test("floats after the table header crosses the top offset", () => {
  assert.equal(shouldFloatHeader({ top: 20, bottom: 900 }, 44, 64), true);
});

test("does not float before the table reaches the top offset", () => {
  assert.equal(shouldFloatHeader({ top: 80, bottom: 900 }, 44, 64), false);
});

test("stops floating before the table bottom crosses the header", () => {
  assert.equal(shouldFloatHeader({ top: -500, bottom: 100 }, 44, 64), false);
});
