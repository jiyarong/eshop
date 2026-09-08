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

const [{ findToolExchangePairs, mergeToolExchanges }] = await Promise.all(
  bundle.outputFiles.map((file) => import(`data:text/javascript;base64,${Buffer.from(file.text).toString("base64")}`)),
);

const message = (attributes = {}) => ({ dataset: attributes });

test("pairs tool requests and responses by tool call id", () => {
  const firstRequest = message({ toolRequest: "true", toolCallId: "call_1" });
  const secondRequest = message({ toolRequest: "true", toolCallId: "call_2" });
  const secondResponse = message({ toolResponse: "true", toolCallId: "call_2" });
  const firstResponse = message({ toolResponse: "true", toolCallId: "call_1" });

  assert.deepEqual(
    findToolExchangePairs([firstRequest, secondRequest, secondResponse, firstResponse]),
    [[secondRequest, secondResponse], [firstRequest, firstResponse]],
  );
});

test("pairs reused tool call ids with the next unmatched request", () => {
  const firstRequest = message({ toolRequest: "true", toolCallId: "call_1" });
  const firstResponse = message({ toolResponse: "true", toolCallId: "call_1" });
  const secondRequest = message({ toolRequest: "true", toolCallId: "call_1" });
  const secondResponse = message({ toolResponse: "true", toolCallId: "call_1" });

  assert.deepEqual(
    findToolExchangePairs([firstRequest, firstResponse, secondRequest, secondResponse]),
    [[firstRequest, firstResponse], [secondRequest, secondResponse]],
  );
});

test("does not merge unanswered, standalone, or unkeyed tool messages", () => {
  assert.deepEqual(
    findToolExchangePairs([
      message({ toolResponse: "true", toolCallId: "call_1" }),
      message({ toolRequest: "true", toolCallId: "call_2" }),
      message({ toolRequest: "true" }),
      message({ toolResponse: "true" }),
    ]),
    [],
  );
});

test("merges a matched pair once and keeps later reconciliations stable", () => {
  const container = {
    children: [],
    remove(element) {
      const index = this.children.indexOf(element);
      if (index >= 0) this.children.splice(index, 1);
    },
  };
  const request = message({ toolRequest: "true", toolCallId: "call_1" });
  const response = message({ toolResponse: "true", toolCallId: "call_1" });
  request.before = (element) => {
    container.children.splice(container.children.indexOf(request), 0, element);
    element.parent = container;
  };
  container.children.push(request, response);
  request.parent = container;
  response.parent = container;

  const createElement = () => ({
    children: [],
    dataset: {},
    setAttribute(name, value) { this[name] = value; },
    append(...elements) {
      elements.forEach((element) => {
        element.parent.remove(element);
        this.children.push(element);
        element.parent = this;
      });
    },
    remove(element) {
      this.children.splice(this.children.indexOf(element), 1);
    },
  });

  mergeToolExchanges(container, "Tool call record", createElement);
  const groupedExchange = container.children[0];
  mergeToolExchanges(container, "Tool call record", createElement);

  assert.equal(container.children.length, 1);
  assert.equal(container.children[0], groupedExchange);
  assert.deepEqual(groupedExchange.children, [request, response]);
  assert.equal(groupedExchange.dataset.toolCallId, "call_1");
});
