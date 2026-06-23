import assert from "node:assert/strict";
import { test } from "node:test";

import { build } from "esbuild";

const bundle = await build({
  entryPoints: ["app/javascript/controllers/page_translation_controller.js"],
  bundle: true,
  format: "esm",
  platform: "browser",
  write: false,
});

const [{ collectTextNodes, parseTranslationContent, applyTranslations, restoreOriginalText }] = await Promise.all(
  bundle.outputFiles.map((file) => import(`data:text/javascript;base64,${Buffer.from(file.text).toString("base64")}`)),
);

function createTextNode(text) {
  return { nodeType: 3, textContent: text, parentElement: null };
}

function createElement(tagName, { hidden = false, display = "block" } = {}) {
  return {
    nodeType: 1,
    tagName: tagName.toUpperCase(),
    hidden,
    style: { display },
    childNodes: [],
    parentElement: null,
    closest(selector) {
      if (selector !== "[data-page-translation-ignore]") return null;

      let current = this;
      while (current) {
        if (current.ignoreTranslation) return current;
        current = current.parentElement;
      }

      return null;
    },
  };
}

function append(parent, child) {
  parent.childNodes.push(child);
  child.parentElement = parent;
  return child;
}

test("collectTextNodes collects visible page text and skips form or hidden content", () => {
  const page = createElement("main");
  const heading = append(page, createElement("h1"));
  const paragraph = append(page, createElement("p"));
  const input = append(page, createElement("input"));
  const hidden = append(page, createElement("span", { hidden: true }));
  const ignored = append(page, createElement("span"));
  ignored.ignoreTranslation = true;

  append(heading, createTextNode("库存报表"));
  append(paragraph, createTextNode("  总库存 10 件  "));
  append(input, createTextNode("搜索"));
  append(hidden, createTextNode("隐藏文本"));
  append(ignored, createTextNode("不要翻译"));

  assert.deepEqual(collectTextNodes(page).map(({ id, text }) => ({ id, text })), [
    { id: "t0", text: "库存报表" },
    { id: "t1", text: "总库存 10 件" },
  ]);
});

test("applyTranslations and restoreOriginalText switch between translated and original text", () => {
  const first = createTextNode("库存报表");
  const second = createTextNode("总库存 10 件");
  const entries = [
    { id: "t0", text: "库存报表", node: first },
    { id: "t1", text: "总库存 10 件", node: second },
  ];

  applyTranslations(entries, [
    { id: "t0", text: "Inventory report" },
    { id: "t1", text: "Total stock: 10 pcs" },
  ]);

  assert.equal(first.textContent, "Inventory report");
  assert.equal(second.textContent, "Total stock: 10 pcs");

  restoreOriginalText(entries);

  assert.equal(first.textContent, "库存报表");
  assert.equal(second.textContent, "总库存 10 件");
});

test("parseTranslationContent accepts only translation arrays", () => {
  assert.deepEqual(parseTranslationContent('[{"id":"t0","text":"Inventory"}]'), [{ id: "t0", text: "Inventory" }]);
  assert.throws(() => parseTranslationContent("数据不足：当前系统尚未配置可用的 AI 模型客户端。"));
  assert.throws(() => parseTranslationContent('{"id":"t0","text":"Inventory"}'));
});
