class PromoteEcSuppliersToCompanies < ActiveRecord::Migration[8.1]
  def change
    rename_table :ec_suppliers, :ec_companies
    reversible do |direction|
      direction.up do
        execute <<~SQL.squish
          UPDATE ec_attachment_links
          SET attachable_type = 'Ec::Company'
          WHERE attachable_type = 'Ec::Supplier'
        SQL
      end
      direction.down do
        execute <<~SQL.squish
          UPDATE ec_attachment_links
          SET attachable_type = 'Ec::Supplier'
          WHERE attachable_type = 'Ec::Company'
        SQL
      end
    end

    change_table :ec_companies, bulk: true do |t|
      t.string :tags, array: true, null: false, default: [ "supplier" ]
      t.string :origin
      t.string :invoice_type
      t.string :channel
      t.string :online_url
      t.references :developer, foreign_key: { to_table: :users, on_delete: :nullify }
      t.references :purchaser, foreign_key: { to_table: :users, on_delete: :nullify }
      t.boolean :factory_audited, null: false, default: false
      t.boolean :credit_terms, null: false, default: false
      t.string :supplier_grade
      t.text :supplier_evaluation
    end

    add_index :ec_companies, :tags, using: :gin
    add_check_constraint :ec_companies,
                         "invoice_type IS NULL OR invoice_type IN ('general', 'special')",
                         name: "ec_companies_invoice_type_check"
    add_check_constraint :ec_companies,
                         "channel IS NULL OR channel IN ('online', 'offline')",
                         name: "ec_companies_channel_check"
    add_check_constraint :ec_companies,
                         "supplier_grade IS NULL OR supplier_grade IN ('S', 'A', 'B', 'C')",
                         name: "ec_companies_supplier_grade_check"
  end
end
