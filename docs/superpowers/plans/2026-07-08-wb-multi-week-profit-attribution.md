# WB Multi-Week Profit Attribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `Ec::WbProfitAttribution` support cross-N-natural-week ad fee cache reuse while preserving exact-period matching and preventing partial-range cache pollution.

**Architecture:** Keep the existing `Ec::WbProfitAttribution` profit chain intact and change only the ad-fee cache resolution path. Add a small period-resolution helper that mirrors Ozon’s exact-period-or-week-pairs strategy, then feed the resolved periods into the existing ad attribution logic.

**Tech Stack:** Rails 8, Minitest, Active Record, existing `RawWb::*` models

---

### Task 1: Add Red Tests For WB Ad Fee Period Resolution

**Files:**
- Create: `test/services/ec/wb_profit_attribution_test.rb`
- Modify: `app/services/ec/wb_profit_attribution.rb`

- [ ] **Step 1: Write the failing tests for exact matching and partial-cache safety**

```ruby
require "test_helper"

class Ec::WbProfitAttributionTest < ActiveSupport::TestCase
  setup do
    unique = SecureRandom.hex(4)
    @account = RawWb::SellerAccount.create!(
      name: "WB Multi Week #{unique}",
      api_token: "token-#{unique}",
      is_active: true,
      company_type: :small
    )
  end

  teardown do
    RawWb::AdSettledFee.where(account_id: @account.id).delete_all
    @account.destroy
  end

  test "resolve_ad_fee_periods returns exact range when cache exists" do
    from = Date.new(2026, 6, 22)
    to = Date.new(2026, 6, 28)
    RawWb::AdSettledFee.create!(account_id: @account.id, advert_id: 101, upd_sum_rub: 10, period_from: from, period_to: to, synced_at: Time.current)

    service = Ec::WbProfitAttribution.new(account_id: @account.id, from_date: from, to_date: to, rate_cny_rub: 10, rate_byn_rub: 3)

    assert_equal [[from, to]], service.send(:resolve_ad_fee_periods)
  end

  test "resolve_ad_fee_periods ignores overlapping partial cache for a full week query" do
    full_from = Date.new(2026, 6, 22)
    full_to = Date.new(2026, 6, 28)
    RawWb::AdSettledFee.create!(account_id: @account.id, advert_id: 101, upd_sum_rub: 10, period_from: Date.new(2026, 6, 23), period_to: Date.new(2026, 6, 25), synced_at: Time.current)

    service = Ec::WbProfitAttribution.new(account_id: @account.id, from_date: full_from, to_date: full_to, rate_cny_rub: 10, rate_byn_rub: 3)

    assert_nil service.send(:resolve_ad_fee_periods)
  end
end
```

- [ ] **Step 2: Run the targeted test file and verify RED**

Run: `bundle exec ruby bin/rails test test/services/ec/wb_profit_attribution_test.rb`

Expected: FAIL with `NoMethodError` for `resolve_ad_fee_periods` or assertion failure showing the current implementation cannot distinguish exact-week cache from overlapping partial cache.

- [ ] **Step 3: Add tests for multi-week exact week-pair resolution**

```ruby
test "resolve_ad_fee_periods returns exact natural week pairs when all weeks exist" do
  first_from = Date.new(2026, 6, 22)
  first_to = Date.new(2026, 6, 28)
  second_from = Date.new(2026, 6, 29)
  second_to = Date.new(2026, 7, 5)

  [[first_from, first_to], [second_from, second_to]].each_with_index do |(from, to), index|
    RawWb::AdSettledFee.create!(account_id: @account.id, advert_id: 200 + index, upd_sum_rub: 10, period_from: from, period_to: to, synced_at: Time.current)
  end
  RawWb::AdSettledFee.create!(account_id: @account.id, advert_id: 999, upd_sum_rub: 5, period_from: Date.new(2026, 6, 23), period_to: Date.new(2026, 6, 25), synced_at: Time.current)

  service = Ec::WbProfitAttribution.new(account_id: @account.id, from_date: first_from, to_date: second_to, rate_cny_rub: 10, rate_byn_rub: 3)

  assert_equal [[first_from, first_to], [second_from, second_to]], service.send(:resolve_ad_fee_periods)
end
```

