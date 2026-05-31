module RawWb
  class Subject < ApplicationRecord
    self.table_name = 'raw_wb_subjects'

    belongs_to :category, class_name: 'RawWb::Category'

    has_many :characteristics, class_name: 'RawWb::Characteristic', foreign_key: :subject_id, dependent: :destroy
    has_many :products,        class_name: 'RawWb::Product',         foreign_key: :subject_id
  end
end
