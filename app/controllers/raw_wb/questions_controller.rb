module RawWb
  class QuestionsController < BaseController
    before_action :set_question,  only: [:show, :update, :destroy]

    def index
      @questions = RawWb::Question.all
      @questions = @questions.where(account_id: params[:account_id]) if params[:account_id].present?
      @questions = @questions.page(params[:page]).per(params[:per_page] || 20)
    end

    def show; end

    def create
      @question = RawWb::Question.new(question_params)
      @question.save!
      @message = 'Created successfully'
      render :show, status: :created
    end

    def update
      @question.update!(question_params)
      @message = 'Updated successfully'
      render :show
    end

    def destroy
      @question.destroy!
      @message = 'Deleted successfully'
      render json: { success: true, data: nil, message: @message }
    end

    private

    def set_question
      @question = RawWb::Question.find(params[:id])
    end

    def question_params
      params.require(:question).permit!
    end
  end
end
