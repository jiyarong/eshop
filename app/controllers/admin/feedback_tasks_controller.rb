module Admin
  class FeedbackTasksController < ApplicationController
    before_action -> { require_permission!(:manage_feedback_tasks) }
    before_action :set_feedback_task, only: [:show, :update]

    def index
      @feedback_tasks = FeedbackTask.includes(:user).order(created_at: :desc)
    end

    def show
    end

    def update
      if @feedback_task.update(feedback_task_params)
        redirect_to admin_feedback_task_path(@feedback_task)
      else
        render :show, status: :unprocessable_entity
      end
    end

    private

    def set_feedback_task
      @feedback_task = FeedbackTask.includes(:user).find(params[:id])
    end

    def feedback_task_params
      params.require(:feedback_task).permit(:status, :assignee_note)
    end
  end
end
