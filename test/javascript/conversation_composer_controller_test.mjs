import assert from "node:assert/strict";
import { test } from "node:test";

import { build } from "esbuild";

const bundle = await build({
  entryPoints: ["app/javascript/controllers/conversation_composer_controller.js"],
  bundle: true,
  format: "esm",
  platform: "browser",
  write: false,
});

const [{ default: ConversationComposerController, canAppendImages, clipboardImageFiles }] = await Promise.all(
  bundle.outputFiles.map((file) => import(`data:text/javascript;base64,${Buffer.from(file.text).toString("base64")}`)),
);

const clipboardItem = (kind, type, file) => ({ kind, type, getAsFile: () => file });

test("extracts supported images from clipboard items", () => {
  const png = { name: "image.png", type: "image/png" };
  const bmp = { name: "image.bmp", type: "image/bmp" };
  const clipboardData = {
    items: [
      clipboardItem("string", "text/plain", null),
      clipboardItem("file", "image/png", png),
      clipboardItem("file", "image/bmp", bmp),
    ],
  };

  assert.deepEqual(clipboardImageFiles(clipboardData, ["image/png", "image/jpeg"]), [png]);
});

test("falls back to clipboard files when items are unavailable", () => {
  const image = { name: "screenshot.webp", type: "image/webp" };

  assert.deepEqual(
    clipboardImageFiles({ files: [image] }, ["image/webp"]),
    [image],
  );
});

test("allows pasted images only when the combined selection fits", () => {
  assert.equal(canAppendImages(2, 2, 4), true);
  assert.equal(canAppendImages(3, 2, 4), false);
  assert.equal(canAppendImages(1, 0, 4), false);
});

test("pasting an image appends it to the existing file selection", () => {
  const existing = { name: "existing.png", type: "image/png" };
  const pasted = { name: "pasted.png", type: "image/png" };
  let prevented = false;
  let previewsRendered = false;
  let errorCleared = false;

  globalThis.DataTransfer = class {
    constructor() {
      const files = [];
      this.files = files;
      this.items = { add: (file) => files.push(file) };
    }
  };

  const context = {
    imagesTarget: { accept: "image/png,image/jpeg", files: [existing] },
    maxImagesValue: 4,
    clearError() { errorCleared = true; },
    renderPreviews() { previewsRendered = true; },
  };
  const event = {
    clipboardData: { items: [clipboardItem("file", "image/png", pasted)] },
    preventDefault() { prevented = true; },
  };

  ConversationComposerController.prototype.paste.call(context, event);

  assert.equal(prevented, true);
  assert.deepEqual(context.imagesTarget.files, [existing, pasted]);
  assert.equal(errorCleared, true);
  assert.equal(previewsRendered, true);
  delete globalThis.DataTransfer;
});
