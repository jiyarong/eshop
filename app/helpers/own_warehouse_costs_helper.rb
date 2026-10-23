module OwnWarehouseCostsHelper
  def own_warehouse_rate_segments(row)
    Array(row&.calculation_inputs&.fetch("segments", nil)).filter_map do |segment|
      period = segment.fetch("period", {})
      denominators = segment.fetch("denominators", {})
      budget = own_warehouse_decimal(segment["budget"])
      {
        period_id: period["id"],
        from: segment["from"],
        to: segment["to"],
        budget: budget,
        storage_rate: own_warehouse_rate(budget * own_warehouse_decimal(period["storage_ratio"]), denominators["storage_cost"]),
        transport_rate: own_warehouse_rate(budget * own_warehouse_decimal(period["transport_ratio"]), denominators["transport_cost"]),
        labor_rate: own_warehouse_rate(budget * own_warehouse_decimal(period["labor_ratio"]), denominators["labor_cost"]),
        fbo_labor_weight: own_warehouse_decimal(period["fbo_labor_weight"])
      }
    end
  end

  def own_warehouse_allocation_metrics(row, rate_segments: own_warehouse_rate_segments(row))
    inputs = Array(row&.calculation_inputs&.fetch("inputs", nil))
    totals = { fbs_quantity: 0.to_d, fbs_volume: 0.to_d, fbo_quantity: 0.to_d, fbo_volume: 0.to_d }
    costs = { fbs: 0.to_d, fbo: 0.to_d }

    rate_segments.each do |segment|
      segment_inputs = inputs.select do |input|
        date = Date.iso8601(input["date"].to_s)
        date >= Date.iso8601(segment[:from].to_s) && date <= Date.iso8601(segment[:to].to_s)
      end
      fbs_quantity = segment_inputs.sum { |input| own_warehouse_decimal(input["fbs_outbound_quantity"]) }
      fbs_volume = segment_inputs.sum { |input| own_warehouse_decimal(input["fbs_outbound_quantity"]) * own_warehouse_decimal(input["unit_volume_m3"]) }
      fbo_quantity = segment_inputs.sum { |input| own_warehouse_decimal(input["fbo_outbound_quantity"]) }
      fbo_volume = segment_inputs.sum { |input| own_warehouse_decimal(input["fbo_outbound_quantity"]) * own_warehouse_decimal(input["unit_volume_m3"]) }

      totals[:fbs_quantity] += fbs_quantity
      totals[:fbs_volume] += fbs_volume
      totals[:fbo_quantity] += fbo_quantity
      totals[:fbo_volume] += fbo_volume
      costs[:fbs] += fbs_quantity * segment[:labor_rate] + fbs_volume * segment[:transport_rate]
      costs[:fbo] += fbo_quantity * segment[:fbo_labor_weight] * segment[:labor_rate] + fbo_volume * segment[:transport_rate]
    end

    {
      fbs_unit_cost: totals[:fbs_quantity].zero? ? nil : costs[:fbs] / totals[:fbs_quantity],
      fbo_unit_cost: totals[:fbo_quantity].zero? ? nil : costs[:fbo] / totals[:fbo_quantity]
    }
  rescue Date::Error, TypeError
    { fbs_unit_cost: nil, fbo_unit_cost: nil }
  end

  private

  def own_warehouse_decimal(value)
    value.blank? ? 0.to_d : BigDecimal(value.to_s)
  end

  def own_warehouse_rate(numerator, denominator)
    denominator = own_warehouse_decimal(denominator)
    denominator.zero? ? 0.to_d : numerator / denominator
  end
end
