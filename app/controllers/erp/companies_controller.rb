module Erp
  class CompaniesController < BaseController
    def search
      scope = Ec::Company.active.order(:name)
      scope = scope.tagged(params[:tag]) if params[:tag].present?

      query = params[:q].to_s.strip
      if query.present?
        keyword = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
        scope = scope.where("name ILIKE ?", keyword)
      end

      render json: scope.limit(20).map { |company| { id: company.id, label: company.name } }
    end
  end
end
