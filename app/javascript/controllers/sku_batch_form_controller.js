import { Controller } from "@hotwired/stimulus";

export function syncDefectOffsetNoteVisibility({ batchType, noteField }) {
  noteField.hidden = batchType === "normal";
}

export default class extends Controller {
  static targets = ["batchType", "defectOffsetNote"];

  connect() {
    this.syncDefectOffsetNote();
  }

  syncDefectOffsetNote() {
    syncDefectOffsetNoteVisibility({
      batchType: this.batchTypeTarget.value,
      noteField: this.defectOffsetNoteTarget,
    });
  }
}
