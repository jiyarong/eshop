module Ec
  class Category < ApplicationRecord
    self.table_name = "ec_categories"

    belongs_to :parent, class_name: "Ec::Category", optional: true
    has_many :children, class_name: "Ec::Category", foreign_key: :parent_id, dependent: :restrict_with_error

    validates :source, :source_type, :source_id, :origin_name, :origin_language, presence: true
    validates :source_id, uniqueness: { scope: [:source, :source_type] }

    before_validation :default_russian_name

    def self.localized_name_column(locale = I18n.locale)
      case locale.to_s
      when "zh"
        "name_cn"
      when "en"
        "name_en"
      when "ru"
        "name_ru"
      else
        "origin_name"
      end
    end

    def self.localized_name_order(locale = I18n.locale)
      table_name = quoted_table_name
      name_column = connection.quote_column_name(localized_name_column(locale))
      origin_column = connection.quote_column_name("origin_name")

      Arel.sql("LOWER(COALESCE(NULLIF(#{table_name}.#{name_column}, ''), #{table_name}.#{origin_column}))")
    end

    scope :translation_pending, -> {
      where("name_cn IS NULL OR name_cn = '' OR name_en IS NULL OR name_en = '' OR name_ru IS NULL OR name_ru = ''")
    }

    def localized_name(locale = I18n.locale)
      public_send(self.class.localized_name_column(locale)).presence ||
        name_cn.presence ||
        name_en.presence ||
        name_ru.presence ||
        origin_name
    end

    private

    def default_russian_name
      self.name_ru = origin_name if origin_language == "ru" && name_ru.blank?
    end
  end
end
