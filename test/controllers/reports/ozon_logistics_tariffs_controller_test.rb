require "test_helper"

class Reports::OzonLogisticsTariffsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(6)
    @user = create_user_with_roles("ozon-tariffs-#{@token}@example.com", "manager")
    sign_in @user
    @logistics_snapshot = RawOzon::LogisticsTariffSnapshot.create!(
      market_code: "ru", effective_from: Date.new(2025, 1, 1), source_file_name: "logistics.xlsx",
      source_checksum: "logistics-#{@token}", status: "succeeded", is_current: true, imported_at: Time.current
    )
    @cross_dock_snapshot = RawOzon::CrossDockTariffSnapshot.create!(
      market_code: "ru", effective_from: Date.new(2025, 1, 1), source_file_name: "cross-dock.xlsx",
      source_checksum: "cross-dock-#{@token}", status: "succeeded", is_current: true, imported_at: Time.current
    )
    create_logistics_rows
    create_cross_dock_rows
  end

  teardown do
    RawOzon::LogisticsTariff.where(snapshot_id: @logistics_snapshot.id).delete_all
    RawOzon::DefaultLogisticsTariff.where(snapshot_id: @logistics_snapshot.id).delete_all
    RawOzon::CrossDockTariff.where(snapshot_id: @cross_dock_snapshot.id).delete_all
    @logistics_snapshot.destroy!
    @cross_dock_snapshot.destroy!
    UserRole.where(user_id: @user.id).delete_all
    @user.destroy!
  end

  test "renders route tariffs and filters by origin" do
    get reports_ozon_logistics_tariffs_path, params: { locale: "zh", origin: "Москва" }

    assert_response :success
    assert_select "h1", text: "Ozon 物流路线费率"
    assert_select "table.prod-tbl tbody tr", 1
    assert_select "td", text: "Москва"
    assert_select "td", text: "Воронеж"
  end

  test "renders default tariffs and cross-dock tariffs with pagination" do
    get reports_ozon_logistics_tariff_defaults_path, params: { locale: "zh" }
    assert_response :success
    assert_select "h1", text: "Ozon 默认物流费率"
    assert_select "table.prod-tbl tbody tr", 1

    assert @user.can?(:view_reports)
    sign_in @user
    get reports_ozon_cross_dock_tariffs_path(format: :json), params: { locale: "zh" }
    assert_response :success
    assert_equal 1, response.parsed_body.dig("pagination", "total")
    assert_equal "Архангельск", response.parsed_body.dig("rows", 0, "supply_receiving_zone_name")
  end

  test "filters route JSON by volume and selected cluster keys and returns the full-scope average" do
    second = RawOzon::LogisticsTariff.create!(
      RawOzon::LogisticsTariff.where(snapshot_id: @logistics_snapshot.id).first.attributes
        .except("id", "created_at", "updated_at")
        .merge(destination_cluster_name: "Казань", destination_cluster_key: "КАЗАНЬ", fbo_rub: 80)
    )

    get reports_ozon_logistics_tariffs_path(format: :json), params: {
      volume_l: "0.1",
      origin_keys: ["МОСКВА"],
      destination_keys: ["ВОРОНЕЖ", "КАЗАНЬ"]
    }

    assert_response :success
    assert_equal 2, response.parsed_body.dig("route_filter", "matched_count")
    assert_equal "70.0", response.parsed_body.dig("route_filter", "average_fbo_rub")
    assert_equal "0-0,200 л", response.parsed_body.dig("route_filter", "volume_band_label")
    assert_equal ["ВОРОНЕЖ", "КАЗАНЬ"], response.parsed_body.dig("route_filter", "destination_keys")
  ensure
    second&.destroy!
  end

  test "filters cross-dock JSON by selected route keys and calculates volume-based amounts" do
    second = RawOzon::CrossDockTariff.create!(
      snapshot_id: @cross_dock_snapshot.id,
      supply_receiving_zone_name: "Москва",
      supply_receiving_zone_key: "МОСКВА",
      destination_cluster_name: "Казань",
      destination_cluster_key: "КАЗАНЬ",
      pallet_rub_per_l: 7,
      box_rub_per_l: 10
    )

    get reports_ozon_cross_dock_tariffs_path(format: :json), params: {
      volume_l: "2.5",
      supply_zone_keys: ["АРХАНГЕЛЬСК"],
      destination_keys: ["ВОРОНЕЖ"]
    }

    assert_response :success
    payload = response.parsed_body
    assert_equal 1, payload.dig("cross_dock_filter", "matched_count")
    assert_equal "9.0", payload.dig("cross_dock_filter", "average_pallet_rub_per_l")
    assert_equal "22.5", payload.dig("cross_dock_filter", "average_pallet_amount_rub")
    assert_equal "29.25", payload.dig("cross_dock_filter", "average_box_amount_rub")
    assert_equal "22.5", payload.dig("rows", 0, "pallet_amount_rub")
    assert_equal "29.25", payload.dig("rows", 0, "box_amount_rub")
  ensure
    second&.destroy!
  end

  private

  def create_logistics_rows
    attrs = {
      snapshot_id: @logistics_snapshot.id, volume_band_order: 1, volume_min_l: 0,
      volume_max_l: 0.2, volume_band_label: "0-0,200 л", origin_cluster_name: "Москва",
      origin_cluster_key: "МОСКВА", destination_cluster_name: "Воронеж", destination_cluster_key: "ВОРОНЕЖ",
      fbo_rub: 60, fbo_fresh_under_300_rub: 18, fbo_fresh_over_300_rub: 60,
      fbs_under_300_rub: 18, fbs_over_300_rub: 60
    }
    RawOzon::LogisticsTariff.create!(attrs)
    RawOzon::DefaultLogisticsTariff.create!(attrs.except(:snapshot_id, :origin_cluster_name, :origin_cluster_key, :destination_cluster_name, :destination_cluster_key).merge(snapshot_id: @logistics_snapshot.id))
  end

  def create_cross_dock_rows
    RawOzon::CrossDockTariff.create!(
      snapshot_id: @cross_dock_snapshot.id, supply_receiving_zone_name: "Архангельск",
      supply_receiving_zone_key: "АРХАНГЕЛЬСК", destination_cluster_name: "Воронеж",
      destination_cluster_key: "ВОРОНЕЖ", pallet_rub_per_l: 9, box_rub_per_l: 11.7
    )
  end
end
