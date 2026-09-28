module Mcp
  class VisibleSkuScope
    GLOBAL_ROLES = %w[super_admin manager].freeze

    def initialize(user)
      @user = user
    end

    def sku_products
      scope = Ec::SkuProduct.includes(:sku, :store).joins(:sku, :store)
      return scope if global_user?

      scope.where(sku_code: Ec::SkuOperatorAssignment.where(user_id: user.id).select(:sku_code))
    end

    def sku_codes
      skus.pluck(:sku_code)
    end

    def sku_count
      skus.count
    end

    def global_user?
      GLOBAL_ROLES.any? { |role| user.has_role?(role) }
    end

    private

    attr_reader :user

    def skus
      scope = Ec::Sku.all
      global_user? ? scope : scope.where(sku_code: Ec::SkuOperatorAssignment.where(user_id: user.id).select(:sku_code))
    end
  end
end
