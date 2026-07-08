import { Controller } from "@hotwired/stimulus";

const MS_PER_DAY = 24 * 60 * 60 * 1000;

export function normalizeDate(dateLike) {
  if (dateLike instanceof Date) {
    return new Date(dateLike.getFullYear(), dateLike.getMonth(), dateLike.getDate());
  }

  if (typeof dateLike === "string" && /^\d{4}-\d{2}-\d{2}$/.test(dateLike)) {
    const [year, month, day] = dateLike.split("-").map(Number);
    return new Date(year, month - 1, day);
  }

  const parsed = new Date(dateLike);
  return new Date(parsed.getFullYear(), parsed.getMonth(), parsed.getDate());
}

export function normalizeDateValue(dateLike) {
  const normalized = normalizeDate(dateLike);
  const year = normalized.getFullYear();
  const month = String(normalized.getMonth() + 1).padStart(2, "0");
  const day = String(normalized.getDate()).padStart(2, "0");

  return `${year}-${month}-${day}`;
}

export function compareDates(left, right) {
  return normalizeDate(left).getTime() - normalizeDate(right).getTime();
}

export function addDays(dateLike, days) {
  const date = normalizeDate(dateLike);
  return new Date(date.getFullYear(), date.getMonth(), date.getDate() + days);
}

export function addMonths(dateLike, months) {
  const date = normalizeDate(dateLike);
  return new Date(date.getFullYear(), date.getMonth() + months, 1);
}

export function startOfMonth(dateLike) {
  const date = normalizeDate(dateLike);
  return new Date(date.getFullYear(), date.getMonth(), 1);
}

export function startOfWeek(dateLike) {
  const date = normalizeDate(dateLike);
  const day = date.getDay();
  const diff = day === 0 ? -6 : 1 - day;
  return addDays(date, diff);
}

export function endOfWeek(dateLike) {
  return addDays(startOfWeek(dateLike), 6);
}

export function buildApplyPayload({ draftStart, draftEnd }) {
  const sorted = compareDates(draftStart, draftEnd) <= 0
    ? { start: normalizeDate(draftStart), end: normalizeDate(draftEnd) }
    : { start: normalizeDate(draftEnd), end: normalizeDate(draftStart) };

  return {
    fromDate: normalizeDateValue(sorted.start),
    toDate: normalizeDateValue(sorted.end),
  };
}

export function resetDraftToCurrentWeek(todayValue = normalizeDateValue(new Date())) {
  const start = startOfWeek(todayValue);
  const end = endOfWeek(todayValue);

  return {
    fromDate: normalizeDateValue(start),
    toDate: normalizeDateValue(end),
    mode: "week",
    preset: "thisWeek",
  };
}

function buildLastWeekRange(todayValue) {
  const thisWeekStart = startOfWeek(todayValue);
  const start = addDays(thisWeekStart, -7);
  const end = addDays(start, 6);

  return {
    fromDate: normalizeDateValue(start),
    toDate: normalizeDateValue(end),
    mode: "week",
    preset: "lastWeek",
  };
}

function buildNaturalWeekBlockRange(todayValue, weeks, preset) {
  const thisWeekStart = startOfWeek(todayValue);
  const start = addDays(thisWeekStart, -((weeks - 1) * 7));
  const end = addDays(thisWeekStart, 6);

  return {
    fromDate: normalizeDateValue(start),
    toDate: normalizeDateValue(end),
    mode: "week",
    preset,
  };
}

export function buildThisMonthRange(todayValue = normalizeDateValue(new Date())) {
  const monthStart = startOfMonth(todayValue);
  const start = startOfWeek(monthStart);
  const end = addDays(start, 34);

  return {
    fromDate: normalizeDateValue(start),
    toDate: normalizeDateValue(end),
    mode: "week",
    preset: "thisMonth",
  };
}

export function resolvePreset({ fromDate, toDate, today = normalizeDateValue(new Date()) }) {
  if (!fromDate || !toDate) return null;

  const normalizedFrom = normalizeDateValue(fromDate);
  const normalizedTo = normalizeDateValue(toDate);

  const candidates = [
    resetDraftToCurrentWeek(today),
    buildLastWeekRange(today),
    buildNaturalWeekBlockRange(today, 2, "last2Weeks"),
    buildNaturalWeekBlockRange(today, 4, "last4Weeks"),
    buildThisMonthRange(today),
  ];

  const match = candidates.find((candidate) => candidate.fromDate === normalizedFrom && candidate.toDate === normalizedTo);
  return match?.preset || null;
}

