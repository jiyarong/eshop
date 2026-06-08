import "@hotwired/turbo-rails";
import { Application } from "@hotwired/stimulus";
import FeedbackController from "./controllers/feedback_controller";
import ModalController from "./controllers/modal_controller";
import ShellController from "./controllers/shell_controller";

window.Stimulus = Application.start();
Stimulus.register("feedback", FeedbackController);
Stimulus.register("modal", ModalController);
Stimulus.register("shell", ShellController);
