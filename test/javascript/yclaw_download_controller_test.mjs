import assert from "node:assert/strict";
import { test } from "node:test";

import { build } from "esbuild";

const bundle = await build({
  entryPoints: ["app/javascript/controllers/yclaw_download_controller.js"],
  bundle: true,
  format: "esm",
  platform: "browser",
  write: false,
});

const [{ fetchRelease, releaseFromManifest }] = await Promise.all(
  bundle.outputFiles.map((file) => import(`data:text/javascript;base64,${Buffer.from(file.text).toString("base64")}`)),
);

test("releaseFromManifest resolves the Windows installer URL", () => {
  const release = releaseFromManifest(
    `version: 2.2.9
files:
  - url: YClaw-2.2.9-win-x64.exe
path: YClaw-2.2.9-win-x64.exe`,
    "https://static.foresight-soft.com/eshop-ai/latest.yml",
    [".exe"],
  );

  assert.deepEqual(release, {
    version: "2.2.9",
    url: "https://static.foresight-soft.com/eshop-ai/YClaw-2.2.9-win-x64.exe",
  });
});

test("releaseFromManifest prefers the macOS dmg", () => {
  const release = releaseFromManifest(
    `version: 2.2.9
files:
  - url: YClaw-2.2.9-mac-arm64.zip
  - url: YClaw-2.2.9-mac-arm64.dmg
path: YClaw-2.2.9-mac-arm64.zip`,
    "https://static.foresight-soft.com/eshop-ai/latest-mac.yml",
    [".dmg", ".zip"],
  );

  assert.equal(release.url, "https://static.foresight-soft.com/eshop-ai/YClaw-2.2.9-mac-arm64.dmg");
});

test("fetchRelease bypasses the browser cache", async () => {
  const requests = [];
  const release = await fetchRelease(
    async (...args) => {
      requests.push(args);
      return {
        ok: true,
        text: async () => "version: 3.0.0\npath: YClaw-3.0.0.exe",
      };
    },
    "https://static.foresight-soft.com/eshop-ai/latest.yml",
    [".exe"],
  );

  assert.deepEqual(requests, [["https://static.foresight-soft.com/eshop-ai/latest.yml", { cache: "no-store" }]]);
  assert.equal(release.version, "3.0.0");
});

test("releaseFromManifest rejects non-HTTPS download URLs", () => {
  assert.throws(
    () => releaseFromManifest("version: 2.2.9\npath: http://example.com/YClaw.exe", "https://example.com/latest.yml", [".exe"]),
    /Invalid YClaw download URL/,
  );
});