export function isInsideComponentClick(event, element) {
  if (typeof event.composedPath === "function") {
    return event.composedPath().includes(element);
  }

  return element.contains(event.target);
}

export function calculatePopoverOffset({ popoverRect, viewportWidth, margin }) {
  const maxRight = viewportWidth - margin;
  let offset = 0;

  if (popoverRect.right > maxRight) {
    offset -= popoverRect.right - maxRight;
  }

  if (popoverRect.left + offset < margin) {
    offset += margin - (popoverRect.left + offset);
  }

  return offset;
}

export function hasCompleteDateRange(fromDate, toDate) {
  return Boolean(fromDate && toDate);
}

export function rangeSpanInDays({ fromDate, toDate }) {
  const payload = buildApplyPayload({ draftStart: fromDate, draftEnd: toDate });
  const span = compareDates(payload.toDate, payload.fromDate) / MS_PER_DAY;
  return span + 1;
}

export function shiftDateRangeBySpan({ fromDate, toDate, direction }) {
  const payload = buildApplyPayload({ draftStart: fromDate, draftEnd: toDate });
  const spanDays = rangeSpanInDays(payload);

  return {
    fromDate: normalizeDateValue(addDays(payload.fromDate, spanDays * direction)),
    toDate: normalizeDateValue(addDays(payload.toDate, spanDays * direction)),
  };
}

function cloneRange(range) {
  return {
    start: normalizeDate(range.start),
    end: normalizeDate(range.end),
    mode: range.mode,
    preset: range.preset || null,
  };
}

function isoWeekNumber(dateLike) {
  const date = normalizeDate(dateLike);
  const thursday = addDays(date, 4 - (date.getDay() || 7));
  const yearStart = new Date(thursday.getFullYear(), 0, 1);
  return Math.ceil((((thursday - yearStart) / MS_PER_DAY) + 1) / 7);
}

export function formatWeekIndexLabel(weekNumber) {
  return `W${weekNumber}`;
}

export function resolveSummaryTagLabel({ fromDate, toDate }) {
  if (!fromDate || !toDate) return null;

  const normalizedFrom = normalizeDateValue(fromDate);
  const normalizedTo = normalizeDateValue(toDate);

  if (normalizedFrom !== normalizeDateValue(startOfWeek(normalizedFrom))) return null;
  if (normalizedTo !== normalizeDateValue(endOfWeek(normalizedFrom))) return null;

  return formatWeekIndexLabel(isoWeekNumber(normalizedFrom));
}

function sameMonth(left, right) {
  return left.getFullYear() === right.getFullYear() && left.getMonth() === right.getMonth();
}

function sameDay(left, right) {
  return compareDates(left, right) === 0;
}

function withinRange(date, rangeStart, rangeEnd) {
  const time = normalizeDate(date).getTime();
  return time >= normalizeDate(rangeStart).getTime() && time <= normalizeDate(rangeEnd).getTime();
}

function parseRange(fromDate, toDate, today) {
  const fallback = resetDraftToCurrentWeek(today);
  const startValue = fromDate || fallback.fromDate;
  const endValue = toDate || fallback.toDate;
  const payload = buildApplyPayload({ draftStart: startValue, draftEnd: endValue });

  return {
    start: normalizeDate(payload.fromDate),
    end: normalizeDate(payload.toDate),
    mode: null,
    preset: resolvePreset({ fromDate: payload.fromDate, toDate: payload.toDate, today }),
  };
}

function rangeFromPreset(preset, today) {
  switch (preset) {
    case "thisWeek":
      return resetDraftToCurrentWeek(today);
    case "lastWeek":
      return buildLastWeekRange(today);
    case "last2Weeks":
      return buildNaturalWeekBlockRange(today, 2, "last2Weeks");
    case "last4Weeks":
      return buildNaturalWeekBlockRange(today, 4, "last4Weeks");
    case "thisMonth":
      return buildThisMonthRange(today);
    default:
      return resetDraftToCurrentWeek(today);
  }
}

export default class extends Controller {
  static targets = [
    "fromInput",
    "monthsGrid",
    "popover",
    "preset",
    "shiftControl",
    "summaryDates",
    "summaryTag",
    "toInput",
    "trigger",
    "visibleRange",
    "weekJump",
  ];

  static values = {
    locale: { type: String, default: "zh" },
    placeholder: { type: String, default: "" },
    rangeSeparator: { type: String, default: "至" },
    submitOnApply: { type: Boolean, default: false },
    today: String,
  };

