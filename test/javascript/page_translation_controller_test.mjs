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

const [
  {
    collectTextNodes,
    parseTranslationContent,
    applyTranslations,
    buildTranslationBatches,
    expandMergedTranslations,
    mergeTranslationEntries,
    requestTranslationsInBatches,
    restoreOriginalText,
    summarizeTranslationResult,
    translationQuestionPayload,
    translationStateLabel,
  },
] = await Promise.all(bundle.outputFiles.map((file) => import(`data:text/javascript;base64,${Buffer.from(file.text).toString("base64")}`)));

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

test("mergeTranslationEntries sends duplicate text only once", () => {
  const first = createTextNode("库存");
  const second = createTextNode("库存");
  const third = createTextNode("售出");
  const entries = [
    { id: "t0", text: "库存", node: first },
    { id: "t1", text: "库存", node: second },
    { id: "t2", text: "售出", node: third },
  ];

  const { mergedEntries, mergedEntriesById } = mergeTranslationEntries(entries);

  assert.deepEqual(
    mergedEntries.map(({ id, text, entryIds }) => ({ id, text, entryIds })),
    [
      { id: "m0", text: "库存", entryIds: ["t0", "t1"] },
      { id: "m1", text: "售出", entryIds: ["t2"] },
    ],
  );
  assert.deepEqual(mergedEntriesById.get("m0").entries.map((entry) => entry.node), [first, second]);
});

test("expandMergedTranslations applies a merged translation to every original item", () => {
  const first = createTextNode("库存");
  const second = createTextNode("库存");
  const third = createTextNode("售出");
  const entries = [
    { id: "t0", text: "库存", node: first },
    { id: "t1", text: "库存", node: second },
    { id: "t2", text: "售出", node: third },
  ];
  const merged = mergeTranslationEntries(entries);

  assert.deepEqual(expandMergedTranslations(merged, [{ id: "m0", text: "Stock" }]), [
    { id: "t0", text: "Stock" },
    { id: "t1", text: "Stock" },
  ]);
});

test("expandMergedTranslations keeps unknown merged ids for diagnostics", () => {
  const merged = mergeTranslationEntries([{ id: "t0", text: "库存", node: createTextNode("库存") }]);

  assert.deepEqual(expandMergedTranslations(merged, [{ id: "ghost", text: "Ghost" }]), [{ id: "ghost", text: "Ghost" }]);
});

test("translationQuestionPayload uses merged ids after duplicate text is collapsed", () => {
  const merged = mergeTranslationEntries([
    { id: "t0", text: "库存", node: createTextNode("库存") },
    { id: "t1", text: "库存", node: createTextNode("库存") },
    { id: "t2", text: "售出", node: createTextNode("售出") },
  ]);
  const payload = translationQuestionPayload(merged.mergedEntries, "en");

  assert.deepEqual(payload.items, [
    { id: "m0", text: "库存" },
    { id: "m1", text: "售出" },
  ]);
});

test("requestTranslationsInBatches yields each expanded batch as soon as it resolves", async () => {
  const entries = [
    { id: "t0", text: "库存", node: createTextNode("库存") },
    { id: "t1", text: "库存", node: createTextNode("库存") },
    { id: "t2", text: "售出", node: createTextNode("售出") },
  ];
  const yielded = [];
  const requestedBatches = [];

  const translations = await requestTranslationsInBatches(
    entries,
    async (batch) => {
      requestedBatches.push(batch.entries.map((entry) => entry.id));
      return batch.index === 1 ? [{ id: "m0", text: "Stock" }] : [{ id: "m1", text: "Sold" }];
    },
    (batchTranslations) => yielded.push(batchTranslations),
    { maxItems: 1, maxChars: 100 },
  );

  assert.deepEqual(requestedBatches, [["m0"], ["m1"]]);
  assert.deepEqual(yielded, [
    [
      { id: "t0", text: "Stock" },
      { id: "t1", text: "Stock" },
    ],
    [{ id: "t2", text: "Sold" }],
  ]);
  assert.deepEqual(translations, [
    { id: "t0", text: "Stock" },
    { id: "t1", text: "Stock" },
    { id: "t2", text: "Sold" },
  ]);
});

test("parseTranslationContent accepts only translation arrays", () => {
  assert.deepEqual(parseTranslationContent('[{"id":"t0","text":"Inventory"}]'), [{ id: "t0", text: "Inventory" }]);
  assert.throws(() => parseTranslationContent("数据不足：当前系统尚未配置可用的 AI 模型客户端。"));
  assert.throws(() => parseTranslationContent('{"id":"t0","text":"Inventory"}'));
});

