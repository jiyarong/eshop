import assert from "node:assert/strict";
import { test } from "node:test";

import { build } from "esbuild";

const bundle = await build({
  entryPoints: ["app/javascript/controllers/sku_batch_form_controller.js"],
  bundle: true,
  format: "esm",
  platform: "browser",
  write: false,
});

const [{ syncDefectOffsetNoteVisibility }] = await Promise.all(
  bundle.outputFiles.map((file) => import(`data:text/javascript;base64,${Buffer.from(file.text).toString("base64")}`)),
);

test("normal batches hide the offset note", () => {
  const noteField = { hidden: false };

  syncDefectOffsetNoteVisibility({ batchType: "normal", noteField });

  assert.equal(noteField.hidden, true);
});

test("non-normal batches show the offset note", () => {
  for (const batchType of ["wb_fbw_offset", "untrackable_defective", "other"]) {
    const noteField = { hidden: true };

    syncDefectOffsetNoteVisibility({ batchType, noteField });

    assert.equal(noteField.hidden, false);
  }
});
