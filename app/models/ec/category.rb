module Ec
  class Category < ApplicationRecord
    self.table_name = "ec_categories"

    belongs_to :parent, class_name: "Ec::Category", optional: true
    has_many :children, class_name: "Ec::Category", foreign_key: :parent_id, dependent: :restrict_with_error

    validates :source, :source_type, :source_id, :origin_name, :origin_language, presence: true
    validates :source_id, uniqueness: { scope: [:source, :source_type] }

    before_validation :default_russian_name

    scope :translation_pending, -> {
      where("name_cn IS NULL OR name_cn = '' OR name_en IS NULL OR name_en = '' OR name_ru IS NULL OR name_ru = ''")
    }

    private

    def default_russian_name
      self.name_ru = origin_name if origin_language == "ru" && name_ru.blank?
    end
  end
end
