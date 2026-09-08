import assert from "node:assert/strict";
import { test } from "node:test";

import { build } from "esbuild";

const bundle = await build({
  entryPoints: ["app/javascript/controllers/conversation_thread_controller.js"],
  bundle: true,
  format: "esm",
  platform: "browser",
  write: false,
});

const [{ findToolExchangeRuns }] = await Promise.all(
  bundle.outputFiles.map((file) => import(`data:text/javascript;base64,${Buffer.from(file.text).toString("base64")}`)),
);

const message = (attributes = {}) => ({ dataset: attributes });

test("groups a tool request with all consecutive tool responses", () => {
  const request = message({ toolRequest: "true" });
  const firstResponse = message({ toolResponse: "true" });
  const secondResponse = message({ toolResponse: "true" });
  const answer = message();

  assert.deepEqual(
    findToolExchangeRuns([request, firstResponse, secondResponse, answer]),
    [[request, firstResponse, secondResponse]],
  );
});

test("does not merge an unanswered tool request or standalone tool response", () => {
  assert.deepEqual(
    findToolExchangeRuns([
      message({ toolResponse: "true" }),
      message({ toolRequest: "true" }),
      message(),
    ]),
    [],
  );
});
