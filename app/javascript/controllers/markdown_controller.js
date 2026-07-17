import { Controller } from "@hotwired/stimulus";
import DOMPurify from "dompurify";
import { marked } from "marked";

export function renderMarkdown(source, sanitize = (html) => DOMPurify.sanitize(html)) {
  const html = marked.parse(source || "", {
    async: false,
    breaks: false,
    gfm: true,
  });

  return sanitize(html);
}

export default class extends Controller {
  static targets = ["source", "output"];

  connect() {
    try {
      this.outputTarget.innerHTML = renderMarkdown(this.sourceTarget.textContent);
      this.outputTarget.hidden = false;
      this.sourceTarget.hidden = true;
    } catch (_error) {
      this.outputTarget.hidden = true;
      this.sourceTarget.hidden = false;
    }
  }
}
