require "digest"

module Ec
  # Inputs represent the complete warehouse population, before any report/access filters.
  class OwnWarehouseCostAllocator
    class InvalidInput < StandardError
      attr_reader :code
      def initialize(code)
        @code = code
        super(I18n.t("own_warehouse.errors.#{code}"))
      end
    end
    INPUT_FIELDS = %i[unit_volume_m3 on_hand_quantity fbs_outbound_quantity fbo_outbound_quantity].freeze

    def self.call(week_start:, warehouse_code:, daily_inputs:, actor: nil, required_sku_codes: nil, source_metadata: { source: "complete_daily_csv" })
      new(week_start:, warehouse_code:, daily_inputs:, actor:, required_sku_codes:, source_metadata:).call
    end

    def initialize(week_start:, warehouse_code:, daily_inputs:, actor: nil, required_sku_codes: nil, source_metadata: { source: "complete_daily_csv" })
      @week_start = Date.iso8601(week_start.to_s)
      @week_end = @week_start + 6
      @warehouse_code = warehouse_code.to_s.strip
      @source_metadata = source_metadata.deep_stringify_keys
      @actor = actor
      @required_sku_codes = Array(required_sku_codes).map { |code| code.to_s.strip.upcase }.compact_blank.uniq
      @inputs = daily_inputs.map { |input| input.to_h.symbolize_keys }
    end

    def call
      validate_inputs!
      Ec::OwnWarehouseCostPeriod.transaction do
        # Serializes confirmation and publication for this warehouse, including the first run.
        Ec::OwnWarehouseCostPeriod.lock_warehouse!(@warehouse_code)
        periods = Ec::OwnWarehouseCostPeriod.published.where(own_warehouse_code: @warehouse_code)
          .where("effective_from <= ? AND (effective_to IS NULL OR effective_to >= ?)", @week_end, @week_start).order(:effective_from).to_a
        days = (@week_start..@week_end).to_a
        versions_by_day = days.index_with do |day|
          matching = periods.select { |period| period.active_on?(day) }
          fail_input!(:missing_version) unless matching.one?
          matching.first
        end
        signature = Digest::SHA256.hexdigest(JSON.generate({ inputs: normalized_inputs, source_metadata: @source_metadata, versions: periods.map { |p| p.attributes.slice("id", "own_warehouse_code", "total_operating_cost", "cost_basis_days", "currency", "storage_ratio", "transport_ratio", "labor_ratio", "fbo_labor_weight").merge("from" => [p.effective_from, @week_start].max, "to" => [p.effective_to, @week_end].compact.min) } }))
        scope = Ec::OwnWarehouseSkuCostAllocation.where(own_warehouse_code: @warehouse_code, week_start: @week_start)
        current = scope.current.order(:sku_id).to_a
        return current if current.any? && current.all? { |row| row.calculation_inputs["signature"] == signature }

        totals = @sku_ids.keys.index_with { { storage_cost: 0.to_d, transport_cost: 0.to_d, labor_cost: 0.to_d } }
        evidence = []
        days.chunk { |day| versions_by_day.fetch(day).id }.each do |_, segment_days|
          period = versions_by_day.fetch(segment_days.first)
          segment_inputs = @inputs.select { |row| segment_days.include?(row[:date]) }.group_by { |row| row[:sku_code] }
          segment_budget = segment_days.sum { |day| period.daily_cost_on(day) }.round(2)
          storage_weights = segment_inputs.transform_values { |rows| rows.sum { |r| r[:unit_volume_m3] * r[:on_hand_quantity] } / segment_days.length }
          transport_weights = segment_inputs.transform_values { |rows| rows.sum { |r| r[:unit_volume_m3] * (r[:fbs_outbound_quantity] + r[:fbo_outbound_quantity]) } }
          labor_weights = segment_inputs.transform_values { |rows| rows.sum { |r| r[:fbs_outbound_quantity] + r[:fbo_outbound_quantity] * period.fbo_labor_weight } }
          pools = split_cents(segment_budget, { storage_cost: period.storage_ratio, transport_cost: period.transport_ratio, labor_cost: period.labor_ratio })
          weights = { storage_cost: storage_weights, transport_cost: transport_weights, labor_cost: labor_weights }
          components = pools.to_h do |key, amount|
            fail_input!(:zero_denominator) if amount.positive? && weights.fetch(key).values.sum.zero?
            distribution = split_cents(amount, weights.fetch(key))
            distribution.each { |sku_code, cost| totals.fetch(sku_code)[key] += cost }
            [key, distribution]
          end
          evidence << { period: period.attributes.slice("id", "effective_from", "effective_to", "total_operating_cost", "cost_basis_days", "currency", "storage_ratio", "transport_ratio", "labor_ratio", "fbo_labor_weight"), from: segment_days.first, to: segment_days.last, budget: segment_budget, denominators: weights.transform_values { |w| w.values.sum }, components: components }
        end
        revision = scope.maximum(:allocation_version).to_i + 1
        scope.current.update_all(is_current: false)
        @sku_ids.keys.sort.map do |sku_code|
          inputs = @inputs.select { |row| row[:sku_code] == sku_code }
          costs = totals.fetch(sku_code)
          total = costs.values.sum
          fbs = inputs.sum { |r| r[:fbs_outbound_quantity] }
          fbo = inputs.sum { |r| r[:fbo_outbound_quantity] }
          outbound = fbs + fbo
          Ec::OwnWarehouseSkuCostAllocation.create!(
            sku_id: @sku_ids.fetch(sku_code), own_warehouse_code: @warehouse_code,
            own_warehouse_cost_period: periods.one? ? periods.first : nil,
            week_start: @week_start, week_end: @week_end, allocation_version: revision,
            unit_volume_m3: inputs.map { |r| r[:unit_volume_m3] }.uniq.one? ? inputs.first[:unit_volume_m3] : nil,
            on_hand_quantity: inputs.sum { |r| r[:on_hand_quantity] } / 7,
            on_hand_volume_m3: inputs.sum { |r| r[:on_hand_quantity] * r[:unit_volume_m3] } / 7,
            fbs_outbound_quantity: fbs, fbo_outbound_quantity: fbo,
            fbs_outbound_volume_m3: inputs.sum { |r| r[:fbs_outbound_quantity] * r[:unit_volume_m3] },
            fbo_outbound_volume_m3: inputs.sum { |r| r[:fbo_outbound_quantity] * r[:unit_volume_m3] },
            **costs, total_cost: total, outbound_quantity: outbound,
            cost_per_outbound_unit: outbound.zero? ? nil : total / outbound,
            calculated_at: Time.current, calculation_inputs: { signature: signature, actor_id: @actor&.id, source: @source_metadata.fetch("source"), source_metadata: @source_metadata.except("by_sku").merge("sku_evidence" => @source_metadata.fetch("by_sku", {}).fetch(sku_code, {})), inputs: inputs, segments: evidence.map { |segment| segment.merge(components: segment[:components].transform_values { |by_sku| by_sku.fetch(sku_code) }) } }
          )
        end
      end
    end

    private

    def validate_inputs!
      fail_input!(:invalid_week) unless @week_start.monday? && @week_end < Time.current.in_time_zone("Asia/Shanghai").to_date.beginning_of_week(:monday)
      fail_input!(:missing_inputs) if @warehouse_code.blank? || @inputs.empty?
      @inputs.each do |row|
        row[:date] = Date.iso8601(row[:date].to_s)
        row[:sku_code] = row[:sku_code].to_s.strip.upcase
        fail_input!(:invalid_inputs) unless (@week_start..@week_end).cover?(row[:date]) && row[:sku_code].present?
        INPUT_FIELDS.each do |key|
          fail_input!(:invalid_inputs) if row[key].blank?
          row[key] = BigDecimal(row[key].to_s)
          fail_input!(:invalid_inputs) unless row[key].finite? && row[key] >= 0
        end
        fail_input!(:invalid_inputs) unless row[:unit_volume_m3].positive?
      end
      fail_input!(:duplicate_inputs) unless @inputs.map { |r| [r[:date], r[:sku_code]] }.uniq.size == @inputs.size
      @inputs.group_by { |r| r[:sku_code] }.each_value do |rows|
        fail_input!(:incomplete_inputs) unless rows.size == 7
      end
      codes = @inputs.map { |r| r[:sku_code] }.uniq
      fail_input!(:missing_skus) if @required_sku_codes.present? && (@required_sku_codes - codes).any?
      @sku_ids = Ec::Sku.with_deleted.where(sku_code: codes).pluck(:sku_code, :id).to_h
      fail_input!(:unknown_sku) unless @sku_ids.size == codes.size
    rescue Date::Error, ArgumentError
      fail_input!(:invalid_inputs)
    end

    def normalized_inputs
      @inputs.sort_by { |row| [row[:date], row[:sku_code]] }.map { |r| r.slice(:date, :sku_code, *INPUT_FIELDS) }
    end

    # Largest remainder allocation reconciles every pool to the cent, deterministically.
    def split_cents(amount, weights)
      denominator = weights.values.sum
      return weights.transform_values { 0.to_d } if denominator.zero?
      cents = (amount * 100).round.to_i
      raw = weights.transform_values { |weight| cents * weight / denominator }
      assigned = raw.transform_values(&:floor)
      remainder = cents - assigned.values.sum
      raw.keys.sort_by { |key| [-(raw[key] - assigned[key]), key.to_s] }.first(remainder).each { |key| assigned[key] += 1 }
      assigned.transform_values { |value| value.to_d / 100 }
    end

    def fail_input!(code)
      raise InvalidInput, code
    end
  end
end
