# frozen_string_literal: true

# Rewrites shipped_at of existing Ozon FBS fulfillments from the posting's delivering_date.
# Idempotent; prints how many fulfillments changed.
#
# Usage:
#   bundle exec rails runner script/backfill_ozon_fbs_shipped_at.rb

puts "Ozon FBS fulfillments updated: #{Ec::OrderImport::OzonShippedAt.call}"
