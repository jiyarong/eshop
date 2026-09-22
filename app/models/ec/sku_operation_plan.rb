module Ec
  class SkuOperationPlan < ApplicationRecord
    self.table_name = "ec_ai_sku_operation_plans"

    TARGET_ALIASES = {
      "价格" => "price",
      "广告" => "advertising",
      "listing属性" => "listing_attribute",
      "listing图" => "listing_image"
    }.freeze
    OPERATION_ALIASES = {
      "增加" => "increase",
      "打开" => "open",
      "关闭" => "close",
      "修改" => "modify",
      "维持" => "maintain"
    }.freeze

    belongs_to :sku, class_name: "Ec::Sku"

    enum :status, { active: "active", done: "done", ignored: "ignored" }, validate: true
    enum :target, {
      price: "price",
      advertising: "advertising",
      listing_attribute: "listing_attribute",
      listing_image: "listing_image"
    }, validate: true
    enum :operation, {
      increase: "increase",
      open: "open",
      close: "close",
      modify: "modify",
      maintain: "maintain"
    }, validate: true

    before_validation :set_retain_until, on: :create
    before_validation :set_completed_at
    before_validation :normalize_plan_values

    validates :message, :retain_until, presence: true
    validate :referer_must_be_event_types

    scope :retained, -> { where("retain_until > ?", Time.current) }

    private

    def set_retain_until
      self.retain_until ||= 48.hours.from_now
    end

    def normalize_plan_values
      self.target = TARGET_ALIASES.fetch(target.to_s, target) if target.present?
      self.operation = OPERATION_ALIASES.fetch(operation.to_s, operation) if operation.present?
    end

    def set_completed_at
      return unless will_save_change_to_status? && status.in?(%w[done ignored])

      self.completed_at ||= Time.current
    end

    def referer_must_be_event_types
      self.referer = Array(referer).filter_map { |event_type| event_type.to_s.strip.presence }.uniq
      errors.add(:referer, :blank) if referer.empty?
    end
  end
end
