module Ec
  class ReturnSourceLink < ApplicationRecord
    self.table_name = "ec_return_source_links"

    belongs_to :return, class_name: "Ec::Return"
    belongs_to :item, class_name: "Ec::ReturnItem", optional: true

    validates :platform, inclusion: { in: Ec::Order::PLATFORMS.values }
    validates :source_type, :source_id, presence: true
    validates :source_id, uniqueness: { scope: :source_type }

    def source
      source_type.constantize.find_by(id: source_id)
    rescue NameError
      nil
    end
  end
end
