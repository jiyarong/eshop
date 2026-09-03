function cloneJson(value) {
  return JSON.parse(JSON.stringify(value));
}

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function eventTooltip(params) {
  const events = params?.data?.operationEvents || [];
  if (events.length === 0) return "";

  const date = escapeHtml(events[0].event_date);
  const rows = events.map((event) => {
    const source = escapeHtml(event.source_label || event.operator_name);
    const details = (event.diff_summary || []).map((item) => `<div>${escapeHtml(item)}</div>`).join("");
    return `<div class="echarts-operation-event"><strong>${escapeHtml(event.operation_type_label)}</strong><div>${escapeHtml(event.store_name)} · ${source}</div>${details}</div>`;
  }).join("<hr>");
  return `<div><strong>${date}</strong>${rows}</div>`;
}

function targetSeriesIndex(series, { seriesId, xAxisIndex }) {
  if (seriesId) return series.findIndex((item) => item.id === seriesId);
  return series.findIndex((item) => ["line", "bar"].includes(item.type) && Number(item.xAxisIndex || 0) === Number(xAxisIndex || 0));
}

export function applyOperationEventMarkLines(option, events, { seriesId = null, xAxisIndex = 0 } = {}) {
  if (!Array.isArray(events) || events.length === 0) return option;

  const enhanced = cloneJson(option);
  const series = Array.isArray(enhanced.series) ? enhanced.series : [];
  const index = targetSeriesIndex(series, { seriesId, xAxisIndex });
  if (index < 0) return enhanced;

  const grouped = events.reduce((result, event) => {
    if (!event?.event_date || !event?.operated_at) return result;
    (result[event.marker_x || event.event_date] ||= []).push(event);
    return result;
  }, {});
  const markerData = Object.keys(grouped).sort().map((eventDate) => {
    const dayEvents = grouped[eventDate].slice().sort((left, right) =>
      left.operated_at.localeCompare(right.operated_at) || Number(left.id) - Number(right.id)
    );
    return { xAxis: dayEvents[0].marker_x || dayEvents[0].operated_at, operationEvents: dayEvents };
  });
  if (markerData.length === 0) return enhanced;

  const existing = series[index].markLine || {};
  series[index].markLine = {
    ...existing,
    symbol: existing.symbol || ["none", "none"],
    silent: false,
    label: { show: false, ...(existing.label || {}) },
    lineStyle: { color: "#8b5e3c", type: "dashed", width: 1, ...(existing.lineStyle || {}) },
    tooltip: { formatter: eventTooltip, ...(existing.tooltip || {}) },
    data: [...(existing.data || []), ...markerData]
  };
  enhanced.series = series;
  return enhanced;
}
