class Role < ApplicationRecord
  DEFINITIONS = {
    "super_admin" => {
      name: "超级管理员",
      description: "系统配置、账号管理、全部数据权限",
      permissions: [:manage_users, :manage_feedback_tasks, :view_reports, :view_erp, :manage_skus, :manage_categories, :manage_purchases, :manage_inventory, :manage_finance]
    },
    "manager" => {
      name: "经营负责人",
      description: "查看全局经营结果，审核关键业务数据",
      permissions: [:manage_feedback_tasks, :view_reports, :view_erp, :manage_skus, :manage_categories, :manage_purchases, :manage_inventory, :manage_finance]
    },
    "sku_manager" => {
      name: "SKU / 商品管理员",
      description: "维护 SKU、类别、商品基础资料",
      permissions: [:view_reports, :view_erp, :manage_skus, :manage_categories]
    },
    "purchaser" => {
      name: "采购员",
      description: "维护供应商、采购单、SKU 批次",
      permissions: [:view_reports, :view_erp, :manage_purchases]
    },
    "warehouse_staff" => {
      name: "仓库 / 库存人员",
      description: "维护到货、库存、批次状态",
      permissions: [:view_reports, :view_erp, :manage_inventory]
    },
    "finance" => {
      name: "财务",
      description: "维护付款、成本、费用分摊",
      permissions: [:view_reports, :view_erp, :manage_finance]
    },
    "operator" => {
      name: "运营",
      description: "查看平台店铺经营报表",
      permissions: [:view_reports, :view_erp]
    },
    "auditor" => {
      name: "只读 / 审计",
      description: "查看数据，不修改数据",
      permissions: [:view_reports, :view_erp]
    }
  }.freeze

  has_many :user_roles, dependent: :destroy
  has_many :users, through: :user_roles

  validates :code, presence: true, uniqueness: true
  validates :name, presence: true

  def self.seed_defaults!
    DEFINITIONS.each_with_index do |(code, definition), index|
      role = find_or_initialize_by(code: code)
      role.update!(
        name: definition.fetch(:name),
        description: definition.fetch(:description),
        position: index
      )
    end
  end

  def permissions
    DEFINITIONS.fetch(code).fetch(:permissions)
  end

  def allows?(permission)
    permissions.include?(permission.to_sym)
  end
end
