import { Controller } from "@hotwired/stimulus";

const FORMAT_CHARACTERS = /[\p{Cf}]/gu;
const BOUNDARY_JUNK = /^[\s\p{Cf},;]+|[\s\p{Cf},;]+$/gu;

export default class extends Controller {
  connect() {
    this.normalize();
  }

  normalize() {
    const currentValue = this.element.value;
    const nextValue = this.normalizedValue(currentValue);

    if (currentValue !== nextValue) {
      this.element.value = nextValue;
    }
  }

  normalizedValue(value) {
    return value
      .normalize("NFKC")
      .replace(FORMAT_CHARACTERS, "")
      .replace(BOUNDARY_JUNK, "");
  }
}
