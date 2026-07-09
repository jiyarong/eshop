module Erp
  class CategoriesController < BaseController
    def index
      categories = if params[:q].present?
        search_categories
      else
        Ec::Category
          .where(parent_id: params[:parent_id].presence)
          .includes(:parent)
          .order(Ec::Category.localized_name_order, :id)
      end

      render json: {
        categories: categories.map { |category| category_payload(category) }
      }
    end

    private

    def search_categories
      keyword = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.strip)}%"
      table_name = Ec::Category.quoted_table_name
      search_columns = %w[origin_name name_cn name_en name_ru].map do |column|
        "#{table_name}.#{Ec::Category.connection.quote_column_name(column)} ILIKE :keyword"
      end.join(" OR ")

      Ec::Category
        .includes(:parent)
        .where(search_columns, keyword: keyword)
        .order(Ec::Category.localized_name_order, :id)
        .limit(80)
    end

    def category_payload(category)
      {
        id: category.id,
        parent_id: category.parent_id,
        name: category.localized_name,
        parent_name: category.parent&.localized_name,
        source: category.source,
        source_type: category.source_type,
        source_id: category.source_id
      }
    end
  end
end
