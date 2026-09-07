module Ec
  class OperatorSkuInventoryDistributionQuery
    CORE_REGIONS = {
      "wb" => %w[Москва Беларусь Белоруссия Белорусь].freeze,
      "ozon" => %w[Россия Российская Федерация Беларусь Белоруссия Белорусь].freeze
    }.freeze

    def initialize(sku_codes:)
      @sku_codes = Array(sku_codes).map { |code| code.to_s.upcase }.uniq
    end

    def call
      return {} if @sku_codes.empty?

      rows = Ec::SkuInventoryLevel.latest.where(sku_code: @sku_codes).to_a
      result = @sku_codes.index_with { empty_result }
      rows.group_by(&:sku_code).each do |sku_code, levels|
        result[sku_code] = build_result(levels)
      end
      result
    end

    private

    def empty_result
      { platforms: {}, warnings: [], freshness: nil }
    end

    def build_result(levels)
      platforms = {}
      warnings = []
      levels.group_by(&:platform).each do |platform, platform_levels|
        buckets = {}
        platform_levels.group_by(&:fulfillment_type).each do |fulfillment, fulfillment_levels|
          total = fulfillment_levels.sum { |level| level.quantity.to_i }
          regions = Hash.new(0)
          mapped = false
          fulfillment_levels.each do |level|
            Array(level.warehouse_breakdown).each do |raw|
              row = raw.to_h.with_indifferent_access
              region = normalized_region(
                platform,
                row[:cluster_name].presence || row[:region_name].presence,
                row[:country_name]
              )
              next unless region

              mapped = true
              regions[region] += row[:quantity].to_i
            end
          end
          buckets[fulfillment] = { total: total, regions: regions }
          if fulfillment == "fbo" && platform_levels.any? && regions.present?
            CORE_REGIONS.fetch(platform, []).each do |name|
              canonical = normalized_region(platform, name)
              warnings << "#{platform}_#{canonical}_out_of_stock" if canonical && regions.fetch(canonical, 0) <= 0
            end
          end
          warnings << "#{platform}_#{fulfillment}_region_unmapped" if fulfillment == "fbo" && total.positive? && !mapped
        end
        platforms[platform] = buckets
      end
      { platforms: platforms, warnings: warnings.uniq, freshness: levels.map(&:synced_at).compact.max }
    end

    def normalized_region(platform, value, country = nil)
      text = value.to_s.strip
      country_text = country.to_s.strip
      combined = "#{country_text} #{text}"
      return "白俄" if combined.match?(/Беларус|Белорус|白俄/i)
      return "俄罗斯" if combined.match?(/Росси|Россия|РФ|俄罗斯/i)
      return "俄罗斯" if platform.to_s == "ozon" && text.present?
      return "俄罗斯" if platform.to_s == "wb" && text.present?
    end
  end
end
