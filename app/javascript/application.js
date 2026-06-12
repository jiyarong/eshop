import "@hotwired/turbo-rails";
import { Application } from "@hotwired/stimulus";
import DatePickerController from "./controllers/date_picker_controller";
import FeedbackController from "./controllers/feedback_controller";
import ModalController from "./controllers/modal_controller";
import ProductTreeController from "./controllers/product_tree_controller";
import ShellController from "./controllers/shell_controller";

window.Stimulus = Application.start();
Stimulus.register("date-picker", DatePickerController);
Stimulus.register("feedback", FeedbackController);
Stimulus.register("modal", ModalController);
Stimulus.register("product-tree", ProductTreeController);
Stimulus.register("shell", ShellController);
