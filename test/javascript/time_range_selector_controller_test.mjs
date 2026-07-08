import assert from "node:assert/strict";
import { test } from "node:test";

import { build } from "esbuild";

const bundle = await build({
  entryPoints: ["app/javascript/controllers/time_range_selector_controller.js"],
  bundle: true,
  format: "esm",
  platform: "browser",
  write: false,
});

const [{ buildApplyPayload, buildThisMonthRange, calculatePopoverOffset, formatWeekIndexLabel, hasCompleteDateRange, isInsideComponentClick, normalizeDateValue, resetDraftToCurrentWeek, resolvePreset, resolveSummaryTagLabel }] = await Promise.all(
  bundle.outputFiles.map((file) => import(`data:text/javascript;base64,${Buffer.from(file.text).toString("base64")}`)),
);

test("normalizeDateValue formats local dates as yyyy-mm-dd", () => {
  assert.equal(normalizeDateValue(new Date(2026, 5, 8)), "2026-06-08");
});

test("resolvePreset matches this week from normalized applied dates", () => {
  assert.equal(
    resolvePreset({
      fromDate: "2026-07-06",
      toDate: "2026-07-12",
      today: "2026-07-08",
    }),
    "thisWeek",
  );
});

test("resolvePreset matches recent two weeks for the current and previous natural week", () => {
  assert.equal(
    resolvePreset({
      fromDate: "2026-06-29",
      toDate: "2026-07-12",
      today: "2026-07-08",
    }),
    "last2Weeks",
  );
});

test("resolvePreset matches recent one month for four natural weeks", () => {
  assert.equal(
    resolvePreset({
      fromDate: "2026-06-15",
      toDate: "2026-07-12",
      today: "2026-07-08",
    }),
    "last4Weeks",
  );
});

test("buildThisMonthRange starts from the month-start week monday and ends on the weekend four weeks later", () => {
  assert.deepEqual(buildThisMonthRange("2026-07-08"), {
    fromDate: "2026-06-29",
    toDate: "2026-08-02",
    mode: "week",
    preset: "thisMonth",
  });
});

test("resolvePreset matches the current month natural-week block", () => {
  assert.equal(
    resolvePreset({
      fromDate: "2026-06-29",
      toDate: "2026-08-02",
      today: "2026-07-08",
    }),
    "thisMonth",
  );
});

test("resolveSummaryTagLabel returns the week number for an exact natural week range", () => {
  assert.equal(
    resolveSummaryTagLabel({
      fromDate: "2026-07-06",
      toDate: "2026-07-12",
    }),
    "W28",
  );
});

test("resolveSummaryTagLabel stays empty for multi-week ranges", () => {
  assert.equal(
    resolveSummaryTagLabel({
      fromDate: "2026-06-29",
      toDate: "2026-07-12",
    }),
    null,
  );
});

test("hasCompleteDateRange requires both bounds", () => {
  assert.equal(hasCompleteDateRange("2026-06-01", "2026-06-08"), true);
  assert.equal(hasCompleteDateRange("", "2026-06-08"), false);
  assert.equal(hasCompleteDateRange("2026-06-01", ""), false);
});

test("buildApplyPayload writes normalized draft dates", () => {
  assert.deepEqual(
    buildApplyPayload({
      draftStart: new Date(2026, 5, 1),
      draftEnd: new Date(2026, 5, 8),
    }),
    { fromDate: "2026-06-01", toDate: "2026-06-08" },
  );
});

test("isInsideComponentClick uses composedPath so rerendered internal clicks are not treated as outside clicks", () => {
  const component = {
    contains() {
      return false;
    },
  };
  const detachedButton = {};
  const event = {
    target: detachedButton,
    composedPath() {
      return [detachedButton, component, {}];
    },
  };

  assert.equal(isInsideComponentClick(event, component), true);
});

test("calculatePopoverOffset shifts left when the popover overflows the right viewport edge", () => {
  assert.equal(
    calculatePopoverOffset({
      popoverRect: { left: 900, right: 1600 },
      viewportWidth: 1280,
      margin: 28,
    }),
    -348,
  );
});

test("calculatePopoverOffset shifts right when the popover overflows the left viewport edge", () => {
  assert.equal(
    calculatePopoverOffset({
      popoverRect: { left: 8, right: 708 },
      viewportWidth: 1280,
      margin: 28,
    }),
    20,
  );
});

test("formatWeekIndexLabel prefixes the week number with W", () => {
  assert.equal(formatWeekIndexLabel(27), "W27");
});

test("resetDraftToCurrentWeek returns monday through sunday for the provided today value", () => {
  assert.deepEqual(resetDraftToCurrentWeek("2026-07-08"), {
    fromDate: "2026-07-06",
    toDate: "2026-07-12",
    mode: "week",
    preset: "thisWeek",
  });
});
