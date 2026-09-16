class AddListingContentToSkuDiagnosisRuleContexts < ActiveRecord::Migration[8.1]
  OLD_CONTEXT_KEYS = %w[
    base inventory lifecycle profit sales_funnel advertise_per_week
    ec_orders_full_period supply_orders_full_period operation_actions_full_period
    warehouse_recommendation search_terms_per_week
  ].freeze
  NEW_CONTEXT_KEYS = (OLD_CONTEXT_KEYS + %w[listing_content]).freeze

  def up
    change_column_default :ec_sku_diagnosis_rules, :configuration,
      from: { "context_keys" => OLD_CONTEXT_KEYS },
      to: { "context_keys" => NEW_CONTEXT_KEYS }

    execute <<~SQL.squish
      UPDATE ec_sku_diagnosis_rules
      SET configuration = jsonb_set(
        configuration,
        '{context_keys}',
        COALESCE(configuration -> 'context_keys', '[]'::jsonb) || '["listing_content"]'::jsonb
      )
      WHERE NOT (COALESCE(configuration -> 'context_keys', '[]'::jsonb) ? 'listing_content')
    SQL
  end

  def down
    execute <<~SQL.squish
      UPDATE ec_sku_diagnosis_rules
      SET configuration = jsonb_set(
        configuration,
        '{context_keys}',
        COALESCE(configuration -> 'context_keys', '[]'::jsonb) - 'listing_content'
      )
    SQL

    change_column_default :ec_sku_diagnosis_rules, :configuration,
      from: { "context_keys" => NEW_CONTEXT_KEYS },
      to: { "context_keys" => OLD_CONTEXT_KEYS }
  end
end
