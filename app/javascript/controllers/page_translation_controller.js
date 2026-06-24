import { Controller } from "@hotwired/stimulus";

const SKIPPED_TAGS = new Set(["SCRIPT", "STYLE", "NOSCRIPT", "INPUT", "TEXTAREA", "SELECT", "OPTION"]);
const ELEMENT_NODE = 1;
const TEXT_NODE = 3;
const MAX_BATCH_ITEMS = 80;
const MAX_BATCH_CHARS = 8_000;

export function collectTextNodes(root) {
  const entries = [];

  walkTextNodes(root, (node) => {
    const text = node.textContent.trim();
    if (!text) return;

    entries.push({
      id: `t${entries.length}`,
      text,
      originalText: node.textContent,
      node,
    });
  });

  return entries;
}

export function applyTranslations(entries, translations) {
  const translationsById = new Map(translations.map((translation) => [translation.id, translation.text]));

  entries.forEach((entry) => {
    const translatedText = translationsById.get(entry.id);
    if (presentTranslationText(translatedText)) entry.node.textContent = translatedText;
  });
}

export function mergeTranslationEntries(entries) {
  const mergedEntries = [];
  const mergedEntriesByText = new Map();
  const mergedEntriesById = new Map();

  entries.forEach((entry) => {
    let mergedEntry = mergedEntriesByText.get(entry.text);

    if (!mergedEntry) {
      mergedEntry = {
        id: `m${mergedEntries.length}`,
        text: entry.text,
        entryIds: [],
        entries: [],
      };
      mergedEntriesByText.set(entry.text, mergedEntry);
      mergedEntriesById.set(mergedEntry.id, mergedEntry);
      mergedEntries.push(mergedEntry);
    }

    mergedEntry.entryIds.push(entry.id);
    mergedEntry.entries.push(entry);
  });

  return { mergedEntries, mergedEntriesById };
}

export function expandMergedTranslations(merged, translations) {
  return translations.flatMap((translation) => {
    const mergedEntry = merged.mergedEntriesById.get(translation.id);
    if (!mergedEntry) return [translation];

    return mergedEntry.entryIds.map((id) => ({ id, text: translation.text }));
  });
}

export function restoreOriginalText(entries) {
  entries.forEach((entry) => {
    entry.node.textContent = entry.originalText ?? entry.text;
  });
}

export function parseTranslationContent(content, context = {}) {
  let parsedContent;

  try {
    parsedContent = JSON.parse(content);
  } catch (error) {
    throw translationJsonParseError(error, content, context);
  }

  const translations = Array.isArray(parsedContent) ? parsedContent : parsedContent?.translations;
  if (!Array.isArray(translations)) throw new Error("Translation content must be an array");

  translations.forEach((translation) => {
    if (typeof translation.id !== "string" || typeof translation.text !== "string") {
      throw new Error("Translation items must include string id and text");
    }
  });

  return translations;
}

export function buildTranslationBatches(entries, { maxItems = MAX_BATCH_ITEMS, maxChars = MAX_BATCH_CHARS } = {}) {
  const batches = [];
  let currentEntries = [];
  let currentChars = 0;

  entries.forEach((entry) => {
    const entryChars = entry.text.length;
    const shouldStartNextBatch =
      currentEntries.length > 0 && (currentEntries.length >= maxItems || currentChars + entryChars > maxChars);

    if (shouldStartNextBatch) {
      batches.push({ entries: currentEntries, index: batches.length + 1 });
      currentEntries = [];
      currentChars = 0;
    }

    currentEntries.push(entry);
    currentChars += entryChars;
  });

  if (currentEntries.length > 0) batches.push({ entries: currentEntries, index: batches.length + 1 });

  return batches.map((batch) => ({ ...batch, count: batches.length }));
}

export async function requestTranslationsInBatches(entries, requestBatch, onBatch = null, batchOptions = {}) {
  const merged = mergeTranslationEntries(entries);
  const batches = buildTranslationBatches(merged.mergedEntries, batchOptions);
  const translations = [];

  for (const batch of batches) {
    const batchTranslations = expandMergedTranslations(merged, await requestBatch(batch));
    translations.push(...batchTranslations);
    onBatch?.(batchTranslations, batch);
  }

  return translations;
}

export function summarizeTranslationResult(entries, translations) {
  const entryIds = new Set(entries.map((entry) => entry.id));
  const translationsById = new Map(translations.map((translation) => [translation.id, translation.text]));

  let applied = 0;
  let unchanged = 0;
  let skipped = 0;

  entries.forEach((entry) => {
    const translatedText = translationsById.get(entry.id);
    if (!presentTranslationText(translatedText)) {
      skipped += 1;
    } else if (translatedText.trim() === entry.text) {
      unchanged += 1;
    } else {
      applied += 1;
    }
  });

  return {
    total: entries.length,
    returned: translations.length,
    applied,
    unchanged,
    skipped,
    unknown: translations.filter((translation) => !entryIds.has(translation.id)).length,
  };
}

export function translationQuestionPayload(entries, targetLocale, batch = null) {
  return {
    instruction: "Translate item.text to the current target locale. Only return items that need translated text. Omit items that are already natural in the target locale, contain only numbers, SKU/order codes, dates, currency, punctuation, or other content that should remain unchanged. Return strict JSON only as an array of objects with id and text values. Do not wrap the JSON in Markdown.",
    target_locale: targetLocale,
    batch: batch ? { index: batch.index, count: batch.count } : undefined,
    items: entries.map(({ id, text }) => ({ id, text })),
  };
}

