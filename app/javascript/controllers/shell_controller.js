import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["sidebar", "toggle"];

  toggleSidebar() {
    this.element.classList.toggle("sidebar-collapsed");
    this.updateToggleState();
  }

  openSidebar() {
    this.sidebarTarget.classList.add("is-open");
  }

  closeSidebar() {
    this.sidebarTarget.classList.remove("is-open");
  }

  updateToggleState() {
    if (!this.hasToggleTarget) return;

    const collapsed = this.element.classList.contains("sidebar-collapsed");
    this.toggleTarget.setAttribute("aria-expanded", collapsed ? "false" : "true");
    this.toggleTarget.setAttribute("aria-label", collapsed ? "展开左侧菜单" : "折叠左侧菜单");

    const icon = this.toggleTarget.querySelector("i");
    if (icon) {
      icon.className = `bi ${collapsed ? "bi-layout-sidebar-inset" : "bi-layout-sidebar"}`;
    }
  }
}
