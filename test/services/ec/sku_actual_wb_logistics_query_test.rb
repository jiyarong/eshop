require "test_helper"

class Ec::SkuActualWbLogisticsQueryTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(6).upcase
    @sku = Ec::Sku.create!(sku_code: "ACT-WB-LOG-#{@token}")
    @account = RawWb::SellerAccount.create!(
      api_token: "key-#{@token}",
      name: "Actual WB logistics #{@token}",
      company_type: "general"
    )
    @store = Ec::Store.create!(
      platform: "wb",
      store_name: "Actual WB logistics #{@token}",
      company_type: "general",
      wb_raw_account_id: @account.id
    )
    @nm_id = rand(20_000_000..29_999_999)
    @product = Ec::SkuProduct.create!(
      sku_code: @sku.sku_code,
      store: @store,
      product_id: @nm_id.to_s
    )
    @day = Date.new(2099, 9, 1)
    @rate = Ec::WeeklyRate.create!(
      week_start: @day.beginning_of_week(:monday),
      rate_cny_rub: 10,
      rate_byn_rub: 25
    )
  end

  teardown do
    RawWb::FinanceDetail.where(account_id: @account.id).delete_all
    @rate.delete
    Ec::OperationLog.where(record_type: "Ec::SkuProduct", record_id: @product.id).delete_all
    Ec::OperationLog.where(record_type: "Ec::Store", record_id: @store.id).delete_all
    Ec::OperationLog.where(record_type: "Ec::Sku", record_id: @sku.id).delete_all
    @product.delete
    @store.delete
    @account.delete
    Ec::Sku.with_deleted.where(id: @sku.id).delete_all
  end

  test "converts WB settlement logistics to RUB and averages by shipment" do
    day = @day
    create_logistics(day:, srid: "OUT-1", bonus: "К клиенту при продаже", amount: 10)
    create_logistics(day:, srid: "OUT-1", bonus: "К клиенту при продаже", amount: 2)
    create_logistics(day:, srid: "OUT-1", bonus: "К клиенту при продаже", amount: -1, operation: "Коррекция логистики")
    create_logistics(day:, srid: "OUT-2", bonus: "К клиенту при отмене", amount: 8)
    create_logistics(day:, srid: "RET-1", bonus: "От клиента при возврате", amount: 1)
    create_logistics(day:, srid: "RET-1", bonus: "От клиента при возврате", amount: 0.5)
    create_logistics(day:, srid: "RET-2", bonus: "От клиента при отмене", amount: 2)
    create_logistics(day:, srid: "IGNORED", bonus: "Возврат товара продавцу (К продавцу)", amount: 9)
    create_logistics(day:, srid: "WRONG-MODE", bonus: "К клиенту при продаже", amount: 100, delivery_method: "FBS, (МГТ)")
    create_logistics(day: day - 10, srid: "OUTSIDE", bonus: "К клиенту при продаже", amount: 100)
    create_logistics(day:, srid: "OTHER-SKU", bonus: "К клиенту при продаже", amount: 100, nm_id: @nm_id + 1)

    payload = Ec::SkuActualLogisticsQuery.run(
      sku: @sku,
      platform: "wb",
      delivery_mode: "fbo",
      today: day.beginning_of_week(:monday) + 4.weeks
    )

    assert_equal "wb", payload[:platform]
    assert_equal "BYN", payload[:source_currency]
    assert_equal "RUB", payload[:output_currency]
    assert_equal 1, payload[:store_count]
    assert_equal 1, payload[:listing_count]
    assert_equal({ total_rub: 475.to_d, sample_count: 2, average_rub: 237.5.to_d }, payload[:outbound])
    assert_equal({ total_rub: 87.5.to_d, sample_count: 2, average_rub: 43.75.to_d }, payload[:return])
    assert_equal 0, payload[:missing_exchange_rate_row_count]

    fbs_payload = Ec::SkuActualLogisticsQuery.run(
      sku: @sku,
      platform: "wb",
      delivery_mode: "fbs",
      today: day.beginning_of_week(:monday) + 4.weeks
    )
    assert_equal({ total_rub: 2_500.to_d, sample_count: 1, average_rub: 2_500.to_d }, fbs_payload[:outbound])
    assert_equal({ total_rub: 0.to_d, sample_count: 0, average_rub: nil }, fbs_payload[:return])
  end

  private

  def create_logistics(day:, srid:, bonus:, amount:, nm_id: @nm_id, delivery_method: "FBW, (МГТ, короба)", operation: "Логистика")
    RawWb::FinanceDetail.create!(
      account: @account,
      nm_id:,
      rrdid: rand(1_000_000_000..9_999_999_999),
      rr_dt: day,
      sale_dt: day,
      srid:,
      seller_oper_name: operation,
      bonus_type_name: bonus,
      delivery_method:,
      delivery_rub: amount
    )
  end
end
