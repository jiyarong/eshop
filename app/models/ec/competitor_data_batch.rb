module Ec
  class CompetitorDataBatch < ApplicationRecord
    self.table_name = "ec_competitor_data_batches"

    belongs_to :sku, class_name: "Ec::Sku", inverse_of: :competitor_data_batches
    has_many :competitor_data, -> { order(:id) },
      class_name: "Ec::CompetitorDatum",
      foreign_key: :competitor_data_batch_id,
      inverse_of: :competitor_data_batch,
      dependent: :destroy
  end
end