- [ ] **Step 4: Run the test file again and keep it red for the right reason**

Run: `bundle exec ruby bin/rails test test/services/ec/wb_profit_attribution_test.rb`

Expected: FAIL because `Ec::WbProfitAttribution` still only understands the single exact `@from_date..@to_date` cache path.

- [ ] **Step 5: Commit the red tests**

```bash
git add test/services/ec/wb_profit_attribution_test.rb
git commit -m "test: cover wb multi-week ad fee period resolution"
```

### Task 2: Implement Exact-Period-Or-Week-Pairs Resolution In WB Attribution

**Files:**
- Modify: `app/services/ec/wb_profit_attribution.rb`
- Test: `test/services/ec/wb_profit_attribution_test.rb`

- [ ] **Step 1: Implement the minimal helper methods**

```ruby
def resolve_ad_fee_periods
  exact_scope = RawWb::AdSettledFee.where(
    account_id: @account_id,
    period_from: @from_date,
    period_to: @to_date
  )
  return [[@from_date, @to_date]] if exact_scope.exists?
  return nil unless multi_week_range?

  week_pairs = (((@to_date - @from_date).to_i + 1) / 7).times.map do |index|
    week_from = @from_date + (index * 7)
    [week_from, week_from + 6]
  end

  all_present = week_pairs.all? do |week_from, week_to|
    RawWb::AdSettledFee.where(account_id: @account_id, period_from: week_from, period_to: week_to).exists?
  end

  all_present ? week_pairs : nil
end

def multi_week_range?
  days = (@to_date - @from_date).to_i + 1
  days >= 14 && (days % 7).zero? && @from_date.cwday == 1 && @to_date.cwday == 7
end
```

- [ ] **Step 2: Run the targeted tests and verify GREEN for period resolution**

Run: `bundle exec ruby bin/rails test test/services/ec/wb_profit_attribution_test.rb`

Expected: PASS for the exact-match, multi-week, and partial-cache-safety resolution tests.

- [ ] **Step 3: Refactor only if needed to keep the helper logic local and readable**

```ruby
private

def exact_ad_fee_scope(from_date, to_date)
  RawWb::AdSettledFee.where(account_id: @account_id, period_from: from_date, period_to: to_date)
end
```

- [ ] **Step 4: Re-run the tests after refactor**

Run: `bundle exec ruby bin/rails test test/services/ec/wb_profit_attribution_test.rb`

Expected: PASS with no behavior change.

- [ ] **Step 5: Commit the helper implementation**

```bash
git add app/services/ec/wb_profit_attribution.rb test/services/ec/wb_profit_attribution_test.rb
git commit -m "feat: resolve wb ad fees across full natural weeks"
```

### Task 3: Switch `load_ad_costs` To The Resolved Periods And Prove Exact-Week Merging

**Files:**
- Modify: `app/services/ec/wb_profit_attribution.rb`
- Modify: `test/services/ec/wb_profit_attribution_test.rb`

- [ ] **Step 1: Add a failing behavior test for multi-week fee loading without partial-cache pollution**

```ruby
test "load_ad_costs merges exact weekly fees but ignores overlapping partial cache" do
  first_from = Date.new(2026, 6, 22)
  first_to = Date.new(2026, 6, 28)
  second_from = Date.new(2026, 6, 29)
  second_to = Date.new(2026, 7, 5)

  campaign = Struct.new(:id).new(77)
  fees = [
    Struct.new(:advert_id, :upd_sum_rub).new(1001, 30.0),
    Struct.new(:advert_id, :upd_sum_rub).new(1002, 40.0)
  ]

  service = Ec::WbProfitAttribution.new(account_id: @account.id, from_date: first_from, to_date: second_to, rate_cny_rub: 10, rate_byn_rub: 5)
  service.instance_variable_set(:@rows, [])
  service.instance_variable_set(:@buckets, { [10, Ec::WbProfitAttribution::REPORT_TYPE_BLR] => service.send(:new_bucket).merge(sales_qty: 1) })

  service.define_singleton_method(:resolve_ad_fee_periods) { [[first_from, first_to], [second_from, second_to]] }
  RawWb::AdCampaign.define_singleton_method(:find_by) { |wb_advert_id:| wb_advert_id == 9999 ? nil : campaign }
  RawWb::AdSkuSpend.define_singleton_method(:where) do |campaign_id:|
    RawWb::AdSkuSpend.where(campaign_id: campaign_id)
  end
end
```

