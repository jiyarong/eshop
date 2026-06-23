import { Controller } from "@hotwired/stimulus";

const SKIPPED_TAGS = new Set(["SCRIPT", "STYLE", "NOSCRIPT", "INPUT", "TEXTAREA", "SELECT", "OPTION"]);
const ELEMENT_NODE = 1;
const TEXT_NODE = 3;

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
    if (translatedText) entry.node.textContent = translatedText;
  });
}

export function restoreOriginalText(entries) {
  entries.forEach((entry) => {
    entry.node.textContent = entry.originalText ?? entry.text;
  });
}

export function parseTranslationContent(content) {
  const translations = JSON.parse(content);
  if (!Array.isArray(translations)) throw new Error("Translation content must be an array");

  translations.forEach((translation) => {
    if (typeof translation.id !== "string" || typeof translation.text !== "string") {
      throw new Error("Translation items must include string id and text");
    }
  });

  return translations;
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

  static targets = ["translateButton", "originalButton", "translationButton", "status"];

  connect() {
    this.entries = [];
    this.translations = [];
  }

  async translate() {
    this.entries = collectTextNodes(document.querySelector(".page"));
    if (this.entries.length === 0) return;

    this.setBusy(true);
    this.setStatus(this.translateButtonTarget.dataset.loadingLabel);

    try {
      const translations = await this.requestTranslations(this.entries);
      this.translations = translations;
      applyTranslations(this.entries, this.translations);
      this.setMode("translation");
      this.setStatus(this.translateButtonTarget.dataset.doneLabel);
    } catch (_error) {
      this.setStatus(this.translateButtonTarget.dataset.errorLabel);
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
        question: this.translationQuestion(entries),
      }),
    });

    if (!response.ok) throw new Error("Translation request failed");

    const payload = await response.json();
    return parseTranslationContent(payload.assistant_message.content);
  }

  translationQuestion(entries) {
    return JSON.stringify({
      instruction: "Translate each item.text to the current target locale. Return strict JSON only as an array of objects with the same id values and translated text values. Do not wrap the JSON in Markdown.",
      target_locale: this.targetLocaleValue,
      items: entries.map(({ id, text }) => ({ id, text })),
    });
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
}
