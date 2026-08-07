module RawOzon
  class RemovalItem < ApplicationRecord
    self.table_name = "raw_ozon_removal_items"

    INVENTORY_DEDUCTING_STATES = [
      "Собирается на складе",
      "Можно забирать всё",
      "В пути"
    ].freeze

    belongs_to :account, class_name: "RawOzon::SellerAccount"

    scope :deducting_return_inventory, -> { where(return_state: INVENTORY_DEDUCTING_STATES) }
  end
end
