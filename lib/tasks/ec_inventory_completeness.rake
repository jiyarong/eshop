namespace :ec do
  namespace :inventory do
    desc "Report raw orders and postings that never became orders (read only)"
    task completeness: :environment do
      result = Ec::Inventory::OrderCompleteness.call
      result.each { |key, count| puts "#{key}: #{count}" }
      # Informational only: unattributed products do not affect the verdict below.
      unattributed = Ec::Inventory::OrderCompleteness.unattributed_summary(limit: 10)
      puts "unattributed_quantity: #{unattributed[:quantity]}"
      puts "unattributed_products: #{unattributed[:products]}"
      unattributed[:top].each do |row|
        puts "  #{row[:platform]} #{row[:platform_sku_id]} #{row[:quantity]}"
      end
      puts(result.values.all?(&:zero?) ? "OK" : "MISSING ORDERS")
    end
  end
end
