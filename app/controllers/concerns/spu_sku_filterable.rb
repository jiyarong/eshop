module SpuSkuFilterable
  extend ActiveSupport::Concern

  private

  def load_spu_sku_filter
    @spu_sku_selected_master_sku_ids = spu_sku_filter_master_sku_ids
    @spu_sku_selected_sku_codes = spu_sku_filter_sku_codes
    @spu_sku_filter_master_skus = Ec::MasterSku.includes(:skus).order(:master_sku_code)
    @spu_sku_filter_orphan_skus = Ec::Sku.where(master_sku_id: nil).order(:sku_code)
  end

  def apply_spu_sku_filter_to_skus(scope)
    return scope unless spu_sku_filter_active?

    table = Ec::Sku.arel_table
    condition = nil
    if @spu_sku_selected_master_sku_ids.present?
      condition = table[:master_sku_id].in(@spu_sku_selected_master_sku_ids)
    end
    if @spu_sku_selected_sku_codes.present?
      sku_condition = table[:sku_code].in(@spu_sku_selected_sku_codes)
      condition = condition ? condition.or(sku_condition) : sku_condition
    end

    scope.where(condition)
  end

  def apply_spu_sku_filter_to_sku_records(scope)
    return scope unless spu_sku_filter_active?

    scope.where(sku_code: apply_spu_sku_filter_to_skus(Ec::Sku.all).select(:sku_code))
  end

  def spu_sku_filter_active?
    @spu_sku_selected_master_sku_ids.present? || @spu_sku_selected_sku_codes.present?
  end

  def spu_sku_filter_master_sku_ids
    ids = Array(params[:master_sku_ids].presence || params[:master_sku_id])
      .reject(&:blank?)
      .filter_map { |value| Integer(value, exception: false) }
      .uniq
    return [] if ids.blank?

    Ec::MasterSku.where(id: ids).pluck(:id)
  end

  def spu_sku_filter_sku_codes
    sku_codes = Array(params[:sku_codes])
      .reject(&:blank?)
      .map { |value| value.to_s.strip.upcase }
      .reject(&:blank?)
      .uniq
    return [] if sku_codes.blank?

    Ec::Sku.where(sku_code: sku_codes).pluck(:sku_code)
  end
end
