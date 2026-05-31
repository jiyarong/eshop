module RawWb
  class SyncTasksController < BaseController
    before_action :set_sync_task,  only: [:show, :update, :destroy]

    def index
      @sync_tasks = RawWb::SyncTask.all
      @sync_tasks = @sync_tasks.where(account_id: params[:account_id]) if params[:account_id].present?
      @sync_tasks = @sync_tasks.page(params[:page]).per(params[:per_page] || 20)
    end

    def show; end

    def create
      @sync_task = RawWb::SyncTask.new(sync_task_params)
      @sync_task.save!
      @message = 'Created successfully'
      render :show, status: :created
    end

    def update
      @sync_task.update!(sync_task_params)
      @message = 'Updated successfully'
      render :show
    end

    def destroy
      @sync_task.destroy!
      @message = 'Deleted successfully'
      render json: { success: true, data: nil, message: @message }
    end

    private

    def set_sync_task
      @sync_task = RawWb::SyncTask.find(params[:id])
    end

    def sync_task_params
      params.require(:sync_task).permit!
    end
  end
end
