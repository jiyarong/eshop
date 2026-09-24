class ExpandSkuProfitVersionContextsIntoTypedRows < ActiveRecord::Migration[8.1]
  INPUT_AMOUNT_COLUMNS = %i[
    purchase_price_cny freight_cny customs_misc_cny
    price_rub rf_price_rub exchange_rate_rub_cny
    wb_logistics_base_rub wb_fixed_return_base_rub fbo_delivery_cny storage_cny
    misc_cny other_cny outbound_logistics_rub return_logistics_rub
    warehouse_operation_rub cross_docking_cny
  ].freeze
  INPUT_RATE_COLUMNS = %i[
    duty_rate import_vat_rate commission_rate acquiring_rate advertising_rate
    tax_rate sales_vat_rate logistics_coeff return_rate logistics_tax_rate damage_rate
  ].freeze
  DIMENSION_COLUMNS = %i[length_cm width_cm height_cm].freeze
  RESULT_AMOUNT_COLUMNS = %i[
    revenue_cny goods_cost_cny import_vat_cny duty_cny logistics_cny returns_cny
    storage_cost_cny commission_cny acquiring_cny advertising_cny tax_cny
    other_cost_cny total_cost_cny profit_cny
  ].freeze

  def up
    INPUT_AMOUNT_COLUMNS.each { |column| add_column :ec_sku_profit_version_contexts, column, :decimal, precision: 20, scale: 8 }
    INPUT_RATE_COLUMNS.each { |column| add_column :ec_sku_profit_version_contexts, column, :decimal, precision: 14, scale: 10 }
    DIMENSION_COLUMNS.each { |column| add_column :ec_sku_profit_version_contexts, column, :decimal, precision: 12, scale: 4 }
    RESULT_AMOUNT_COLUMNS.each { |column| add_column :ec_sku_profit_version_contexts, column, :decimal, precision: 20, scale: 8 }
    add_column :ec_sku_profit_version_contexts, :margin, :decimal, precision: 14, scale: 10
    add_column :ec_sku_profit_version_contexts, :calculation_status, :string, null: false, default: "pending"
    add_column :ec_sku_profit_version_contexts, :formula_version, :string
    add_column :ec_sku_profit_version_contexts, :calculated_at, :datetime

    (INPUT_AMOUNT_COLUMNS + INPUT_RATE_COLUMNS + DIMENSION_COLUMNS).each do |column|
      backfill_numeric_column(column)
    end
    backfill_sku_base_inputs

    remove_column :ec_sku_profit_version_contexts, :parameters, :jsonb
  end

  def down
    add_column :ec_sku_profit_version_contexts, :parameters, :jsonb, null: false, default: {}
    input_pairs = (INPUT_AMOUNT_COLUMNS + INPUT_RATE_COLUMNS + DIMENSION_COLUMNS).flat_map do |column|
      ["'#{column}'", column.to_s]
    end.join(", ")
    execute <<~SQL.squish
      UPDATE ec_sku_profit_version_contexts
      SET parameters = jsonb_build_object(
        'schema_version', 1,
        'values', jsonb_strip_nulls(jsonb_build_object(#{input_pairs})),
        'sources', '{}'::jsonb
      )
    SQL

    remove_column :ec_sku_profit_version_contexts, :calculated_at, :datetime
    remove_column :ec_sku_profit_version_contexts, :formula_version, :string
    remove_column :ec_sku_profit_version_contexts, :calculation_status, :string
    remove_column :ec_sku_profit_version_contexts, :margin, :decimal
    RESULT_AMOUNT_COLUMNS.reverse_each { |column| remove_column :ec_sku_profit_version_contexts, column, :decimal }
    DIMENSION_COLUMNS.reverse_each { |column| remove_column :ec_sku_profit_version_contexts, column, :decimal }
    INPUT_RATE_COLUMNS.reverse_each { |column| remove_column :ec_sku_profit_version_contexts, column, :decimal }
    INPUT_AMOUNT_COLUMNS.reverse_each { |column| remove_column :ec_sku_profit_version_contexts, column, :decimal }
  end

  private

  def backfill_numeric_column(column)
    raw_value = "parameters #>> '{values,#{column}}'"
    execute <<~SQL.squish
      UPDATE ec_sku_profit_version_contexts
      SET #{column} = CASE
        WHEN #{raw_value} ~ '^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][+-]?[0-9]+)?$'
        THEN (#{raw_value})::numeric
        ELSE NULL
      END
    SQL
  end

  def backfill_sku_base_inputs
    execute <<~SQL.squish
      WITH latest_cost AS (
        SELECT DISTINCT ON (context.id)
               context.id AS context_id,
               cost.purchase_price_cny,
               cost.freight_to_by_cny,
               cost.customs_misc_cny,
               cost.customs_duty_rate,
               cost.import_vat_rate
        FROM ec_sku_profit_version_contexts AS context
        JOIN ec_sku_profit_versions AS version ON version.id = context.sku_profit_version_id
        JOIN ec_skus AS sku ON sku.id = version.sku_id
        JOIN ec_sku_costs AS cost ON cost.sku_code = sku.sku_code
        WHERE cost.effective_on <= version.effective_from
        ORDER BY context.id, cost.effective_on DESC, cost.id DESC
      )
      UPDATE ec_sku_profit_version_contexts AS context
      SET purchase_price_cny = COALESCE(context.purchase_price_cny, source.purchase_price_cny),
          freight_cny = COALESCE(context.freight_cny, source.freight_to_by_cny),
          customs_misc_cny = COALESCE(context.customs_misc_cny, source.customs_misc_cny),
          duty_rate = COALESCE(context.duty_rate, source.customs_duty_rate),
          import_vat_rate = COALESCE(context.import_vat_rate, source.import_vat_rate)
      FROM latest_cost AS source
      WHERE source.context_id = context.id
    SQL

    execute <<~SQL.squish
      UPDATE ec_sku_profit_version_contexts AS context
      SET length_cm = COALESCE(context.length_cm, dimension.inner_length_cm),
          width_cm = COALESCE(context.width_cm, dimension.inner_width_cm),
          height_cm = COALESCE(context.height_cm, dimension.inner_height_cm)
      FROM ec_sku_profit_versions AS version
      JOIN ec_skus AS sku ON sku.id = version.sku_id
      JOIN ec_sku_dimensions AS dimension ON dimension.sku_code = sku.sku_code
      WHERE version.id = context.sku_profit_version_id
    SQL
  end
end
