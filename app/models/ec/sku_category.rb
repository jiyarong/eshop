require "set"

module Ec
  class SkuCategory < ApplicationRecord
    include Ec::Auditable

    self.table_name = "ec_sku_categories"

    belongs_to :parent, class_name: "Ec::SkuCategory", optional: true
    has_many :children, class_name: "Ec::SkuCategory", foreign_key: :parent_id, dependent: :restrict_with_error

    validates :code, :name, presence: true
    validates :code, uniqueness: true
    validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validate :parent_is_not_self_or_descendant
    validate :parent_depth_within_limit

    before_validation { self.code = code&.strip&.upcase }

    scope :active, -> { where(is_active: true) }

    def depth(visited = Set.new)
      return 1 if visited.include?(id)

      visited.add(id)
      parent ? parent.depth(visited) + 1 : 1
    end

    private

    def parent_depth_within_limit
      return unless parent
      return if parent.depth < 3

      errors.add(:parent, "最多支持三级类目")
    end

    def parent_is_not_self_or_descendant
      return unless parent && id

      current = parent
      while current
        if current.id == id
          errors.add(:parent, "不能选择自己或子级类目")
          break
        end
        current = current.parent
      end
    end
  end
end