  connect() {
    this.boundDocumentClick = this.handleDocumentClick.bind(this);
    this.boundDocumentKeydown = this.handleDocumentKeydown.bind(this);
    this.boundWindowResize = this.handleWindowResize.bind(this);

    document.addEventListener("click", this.boundDocumentClick);
    document.addEventListener("keydown", this.boundDocumentKeydown);
    window.addEventListener("resize", this.boundWindowResize);

    this.today = normalizeDate(this.todayValue || new Date());
    this.hasAppliedRange = hasCompleteDateRange(this.fromInputTarget.value, this.toInputTarget.value);
    this.appliedRange = parseRange(this.fromInputTarget.value, this.toInputTarget.value, normalizeDateValue(this.today));
    this.draftRange = cloneRange(this.appliedRange);
    this.pendingAnchor = null;
    this.isOpen = false;
    this.visibleMonth = startOfMonth(this.appliedRange.end);

    this.render();
  }

  disconnect() {
    document.removeEventListener("click", this.boundDocumentClick);
    document.removeEventListener("keydown", this.boundDocumentKeydown);
    window.removeEventListener("resize", this.boundWindowResize);
  }

  toggle(event) {
    event.preventDefault();

    if (this.isOpen) {
      this.close();
    } else {
      this.open();
    }
  }

  open() {
    this.draftRange = cloneRange(this.appliedRange);
    this.pendingAnchor = null;
    this.visibleMonth = startOfMonth(this.draftRange.end);
    this.isOpen = true;
    this.popoverTarget.hidden = false;
    this.triggerTarget.setAttribute("aria-expanded", "true");
    this.renderPopover();
  }

  close({ restoreFocus = false } = {}) {
    this.isOpen = false;
    this.pendingAnchor = null;
    this.popoverTarget.hidden = true;
    this.triggerTarget.setAttribute("aria-expanded", "false");
    this.popoverTarget.style.transform = "";

    if (restoreFocus) {
      this.triggerTarget.focus();
    }
  }

  apply() {
    const payload = buildApplyPayload({
      draftStart: this.draftRange.start,
      draftEnd: this.draftRange.end,
    });

    this.fromInputTarget.value = payload.fromDate;
    this.toInputTarget.value = payload.toDate;
    this.appliedRange = {
      start: normalizeDate(payload.fromDate),
      end: normalizeDate(payload.toDate),
      mode: this.draftRange.mode,
      preset: resolvePreset({ ...payload, today: normalizeDateValue(this.today) }),
    };
    this.hasAppliedRange = true;
    this.renderTrigger();
    this.close();

    if (this.submitOnApplyValue) {
      this.element.closest("form")?.requestSubmit();
    }
  }

  reset() {
    this.applyPresetDescriptor(resetDraftToCurrentWeek(normalizeDateValue(this.today)));
    this.renderPopover();
  }

  selectPreset(event) {
    const { preset } = event.currentTarget.dataset;

    this.applyPresetDescriptor(rangeFromPreset(preset, normalizeDateValue(this.today)));
    this.renderPopover();
  }

  shiftWeek(event) {
    const direction = Number(event.currentTarget.dataset.direction || "0");

    if (direction === 0) {
      this.applyPresetDescriptor(resetDraftToCurrentWeek(normalizeDateValue(this.today)));
      this.renderPopover();
      return;
    }

    const start = addDays(startOfWeek(this.draftRange.start), direction * 7);
    const end = addDays(start, 6);

    this.setDraftRange({ start, end, mode: "week" });
    this.renderPopover();
  }

  previousMonth() {
    this.visibleMonth = addMonths(this.visibleMonth, -1);
    this.renderPopover();
  }

  nextMonth() {
    this.visibleMonth = addMonths(this.visibleMonth, 1);
    this.renderPopover();
  }

  selectDay(event) {
    const date = normalizeDate(event.currentTarget.dataset.date);

    if (this.pendingAnchor) {
      this.setDraftRange({ start: this.pendingAnchor, end: date, mode: "day-range" });
      this.pendingAnchor = null;
    } else {
      this.setDraftRange({ start: date, end: date, mode: "day-range" });
      this.pendingAnchor = date;
    }

    this.renderPopover();
  }

  selectWeek(event) {
    const start = normalizeDate(event.currentTarget.dataset.weekStart);
    const end = normalizeDate(event.currentTarget.dataset.weekEnd);

    this.pendingAnchor = null;
    this.setDraftRange({ start, end, mode: "week" });
    this.renderPopover();
  }

