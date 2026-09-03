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

const [{ findVerticalScrollContainer, shouldFloatHeader }] = await Promise.all(
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

test("does not float outside the bottom of a nested scroll viewport", () => {
  assert.equal(shouldFloatHeader({ top: -500, bottom: 900 }, 44, 580, 600), false);
});

test("uses the nearest vertically scrollable ancestor", () => {
  const drawer = { parentElement: null, scrollHeight: 900, clientHeight: 500 };
  const wrapper = { parentElement: drawer, scrollHeight: 300, clientHeight: 300 };
  const table = { parentElement: wrapper };
  const styleFor = (node) => ({ overflowY: node === drawer ? "auto" : "visible" });

  assert.equal(findVerticalScrollContainer(table, styleFor, "window"), drawer);
});

test("falls back to the window when no ancestor scrolls vertically", () => {
  const parent = { parentElement: null, scrollHeight: 300, clientHeight: 300 };
  const table = { parentElement: parent };

  assert.equal(findVerticalScrollContainer(table, () => ({ overflowY: "auto" }), "window"), "window");
});
