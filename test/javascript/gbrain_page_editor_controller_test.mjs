import assert from "node:assert/strict";
import { test } from "node:test";

import { build } from "esbuild";

const bundle = await build({
  entryPoints: ["app/javascript/controllers/gbrain_page_editor_controller.js"],
  bundle: true,
  format: "esm",
  platform: "browser",
  write: false,
});

const [{ classificationFieldValues, simpleModeRequiresClassification }] = await Promise.all(
  bundle.outputFiles.map((file) => import(`data:text/javascript;base64,${Buffer.from(file.text).toString("base64")}`)),
);

test("classificationFieldValues maps model arrays to the existing multiline form fields", () => {
  const values = classificationFieldValues({
    page: {
      title: "Ozon warehouse strategy",
      page_type: "operation-playbook",
      aliases: ["FBO strategy", "仓库策略"],
      tags: ["platform/ozon", "topic/warehouse"],
      region_scope: [],
      effective_date: null,
    },
  });

  assert.deepEqual(values, {
    title: "Ozon warehouse strategy",
    page_type: "operation-playbook",
    aliases_text: "FBO strategy\n仓库策略",
    tags_text: "platform/ozon\ntopic/warehouse",
    region_scope_text: "",
    effective_date: "",
  });
});

test("classificationFieldValues rejects an invalid response shape", () => {
  assert.throws(() => classificationFieldValues({ error: "failed" }), /page object/);
});

test("simple mode requires a fresh classification while complex mode does not", () => {
  assert.equal(simpleModeRequiresClassification("simple", false), true);
  assert.equal(simpleModeRequiresClassification("simple", true), false);
  assert.equal(simpleModeRequiresClassification("complex", false), false);
});
