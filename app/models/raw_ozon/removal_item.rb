module RawOzon
  class RemovalItem < ApplicationRecord
    self.table_name = "raw_ozon_removal_items"

    COMPLETED_STATE = "Завершено".freeze
    RECEIVED_BOX_STATE = "Получена".freeze

    belongs_to :account, class_name: "RawOzon::SellerAccount"

    scope :seller_received, -> {
      where(return_state: COMPLETED_STATE)
        .where("box_state = :received_box_state OR given_out_date IS NOT NULL", received_box_state: RECEIVED_BOX_STATE)
    }
  end
end
