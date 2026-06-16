#!/usr/bin/env ruby

require_relative "../config/environment"

result = Ec::SkuProductAutoBinder.call

puts "Created: #{result.created_count}"
puts "Skipped existing: #{result.skipped_count}"
