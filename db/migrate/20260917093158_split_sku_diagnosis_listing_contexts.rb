class SplitSkuDiagnosisListingContexts < ActiveRecord::Migration[8.1]
  OLD_CONTEXT_KEYS = %w[
    base inventory lifecycle profit sales_funnel advertise_per_week
    ec_orders_full_period supply_orders_full_period operation_actions_full_period
    warehouse_recommendation search_terms_per_week listing_content product_attributes
  ].freeze
  NEW_CONTEXT_KEYS = %w[
    base inventory lifecycle profit sales_funnel advertise_per_week
    ec_orders_full_period supply_orders_full_period operation_actions_full_period
    warehouse_recommendation search_terms_per_week ozon_listing_content wb_listing_content
  ].freeze

  def change
    reversible do |direction|
      direction.up do
        change_column_default :ec_sku_diagnosis_rules, :configuration,
          from: { "context_keys" => OLD_CONTEXT_KEYS },
          to: { "context_keys" => NEW_CONTEXT_KEYS }
        replace_listing_contexts(
          remove: %w[listing_content product_attributes],
          add: %w[ozon_listing_content wb_listing_content]
        )
      end

      direction.down do
        replace_listing_contexts(
          remove: %w[ozon_listing_content wb_listing_content],
          add: %w[listing_content]
        )
        change_column_default :ec_sku_diagnosis_rules, :configuration,
          from: { "context_keys" => NEW_CONTEXT_KEYS },
          to: { "context_keys" => OLD_CONTEXT_KEYS }
      end
    end
  end

  private

  def replace_listing_contexts(remove:, add:)
    remove_sql = remove.map { |key| " - #{connection.quote(key)}" }.join
    old_keys_sql = remove.map { |key| connection.quote(key) }.join(", ")
    add_json = connection.quote(add.to_json)
    execute <<~SQL.squish
      UPDATE ec_sku_diagnosis_rules
      SET configuration = jsonb_set(
        configuration,
        '{context_keys}',
        (COALESCE(configuration -> 'context_keys', '[]'::jsonb)#{remove_sql}) || #{add_json}::jsonb
      )
      WHERE COALESCE(configuration -> 'context_keys', '[]'::jsonb) ?| ARRAY[#{old_keys_sql}]
    SQL
  end
end
