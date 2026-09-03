module ErpAI
  class SkuProductAttributesQuery
    DEFAULT_LIMIT = 100
    MAX_LIMIT = 500
    PROMOTED_ATTRIBUTE_IDS = %w[4191 21841].freeze
    DESCRIPTION_ATTRIBUTE_ID = "4191"
    RICH_CONTENT_ATTRIBUTE_ID = "11254"

    SQL = <<~SQL.freeze
      WITH sku_bindings AS (
        SELECT
          sp.platform,
          sp.product_id,
          sp.platform_sku_id,
          sp.offer_id,
          sp.product_name AS bound_product_name,
          st.store_name,
          st.wb_raw_account_id,
          st.ozon_raw_account_id
        FROM ec_skus sk
        INNER JOIN ec_sku_products sp ON sp.sku_code = sk.sku_code
        INNER JOIN ec_stores st ON st.id = sp.store_id
        WHERE sk.sku_code = $1
          AND sk.deleted_at IS NULL
      ),
      all_platform_products AS (
        SELECT
          b.*,
          p.name AS platform_product_name,
          COALESCE(p.raw_json ->> 'description', a.raw_json ->> 'description') AS product_description,
          p.raw_json -> 'primary_image' AS primary_image_data,
          p.images AS image_data,
          p.images360 AS image_360_data,
          NULL::jsonb AS platform_video_data,
          p.is_archived,
          a.product_attributes,
          a.complex_attributes,
          p.ozon_product_id IS NOT NULL AS source_found,
          NULL::jsonb AS wb_product_info
        FROM sku_bindings b
        LEFT JOIN raw_ozon_products p
          ON p.account_id = b.ozon_raw_account_id
         AND p.ozon_product_id::text = b.product_id
        LEFT JOIN raw_ozon_product_attributes a
          ON a.account_id = b.ozon_raw_account_id
         AND a.ozon_product_id::text = b.product_id
        WHERE b.platform = 'ozon'

        UNION ALL

        SELECT
          b.*,
          p.title AS platform_product_name,
          p.description AS product_description,
          NULL::jsonb AS primary_image_data,
          COALESCE(wb_media.image_urls, '[]'::jsonb) AS image_data,
          NULL::jsonb AS image_360_data,
          COALESCE(wb_media.video_urls, '[]'::jsonb) AS platform_video_data,
          p.is_in_trash AS is_archived,
          COALESCE(wb_attributes.items, '[]'::jsonb) AS product_attributes,
          NULL::jsonb AS complex_attributes,
          p.nm_id IS NOT NULL AS source_found,
          CASE WHEN p.nm_id IS NULL THEN NULL ELSE jsonb_build_object(
            'brand', p.brand,
            'subject_name', p.subject_name,
            'category', p.wb_category
          ) END AS wb_product_info
        FROM sku_bindings b
        LEFT JOIN raw_wb_products p
          ON p.account_id = b.wb_raw_account_id
         AND p.nm_id::text = b.product_id
        LEFT JOIN LATERAL (
          SELECT jsonb_agg(
            jsonb_build_object('name', characteristic.charc_name, 'value', characteristic.value)
            ORDER BY characteristic.id
          ) AS items
          FROM raw_wb_product_characteristics characteristic
          WHERE characteristic.product_id = p.id
        ) wb_attributes ON true
        LEFT JOIN LATERAL (
          SELECT
            jsonb_agg(medium.url ORDER BY medium.position, medium.id)
              FILTER (WHERE medium.media_type = 'image' AND medium.url IS NOT NULL AND btrim(medium.url) <> '') AS image_urls,
            jsonb_agg(medium.url ORDER BY medium.position, medium.id)
              FILTER (WHERE medium.media_type = 'video' AND medium.url IS NOT NULL AND btrim(medium.url) <> '') AS video_urls
          FROM raw_wb_product_media medium
          WHERE medium.product_id = p.id
        ) wb_media ON true
        WHERE b.platform = 'wb'
      )
      SELECT *
      FROM all_platform_products
      ORDER BY platform, store_name, product_id
      LIMIT $2 OFFSET $3
    SQL

    def initialize(sku_code:, limit: DEFAULT_LIMIT, offset: 0)
      @sku_code = sku_code
      @limit = limit
      @offset = offset
    end

    def call
      sku = Ec::Sku.find_by!(sku_code: sku_code)
      rows = execute_query.to_a
      listings = rows.map { |row| serialize(row.with_indifferent_access) }

      {
        success: true,
        sku: sku_payload(sku),
        listings: listings
      }
    end

    private

    attr_reader :sku_code, :limit, :offset

    def execute_query
      binds = [
        query_attribute("sku_code", sku_code, ActiveRecord::Type::String.new),
        query_attribute("limit", limit, ActiveRecord::Type::Integer.new),
        query_attribute("offset", offset, ActiveRecord::Type::Integer.new)
      ]
      ActiveRecord::Base.connection.exec_query(SQL, self.class.name, binds)
    end

    def query_attribute(name, value, type)
      ActiveRecord::Relation::QueryAttribute.new(name, value, type)
    end

    def serialize(row)
      source_found = ActiveModel::Type::Boolean.new.cast(row[:source_found])
      archived = ActiveModel::Type::Boolean.new.cast(row[:is_archived])

      {
        platform: row[:platform],
        store: row[:store_name],
        name: row[:platform_product_name].presence || row[:bound_product_name],
        description: product_description(row),
        status: product_status(source_found:, archived:),
        image_urls: product_image_urls(row),
        image_360_urls: media_urls(row[:image_360_data]),
        video_urls: video_urls(row),
        attributes: attribute_text(row)
      }.compact_blank
    end

    def sku_payload(sku)
      payload = {
        sku_code: sku.sku_code,
        product_name: sku.product_name,
        product_name_ru: sku.product_name_ru,
        specifications: specification_text(sku)
      }.compact_blank
      payload[:product_info] = product_info(sku)
      payload
    end

    def specification_text(sku)
      [
        [ "Color", sku.color ],
        [ "Size", sku.size ],
        [ "Model", sku.model ],
        [ "Specification", sku.spec ],
        [ "Features", sku.features ],
        [ "Weight", formatted_measure(sku.weight_kg, "kg") ],
        [ "Volume", formatted_measure(sku.volume_l, "L") ]
      ].filter_map { |name, value| "#{name}: #{value}" if value.present? }.join("\n")
    end

    def formatted_measure(value, unit)
      "#{value.to_s("F")} #{unit}" if value
    end

    def product_info(sku)
      return sku.product_info if sku.product_info.present?
      return unless sku.master_sku

      sku.master_sku.skus
        .where.not(id: sku.id)
        .where("char_length(btrim(product_info)) > ?", 20)
        .order(Arel.sql("char_length(product_info) DESC"), :id)
        .pick(:product_info)
    end

    def product_status(source_found:, archived:)
      return "source_not_found" unless source_found

      archived ? "archived_or_trashed" : "active"
    end

    def array_value(value)
      parsed = parsed_json(value)
      return parsed if parsed.is_a?(Array)
      return postgres_array(value) if value.is_a?(String)

      []
    end

    def parsed_json(value)
      value.is_a?(String) ? JSON.parse(value) : value
    rescue JSON::ParserError
      nil
    end

    def postgres_array(value)
      PG::TextDecoder::Array.new.decode(value)
    rescue TypeError, ArgumentError
      []
    end

    def media_urls(value)
      array_value(value).filter_map do |media|
        case media
        when String
          media.presence
        when Hash
          media["default"] || media[:default] || media["original"] || media[:original] || media["url"] || media[:url]
        end
      end.uniq
    end

    def product_image_urls(row)
      (
        media_urls(row[:primary_image_data]) +
        media_urls(row[:image_data]) +
        rich_content_image_urls(row[:product_attributes])
      ).uniq
    end

    def rich_content_image_urls(attributes)
      entry = flattened_attributes(attributes).find do |attribute|
        attribute["id"].to_s == RICH_CONTENT_ATTRIBUTE_ID
      end
      attribute_values(entry).flat_map do |value|
        nested_urls(parsed_json(value), keys: %w[src srcMobile])
      end.uniq
    end

    def nested_urls(value, keys:)
      case value
      when Array
        value.flat_map { |item| nested_urls(item, keys:) }
      when Hash
        value.flat_map do |key, item|
          if keys.include?(key.to_s) && item.is_a?(String) && item.match?(%r{\Ahttps?://}i)
            item
          else
            nested_urls(item, keys:)
          end
        end
      else
        []
      end
    end

    def video_urls(row)
      attribute_urls = all_attribute_values(row).filter_map do |value|
        value if value.match?(%r{\Ahttps?://}i) && value.match?(/\.mp4(?:\?|\z)/i)
      end
      (media_urls(row[:platform_video_data]) + attribute_urls).uniq
    end

    def product_description(row)
      value = row[:product_description].presence || attribute_value(row[:product_attributes], DESCRIPTION_ATTRIBUTE_ID)
      plain_text(value)
    end

    def plain_text(value)
      return if value.blank?

      fragment = Nokogiri::HTML.fragment(value.to_s)
      fragment.css("br").each { |node| node.replace("\n") }
      fragment.text.lines.map(&:strip).reject(&:blank?).join("\n")
    end

    def attribute_text(row)
      wb_attributes = parsed_json(row[:wb_product_info]).to_h
      lines = [
        attribute_line("Brand", wb_attributes["brand"]),
        attribute_line("Subject", wb_attributes["subject_name"]),
        attribute_line("Category", wb_attributes["category"])
      ]
      lines.concat(attribute_entries(row[:product_attributes]))
      lines.concat(attribute_entries(row[:complex_attributes]))
      lines.concat(description_attribute_lines(product_description(row))) if row[:platform] == "ozon" && lines.compact_blank.empty?
      lines.compact_blank.uniq.join("\n")
    end

    def description_attribute_lines(description)
      description.to_s.lines.filter_map do |line|
        match = line.strip.match(/\A[•·▪-]\s*([^:]{2,80}):\s*(.+)\z/)
        attribute_line(match[1].strip, match[2].strip) if match
      end
    end

    def attribute_entries(value)
      array_value(value).flat_map do |attribute|
        next unless attribute.respond_to?(:with_indifferent_access)

        attribute = attribute.with_indifferent_access
        nested = attribute[:attributes]
        next attribute_entries(nested) if nested.is_a?(Array)
        next if PROMOTED_ATTRIBUTE_IDS.include?(attribute[:id].to_s)

        name = attribute[:name].to_s.strip
        values = if attribute[:id].to_s == RICH_CONTENT_ATTRIBUTE_ID
          attribute_values(attribute).filter_map { |item| rich_content_text(item) }
        else
          attribute_values(attribute)
        end
        attribute_line(name, values.join(", "))
      end.compact_blank
    end

    def rich_content_text(value)
      parts = nested_text_values(parsed_json(value)).map { |item| item.gsub(/\s+/, " ").strip }.compact_blank
      parts.uniq.join(" | ").presence
    end

    def nested_text_values(value)
      case value
      when Array
        value.flat_map { |item| nested_text_values(item) }
      when Hash
        value.flat_map do |key, item|
          key.to_s == "content" && item.is_a?(String) ? item : nested_text_values(item)
        end
      else
        []
      end
    end

    def attribute_line(name, value)
      "#{name}: #{value}" if name.present? && value.present?
    end

    def attribute_value(attributes, id)
      entry = flattened_attributes(attributes).find { |attribute| attribute["id"].to_s == id }
      attribute_values(entry).first
    end

    def all_attribute_values(row)
      flattened_attributes(row[:product_attributes])
        .concat(flattened_attributes(row[:complex_attributes]))
        .flat_map { |attribute| attribute_values(attribute) }
    end

    def flattened_attributes(value)
      array_value(value).flat_map do |attribute|
        next [] unless attribute.is_a?(Hash)

        nested = attribute["attributes"] || attribute[:attributes]
        [ attribute ] + (nested.is_a?(Array) ? flattened_attributes(nested) : [])
      end
    end

    def attribute_values(attribute)
      return [] unless attribute.is_a?(Hash)

      raw_values = if attribute.key?("values") || attribute.key?(:values)
        attribute["values"] || attribute[:values]
      else
        attribute["value"] || attribute[:value]
      end
      values = raw_values.is_a?(Array) ? raw_values : [ raw_values ]
      values.filter_map do |item|
        value = item.is_a?(Hash) ? (item["value"] || item[:value]) : item
        value.to_s if value.present?
      end.uniq
    end
  end
end
