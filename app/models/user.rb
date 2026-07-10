class User < ApplicationRecord
  DEFAULT_TIME_ZONE = "Asia/Shanghai"
  TIME_ZONE_OPTIONS = {
    DEFAULT_TIME_ZONE => "上海 (UTC+08:00)",
    "UTC" => "UTC (UTC+00:00)",
    "Europe/Moscow" => "莫斯科 (UTC+03:00)"
  }.freeze

  devise :database_authenticatable,
         :recoverable,
         :rememberable,
         :validatable,
         :trackable

  before_validation :set_default_time_zone

  has_many :user_roles, dependent: :destroy
  has_many :roles, through: :user_roles
  has_many :api_keys, class_name: "UserApiKey", dependent: :destroy
  has_one :sub2_user_api_key, dependent: :destroy
  has_many :access_tokens, class_name: "UserAccessToken", dependent: :destroy
  has_many :feedback_tasks, dependent: :destroy
  has_many :sku_product_operator_assignments,
    class_name: "Ec::SkuProductOperator",
    dependent: :destroy
  has_many :operated_sku_product_assignments,
    -> { where(role: Ec::SkuProductOperator.roles.fetch("operator")) },
    class_name: "Ec::SkuProductOperator"
  has_many :operated_sku_products,
    through: :operated_sku_product_assignments,
    source: :sku_product
  has_one_attached :avatar

  validates :active, inclusion: { in: [true, false] }
  validates :time_zone, inclusion: { in: TIME_ZONE_OPTIONS.keys, message: "不在可选范围内" }

  def self.time_zone_options
    TIME_ZONE_OPTIONS.map { |name, label| [label, name] }
  end

  def self.profile_time_zone(name)
    ActiveSupport::TimeZone[name.presence_in(TIME_ZONE_OPTIONS.keys) || DEFAULT_TIME_ZONE]
  end

  def display_name
    name.to_s.strip.presence || email
  end

  def active_for_authentication?
    super && active?
  end

  def inactive_message
    active? ? super : :inactive
  end

  def has_role?(role_code)
    roles.any? { |role| role.code == role_code.to_s }
  end

  def can?(permission)
    roles.any? { |role| role.allows?(permission) }
  end

  private

  def set_default_time_zone
    self.time_zone = DEFAULT_TIME_ZONE if time_zone.blank?
  end
end