  shiftAppliedRange(event) {
    event.preventDefault();

    if (!this.hasAppliedRange) return;

    const direction = Number(event.currentTarget.dataset.direction || "0");
    if (direction === 0) return;

    const payload = shiftDateRangeBySpan({
      fromDate: normalizeDateValue(this.appliedRange.start),
      toDate: normalizeDateValue(this.appliedRange.end),
      direction,
    });

    this.fromInputTarget.value = payload.fromDate;
    this.toInputTarget.value = payload.toDate;
    this.appliedRange = {
      start: normalizeDate(payload.fromDate),
      end: normalizeDate(payload.toDate),
      mode: this.appliedRange.mode,
      preset: resolvePreset({ ...payload, today: normalizeDateValue(this.today) }),
    };
    this.draftRange = cloneRange(this.appliedRange);
    this.pendingAnchor = null;
    this.visibleMonth = startOfMonth(this.appliedRange.end);
    this.render();

    if (this.submitOnApplyValue) {
      this.element.closest("form")?.requestSubmit();
    }
  }

  render() {
    this.renderTrigger();
    if (this.isOpen) {
      this.renderPopover();
    }
  }

  renderTrigger() {
    this.renderShiftControls();

    if (!this.hasAppliedRange) {
      this.summaryTagTarget.textContent = "";
      this.summaryTagTarget.hidden = true;
      this.summaryDatesTarget.textContent = this.placeholderValue;
      this.triggerTarget.classList.add("is-placeholder");
      return;
    }

    const payload = buildApplyPayload({
      draftStart: this.appliedRange.start,
      draftEnd: this.appliedRange.end,
    });
    const summaryTagLabel = resolveSummaryTagLabel(payload);
    const summaryText = payload.fromDate === payload.toDate
      ? payload.fromDate
      : `${payload.fromDate} ${this.rangeSeparatorValue} ${payload.toDate}`;

    if (summaryTagLabel) {
      this.summaryTagTarget.textContent = summaryTagLabel;
      this.summaryTagTarget.hidden = false;
    } else {
      this.summaryTagTarget.textContent = "";
      this.summaryTagTarget.hidden = true;
    }

    this.summaryDatesTarget.textContent = summaryText;
    this.triggerTarget.classList.remove("is-placeholder");
  }

  renderShiftControls() {
    this.shiftControlTargets.forEach((control) => {
      control.disabled = !this.hasAppliedRange;
      control.setAttribute("aria-disabled", this.hasAppliedRange ? "false" : "true");
    });
  }

  renderPopover() {
    const secondMonth = addMonths(this.visibleMonth, 1);
    this.visibleRangeTarget.textContent = `${this.formatMonthLabel(this.visibleMonth)} - ${this.formatMonthLabel(secondMonth)}`;
    this.monthsGridTarget.innerHTML = `${this.renderMonthCard(this.visibleMonth)}${this.renderMonthCard(secondMonth)}`;
    this.renderPresetState();
    this.positionPopover();
  }

  renderPresetState() {
    const payload = buildApplyPayload({
      draftStart: this.draftRange.start,
      draftEnd: this.draftRange.end,
    });
    const activePreset = resolvePreset({ ...payload, today: normalizeDateValue(this.today) });

    this.presetTargets.forEach((button) => {
      const isActive = button.dataset.preset === activePreset;
      button.classList.toggle("is-active", isActive);
      button.setAttribute("aria-pressed", isActive ? "true" : "false");
    });

    this.weekJumpTargets.forEach((button) => {
      const isCurrent = button.dataset.direction === "0" && activePreset === "thisWeek";
      button.classList.toggle("is-active", isCurrent);
      if (isCurrent) {
        button.setAttribute("aria-current", "true");
      } else {
        button.removeAttribute("aria-current");
      }
    });
  }

