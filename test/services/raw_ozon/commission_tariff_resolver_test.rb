require "test_helper"
require "securerandom"

class RawOzon::CommissionTariffResolverTest < ActiveSupport::TestCase
  setup do
    @account = RawOzon::SellerAccount.create!(
      client_id: "client-#{SecureRandom.hex(4)}",
      api_key: "key-#{SecureRandom.hex(6)}",
      company_type: "general"
    )
    @product_id = rand(1_000_000..9_999_999)
  end

  teardown do
    RawOzon::ProductPrice.where(account_id: @account.id).delete_all
    RawOzon::SellerAccount.where(id: @account.id).delete_all
  end

  def create_price(commissions:)
    RawOzon::ProductPrice.create!(
      account: @account,
      ozon_product_id: @product_id,
      raw_json: {},
      commissions: commissions
    )
  end

  test "reads all four sales_percent_* fields as decimal fractions" do
    create_price(commissions: {
      "sales_percent_fbo" => 51, "sales_percent_fbp" => 48,
      "sales_percent_fbs" => 45, "sales_percent_rfbs" => 40
    })

    resolver = RawOzon::CommissionTariffResolver.new
    assert_equal BigDecimal("0.51"), resolver.rate_for(account_id: @account.id, ozon_product_id: @product_id, delivery_mode: "fbo")
    assert_equal BigDecimal("0.48"), resolver.rate_for(account_id: @account.id, ozon_product_id: @product_id, delivery_mode: "fbp")
    assert_equal BigDecimal("0.45"), resolver.rate_for(account_id: @account.id, ozon_product_id: @product_id, delivery_mode: "fbs")
    assert_equal BigDecimal("0.40"), resolver.rate_for(account_id: @account.id, ozon_product_id: @product_id, delivery_mode: "rfbs")
  end

  test "isolates commissions by account_id and ozon_product_id" do
    create_price(commissions: { "sales_percent_fbo" => 51 })
    other_account = RawOzon::SellerAccount.create!(
      client_id: "other-#{SecureRandom.hex(4)}", api_key: "otherkey-#{SecureRandom.hex(6)}", company_type: "general"
    )

    begin
      resolver = RawOzon::CommissionTariffResolver.new
      error = assert_raises(RawOzon::CommissionTariffResolver::ResolutionError) do
        resolver.rate_for(account_id: other_account.id, ozon_product_id: @product_id, delivery_mode: "fbo")
      end
      assert_equal :missing_commission_rate, error.code
    ensure
      RawOzon::SellerAccount.where(id: other_account.id).delete_all
    end
  end

  test "raises missing_commission_rate instead of defaulting to zero when the field is absent" do
    create_price(commissions: { "sales_percent_fbs" => 45 })

    resolver = RawOzon::CommissionTariffResolver.new
    error = assert_raises(RawOzon::CommissionTariffResolver::ResolutionError) do
      resolver.rate_for(account_id: @account.id, ozon_product_id: @product_id, delivery_mode: "fbo")
    end
    assert_equal :missing_commission_rate, error.code
  end

  test "rejects negative and non-numeric commission rates" do
    resolver = RawOzon::CommissionTariffResolver.new

    create_price(commissions: { "sales_percent_fbo" => -1 })
    error = assert_raises(RawOzon::CommissionTariffResolver::ResolutionError) do
      resolver.rate_for(account_id: @account.id, ozon_product_id: @product_id, delivery_mode: "fbo")
    end
    assert_equal :invalid_commission_rate, error.code

    RawOzon::ProductPrice.where(account_id: @account.id, ozon_product_id: @product_id).delete_all
    create_price(commissions: { "sales_percent_fbo" => "not-a-number" })
    error = assert_raises(RawOzon::CommissionTariffResolver::ResolutionError) do
      resolver.rate_for(account_id: @account.id, ozon_product_id: @product_id, delivery_mode: "fbo")
    end
    assert_equal :invalid_commission_rate, error.code
  end

  test "raises unsupported_delivery_mode for an unmapped mode" do
    create_price(commissions: { "sales_percent_fbo" => 51 })
    resolver = RawOzon::CommissionTariffResolver.new
    error = assert_raises(RawOzon::CommissionTariffResolver::ResolutionError) do
      resolver.rate_for(account_id: @account.id, ozon_product_id: @product_id, delivery_mode: "dbs")
    end
    assert_equal :unsupported_delivery_mode, error.code
  end
end
