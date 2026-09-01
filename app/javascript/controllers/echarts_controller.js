import { Controller } from "@hotwired/stimulus";
import { applyOperationEventMarkLines } from "../lib/echarts_operation_event_markers";

const ECHARTS_URL = "https://cdn.jsdelivr.net/npm/echarts@5.6.0/dist/echarts.min.js";

function loadEcharts() {
  if (window.echarts) return Promise.resolve(window.echarts);
  if (window.echartsLoadingPromise) return window.echartsLoadingPromise;

  window.echartsLoadingPromise = new Promise((resolve, reject) => {
    const script = document.createElement("script");
    script.src = ECHARTS_URL;
    script.async = true;
    script.onload = () => resolve(window.echarts);
    script.onerror = reject;
    document.head.appendChild(script);
  });
  return window.echartsLoadingPromise;
}

export default class extends Controller {
  static targets = ["chart", "data", "events"];

  connect() {
    this.connected = true;
    loadEcharts().then(() => {
      if (!this.connected || !this.hasChartTarget || !this.hasDataTarget) return;
      try {
        const option = JSON.parse(this.dataTarget.textContent);
        const events = this.hasEventsTarget ? JSON.parse(this.eventsTarget.textContent) : [];
        this.chart = window.echarts.init(this.chartTarget);
        this.chart.setOption(applyOperationEventMarkLines(option, events));
      } catch (error) {
        console.error("Unable to initialize ECharts", error);
        return;
      }
      this.resizeObserver = new ResizeObserver(() => this.chart?.resize());
      this.resizeObserver.observe(this.chartTarget);
    }).catch((error) => console.error("Unable to load ECharts", error));
  }

  disconnect() {
    this.connected = false;
    this.resizeObserver?.disconnect();
    this.chart?.dispose();
  }
}
