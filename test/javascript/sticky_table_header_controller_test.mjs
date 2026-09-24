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

const [{ findVerticalScrollContainer, shouldFloatHeader, stickyColumnPlacements }] = await Promise.all(
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

test("selects the first logical columns across grouped and detail header rows", () => {
  const groupedSticky = { colSpan: 3, rowSpan: 1 };
  const groupedScrolling = { colSpan: 4, rowSpan: 1 };
  const detailCells = Array.from({ length: 7 }, () => ({ colSpan: 1, rowSpan: 1 }));
  const rows = [
    { cells: [groupedSticky, groupedScrolling] },
    { cells: detailCells },
  ];

  const placements = stickyColumnPlacements(rows, 3);

  assert.deepEqual(placements.map(({ cell }) => cell), [groupedSticky, ...detailCells.slice(0, 3)]);
  assert.deepEqual(placements.map(({ start, end }) => [start, end]), [[0, 3], [0, 1], [1, 2], [2, 3]]);
});

test("accounts for row-spanning cells when locating sticky columns", () => {
  const rowSpanning = { colSpan: 1, rowSpan: 2 };
  const firstRowSecond = { colSpan: 1, rowSpan: 1 };
  const secondRowSecond = { colSpan: 1, rowSpan: 1 };
  const rows = [
    { cells: [rowSpanning, firstRowSecond] },
    { cells: [secondRowSecond] },
  ];

  const placements = stickyColumnPlacements(rows, 2);

  assert.deepEqual(placements.map(({ cell }) => cell), [rowSpanning, firstRowSecond, secondRowSecond]);
  assert.equal(placements.at(-1).start, 1);
});
