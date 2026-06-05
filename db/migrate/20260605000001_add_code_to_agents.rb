class AddCodeToAgents < ActiveRecord::Migration[8.0]
  def change
    add_column :agents, :code, :string
    add_index :agents, :code, unique: true

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE agents
          SET code = 'business_analysis'
          WHERE code IS NULL
            AND id = (SELECT id FROM agents ORDER BY id ASC LIMIT 1)
        SQL

        execute <<~SQL.squish
          DELETE FROM agents
          WHERE code IS NULL
        SQL
      end
    end

    change_column_null :agents, :code, false
  end
end
