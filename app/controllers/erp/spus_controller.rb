module Erp
  class SpusController < BaseController
    include ResponsibleUserFilterable

    SPU_PAGE_SIZE = 10

    def index
      @category_options = master_sku_category_options
      @q = params[:q].to_s.strip
      @status = params[:status].presence_in(%w[active inactive all]) || "all"
      @category_ids = selected_category_ids
      load_responsible_user_filters

      scope = Ec::MasterSku.includes(
        { ec_category: :parent },
        skus: [
          :sku_category,
          :batches,
          :current_marketing_state,
          :developers,
          { sku_products: :operators }
        ]
      ).order(:master_sku_code)
      scope = scope.where(is_active: true) if @status == "active"
      scope = scope.where(is_active: false) if @status == "inactive"
      scope = scope.where(ec_category_id: @category_ids) if @category_ids.any?
      scope = apply_responsible_user_filters_to_master_skus(scope)
      if @q.present?
        keyword = "%#{ActiveRecord::Base.sanitize_sql_like(@q)}%"
        scope = scope.left_joins(:skus).where(
          "ec_master_skus.master_sku_code ILIKE :keyword OR ec_master_skus.product_name ILIKE :keyword OR ec_master_skus.product_name_ru ILIKE :keyword OR ec_skus.sku_code ILIKE :keyword OR ec_skus.product_name ILIKE :keyword OR ec_skus.product_name_ru ILIKE :keyword OR ec_skus.owner_name ILIKE :keyword",
          keyword: keyword
        ).distinct
      end

      orphan_scope = orphan_sku_scope
      @spu_rows = paginated_spu_rows(scope, orphan_scope)
      @master_skus = @spu_rows.filter_map { |row| row[:record] if row[:type] == :master_sku }
      @master_sku_entries = @master_skus.map do |master_sku|
        {
          master_sku: master_sku,
          skus: skus_for_display(master_sku.skus)
        }
      end
      @orphan_skus = @spu_rows.filter_map { |row| row[:record] if row[:type] == :orphan_sku }
      @product_counts = {
        master_total: Ec::MasterSku.count,
        sku_total: Ec::Sku.count,
        batch_total: Ec::SkuBatch.count,
        active_master_total: Ec::MasterSku.active.count
      }
    end

    private

    def orphan_sku_scope
      return Ec::Sku.none if @category_ids.any?

      scope = Ec::Sku.includes(:sku_category, :batches, :current_marketing_state, :developers, sku_products: :operators).where(master_sku_id: nil).order(:sku_code)
      scope = scope.where(is_active: true) if @status == "active"
      scope = scope.where(is_active: false) if @status == "inactive"
      scope = apply_responsible_user_filters_to_skus(scope)
      if @q.present?
        keyword = "%#{ActiveRecord::Base.sanitize_sql_like(@q)}%"
        scope = scope.where(
          "ec_skus.sku_code ILIKE :keyword OR ec_skus.product_name ILIKE :keyword OR ec_skus.product_name_ru ILIKE :keyword OR ec_skus.owner_name ILIKE :keyword",
          keyword: keyword
        )
      end
      scope
    end

    def paginated_spu_rows(master_scope, orphan_scope)
      master_count = relation_count(master_scope)
      orphan_count = relation_count(orphan_scope)
      total_count = master_count + orphan_count
      total_pages = [(total_count.to_f / SPU_PAGE_SIZE).ceil, 1].max
      current_page = [spu_page_param, total_pages].min
      offset = (current_page - 1) * SPU_PAGE_SIZE
      remaining = SPU_PAGE_SIZE
      rows = []

      if offset < master_count
        master_limit = [remaining, master_count - offset].min
        master_skus = master_scope.offset(offset).limit(master_limit).to_a
        rows.concat(master_skus.map { |master_sku| { type: :master_sku, record: master_sku } })
        remaining -= master_skus.size
        orphan_offset = 0
      else
        orphan_offset = offset - master_count
      end

      if remaining.positive?
        orphan_skus = orphan_scope.offset(orphan_offset).limit(remaining).to_a
        rows.concat(orphan_skus.map { |sku| { type: :orphan_sku, record: sku } })
      end

      Kaminari.paginate_array(rows, limit: SPU_PAGE_SIZE, offset: offset, total_count: total_count)
    end

    def relation_count(scope)
      scope.except(:order).count(:id)
    end

    def spu_page_param
      requested_page = params[:jump_page].presence || params[:page].presence
      current_page = params[:current_page].presence || params[:page].presence

      page = requested_page.to_i if requested_page.to_s.match?(/\A\d+\z/)
      page ||= current_page.to_i if current_page.to_s.match?(/\A\d+\z/)
      page = 1 if page.to_i <= 0
      page
    end

    def skus_for_display(skus)
      visible_skus = skus
      if responsible_user_filters_active?
        visible_skus = visible_skus.select { |sku| responsible_user_filtered_sku_codes.include?(sku.sku_code) }
      end

      visible_skus.sort_by(&:sku_code)
    end

    def selected_category_ids
      Array(params[:category_ids].presence || params[:category_id])
        .reject(&:blank?)
        .filter_map { |value| Integer(value, exception: false) }
        .uniq
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
end
