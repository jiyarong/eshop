module RawWb
  class Category < ApplicationRecord
    self.table_name = 'raw_wb_categories'

    has_many :subjects, class_name: 'RawWb::Subject', foreign_key: :category_id, dependent: :destroy
  end
end
