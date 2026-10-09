require "set"

module WeeklyProfitReports
  class AccessScope
    def initialize(user)
      @user = user
    end

    def restricted?
      !super_admin?
    end

    def super_admin?
      @super_admin ||= @user&.has_role?(:super_admin) == true
    end

    def visible_skus
      return Ec::Sku.all unless restricted?

      developer_codes = Ec::SkuDeveloperAssignment.where(user_id: @user.id).select(:sku_code)
      operator_codes = Ec::SkuOperatorAssignment.where(user_id: @user.id).select(:sku_code)
      Ec::Sku.where(sku_code: developer_codes).or(Ec::Sku.where(sku_code: operator_codes)).distinct
    end

    def visible_sku_codes
      @visible_sku_codes ||= visible_skus.pluck(:sku_code)
    end

    def visible_master_skus
      return Ec::MasterSku.includes(:skus).order(:master_sku_code) unless restricted?

      Ec::MasterSku
        .where(id: visible_skus.where.not(master_sku_id: nil).select(:master_sku_id).distinct)
        .preload(:skus)
        .order(:master_sku_code)
    end

    def visible_orphan_skus
      visible_skus.where(master_sku_id: nil).order(:sku_code)
    end

    def filter_sku_codes(codes)
      requested = Array(codes).map { |code| code.to_s.strip.upcase }.reject(&:blank?).uniq
      return requested unless restricted?

      intersect_sku_codes(requested)
    end

    def intersect_sku_codes(codes)
      requested = Array(codes).map { |code| code.to_s.strip.upcase }.reject(&:blank?).uniq
      return requested unless restricted?

      visible_sku_code_set = visible_sku_codes.to_set
      requested.select { |code| visible_sku_code_set.include?(code) }
    end

    def filter_master_sku_ids(ids)
      requested = Array(ids).map { |id| Integer(id, exception: false) }.compact.uniq
      return requested unless restricted?
      return [] if requested.empty?

      visible_master_skus.where(id: requested).pluck(:id)
    end
  end
end
