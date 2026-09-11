module RawWb
  class AttributeDict < ApplicationRecord
    self.table_name = 'raw_wb_attribute_dicts'

    belongs_to :subject, class_name: 'RawWb::Subject', optional: true
  end
end
