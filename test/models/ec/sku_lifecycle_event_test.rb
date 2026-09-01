require "test_helper"

class Ec::SkuLifecycleEventTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
    @sku = Ec::Sku.create!(sku_code: "LIFECYCLE-#{@token}")
    @other_sku = Ec::Sku.create!(sku_code: "LIFECYCLE-OTHER-#{@token}")
    @store = Ec::Store.create!(store_name: "Lifecycle #{@token}", platform: "ozon", company_type: "general")
    @product = Ec::SkuProduct.create!(sku: @sku, store: @store, product_id: "P-#{@token}", platform_sku_id: "PS-#{@token}")
    @other_product = Ec::SkuProduct.create!(sku: @other_sku, store: @store, product_id: "OP-#{@token}", platform_sku_id: "OPS-#{@token}")
  end

  teardown do
    Ec::SkuLifecycleEvent.where(sku_id: [ @sku.id, @other_sku.id ]).delete_all
    Ec::SkuProduct.where(id: [ @product.id, @other_product.id ]).delete_all
    Ec::Store.where(id: @store.id).delete_all
    Ec::Sku.with_deleted.where(id: [ @sku.id, @other_sku.id ]).delete_all
  end

  test "validates event type occurrence source key and content schema" do
    event = @sku.lifecycle_events.build(event_type: "unknown", content: {})

    assert_not event.valid?
    assert event.errors[:event_type].any?
    assert event.errors[:occurred_at].any?
    assert event.errors[:source_key].any?

    event.assign_attributes(valid_marketing_attributes)
    assert event.valid?
  end

  test "requires the event-specific content fields" do
    event = @sku.lifecycle_events.build(valid_marketing_attributes.merge(content: { to_grade: "A" }))

    assert_not event.valid?
    assert event.errors[:content].any?
  end

  test "requires a globally unique source key" do
    @sku.lifecycle_events.create!(valid_marketing_attributes)
    duplicate = @other_sku.lifecycle_events.build(valid_marketing_attributes)

    assert_not duplicate.valid?
    assert duplicate.errors[:source_key].any?
  end

  test "requires a listing assigned to the same sku" do
    event = @sku.lifecycle_events.build(valid_first_sale_attributes.merge(sku_product: @other_product))

    assert_not event.valid?
    assert event.errors[:sku_product].any?

    event.sku_product = @product
    assert event.valid?
  end

  private

  def valid_marketing_attributes
    {
      event_type: "marketing_state_changed",
      occurred_at: Time.zone.parse("2026-08-01 10:00"),
      source_key: "marketing_state:#{@token}",
      content: { to_grade: "A", to_stage: "grw", initial_state: false }
    }
  end

  def valid_first_sale_attributes
    {
      event_type: "first_sale",
      occurred_at: Time.zone.parse("2026-08-01 10:00"),
      source_key: "first_sale:sku:#{@sku.id}",
      content: {
        order_id: 1, order_item_id: 2, platform: "ozon", store_id: @store.id,
        sku_product_id: @product.id, quantity: 1, platform_sku_id: @product.platform_sku_id
      }
    }
  end
end