test("parseTranslationContent accepts wrapped translation responses", () => {
  assert.deepEqual(
    parseTranslationContent('{"translations":[{"id":"t0","text":"Inventory"}]}'),
    [{ id: "t0", text: "Inventory" }],
  );
});

test("parseTranslationContent adds diagnostics when JSON is invalid", () => {
  const invalidJson = '[{"id":"t0","text":"Inventory},{"id":"t1","text":"Stock"}]';

  assert.throws(
    () => parseTranslationContent(invalidJson, { batchIndex: 2, batchCount: 3 }),
    (error) => {
      assert.equal(error.name, "TranslationJsonParseError");
      assert.equal(error.message, "Translation response is not valid JSON");
      assert.equal(error.details.batchIndex, 2);
      assert.equal(error.details.batchCount, 3);
      assert.equal(error.details.contentLength, invalidJson.length);
      assert.match(error.details.parseMessage, /JSON/);
      assert.ok(error.details.contentExcerpt.includes("Inventory"));
      return true;
    },
  );
});

test("buildTranslationBatches splits large pages by item count and text length", () => {
  const entries = [
    { id: "t0", text: "库存报表" },
    { id: "t1", text: "总库存".repeat(5) },
    { id: "t2", text: "售出" },
    { id: "t3", text: "FBS" },
  ];

  assert.deepEqual(
    buildTranslationBatches(entries, { maxItems: 2, maxChars: 12 }).map((batch) => ({
      index: batch.index,
      entries: batch.entries.map((entry) => entry.id),
    })),
    [
      { index: 1, entries: ["t0"] },
      { index: 2, entries: ["t1"] },
      { index: 3, entries: ["t2", "t3"] },
    ],
  );
});

test("translationQuestionPayload asks AI to omit items that do not need translation", () => {
  const payload = translationQuestionPayload(
    [{ id: "t0", text: "SKU" }],
    "zh",
    { index: 1, count: 2 },
  );

  assert.equal(payload.target_locale, "zh");
  assert.deepEqual(payload.batch, { index: 1, count: 2 });
  assert.deepEqual(payload.items, [{ id: "t0", text: "SKU" }]);
  assert.match(payload.instruction, /Only return items that need translated text/);
  assert.match(payload.instruction, /Omit items/);
});

test("summarizeTranslationResult treats omitted entries as skipped translations", () => {
  const entries = [
    { id: "t0", text: "库存报表", node: createTextNode("库存报表") },
    { id: "t1", text: "总库存", node: createTextNode("总库存") },
    { id: "t2", text: "售出", node: createTextNode("售出") },
  ];

  assert.deepEqual(
    summarizeTranslationResult(entries, [
      { id: "t0", text: "Inventory report" },
      { id: "t1", text: "总库存" },
      { id: "ghost", text: "Unknown row" },
    ]),
    {
      total: 3,
      returned: 3,
      applied: 1,
      unchanged: 1,
      skipped: 1,
      unknown: 1,
    },
  );
});

test("summarizeTranslationResult treats blank returned text as skipped", () => {
  const entries = [{ id: "t0", text: "库存报表", node: createTextNode("库存报表") }];

  assert.deepEqual(summarizeTranslationResult(entries, [{ id: "t0", text: "   " }]), {
    total: 1,
    returned: 1,
    applied: 0,
    unchanged: 0,
    skipped: 1,
    unknown: 0,
  });
});

test("translationStateLabel maps AI translation state to visible summary text", () => {
  const labels = {
    idleLabel: "未翻译",
    loadingLabel: "翻译中",
    doneLabel: "已翻译",
    errorLabel: "翻译失败",
    jsonErrorLabel: "翻译结果格式异常",
    noChangeLabel: "翻译无变化",
  };

  assert.equal(translationStateLabel(labels, "idle"), "未翻译");
  assert.equal(translationStateLabel(labels, "loading"), "翻译中");
  assert.equal(translationStateLabel(labels, "done"), "已翻译");
  assert.equal(translationStateLabel(labels, "error"), "翻译失败");
  assert.equal(translationStateLabel(labels, "jsonError"), "翻译结果格式异常");
  assert.equal(translationStateLabel(labels, "noChange"), "翻译无变化");
  assert.equal(translationStateLabel(labels, "unknown"), "");
});
