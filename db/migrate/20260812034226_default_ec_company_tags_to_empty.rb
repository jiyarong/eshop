class DefaultEcCompanyTagsToEmpty < ActiveRecord::Migration[8.1]
  def change
    change_column_default :ec_companies, :tags, from: [ "supplier" ], to: []
  end
end
