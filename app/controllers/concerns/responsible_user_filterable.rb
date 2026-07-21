require "set"

module ResponsibleUserFilterable
  extend ActiveSupport::Concern

  private

  def load_responsible_user_filters
    @operator_id = responsible_user_id_param(:operator_id)
    @developer_id = responsible_user_id_param(:developer_id)
    @operator_filter_options = responsible_user_options
    @developer_filter_options = responsible_user_options
  end

  def apply_responsible_user_filters_to_skus(scope)
    scope = scope.where(sku_code: developer_filter_sku_codes) if @developer_id.present?
    scope = scope.where(sku_code: operator_filter_sku_codes) if @operator_id.present?
    scope
  end

  def apply_responsible_user_filters_to_master_skus(scope)
    return scope unless responsible_user_filters_active?

    matching_skus = apply_responsible_user_filters_to_skus(Ec::Sku.where.not(master_sku_id: nil))
    scope.where(id: matching_skus.select(:master_sku_id))
  end

  def apply_responsible_user_filters_to_sku_records(scope)
    scope = scope.where(sku_code: developer_filter_sku_codes) if @developer_id.present?
    scope = scope.where(sku_code: operator_filter_sku_codes) if @operator_id.present?
    scope
  end

  def responsible_user_filters_active?
    @operator_id.present? || @developer_id.present?
  end

  def responsible_user_filtered_sku_codes
    @responsible_user_filtered_sku_codes ||= begin
      scope = apply_responsible_user_filters_to_skus(Ec::Sku.all)
      scope.pluck(:sku_code).to_set
    end
  end

  def responsible_user_id_param(name)
    user_id = Integer(params[name], exception: false)
    return unless user_id

    User.exists?(id: user_id) ? user_id : nil
  end

  def responsible_user_options
    User.order(:email)
  end

  def developer_filter_sku_codes
    Ec::SkuDeveloperAssignment.where(user_id: @developer_id).select(:sku_code)
  end

  def operator_filter_sku_codes
    Ec::SkuProduct
      .joins(:operator_role_assignments)
      .where(ec_sku_product_operators: {
        user_id: @operator_id,
        role: Ec::SkuProductOperator.roles.fetch("operator")
      })
      .select(:sku_code)
  end
end
