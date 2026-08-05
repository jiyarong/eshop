import { Controller } from "@hotwired/stimulus";
import { parse } from "yaml";

const HTTPS_PROTOCOL = "https:";

export function releaseFromManifest(content, manifestUrl, preferredExtensions) {
  const manifest = parse(content);
  const files = Array.isArray(manifest?.files) ? manifest.files : [];
  const file = preferredExtensions
    .map((extension) => files.find(({ url }) => String(url || "").toLowerCase().endsWith(extension)))
    .find(Boolean);
  const path = file?.url || manifest?.path;

  if (!manifest?.version || !path) throw new Error("Invalid YClaw release manifest");

  const url = new URL(path, manifestUrl);
  if (url.protocol !== HTTPS_PROTOCOL) throw new Error("Invalid YClaw download URL");

  return { version: String(manifest.version), url: url.href };
}

export async function fetchRelease(fetcher, manifestUrl, preferredExtensions) {
  const response = await fetcher(manifestUrl, { cache: "no-store" });
  if (!response.ok) throw new Error(`YClaw manifest request failed: ${response.status}`);

  return releaseFromManifest(await response.text(), manifestUrl, preferredExtensions);
}

export default class extends Controller {
  static targets = ["status", "windowsLink", "windowsVersion", "macLink", "macVersion"];

  static values = {
    windowsManifestUrl: String,
    macManifestUrl: String,
    loadingLabel: String,
    errorLabel: String,
  };

  async load() {
    if (!this.element.open || this.loading || this.loaded) return;

    this.loading = true;
    this.showStatus(this.loadingLabelValue);
    this.element.setAttribute("aria-busy", "true");

    const results = await Promise.allSettled([
      fetchRelease(fetch, this.windowsManifestUrlValue, [".exe"]),
      fetchRelease(fetch, this.macManifestUrlValue, [".dmg", ".zip"]),
    ]);

    if (results[0].status === "fulfilled") this.renderRelease("windows", results[0].value);
    if (results[1].status === "fulfilled") this.renderRelease("mac", results[1].value);

    this.loaded = results.every(({ status }) => status === "fulfilled");
    this.loading = false;
    this.element.removeAttribute("aria-busy");

    if (this.loaded) {
      this.statusTarget.hidden = true;
    } else {
      this.showStatus(this.errorLabelValue);
    }
  }

  renderRelease(platform, release) {
    const link = platform === "windows" ? this.windowsLinkTarget : this.macLinkTarget;
    const version = platform === "windows" ? this.windowsVersionTarget : this.macVersionTarget;

    link.href = release.url;
    link.hidden = false;
    version.textContent = `v${release.version}`;
  }

  showStatus(message) {
    this.statusTarget.textContent = message;
    this.statusTarget.hidden = false;
  }
}
