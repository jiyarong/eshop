module SkuProfitPredictionHelper
  PROFIT_IDENTITY_COLUMNS = %i[platform market delivery_mode company_type].freeze
  PROFIT_BASE_INPUT_COLUMNS = %i[
    purchase_price_cny freight_cny customs_misc_cny duty_rate import_vat_rate
    length_cm width_cm height_cm
  ].freeze
  PROFIT_COMMERCIAL_INPUT_COLUMNS = %i[
    price_rub rf_price_rub exchange_rate_rub_cny commission_rate acquiring_rate
    advertising_rate tax_rate sales_vat_rate
  ].freeze
  PROFIT_LOGISTICS_INPUT_COLUMNS = %i[
    logistics_coeff return_rate logistics_tax_rate wb_logistics_base_rub wb_logistics_liter_rub
    wb_fixed_return_base_rub fbo_delivery_cny storage_cny damage_rate misc_cny
    other_cny outbound_logistics_rub return_logistics_rub warehouse_operation_rub
    cross_docking_cny
  ].freeze
  PROFIT_RESULT_COLUMNS = %i[
    revenue_cny goods_cost_cny import_vat_cny duty_cny logistics_cny returns_cny
    storage_cost_cny commission_cny acquiring_cny advertising_cny tax_cny
    other_cost_cny total_cost_cny profit_cny margin
  ].freeze

  PROFIT_RATE_INPUT_COLUMNS = %i[
    duty_rate import_vat_rate commission_rate acquiring_rate advertising_rate
    tax_rate sales_vat_rate return_rate logistics_tax_rate damage_rate
  ].freeze

  PROFIT_WB_ONLY_COLUMNS = %i[
    logistics_coeff logistics_tax_rate wb_logistics_base_rub wb_logistics_liter_rub
    wb_fixed_return_base_rub fbo_delivery_cny storage_cny damage_rate
    misc_cny tax_rate
  ].freeze

  PROFIT_OZON_ONLY_COLUMNS = %i[
    rf_price_rub outbound_logistics_rub return_logistics_rub
    warehouse_operation_rub cross_docking_cny
  ].freeze

  # Keep calculated values beside the inputs that drive them, following the
  # source workbook's left-to-right calculation flow.
  PROFIT_TABLE_GROUPS = [
    [ :base_inputs, [
      [ :input, :purchase_price_cny ],
      [ :input, :freight_cny ],
      [ :input, :customs_misc_cny ],
      [ :input, :duty_rate ],
      [ :result, :duty_cny ],
      [ :input, :import_vat_rate ],
      [ :result, :import_vat_cny ],
      [ :result, :goods_cost_cny ],
      [ :input, :length_cm ],
      [ :input, :width_cm ],
      [ :input, :height_cm ]
    ] ],
    [ :logistics_inputs, [
      [ :input, :storage_cny ],
      [ :input, :cross_docking_cny ],
      [ :input, :outbound_logistics_rub ],
      [ :input, :return_logistics_rub ],
      [ :input, :warehouse_operation_rub ],
      [ :input, :logistics_coeff ],
      [ :input, :return_rate ],
      [ :input, :logistics_tax_rate ],
      [ :input, :wb_logistics_base_rub ],
      [ :input, :wb_logistics_liter_rub ],
      [ :input, :wb_fixed_return_base_rub ],
      [ :input, :fbo_delivery_cny ],
      [ :result, :logistics_cny ],
      [ :result, :returns_cny ]
    ] ],
    [ :commercial_inputs, [
      [ :input, :price_rub ],
      [ :input, :exchange_rate_rub_cny ],
      [ :result, :revenue_cny ],
      [ :input, :commission_rate ],
      [ :result, :commission_cny ],
      [ :input, :acquiring_rate ],
      [ :result, :acquiring_cny ],
      [ :input, :advertising_rate ],
      [ :result, :advertising_cny ],
      [ :input, :tax_rate ],
      [ :input, :sales_vat_rate ],
      [ :result, :tax_cny ],
      [ :input, :damage_rate ],
      [ :input, :misc_cny ],
      [ :input, :other_cny ],
      [ :result, :other_cost_cny ]
    ] ],
    [ :results, [
      [ :result, :total_cost_cny ],
      [ :result, :profit_cny ],
      [ :result, :margin ]
    ] ]
  ].map { |group, columns| [ group, columns.freeze ] }.freeze

  def profit_prediction_input_groups
    [
      [:base_inputs, PROFIT_BASE_INPUT_COLUMNS],
      [:logistics_inputs, PROFIT_LOGISTICS_INPUT_COLUMNS],
      [:commercial_inputs, PROFIT_COMMERCIAL_INPUT_COLUMNS]
    ]
  end

  def profit_prediction_table_groups
    PROFIT_TABLE_GROUPS
  end

  def profit_prediction_parameter_labels
    PROFIT_TABLE_GROUPS.each_with_object({}) do |(_group, columns), labels|
      columns.each do |kind, field|
        next unless kind == :input

        labels[field] = t("reports.profit_prediction.fields.#{field}")
      end
    end
  end

  def profit_prediction_column_platforms(field)
    field = field.to_sym
    return %w[wb] if PROFIT_WB_ONLY_COLUMNS.include?(field)
    return %w[ozon] if PROFIT_OZON_ONLY_COLUMNS.include?(field)

    %w[wb ozon]
  end

  def profit_prediction_contexts(version)
    Ec::SkuProfitStandardContexts.sort(version.contexts)
  end

  def profit_prediction_input_applicable?(context, field)
    field = field.to_sym
    return true if PROFIT_BASE_INPUT_COLUMNS.include?(field)
    return true if %i[price_rub exchange_rate_rub_cny commission_rate acquiring_rate advertising_rate other_cny].include?(field)

    context.platform == "wb" ? wb_profit_input_applicable?(context, field) : ozon_profit_input_applicable?(context, field)
  end

  def profit_prediction_not_applicable_label(context, field)
    if context.platform == "ozon" && context.market == "by" && field.to_sym == :cross_docking_cny
      t("reports.profit_prediction.values.cross_docking_not_applicable")
    else
      t("reports.profit_prediction.values.not_applicable")
    end
  end

  def profit_prediction_input_editable?(context, field)
    field = field.to_sym
    return false if %i[length_cm width_cm height_cm].include?(field)
    return false if context.platform == "ozon" && context.market == "ru" && field == :import_vat_rate

    true
  end

  def profit_prediction_identity_value(context, field)
    case field.to_sym
    when :platform
      t("reports.profit_prediction.options.platforms.#{context.platform}")
    when :market
      t("reports.profit_prediction.options.markets.#{context.market}", default: context.market.to_s.upcase)
    when :delivery_mode
      t("reports.profit_prediction.options.delivery_modes.#{context.platform}_#{context.delivery_mode}")
    when :warehouse_region
      t("reports.profit_prediction.options.warehouse_regions.#{context.warehouse_region}", default: context.warehouse_region.presence || "-")
    when :company_type
      company_type = context.company_type.presence || ("general" if context.platform == "ozon")
      company_type ? t("reports.profit_prediction.options.company_types.#{company_type}") : t("reports.profit_prediction.values.not_applicable")
    end
  end

  def profit_prediction_result_value(context, field)
    value = context.public_send(field)
    return t("reports.profit_prediction.values.unavailable") if value.nil?
    return number_to_percentage(value * 100, precision: 2) if field.to_sym == :margin
    return t("reports.profit_prediction.calculation_statuses.#{value}") if field.to_sym == :calculation_status

    number_with_precision(value, precision: 2)
  end

  def profit_prediction_input_value(value, field)
    return if value.nil?
    return value.to_d.to_s("F") if PROFIT_RATE_INPUT_COLUMNS.include?(field.to_sym)

    format("%.2f", value)
  end

  def profit_prediction_raw_value(value)
    value.nil? ? "" : value.to_d.to_s("F")
  end

  private

  def wb_profit_input_applicable?(context, field)
    common = %i[
      logistics_coeff return_rate wb_logistics_base_rub wb_logistics_liter_rub fbo_delivery_cny storage_cny
      damage_rate misc_cny
    ]
    return true if common.include?(field)
    return %i[wb_fixed_return_base_rub sales_vat_rate].include?(field) if context.company_type == "general"
    return %i[logistics_tax_rate tax_rate].include?(field) if context.company_type == "small"

    false
  end

  def ozon_profit_input_applicable?(context, field)
    common = %i[return_rate storage_cny outbound_logistics_rub return_logistics_rub warehouse_operation_rub]
    return true if common.include?(field)
    return field == :cross_docking_cny if context.market == "ru"
    return %i[rf_price_rub sales_vat_rate].include?(field) if context.market == "by"

    false
  end
end
