import assert from "node:assert/strict";
import { test } from "node:test";

import { build } from "esbuild";

const bundle = await build({
  entryPoints: ["app/javascript/controllers/category_selector_controller.js"],
  bundle: true,
  format: "esm",
  platform: "browser",
  write: false,
});

const [{ categoryOptionsFromResponse, selectedCategoryId }] = await Promise.all(
  bundle.outputFiles.map((file) => import(`data:text/javascript;base64,${Buffer.from(file.text).toString("base64")}`)),
);

test("categoryOptionsFromResponse maps JSON categories for select options", () => {
  assert.deepEqual(
    categoryOptionsFromResponse({
      categories: [
        { id: 1, name: "Parent" },
        { id: 2, name: "Child" },
      ],
    }),
    [
      { id: "1", name: "Parent", parentId: "", parentName: "" },
      { id: "2", name: "Child", parentId: "", parentName: "" },
    ],
  );
});

test("categoryOptionsFromResponse tolerates missing category arrays", () => {
  assert.deepEqual(categoryOptionsFromResponse({}), []);
});

test("selectedCategoryId uses child category when present", () => {
  assert.equal(selectedCategoryId("parent-1", "child-1"), "child-1");
});

test("selectedCategoryId falls back to parent category when child is blank", () => {
  assert.equal(selectedCategoryId("parent-1", ""), "parent-1");
});
