module Admin
  class Sub2UsagesController < BaseController
    def show
      @start_date = parse_user_date(params[:start_date]) || user_today - 6.days
      @end_date = parse_user_date(params[:end_date]) || user_today

      if @start_date > @end_date
        @error = t("admin.sub2_usage.errors.invalid_date_range")
      else
        result = Sub2UsageDashboard.call(start_date: @start_date, end_date: @end_date)
        @stats = result.stats
        @user_rows = result.user_rows
      end

      render "admin/sub2_usage/show"
    rescue Sub2AIService::Error => error
      Rails.logger.error("Sub2 usage dashboard failed: #{error.message}")
      @error = t("admin.sub2_usage.errors.unavailable")
      render "admin/sub2_usage/show"
    end
  end
end
