require "test_helper"

class SalesFunnelReports::EndingInventoryQueryTest < ActiveSupport::TestCase
  setup do
    token = SecureRandom.hex(6)
    @sku = Ec::Sku.create!(sku_code: "ENDING-INVENTORY-#{token}", product_name: "Ending inventory")
    @date = Date.new(2026, 8, 18)
  end

  teardown do
    Ec::Snapshot.where(sku_id: @sku&.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
  end

  test "uses the exact ending date and separates total from store inventory" do
    create_snapshot(@date - 1, book_stock: 999, fbo: 999, fbs: 999, inbound: 999)
    create_snapshot(@date, book_stock: 587, fbo: 80, fbs: 15, inbound: 5)

    result = SalesFunnelReports::EndingInventoryQuery.by_sku(
      sku_ids: [@sku.id], store_id: 3, on_date: @date
    ).fetch(@sku.id)

    assert_equal 587, result[:total_ending_inventory]
    assert_equal 95, result[:store_ending_inventory]
  end

  private

  def create_snapshot(date, book_stock:, fbo:, fbs:, inbound:)
    Ec::Snapshot.create!(
      sku: @sku,
      snapshot_type: Ec::InventorySnapshot.snapshot_type,
      snapshot_date: date,
      content: {
        overview: { book_stock: book_stock },
        distribution: {
          levels: [
            { store_id: 3, fulfillment_type: "fbo", quantity: fbo },
            { store_id: 3, fulfillment_type: "fbs", quantity: fbs },
            { store_id: 3, fulfillment_type: "inbound", quantity: inbound },
            { store_id: 4, fulfillment_type: "fbo", quantity: 200 }
          ]
        }
      }
    )
  end
end
