namespace :ec do
  namespace :inventory do
    desc "Report raw orders and postings that never became orders (read only)"
    task completeness: :environment do
      result = Ec::Inventory::OrderCompleteness.call
      result.each { |key, count| puts "#{key}: #{count}" }
      puts(result.values.all?(&:zero?) ? "OK" : "MISSING ORDERS")
    end
  end
end
