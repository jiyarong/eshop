import { Controller } from "@hotwired/stimulus";

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
  static targets = ["chart", "data"];

  connect() {
    this.connected = true;
    loadEcharts().then(() => {
      if (!this.connected || !this.hasChartTarget || !this.hasDataTarget) return;
      this.chart = window.echarts.init(this.chartTarget);
      this.chart.setOption(JSON.parse(this.dataTarget.textContent));
      this.resizeObserver = new ResizeObserver(() => this.chart?.resize());
      this.resizeObserver.observe(this.chartTarget);
    });
  }

  disconnect() {
    this.connected = false;
    this.resizeObserver?.disconnect();
    this.chart?.dispose();
  }
}
