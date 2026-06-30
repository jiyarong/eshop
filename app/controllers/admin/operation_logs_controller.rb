module Admin
  class OperationLogsController < BaseController
    def index
      @user_id = params[:user_id].presence
      @record_type = params[:record_type].presence_in(audited_record_types)
      @from_date = parse_user_date(params[:from_date])
      @to_date = parse_user_date(params[:to_date])
      @users = User.where(id: Ec::OperationLog.select(:user_id)).order(:email)
      @record_type_options = audited_record_types
      @operation_logs = filtered_operation_logs
    end

    private

    def filtered_operation_logs
      scope = Ec::OperationLog.includes(:user).order(created_at: :desc, id: :desc)
      scope = scope.where(user_id: @user_id) if @user_id.present?
      scope = scope.where(record_type: @record_type) if @record_type.present?
      scope = scope.where("created_at >= ?", time_for_user_date(@from_date).beginning_of_day) if @from_date.present?
      scope = scope.where("created_at <= ?", time_for_user_date(@to_date).end_of_day) if @to_date.present?
      scope.limit(200)
    end

    def audited_record_types
      Ec::AuditConfig::ATTRIBUTES.keys.sort
    end
  end
end
