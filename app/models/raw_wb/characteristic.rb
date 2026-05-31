module RawWb
  class Characteristic < ApplicationRecord
    self.table_name = 'raw_wb_characteristics'

    belongs_to :subject, class_name: 'RawWb::Subject'
  end
end
