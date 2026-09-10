module Ec
  class CompetitorDatum < ApplicationRecord
    self.table_name = "ec_competitor_data"

    belongs_to :competitor_data_batch,
      class_name: "Ec::CompetitorDataBatch",
      inverse_of: :competitor_data
    has_one_attached :combined_image

    validates :markdown, presence: true
    validate :combined_image_must_be_attached

    delegate :sku, to: :competitor_data_batch

    private

    def combined_image_must_be_attached
      errors.add(:combined_image, :blank) unless combined_image.attached?
    end
  end
end