- [ ] **Step 2: Run the targeted file and confirm RED**

Run: `bundle exec ruby bin/rails test test/services/ec/wb_profit_attribution_test.rb`

Expected: FAIL because `load_ad_costs` still hardcodes `.where('period_from = ? AND period_to = ?', @from_date, @to_date)`.

- [ ] **Step 3: Replace the single-range fee query with resolved-period OR scope**

```ruby
def load_ad_costs
  pairs = resolve_ad_fee_periods
  return if pairs.blank?

  fees = pairs.reduce(RawWb::AdSettledFee.none) do |scope, (from_date, to_date)|
    scope.or(RawWb::AdSettledFee.where(account_id: @account_id, period_from: from_date, period_to: to_date))
  end.to_a
  return if fees.empty?

  # existing logic continues unchanged
end
```

- [ ] **Step 4: Tighten the test to assert only exact week fees are loaded**

```ruby
loaded_periods = []
original_where = RawWb::AdSettledFee.method(:where)

RawWb::AdSettledFee.define_singleton_method(:where) do |*args|
  relation = original_where.call(*args)
  if args.first.is_a?(Hash) && args.first[:period_from] && args.first[:period_to]
    loaded_periods << [args.first[:period_from], args.first[:period_to]]
  end
  relation
end

service.send(:load_ad_costs)

assert_includes loaded_periods, [first_from, first_to]
assert_includes loaded_periods, [second_from, second_to]
refute_includes loaded_periods, [Date.new(2026, 6, 23), Date.new(2026, 6, 25)]
```

- [ ] **Step 5: Run the test file and verify GREEN**

Run: `bundle exec ruby bin/rails test test/services/ec/wb_profit_attribution_test.rb`

Expected: PASS, proving exact weekly fee merging works and overlapping partial caches are not read.

- [ ] **Step 6: Commit the loading-path change**

```bash
git add app/services/ec/wb_profit_attribution.rb test/services/ec/wb_profit_attribution_test.rb
git commit -m "feat: load wb ad fees from exact natural week caches"
```

### Task 4: Regression Verification And Handoff

**Files:**
- Modify: `app/services/ec/wb_profit_attribution.rb`
- Modify: `test/services/ec/wb_profit_attribution_test.rb`

- [ ] **Step 1: Run the focused WB attribution tests**

Run: `bundle exec ruby bin/rails test test/services/ec/wb_profit_attribution_test.rb`

Expected: PASS

- [ ] **Step 2: Run the existing weekly profit controller tests**

Run: `bundle exec ruby bin/rails test test/controllers/weekly_profit_reports_controller_test.rb`

Expected: PASS

- [ ] **Step 3: Inspect the diff before finalizing**

Run: `git diff -- app/services/ec/wb_profit_attribution.rb test/services/ec/wb_profit_attribution_test.rb docs/superpowers/specs/2026-07-08-wb-multi-week-profit-attribution-design.md`

Expected: Only the WB multi-week resolution changes plus the explicit spec clarification.

- [ ] **Step 4: Commit the final verified state**

```bash
git add app/services/ec/wb_profit_attribution.rb test/services/ec/wb_profit_attribution_test.rb docs/superpowers/specs/2026-07-08-wb-multi-week-profit-attribution-design.md
git commit -m "feat: support wb multi-week ad fee cache resolution"
```
