import assert from "node:assert/strict";
import { test } from "node:test";

import { build } from "esbuild";

const bundle = await build({
  entryPoints: ["app/javascript/controllers/clipboard_controller.js"],
  bundle: true,
  format: "esm",
  platform: "browser",
  write: false,
});

const [{ writeClipboardText }] = await Promise.all(
  bundle.outputFiles.map((file) => import(`data:text/javascript;base64,${Buffer.from(file.text).toString("base64")}`)),
);

test("writes the original text with the Clipboard API", async () => {
  const copied = [];

  await writeClipboardText("## 原文\n\n库存 3 件", {
    writeText(text) {
      copied.push(text);
      return Promise.resolve();
    },
  });

  assert.deepEqual(copied, ["## 原文\n\n库存 3 件"]);
});

test("falls back to a temporary textarea when Clipboard API access fails", async () => {
  let selected = false;
  let removed = false;
  let appended;
  const textarea = {
    setAttribute() {},
    style: {},
    select() { selected = true; },
    remove() { removed = true; },
  };
  const documentObject = {
    createElement() { return textarea; },
    body: { append(element) { appended = element; } },
    execCommand(command) {
      assert.equal(command, "copy");
      return true;
    },
  };

  await writeClipboardText(
    "raw reply",
    { writeText: () => Promise.reject(new Error("denied")) },
    documentObject,
  );

  assert.equal(textarea.value, "raw reply");
  assert.equal(appended, textarea);
  assert.equal(selected, true);
  assert.equal(removed, true);
});
