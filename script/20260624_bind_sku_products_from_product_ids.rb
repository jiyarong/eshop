#!/usr/bin/env ruby

require_relative "../config/environment"


OZON_PRODUCTS = [["2438523273", "JZDJ-WS"],
                 ["4117782311", "JD-ZQTB-206"],
                 ["2439483003", "JZDJ-YS"],
                 ["5000511131", "KJ-207-GD"],
                 ["5011653566", "KJ-207-GY"],
                 ["5011486096", "KJ-207-WT"],
                 ["4969902127", "LDD001-BK"],
                 ["3250554661", "JD-ZQTB310"],
                 ["3424455479", "JZDJ-YS"],
                 ["3692656462", "JXZ-WHITE-02"],
                 ["3042358112", "JD-ZQTB-206"],
                 ["3047471278", "JD-ZQTB310"],
]
WB_PRODUCTS = [["1139480385", "KJ-207-GD"],
               ["1140839385", "KJ-207-GY"],
               ["1140839384", "KJ-207-WT"],
               ["1032191800", "KJ-217-GD"],
               ["1135117446", "LDD001-BK"],
               ["1055556351", "JD-ZQTB-206"],
               ["492137717", "JDCCJ-01"],
               ["742734723", "JDCCJ-01"],
               ["742522297", "JDCCJ-01"],
               ["492548473", "JZDJ-WS"],
               ["492254706", "JZDJ-YS"],
               ["1055716692", "KJ-217-GD"],
               ["588933803", "JD-ZQTB-206"],
               ["591080060", "JD-ZQTB310"],
               ["591143155", "JD-ZQTB310"],
               ["589000449", "JD-ZQTB-206"]]


Result = Data.define(:created, :skipped, :conflicts, :missing_skus, :missing_products, :missing_stores)

def bind_products(platform, pairs)
  pairs.each_with_object(Result.new(created: [], skipped: [], conflicts: [], missing_skus: [], missing_products: [], missing_stores: [])) do |(product_id, sku_code), result|
    normalized_product_id = product_id.to_s.strip
    normalized_sku_code = sku_code.to_s.strip.upcase

    sku = Ec::Sku.find_by(sku_code: normalized_sku_code)
    unless sku
      result.missing_skus << [platform, normalized_product_id, normalized_sku_code]
      next
    end

    products = raw_products(platform, normalized_product_id).to_a
    if products.empty?
      result.missing_products << [platform, normalized_product_id, normalized_sku_code]
      next
    end

    products.each do |product|
      store = store_for(platform, product.account_id)
      unless store
        result.missing_stores << [platform, normalized_product_id, normalized_sku_code, product.account_id]
        next
      end

      attributes = sku_product_attributes(platform, store, product, sku.sku_code)
      existing = Ec::SkuProduct.find_by(store: store, product_id: attributes.fetch(:product_id))

      if existing&.sku_code == sku.sku_code
        result.skipped << [platform, store.store_name, normalized_product_id, sku.sku_code]
      elsif existing
        result.conflicts << [platform, store.store_name, normalized_product_id, sku.sku_code, existing.sku_code]
      else
        Ec::SkuProduct.create!(attributes)
        result.created << [platform, store.store_name, normalized_product_id, sku.sku_code]
      end
    end
  end
end

def raw_products(platform, product_id)
  case platform
  when "ozon"
    RawOzon::Product.where(ozon_product_id: product_id)
  when "wb"
    RawWb::Product.where(nm_id: product_id)
  else
    raise ArgumentError, "Unsupported platform: #{platform}"
  end
end

def store_for(platform, account_id)
  case platform
  when "ozon"
    Ec::Store.active.find_by(platform: "ozon", ozon_raw_account_id: account_id)
  when "wb"
    Ec::Store.active.find_by(platform: "wb", wb_raw_account_id: account_id)
  else
    raise ArgumentError, "Unsupported platform: #{platform}"
  end
end

def sku_product_attributes(platform, store, product, sku_code)
  case platform
  when "ozon"
    {
      sku_code: sku_code,
      store: store,
      product_id: product.ozon_product_id.to_s,
      offer_id: product.offer_id,
      platform_sku_id: product.raw_json&.dig("sku").to_s.presence,
      product_name: product.name
    }
  when "wb"
    {
      sku_code: sku_code,
      store: store,
      product_id: product.nm_id.to_s,
      offer_id: product.vendor_code,
      product_name: product.title
    }
  else
    raise ArgumentError, "Unsupported platform: #{platform}"
  end
end

def merge_results(*results)
  Result.members.to_h do |member|
    [member, results.flat_map { |result| result.public_send(member) }]
  end.then { |values| Result.new(**values) }
end

def print_rows(title, rows, columns)
  puts "#{title}: #{rows.size}"
  rows.each do |row|
    puts "  #{columns.zip(row).map { |column, value| "#{column}=#{value}" }.join(", ")}"
  end
end

result = merge_results(
  bind_products("ozon", OZON_PRODUCTS),
  bind_products("wb", WB_PRODUCTS)
)

print_rows("Created", result.created, %w[platform store product_id sku_code])
print_rows("Skipped existing", result.skipped, %w[platform store product_id sku_code])
print_rows("Conflicts", result.conflicts, %w[platform store product_id target_sku existing_sku])
print_rows("Missing SKUs", result.missing_skus, %w[platform product_id sku_code])
print_rows("Missing raw products", result.missing_products, %w[platform product_id sku_code])
print_rows("Missing stores", result.missing_stores, %w[platform product_id sku_code account_id])
