module Mcp
  class VisibleSkuScope
    GLOBAL_ROLES = %w[super_admin manager].freeze

    def initialize(user)
      @user = user
    end

    def sku_products
      scope = Ec::SkuProduct.includes(:sku, :store).joins(:sku, :store)
      return scope if global_user?

      scope.joins(:operator_assignments).where(
        ec_sku_product_operators: {
          user_id: user.id,
          role: Ec::SkuProductOperator.roles.fetch("operator")
        }
      )
    end

    def sku_codes
      sku_products.distinct.pluck(:sku_code)
    end

    def sku_count
      sku_products.distinct.count(:sku_code)
    end

    def global_user?
      GLOBAL_ROLES.any? { |role| user.has_role?(role) }
    end

    private

    attr_reader :user
  end
end
