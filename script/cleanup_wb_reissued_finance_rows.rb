# One-off production cleanup (2026-10-19). WRITES to the database.
#
# WB re-issued settlement reports 865217120 / 865217124 (account 2, 2026-10-01..04) under new rrdIds and the
# old sync kept both copies. This replaces the stored rows of those reports for each of the four days by
# what WB lists now: it inserts the current rows and deletes the superseded copy.
#
# It asks WB for each day first and aborts WITHOUT writing anything unless the plan equals the one verified on
# 2026-10-19 (fresh rows per day 540 / 596 / 336 / 948, deletions 540 / 596 / 336 / 948, insertions 540 / 596 / 0 / 0).
# The WB finance endpoint allows one request per minute, so it takes about five minutes.
#
# Run it on production (once):
#   bin/kamal app exec --reuse --roles web "bin/rails runner 'eval(Base64.decode64(\"$(base64 < script/cleanup_wb_reissued_finance_rows.rb | tr -d "\n")\").force_encoding(\"UTF-8\"))'"
IDS = [ 865217120, 865217124 ].freeze
EXPECTED = {
  "2026-10-01" => { fresh: 540, delete: 540, insert: 540 },
  "2026-10-02" => { fresh: 596, delete: 596, insert: 596 },
  "2026-10-03" => { fresh: 336, delete: 336, insert: 0 },
  "2026-10-04" => { fresh: 948, delete: 948, insert: 0 }
}.freeze

acc = RawWb::SellerAccount.find(2)
client = RawWb::WbClient.new(acc.api_token)
sync = RawWb::WeeklySync.new(acc, days: 1)
plan = {}
EXPECTED.keys.each_with_index do |day, index|
  sleep 65 if index.positive?
  items = []
  cursor = 0
  loop do
    response = client.post(:finance, "/api/finance/v1/sales-reports/detailed", { dateFrom: day, dateTo: day, limit: 1000, rrdid: cursor })
    page = response.is_a?(Array) ? response : Array(response["data"] || response["items"] || response)
    break if page.empty?

    items.concat(page)
    cursor = page.last["rrdId"].to_i
    break if page.size < 1000

    sleep 65
  end
  rows = items.filter_map { |item| sync.send(:build_finance_detail, item) }
  fresh_ids = rows.map { |row| row[:rrdid] }.to_set
  in_scope = rows.select { |row| IDS.include?(row[:wb_report_id].to_i) }
  existing = RawWb::FinanceDetail.where(account_id: 2, wb_report_id: IDS, rr_dt: Date.parse(day)).to_a
  stored_ids = existing.map(&:rrdid).to_set
  stale = existing.reject { |row| fresh_ids.include?(row.rrdid) }
  insert = in_scope.reject { |row| stored_ids.include?(row[:rrdid]) }
  plan[day] = { rows: rows, in_scope: in_scope, stale_ids: stale.map(&:id), insert: insert }
  puts "#{day}: WB lists #{rows.size} rows (in the two reports: #{in_scope.size}); stored #{existing.size}; to delete #{stale.size}; to insert #{insert.size}"
end

verified = EXPECTED.all? do |day, expected|
  entry = plan[day]
  entry[:in_scope].size == expected[:fresh] && entry[:rows].size == expected[:fresh] &&
    entry[:stale_ids].size == expected[:delete] && entry[:insert].size == expected[:insert]
end
abort("PLAN DIFFERS FROM THE VERIFIED ONE - nothing written") unless verified

puts "plan matches the verified one; applying"
update_only = %i[
  for_pay acquiring_fee delivery_rub vw penalty rebill_logistic_cost ppvz_reward retail_price_with_disc retail_amount
  commission_percent quantity country office_name ppvz_office_name delivery_method bonus_type_name paid_storage deduction
  additional_payment wb_report_id rr_dt synced_at
]
plan.each do |day, entry|
  RawWb::FinanceDetail.transaction do
    if entry[:in_scope].any?
      RawWb::FinanceDetail.upsert_all(entry[:in_scope], unique_by: :idx_raw_wb_finance_details_unique, update_only: update_only)
    end
    deleted = RawWb::FinanceDetail.where(id: entry[:stale_ids]).delete_all
    puts "#{day}: upserted #{entry[:in_scope].size}, deleted #{deleted}"
  end
end
puts "applied at #{Time.now.utc}"
