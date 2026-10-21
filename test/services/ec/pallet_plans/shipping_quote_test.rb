require "test_helper"

class Ec::PalletPlans::ShippingQuoteTest < ActiveSupport::TestCase
  test "loads the effective route tariff and compares both cargo modes" do
    snapshot = RawOzon::CrossDockTariffSnapshot.create!(
      market_code: "ru", effective_from: Date.new(2026, 10, 1), effective_to: Date.new(2026, 11, 1),
      source_file_name: "test.xlsx", source_checksum: SecureRandom.hex(16), imported_at: Time.current, status: "succeeded"
    )
    RawOzon::CrossDockTariff.create!(snapshot: snapshot, supply_receiving_zone_name: "Zone A",
      supply_receiving_zone_key: "ZONE-A", destination_cluster_name: "Москва", destination_cluster_key: "МОСКВА",
      box_rub_per_l: 5, pallet_rub_per_l: 2.5)
    cluster = Struct.new(:cluster_name).new(" Москва ")

    quote = Ec::PalletPlans::ShippingQuote.new(items: [{ unit_volume_l: 40, pcs: 1, quantity: 20 }],
      pallet_result: { pallets: [{ goods_l: 800 }] }, box_result: { pallets: [] },
      attributes: { supply_receiving_zone_key: "ZONE-A", shipping_date: "2026-10-21" },
      cluster: cluster, time_zone: "Asia/Shanghai").call

    assert_equal snapshot.id, quote[:snapshot_id]
    assert_equal 950, quote[:break_even_volume_l]
    assert_equal 4000, quote.dig(:box, :cost)
    assert_equal 4750, quote.dig(:pallet, :cost)
    assert_equal :box, quote[:recommended]
  end
end
