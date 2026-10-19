module Ec
  # Whether one pricing scenario is shown in a SKU's workbench. A row exists only after somebody
  # hid or restored the scenario; a scenario without a row is shown. Hiding is a view choice about
  # the SKU, shared by everybody: it does not touch any version's data and is not an edit of the
  # version.
  class SkuScenarioVisibility < ApplicationRecord
    include Ec::Auditable

    self.table_name = "ec_sku_scenario_visibilities"
    IDENTITY_KEYS = Ec::SkuProfitStandardContexts::IDENTITY_KEYS

    belongs_to :sku, class_name: "Ec::Sku"
    belongs_to :updated_by, class_name: "User", optional: true

    validates(*IDENTITY_KEYS, presence: true)
    validate :scenario_is_known

    # Keys ("wb|ru|fbo|main|general") of the scenarios the SKU has hidden.
    def self.hidden_keys_for(sku)
      where(sku_id: sku.id, hidden: true).map { |row| key_for(row) }.to_set
    end

    def self.key_for(record)
      Ec::SkuProfitStandardContexts.key_for(record.attributes.slice(*IDENTITY_KEYS))
    end

    # identity: { "platform" => ..., "market" => ..., "delivery_mode" => ..., "company_type" => ... }
    def self.set!(sku:, identity:, hidden:, user: nil)
      attributes = IDENTITY_KEYS.index_with do |key|
        value = identity[key] || identity[key.to_sym]
        value = Ec::SkuProfitStandardContexts::DEFAULT_WAREHOUSE_REGION if key == "warehouse_region" && value.blank?
        value.to_s.downcase
      end
      record = find_or_initialize_by(sku_id: sku.id, **attributes)
      record.hidden = hidden
      record.updated_by = user
      record.save!
      record
    end

    private

    def scenario_is_known
      return if errors.any? || Ec::SkuProfitStandardContexts.scenario_keys.include?(self.class.key_for(self))

      errors.add(:base, :invalid)
    end
  end
end
