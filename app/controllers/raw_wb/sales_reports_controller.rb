module RawWb
  class SalesReportsController < BaseController
    before_action :set_sales_report,  only: [:show, :update, :destroy]

    def index
      @sales_reports = RawWb::SalesReport.all
      @sales_reports = @sales_reports.where(account_id: params[:account_id]) if params[:account_id].present?
      @sales_reports = @sales_reports.page(params[:page]).per(params[:per_page] || 20)
    end

    def show; end

    def create
      @sales_report = RawWb::SalesReport.new(sales_report_params)
      @sales_report.save!
      @message = 'Created successfully'
      render :show, status: :created
    end

    def update
      @sales_report.update!(sales_report_params)
      @message = 'Updated successfully'
      render :show
    end

    def destroy
      @sales_report.destroy!
      @message = 'Deleted successfully'
      render json: { success: true, data: nil, message: @message }
    end

    private

    def set_sales_report
      @sales_report = RawWb::SalesReport.find(params[:id])
    end

    def sales_report_params
      params.require(:sales_report).permit!
    end
  end
end
