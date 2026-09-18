require "test_helper"
require "securerandom"

class RawWb::CommissionTariffResolverTest < ActiveSupport::TestCase
  class CapturingLogger
    attr_reader :messages

    def initialize
      @messages = []
    end

    def warn(message)
      @messages << message
    end
  end

  setup do
    @account = RawWb::SellerAccount.create!(
      name: "wb-resolver-#{SecureRandom.hex(6)}",
      api_token: "token-#{SecureRandom.hex(6)}",
      company_type: "small"
    )
  end

  teardown do
    RawWb::CommissionTariff.where(
      snapshot_id: RawWb::CommissionTariffSnapshot.where(source_account_id: @account.id).select(:id)
    ).delete_all
    RawWb::CommissionTariffSnapshot.where(source_account_id: @account.id).delete_all
    RawWb::SellerAccount.where(id: @account.id).delete_all
  end

  def create_current_snapshot(fetched_at: Time.current)
    RawWb::CommissionTariffSnapshot.create!(
      status: "succeeded", source_account: @account, locale: "ru",
      fetched_at: fetched_at, completed_at: fetched_at, is_current: true
    )
  end

  test "resolves fbs from kgvpMarketplace and fbo/fbw from paidStorageKgvp" do
    snapshot = create_current_snapshot
    RawWb::CommissionTariff.create!(snapshot: snapshot, wb_subject_id: 3319, kgvp_marketplace: 21, paid_storage_kgvp: 17.5)

    resolver = RawWb::CommissionTariffResolver.new
    assert_equal BigDecimal("0.21"), resolver.rate_for(wb_subject_id: 3319, delivery_mode: "fbs")
    assert_equal BigDecimal("0.175"), resolver.rate_for(wb_subject_id: 3319, delivery_mode: "fbo")
    assert_equal BigDecimal("0.175"), resolver.rate_for(wb_subject_id: 3319, delivery_mode: "fbw")
  end

  test "raises missing_snapshot when there is no current snapshot" do
    resolver = RawWb::CommissionTariffResolver.new
    error = assert_raises(RawWb::CommissionTariffResolver::ResolutionError) do
      resolver.rate_for(wb_subject_id: 3319, delivery_mode: "fbs")
    end
    assert_equal :missing_snapshot, error.code
  end

  test "raises missing_subject_tariff when the subject is absent from the current snapshot" do
    create_current_snapshot
    resolver = RawWb::CommissionTariffResolver.new
    error = assert_raises(RawWb::CommissionTariffResolver::ResolutionError) do
      resolver.rate_for(wb_subject_id: 999_999, delivery_mode: "fbs")
    end
    assert_equal :missing_subject_tariff, error.code
  end

  test "raises unsupported_delivery_mode for an unmapped mode" do
    create_current_snapshot
    resolver = RawWb::CommissionTariffResolver.new
    error = assert_raises(RawWb::CommissionTariffResolver::ResolutionError) do
      resolver.rate_for(wb_subject_id: 3319, delivery_mode: "dbs")
    end
    assert_equal :unsupported_delivery_mode, error.code
  end

  test "logs a stale warning but still returns the rate when the snapshot is older than 45 days" do
    snapshot = create_current_snapshot(fetched_at: 46.days.ago)
    RawWb::CommissionTariff.create!(snapshot: snapshot, wb_subject_id: 3319, kgvp_marketplace: 21)

    logger = CapturingLogger.new
    resolver = RawWb::CommissionTariffResolver.new
    rate = nil
    with_constant_logger(logger) do
      rate = resolver.rate_for(wb_subject_id: 3319, delivery_mode: "fbs")
    end

    assert_equal BigDecimal("0.21"), rate
    assert logger.messages.any? { |m| m.include?("stale") }
  end

  test "rate_for_wb_product resolves the subject through RawWb::Subject.wb_id, never RawWb::Product.subject_id directly" do
    category = RawWb::Category.create!(wb_id: 900_000 + rand(90_000), name: "cat-#{SecureRandom.hex(4)}")
    subject = RawWb::Subject.create!(wb_id: 3319, name: "subject-#{SecureRandom.hex(4)}", category: category)
    product = RawWb::Product.create!(
      account: @account,
      subject_id: subject.id,
      nm_id: rand(1_000_000..1_999_999),
      vendor_code: "code-#{SecureRandom.hex(4)}"
    )
    snapshot = create_current_snapshot
    RawWb::CommissionTariff.create!(snapshot: snapshot, wb_subject_id: 3319, kgvp_marketplace: 21)

    begin
      resolver = RawWb::CommissionTariffResolver.new
      assert_equal BigDecimal("0.21"), resolver.rate_for_wb_product(product: product, delivery_mode: "fbs")
    ensure
      RawWb::Product.where(id: product.id).delete_all
      RawWb::Subject.where(id: subject.id).delete_all
      RawWb::Category.where(id: category.id).delete_all
    end
  end

  test "products from different WB accounts resolve against the single shared current snapshot" do
    other_account = RawWb::SellerAccount.create!(
      name: "wb-resolver-other-#{SecureRandom.hex(6)}",
      api_token: "token-#{SecureRandom.hex(6)}",
      company_type: "small"
    )
    category = RawWb::Category.create!(wb_id: 900_000 + rand(90_000), name: "cat-#{SecureRandom.hex(4)}")
    subject = RawWb::Subject.create!(wb_id: 3319, name: "subject-#{SecureRandom.hex(4)}", category: category)
    product_a = RawWb::Product.create!(
      account: @account, subject_id: subject.id,
      nm_id: rand(2_000_000..2_999_999), vendor_code: "a-#{SecureRandom.hex(4)}"
    )
    product_b = RawWb::Product.create!(
      account: other_account, subject_id: subject.id,
      nm_id: rand(3_000_000..3_999_999), vendor_code: "b-#{SecureRandom.hex(4)}"
    )
    snapshot = create_current_snapshot
    RawWb::CommissionTariff.create!(snapshot: snapshot, wb_subject_id: 3319, kgvp_marketplace: 21)

    begin
      resolver = RawWb::CommissionTariffResolver.new
      rate_a = resolver.rate_for_wb_product(product: product_a, delivery_mode: "fbs")
      rate_b = resolver.rate_for_wb_product(product: product_b, delivery_mode: "fbs")

      assert_equal rate_a, rate_b
      assert_equal 1, RawWb::CommissionTariffSnapshot.where(is_current: true).count
    ensure
      RawWb::Product.where(id: [ product_a.id, product_b.id ]).delete_all
      RawWb::Subject.where(id: subject.id).delete_all
      RawWb::Category.where(id: category.id).delete_all
      RawWb::SellerAccount.where(id: other_account.id).delete_all
    end
  end

  private

  def with_singleton_method(klass, method_name, replacement)
    original = klass.method(method_name)
    klass.define_singleton_method(method_name, replacement)
    yield
  ensure
    klass.define_singleton_method(method_name, original)
  end

  def with_constant_logger(logger)
    with_singleton_method(Rails, :logger, -> { logger }) { yield }
  end
end
