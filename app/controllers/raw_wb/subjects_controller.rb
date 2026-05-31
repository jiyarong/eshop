module RawWb
  class SubjectsController < BaseController
    before_action :set_subject,  only: [:show, :update, :destroy]

    def index
      @subjects = RawWb::Subject.all
      @subjects = @subjects.where(account_id: params[:account_id]) if params[:account_id].present?
      @subjects = @subjects.page(params[:page]).per(params[:per_page] || 20)
    end

    def show; end

    def create
      @subject = RawWb::Subject.new(subject_params)
      @subject.save!
      @message = 'Created successfully'
      render :show, status: :created
    end

    def update
      @subject.update!(subject_params)
      @message = 'Updated successfully'
      render :show
    end

    def destroy
      @subject.destroy!
      @message = 'Deleted successfully'
      render json: { success: true, data: nil, message: @message }
    end

    private

    def set_subject
      @subject = RawWb::Subject.find(params[:id])
    end

    def subject_params
      params.require(:subject).permit!
    end
  end
end
