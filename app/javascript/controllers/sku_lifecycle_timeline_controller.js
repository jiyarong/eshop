import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["timeline", "collapsed", "hiddenEvent"];

  expand() {
    const firstEvent = this.hiddenEventTargets[0];
    this.hiddenEventTargets.forEach((event) => { event.hidden = false; });
    this.collapsedTarget.hidden = true;

    if (!firstEvent) return;

    requestAnimationFrame(() => {
      this.timelineTarget.scrollTo({ left: Math.max(firstEvent.offsetLeft - 12, 0), behavior: "smooth" });
    });
  }
}
