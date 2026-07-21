module MasterSkuCategoryFilterable
  extend ActiveSupport::Concern

  private

  def load_master_sku_category_filter
    @category_options = master_sku_category_options
    @category_ids = selected_master_sku_category_ids
  end

  def apply_master_sku_category_filter_to_skus(scope)
    return scope unless master_sku_category_filter_active?

    scope.joins(:master_sku).where(ec_master_skus: { ec_category_id: @category_ids })
  end

  def apply_master_sku_category_filter_to_master_skus(scope)
    return scope unless master_sku_category_filter_active?

    scope.where(ec_category_id: @category_ids)
  end

  def apply_master_sku_category_filter_to_sku_records(scope)
    return scope unless master_sku_category_filter_active?

    scope.joins(sku: :master_sku).where(ec_master_skus: { ec_category_id: @category_ids })
  end

  def master_sku_category_filter_active?
    @category_ids.present?
  end

  def selected_master_sku_category_ids
    ids = Array(params[:category_ids].presence || params[:category_id])
      .reject(&:blank?)
      .filter_map { |value| Integer(value, exception: false) }
      .uniq
    return [] if ids.blank?

    Ec::Category.where(id: ids).pluck(:id)
  end

  def master_sku_category_options
    category_ids = Ec::MasterSku.where.not(ec_category_id: nil).distinct.select(:ec_category_id)

    Ec::Category.where(id: category_ids).includes(:parent).to_a
      .map { |category| [master_sku_category_label(category), category.id] }
      .sort_by { |label, id| [label.downcase, id] }
  end

  def master_sku_category_label(category)
    [category.parent&.localized_name, category.localized_name].compact.join(" / ")
  end
end
