require "test_helper"

class Ec::CapitalDistributionProfitQueryTest < ActiveSupport::TestCase
  setup do
    @first_week = Date.new(2099, 1, 1).beginning_of_week(:monday)
    @second_week = @first_week + 1.week
    @sku = Ec::Sku.create!(sku_code: "SKU-A-#{SecureRandom.hex(4).upcase}")
    Ec::SkuCost.create!(
      sku_code: @sku.sku_code,
      effective_on: @first_week,
      purchase_price_cny: 20,
      freight_to_by_cny: 10,
      customs_misc_cny: 10,
      customs_duty_rate: BigDecimal("0.25"),
      import_vat_rate: BigDecimal("0.2")
    )
    Ec::WeeklyRate.create!(week_start: @first_week, rate_cny_rub: 10, rate_byn_rub: 30)
  end

  teardown do
    Ec::WeeklyRate.where(week_start: [ @first_week, @second_week ]).delete_all
    cost_ids = Ec::SkuCost.where(sku_code: @sku.sku_code).pluck(:id)
    Ec::OperationLog.where(record_type: "Ec::SkuCost", record_id: cost_ids).delete_all
    Ec::SkuCost.where(id: cost_ids).delete_all
    Ec::Sku.with_deleted.where(id: @sku.id).delete_all
  end

  test "aggregates completed weekly profit rows and reports weeks without an exact rate" do
    fake_query = Class.new do
      class << self
        attr_accessor :calls
      end
      self.calls = []

      define_method(:initialize) do |**attributes|
        @attributes = attributes
        self.class.calls << attributes
      end

      define_method(:run) do
        {
          summary: { unallocated_total: BigDecimal("-7.5") },
          rows: [
            {
              sku: @attributes.fetch(:sku_codes).first,
              net_sales: 3,
              revenue: BigDecimal("120"),
              goods_cost: BigDecimal("45"),
              after_tax: BigDecimal("20")
            }
          ]
        }
      end
    end

    result = Ec::CapitalDistributionProfitQuery.new(
      sku_codes: [ @sku.sku_code.downcase ],
      from_date: @first_week,
      to_date: @second_week.end_of_week(:monday),
      as_of_date: @second_week.end_of_week(:monday) + 1.day,
      weekly_summary_query: fake_query,
      week_starts: [ @first_week, @second_week ]
    ).call

    assert_equal [ @first_week ], fake_query.calls.map { |call| call[:from_date] }
    assert_equal [ @second_week ], result[:missing_week_starts]
    assert_equal @first_week, result[:period_from]
    assert_equal @first_week.end_of_week(:monday), result[:period_to]
    assert_equal BigDecimal("-7.5"), result[:unallocated_total_cny]
    metrics = result.dig(:rows_by_sku, @sku.sku_code)
    assert_equal 3, metrics[:net_sales_quantity]
    assert_equal BigDecimal("120"), metrics[:sales_revenue_cny]
    assert_equal BigDecimal("27"), metrics[:sold_goods_cost_cny]
    assert_equal BigDecimal("18"), metrics[:sold_customs_tax_cost_cny]
    assert_equal BigDecimal("45"), metrics[:goods_cost_cny]
    assert_equal metrics[:goods_cost_cny], metrics[:sold_goods_cost_cny] + metrics[:sold_customs_tax_cost_cny]
    assert_equal BigDecimal("20"), metrics[:net_profit_cny]
  end

  test "preserves negative weekly goods cost when splitting returns" do
    fake_query = Class.new do
      define_method(:initialize) { |**attributes| @attributes = attributes }
      define_method(:run) do
        {
          rows: [
            {
              sku: @attributes.fetch(:sku_codes).first,
              net_sales: -1,
              revenue: BigDecimal("-30"),
              goods_cost: BigDecimal("-12.34"),
              after_tax: BigDecimal("-4")
            }
          ]
        }
      end
    end

    result = Ec::CapitalDistributionProfitQuery.new(
      sku_codes: [ @sku.sku_code ],
      from_date: @first_week,
      to_date: @first_week.end_of_week(:monday),
      as_of_date: @first_week.end_of_week(:monday) + 1.day,
      weekly_summary_query: fake_query,
      week_starts: [ @first_week ]
    ).call

    metrics = result.dig(:rows_by_sku, @sku.sku_code)
    assert_equal BigDecimal("-7.4"), metrics[:sold_goods_cost_cny]
    assert_equal BigDecimal("-4.94"), metrics[:sold_customs_tax_cost_cny]
    assert_equal BigDecimal("-12.34"), metrics[:goods_cost_cny]
    assert_equal metrics[:goods_cost_cny], metrics[:sold_goods_cost_cny] + metrics[:sold_customs_tax_cost_cny]
  end

  test "only queries completed natural weeks fully inside the selected range" do
    Ec::WeeklyRate.create!(week_start: @second_week, rate_cny_rub: 10, rate_byn_rub: 30)
    fake_query = Class.new do
      class << self
        attr_accessor :calls
      end
      self.calls = []

      define_method(:initialize) do |**attributes|
        self.class.calls << attributes
      end

      define_method(:run) { { summary: { unallocated_total: 0 }, rows: [] } }
    end

    Ec::CapitalDistributionProfitQuery.new(
      sku_codes: [ @sku.sku_code ],
      from_date: @first_week + 1.day,
      to_date: @second_week.end_of_week(:monday),
      as_of_date: @second_week.end_of_week(:monday) + 1.day,
      weekly_summary_query: fake_query,
      week_starts: [ @first_week, @second_week, @second_week + 1.week ]
    ).call

    assert_equal [ @second_week ], fake_query.calls.map { |call| call[:from_date] }
    assert_equal [ @second_week.end_of_week(:monday) ], fake_query.calls.map { |call| call[:to_date] }
  end
end
