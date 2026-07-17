import assert from "node:assert/strict";
import { test } from "node:test";

import { build } from "esbuild";

const bundle = await build({
  entryPoints: ["app/javascript/controllers/markdown_controller.js"],
  bundle: true,
  format: "esm",
  platform: "browser",
  write: false,
});

const [{ renderMarkdown }] = await Promise.all(
  bundle.outputFiles.map((file) => import(`data:text/javascript;base64,${Buffer.from(file.text).toString("base64")}`)),
);

test("renderMarkdown formats GFM headings lists code and tables", () => {
  const markdown = "# Title\n\n- Item\n\n```ruby\nputs :ok\n```\n\n| A | B |\n| - | - |\n| 1 | 2 |";
  const html = renderMarkdown(markdown, (value) => value);

  assert.match(html, /<h1>Title<\/h1>/);
  assert.match(html, /<li>Item<\/li>/);
  assert.match(html, /<code class="language-ruby">/);
  assert.match(html, /<table>/);
});

test("renderMarkdown sanitizes generated HTML", () => {
  let receivedHtml;
  const html = renderMarkdown("<script>alert('xss')</script>\n\nSafe", (value) => {
    receivedHtml = value;
    return "<p>sanitized</p>";
  });

  assert.match(receivedHtml, /<script>/);
  assert.equal(html, "<p>sanitized</p>");
});
