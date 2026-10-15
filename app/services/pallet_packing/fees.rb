module PalletPacking
  class Fees
    def initialize(profile:, items:, settings:, pallets:)
      @profile, @items, @settings, @pallets = profile, items, settings, pallets
    end

    def call
      sku_totals = @items.each_index.map { |index| { item_index: index, boxes: 0, units: 0, known_fee: 0.0 } }
      @pallets.each_with_index do |pallet, pallet_index|
        zones = pallet[:zones]
        volume_known = zones.all? { |zone| @items[zone[:item_index]][:unit_volume_l] }
        goods_l = volume_known ? zones.sum { |zone| goods_volume(zone) } : nil
        bill_l = goods_l && [goods_l.ceil, 1900].max
        missing = []
        route = handling = storage = 0.0
        if @profile == "ozon_fbo"
          missing << :goods_volume unless volume_known
          missing << :route_rate if @settings[:route_rate].nil? && @settings[:discount] < 100
          route = bill_l && (@settings[:route_rate] || @settings[:discount] == 100) ? bill_l * (@settings[:route_rate] || 0) * (1 - @settings[:discount] / 100) : nil
          handling = volume_known ? zones.sum { |zone| sorting_fee(zone, zones.size) } : nil
          storage = volume_known ? goods_l * @settings[:storage_rate] * @settings[:storage_days] * @settings[:coefficient] : (@settings[:storage_days].zero? ? 0.0 : nil)
          pickup = @settings[:pickup] ? (goods_l && goods_l.ceil * 1.55) : 0.0
        elsif @profile == "ozon_fbs"
          handling = pallet[:units] * @settings[:handling_rate]
          pickup = 0.0
        elsif @profile == "wb_mono"
          storage = @settings[:storage_rate] * @settings[:storage_days] * @settings[:coefficient]
          pickup = 0.0
        else
          missing << :goods_volume unless volume_known || @settings[:storage_days].zero?
          storage = volume_known ? goods_l * @settings[:storage_rate] * @settings[:storage_days] * @settings[:coefficient] : (@settings[:storage_days].zero? ? 0.0 : nil)
          pickup = 0.0
        end
        breakdown = { route: route, handling: handling, pickup: pickup, storage: storage, fixed: pallet_index.zero? ? @settings[:fixed_fee] : 0.0 }
        known_fee = breakdown.values.compact.sum
        pallet.merge!(goods_l: goods_l, bill_l: @profile == "ozon_fbo" ? bill_l : goods_l, breakdown: breakdown,
          missing: missing, known_fee: known_fee, fee: missing.empty? ? known_fee : nil)
        # Allocate shared costs by product volume, falling back to carton volume
        # only as an explicit allocation key when product volume is unavailable.
        shares = zones.map { |zone| volume_known ? goods_volume(zone) : zone[:count] * @items[zone[:item_index]].values_at(:length, :width, :height).reduce(:*) }
        zones.each_with_index do |zone, index|
          own_handling = if @profile == "ozon_fbs"
            zone[:count] * @items[zone[:item_index]][:pcs] * @settings[:handling_rate]
          elsif @profile == "ozon_fbo" && volume_known
            sorting_fee(zone, zones.size)
          else
            0.0
          end
          allocated = (known_fee - (handling || 0)) * shares[index] / shares.sum + own_handling
          total = sku_totals[zone[:item_index]]
          total[:boxes] += zone[:count]
          total[:units] += (zone[:count] * @items[zone[:item_index]][:pcs]).to_i
          total[:known_fee] += allocated
        end
      end
      missing = @pallets.flat_map { |pallet| pallet[:missing] }.uniq
      { sku_totals: sku_totals, missing: missing, known_fee: @pallets.sum { |pallet| pallet[:known_fee] },
        total_fee: missing.empty? ? @pallets.sum { |pallet| pallet[:fee] } : nil,
        total_boxes: sku_totals.sum { |row| row[:boxes] }, total_units: sku_totals.sum { |row| row[:units] } }
    end

    private

    def goods_volume(zone)
      item = @items[zone[:item_index]]
      zone[:count] * item[:pcs] * item[:unit_volume_l]
    end

    def sorting_fee(zone, sku_count)
      item = @items[zone[:item_index]]
      volume = item[:unit_volume_l].ceil
      per_unit = case @settings[:sorting]
      when "correction" then [10 * volume, 200].min
      when "zones" then [5 * volume, 200].min
      else
        return 0 if sku_count == 1 || item[:fashion]
        [5 + [volume - 1, 0].max, 60].min
      end
      zone[:count] * item[:pcs] * per_unit
    end
  end
end
