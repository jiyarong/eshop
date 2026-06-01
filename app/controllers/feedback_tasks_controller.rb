class FeedbackTasksController < ApplicationController
  before_action :authenticate_user!

  def create
    task = current_user.feedback_tasks.new(feedback_task_params)
    task.user_agent = request.user_agent

    if task.save
      render json: { success: true, id: task.id }, status: :created
    else
      render json: { success: false, errors: task.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def feedback_task_params
    params.require(:feedback_task).permit(
      :page_url,
      :page_title,
      :issue_type,
      :description,
      :suggestion,
      :selector,
      :element_text,
      :scroll_x,
      :scroll_y,
      :viewport_width,
      :viewport_height,
      element_rect: [:x, :y, :width, :height]
    )
  end
end
