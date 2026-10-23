require "zlib"

module Ec
  class OwnWarehouseCostPeriod < ApplicationRecord
    include Ec::Auditable
    self.table_name = "ec_own_warehouse_cost_periods"
    belongs_to :creator, class_name: "User", foreign_key: :created_by_id, optional: true
    belongs_to :confirmer, class_name: "User", foreign_key: :confirmed_by_id, optional: true
    has_many :sku_cost_allocations, class_name: "Ec::OwnWarehouseSkuCostAllocation", dependent: :restrict_with_exception
    enum :status, { draft: "draft", confirmed: "confirmed", superseded: "superseded" }, validate: true
    scope :published, -> { where(status: %w[confirmed superseded]) }
    validates :own_warehouse_code, :effective_from, :total_operating_cost, presence: true
    validates :own_warehouse_code, uniqueness: { scope: :effective_from }
    validates :currency, inclusion: { in: ["CNY"] }
    validates :total_operating_cost, numericality: { greater_than_or_equal_to: 0 }
    validates :cost_basis_days, numericality: { only_integer: true, greater_than: 0 }
    validates :storage_ratio, :transport_ratio, :labor_ratio, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }
    validates :fbo_labor_weight, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }
    validate :valid_configuration
    before_update :prevent_published_changes
    before_destroy :prevent_published_changes

    def self.lock_warehouse!(warehouse_code)
      key = Zlib.crc32("own_warehouse_cost:#{warehouse_code}")
      connection.execute("SELECT pg_advisory_xact_lock(#{key})")
    end

    def active_on?(date)
      effective_from <= date && (effective_to.nil? || effective_to >= date)
    end

    def daily_cost_on(_date)
      total_operating_cost / cost_basis_days
    end

    def confirm!(actor:)
      self.class.transaction do
        self.class.lock_warehouse!(own_warehouse_code)
        lock!
        return self unless draft?
        raise Ec::OwnWarehouseCostAllocator::InvalidInput, :immutable_history if Ec::OwnWarehouseSkuCostAllocation.current.where(own_warehouse_code: own_warehouse_code).where("week_end >= ?", effective_from).exists?
        previous = self.class.published.where(own_warehouse_code: own_warehouse_code).order(effective_from: :desc).first
        if previous
          raise Ec::OwnWarehouseCostAllocator::InvalidInput, :overlap if previous.effective_from >= effective_from
          if previous.effective_to.nil? || previous.effective_to >= effective_from
            # Only lifecycle boundaries change; the calculation stores original full configuration evidence.
            previous.send(:supersede_at!, effective_from - 1)
          end
        end
        update!(status: "confirmed", confirmed_by_id: actor.id, confirmed_at: Time.current)
      end
      self
    end

    private

    def valid_configuration
      if [storage_ratio, transport_ratio, labor_ratio].all?(&:present?) && [storage_ratio, transport_ratio, labor_ratio].sum != 1.to_d
        errors.add(:base, I18n.t("own_warehouse.errors.ratios"))
      end
      if effective_from && !draft?
        overlapping = self.class.published.where(own_warehouse_code: own_warehouse_code).where.not(id: id)
          .where("effective_to IS NULL OR effective_to >= ?", effective_from)
        overlapping = overlapping.where("effective_from <= ?", effective_to) if effective_to
        errors.add(:base, I18n.t("own_warehouse.errors.overlap")) if overlapping.exists?
      end
      errors.add(:effective_to, I18n.t("own_warehouse.errors.dates")) if effective_to && effective_from && effective_to < effective_from
    end

    def supersede_at!(date)
      @closing_for_successor = true
      update!(effective_to: date, status: "superseded")
    ensure
      @closing_for_successor = false
    end

    def prevent_published_changes
      return if attribute_in_database("status") == "draft"
      return if @closing_for_successor && (changes_to_save.keys - %w[effective_to status updated_at]).empty?
      errors.add(:base, I18n.t("own_warehouse.errors.immutable"))
      throw :abort
    end
  end
end