  renderMonthCard(monthStart) {
    const gridStart = startOfWeek(monthStart);
    const monthEnd = addDays(addMonths(monthStart, 1), -1);
    const rows = [];
    let cursor = gridStart;

    while (cursor <= monthEnd || rows.length < 5 || (rows.length < 6 && sameMonth(cursor, monthStart))) {
      const weekStart = cursor;
      const weekEnd = addDays(weekStart, 6);
      rows.push(this.renderWeekRow(weekStart, weekEnd, monthStart));
      cursor = addDays(weekStart, 7);
      if (rows.length >= 6 && cursor > monthEnd) break;
    }

    return `
      <section class="time-range-month-card">
        <header class="time-range-month-name">${this.formatMonthLabel(monthStart)}</header>
        <div class="time-range-weekday-row" aria-hidden="true">
          <span class="time-range-week-index"></span>
          ${["mon", "tue", "wed", "thu", "fri", "sat", "sun"].map((day) => `<span>${this.weekdayLabel(day)}</span>`).join("")}
        </div>
        <div class="time-range-weeks-grid">
          ${rows.join("")}
        </div>
      </section>
    `;
  }

  renderWeekRow(weekStart, weekEnd, monthStart) {
    const days = Array.from({ length: 7 }, (_, index) => addDays(weekStart, index)).map((day) => this.renderDayButton(day, monthStart)).join("");

    return `
      <div class="time-range-week-row">
        <button
          class="time-range-week-index"
          type="button"
          data-action="time-range-selector#selectWeek"
          data-week-start="${normalizeDateValue(weekStart)}"
          data-week-end="${normalizeDateValue(weekEnd)}"
          aria-label="${this.weekLabel(weekStart)}">
          ${formatWeekIndexLabel(isoWeekNumber(weekStart))}
        </button>
        ${days}
      </div>
    `;
  }

  renderDayButton(day, monthStart) {
    const inRange = withinRange(day, this.draftRange.start, this.draftRange.end);
    const isStart = sameDay(day, this.draftRange.start);
    const isEnd = sameDay(day, this.draftRange.end);
    const isSingle = isStart && isEnd;
    const classes = [
      "time-range-day",
      inRange ? "is-in-range" : null,
      isStart ? "is-range-start" : null,
      isEnd ? "is-range-end" : null,
      isSingle ? "is-single" : null,
      sameDay(day, this.today) ? "is-today" : null,
      sameMonth(day, monthStart) ? null : "is-outside-month",
    ].filter(Boolean).join(" ");

    return `
      <button
        class="${classes}"
        type="button"
        data-action="time-range-selector#selectDay"
        data-date="${normalizeDateValue(day)}"
        aria-pressed="${inRange ? "true" : "false"}"
        aria-label="${normalizeDateValue(day)}">
        ${day.getDate()}
      </button>
    `;
  }

  setDraftRange({ start, end, mode }) {
    const payload = buildApplyPayload({ draftStart: start, draftEnd: end });

    this.draftRange = {
      start: normalizeDate(payload.fromDate),
      end: normalizeDate(payload.toDate),
      mode,
      preset: resolvePreset({ ...payload, today: normalizeDateValue(this.today) }),
    };
  }

  applyPresetDescriptor(descriptor) {
    this.pendingAnchor = null;
    this.draftRange = {
      start: normalizeDate(descriptor.fromDate),
      end: normalizeDate(descriptor.toDate),
      mode: descriptor.mode,
      preset: descriptor.preset,
    };
    this.visibleMonth = startOfMonth(this.draftRange.end);
  }

  formatMonthLabel(date) {
    if (this.localeValue.startsWith("zh")) {
      return `${date.getFullYear()}年${date.getMonth() + 1}月`;
    }

    return new Intl.DateTimeFormat(this.localeValue, {
      year: "numeric",
      month: "long",
    }).format(date);
  }

  weekdayLabel(dayKey) {
    return this.element.dataset[`weekday${dayKey.charAt(0).toUpperCase()}${dayKey.slice(1)}`];
  }

  weekLabel(weekStart) {
    return `${this.weekdayLabel("mon")} ${normalizeDateValue(weekStart)}`;
  }

  handleDocumentClick(event) {
    if (!this.isOpen) return;
    if (isInsideComponentClick(event, this.element)) return;

    this.close();
  }

  handleDocumentKeydown(event) {
    if (!this.isOpen) return;
    if (event.key !== "Escape") return;

    event.preventDefault();
    this.close({ restoreFocus: true });
  }

  handleWindowResize() {
    if (!this.isOpen) return;

    this.positionPopover();
  }

  positionPopover() {
    const margin = window.innerWidth <= 980 ? 20 : 28;
    const offset = calculatePopoverOffset({
      popoverRect: this.popoverTarget.getBoundingClientRect(),
      viewportWidth: window.innerWidth,
      margin,
    });

    this.popoverTarget.style.transform = offset === 0 ? "" : `translateX(${offset}px)`;
  }
}