export function translationStateLabel(labels, state) {
  return labels?.[`${state}Label`] || "";
}

function presentTranslationText(text) {
  return typeof text === "string" && text.trim().length > 0;
}

function translationJsonParseError(error, content, context) {
  const wrappedError = new Error("Translation response is not valid JSON");
  wrappedError.name = "TranslationJsonParseError";
  wrappedError.cause = error;
  wrappedError.details = {
    ...context,
    parseMessage: error.message,
    contentLength: content.length,
    contentExcerpt: translationContentExcerpt(content, error.message),
  };

  return wrappedError;
}

function translationContentExcerpt(content, parseMessage) {
  const position = Number.parseInt(parseMessage.match(/position\s+(\d+)/)?.[1] || "", 10);
  const center = Number.isFinite(position) ? position : content.length;
  const start = Math.max(center - 160, 0);
  const end = Math.min(center + 160, content.length);

  return content.slice(start, end);
}

function walkTextNodes(node, visit) {
  if (!node) return;

  if (node.nodeType === TEXT_NODE) {
    visit(node);
    return;
  }

  if (!node.childNodes || shouldSkipElement(node)) return;

  Array.from(node.childNodes).forEach((childNode) => walkTextNodes(childNode, visit));
}

function shouldSkipElement(element) {
  return (
    element.nodeType !== ELEMENT_NODE ||
    SKIPPED_TAGS.has(element.tagName) ||
    element.hidden ||
    element.style?.display === "none" ||
    computedDisplay(element) === "none" ||
    Boolean(element.closest?.("[data-page-translation-ignore]"))
  );
}

function computedDisplay(element) {
  if (typeof window === "undefined" || typeof window.getComputedStyle !== "function") return null;

  return window.getComputedStyle(element).display;
}

export default class extends Controller {
  static values = {
    targetLocale: String,
  };

  static targets = ["translateButton", "originalButton", "translationButton", "status", "summary", "summaryStatus"];

  connect() {
    this.entries = [];
    this.translations = [];
    this.setState("idle");
  }

  async translate() {
    this.entries = collectTextNodes(document.querySelector(".page"));
    if (this.entries.length === 0) return;

    this.setBusy(true);
    this.setState("loading");
    this.setStatus(this.translateButtonTarget.dataset.loadingLabel);

    try {
      const translations = await this.requestTranslations(this.entries);
      const summary = summarizeTranslationResult(this.entries, translations);
      this.logTranslationSummary(summary, translations);

      if (summary.applied === 0) {
        this.translations = [];
        this.setMode("original");
        this.setState("noChange");
        this.setStatus(this.translateButtonTarget.dataset.noChangeLabel);
        return;
      }

      this.translations = translations;
      this.setMode("translation");
      this.setState("done");
      this.setStatus(this.translateButtonTarget.dataset.doneLabel);
    } catch (error) {
      this.logTranslationError(error);
      const state = error?.name === "TranslationJsonParseError" ? "jsonError" : "error";
      this.setState(state);
      this.setStatus(this.translateButtonTarget.dataset[`${state}Label`]);
    } finally {
      this.setBusy(false);
    }
  }

  showOriginal() {
    restoreOriginalText(this.entries);
    this.setMode("original");
  }

  showTranslation() {
    applyTranslations(this.entries, this.translations);
    this.setMode("translation");
  }

  async requestTranslations(entries) {
    return requestTranslationsInBatches(
      entries,
      (batch) => this.requestTranslationBatch(batch),
      (batchTranslations) => applyTranslations(entries, batchTranslations),
    );
  }

  async requestTranslationBatch(batch) {
    const response = await fetch("/ai/conversations.json", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content,
      },
      body: JSON.stringify({
        agent_code: "page_translation",
        module_name: "page_translation",
        business_object_type: "Page",
        business_object_id: window.location.pathname,
        question: this.translationQuestion(batch.entries, batch),
      }),
    });

    if (!response.ok) throw new Error("Translation request failed");

    const payload = await response.json();
    return parseTranslationContent(payload.assistant_message.content, {
      batchIndex: batch.index,
      batchCount: batch.count,
    });
  }

  translationQuestion(entries, batch = null) {
    return JSON.stringify(translationQuestionPayload(entries, this.targetLocaleValue, batch));
  }

  setBusy(isBusy) {
    this.translateButtonTarget.disabled = isBusy;
  }

  setMode(mode) {
    this.originalButtonTarget.disabled = mode === "original" || this.entries.length === 0;
    this.translationButtonTarget.disabled = mode === "translation" || this.translations.length === 0;
  }

  setStatus(text) {
    if (this.hasStatusTarget) this.statusTarget.textContent = text || "";
  }

  setState(state) {
    this.element.dataset.translationState = state;
    if (!this.hasSummaryStatusTarget) return;

    this.summaryStatusTarget.textContent = translationStateLabel(this.summaryStatusTarget.dataset, state);
  }

  logTranslationSummary(summary, translations) {
    if (typeof console === "undefined") return;

    const message = "[PageTranslation] Translation response summary";
    const detail = {
      ...summary,
      targetLocale: this.targetLocaleValue,
      path: window.location.pathname,
    };

    if (summary.applied === 0) {
      console.warn(message, detail, { translations });
    } else if (summary.unknown > 0) {
      console.warn(message, detail);
    } else {
      console.info(message, detail);
    }
  }

  logTranslationError(error) {
    if (typeof console === "undefined") return;

    console.error("[PageTranslation] Translation failed", {
      message: error?.message,
      details: error?.details,
      targetLocale: this.targetLocaleValue,
      path: window.location.pathname,
    });
  }
}
