if ENV["RUN_LIVE_OZON_ADS_TESTS"] == "1"
  require_relative "../../../config/environment"
  require "minitest/autorun"
else
  require "test_helper"
end
require "csv"

class RawOzonAdsApiContractTest < Minitest::Test
  LIVE_FLAG = "RUN_LIVE_OZON_ADS_TESTS"
  DEFAULT_STORE_NAME = "NEVASTAL"
  REPORT_TIMEOUT = 240
  POLL_INTERVAL = 3

  def setup
    skip "set #{LIVE_FLAG}=1 to run live Ozon ads contracts" unless ENV[LIVE_FLAG] == "1"

    @store = if ENV["OZON_LIVE_STORE_ID"].present?
      Ec::Store.find(ENV.fetch("OZON_LIVE_STORE_ID"))
    else
      Ec::Store.find_by!(store_name: ENV.fetch("OZON_LIVE_STORE_NAME", DEFAULT_STORE_NAME))
    end
    assert_equal "ozon", @store.platform
    assert_predicate @store.ozon_performance_client_id, :present?
    assert_predicate @store.ozon_performance_client_secret, :present?

    @client = RawOzon::PerformanceClient.new(
      @store.ozon_performance_client_id,
      @store.ozon_performance_client_secret
    )
    @date_to = Date.current - 1
    @date_from = @date_to - 2
  end

  def test_live_contracts_for_promotion_analysis
    campaigns = fetch_campaigns
    cpc_campaigns = campaigns.select { |campaign| cpc_campaign?(campaign) }.first(10)
    cpc_campaign = cpc_campaigns.first
    assert cpc_campaign, "expected at least one CPC product campaign"

    campaign_id = cpc_campaign.fetch("id").to_s
    products = fetch_cpc_products(campaign_id)
    competitive_bids = fetch_cpc_competitive_bids(campaign_id, products)
    daily_csv = fetch_campaign_daily_stats(campaign_id)
    cpc_sku_result = fetch_cpc_sku_stats(cpc_campaigns.map { |campaign| campaign.fetch("id").to_s })
    cpo_selected_products = fetch_cpo_selected_products
    cpo_selected_csv = fetch_cpo_selected_product_report
    cpo_all_csv = fetch_cpo_all_product_report

    assert_operator products.size, :>, 0
    assert_kind_of Hash, competitive_bids
    assert_operator cpo_selected_products.size, :>, 0
    assert_csv_contract daily_csv, required_headers: %w[ID], label: "campaign daily"
    assert_cpc_sku_contract(cpc_sku_result)
    assert_csv_has_sku cpo_selected_csv, label: "CPO selected products"
    assert_cpo_all_contract cpo_all_csv

    emit_contract_summary(
      campaign_keys: cpc_campaign.keys,
      campaign_count: campaigns.size,
      cpc_product_keys: products.first.keys,
      cpc_product_count: products.size,
      cpc_sku_stats_status: cpc_sku_result["contract_error"] ? "unavailable_empty_campaigns" : "available",
      cpc_sku_stat_keys: Array(cpc_sku_result["rows"]).first&.keys || [],
      cpc_sku_stat_count: Array(cpc_sku_result["rows"]).size,
      competitive_bid_keys: competitive_bids.keys,
      cpo_selected_product_keys: cpo_selected_products.first.keys,
      cpo_selected_product_count: cpo_selected_products.size,
      daily_headers: csv_headers(daily_csv),
      cpo_selected_headers: csv_headers(cpo_selected_csv),
      cpo_all_headers: csv_headers(cpo_all_csv)
    )
  end

  private

  def fetch_campaigns
    response = @client.get("/api/client/campaign")
    assert_kind_of Hash, response
    campaigns = Array(response["list"])
    assert_operator campaigns.size, :>, 0
    assert campaigns.all? { |campaign| campaign.is_a?(Hash) && campaign["id"].present? }
    campaigns
  end

  def cpc_campaign?(campaign)
    payment_type = campaign["PaymentType"].presence || campaign["paymentType"]
    payment_type.to_s.casecmp("CPC").zero? &&
      campaign["advObjectType"].to_s.casecmp("SKU").zero? &&
      campaign["state"].to_s.casecmp("CAMPAIGN_STATE_RUNNING").zero?
  end

  def fetch_cpc_products(campaign_id)
    response = @client.get("/api/client/campaign/#{campaign_id}/v2/products")
    assert_kind_of Hash, response
    products = first_array(response, "list", "products", "items")
    assert products.all? { |product| product.is_a?(Hash) }
    products
  end

  def fetch_campaign_daily_stats(campaign_id)
    @client.get_csv(
      "/api/client/statistics/daily",
      campaigns: campaign_id,
      dateFrom: @date_from.to_s,
      dateTo: @date_to.to_s
    )
  end

  def fetch_cpc_competitive_bids(campaign_id, products)
    skus = products.filter_map do |product|
      product["sku"] || product["skuId"] || product["id"]
    end.map(&:to_s).reject(&:blank?)
    assert_operator skus.size, :>, 0, "CPC products should expose SKU identifiers"

    @client.get(
      "/api/client/campaign/#{campaign_id}/products/bids/competitive",
      skus: skus.first(100).join(",")
    )
  end

  def fetch_cpc_sku_stats(campaign_ids)
    response = @client.post("/api/client/statistics/products/sku", {
      campaignIds: campaign_ids,
      dateFrom: @date_to.to_s,
      dateTo: @date_to.to_s
    })
    return { "report" => download_report(response["UUID"]) } if response["UUID"].present?

    response
  rescue RawOzon::PerformanceClient::ApiError => error
    { "contract_error" => error.message }
  end

  def fetch_cpo_selected_products
    response = @client.post("/api/client/campaign/search_promo/v2/products", {})
    assert_kind_of Hash, response
    products = first_array(response, "list", "products", "items")
    assert products.all? { |product| product.is_a?(Hash) }
    products
  end

  def fetch_cpo_selected_product_report
    response = @client.post("/api/client/statistic/products/generate", {
      from: "#{@date_from}T00:00:00+03:00",
      to: "#{@date_to}T23:59:59+03:00"
    })
    download_report(response.fetch("UUID"))
  end

  def fetch_cpo_all_product_report
    response = @client.get("/api/client/statistics/all_sku_promo/products/generate", {
      "timeBounds.from" => "#{@date_from}T00:00:00+03:00",
      "timeBounds.to" => "#{@date_to}T23:59:59+03:00"
    })
    download_report(response.fetch("UUID"))
  end

  def download_report(uuid)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + REPORT_TIMEOUT

    loop do
      status = @client.get("/api/client/statistics/#{uuid}")
      state = status["state"].to_s.upcase
      return @client.get_csv("/api/client/statistics/report", UUID: uuid) if %w[OK SUCCESS READY DONE].include?(state)
      flunk "Ozon report #{uuid} entered ERROR state" if state == "ERROR"
      flunk "Ozon report #{uuid} exceeded #{REPORT_TIMEOUT}s" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep POLL_INTERVAL
    end
  end

  def first_array(response, *keys)
    keys.each do |key|
      value = response[key]
      return value if value.is_a?(Array)
      return value.values.find { |nested| nested.is_a?(Array) } || [] if value.is_a?(Hash)
    end
    response.values.find { |value| value.is_a?(Array) } || []
  end

  def assert_csv_contract(body, required_headers:, label:)
    headers = csv_headers(body)
    assert_operator headers.size, :>, 1, "#{label} should expose multiple columns"
    required_headers.each do |header|
      assert headers.any? { |value| value.casecmp(header).zero? }, "#{label} missing #{header.inspect}: #{headers.inspect}"
    end
  end

  def assert_csv_has_sku(body, label:)
    headers = csv_headers(body)
    diagnostic = {
      bytesize: body.to_s.bytesize,
      prefix_hex: body.to_s.byteslice(0, 16).to_s.unpack1("H*"),
      encoding: body.to_s.encoding.name
    }
    assert headers.any? { |value| value.match?(/SKU/i) }, "#{label} missing SKU: #{headers.inspect}; #{diagnostic.inspect}"
  end

  def assert_cpc_sku_contract(result)
    assert_kind_of Hash, result
    if result["contract_error"]
      assert_match(/empty campaigns/, result["contract_error"])
    elsif result["report"]
      assert_csv_has_sku result["report"], label: "CPC SKU statistics"
    else
      rows = first_array(result, "list", "products", "items", "rows")
      assert_operator rows.size, :>, 0
      assert rows.all? { |row| row.is_a?(Hash) }
    end
  end

  def assert_cpo_all_contract(body)
    headers = csv_headers(body)
    assert_operator headers.size, :>=, 7
    assert headers.any? { |value| value.match?(/Дата/i) }, "CPO all report missing date: #{headers.inspect}"
    refute headers.any? { |value| value.match?(/SKU/i) }, "CPO all report unexpectedly changed to SKU grain: #{headers.inspect}"
  end

  def csv_headers(body)
    normalized = normalize_csv(body)
    candidates = []
    normalized.each_line do |line|
      columns = CSV.parse_line(line, col_sep: ";")&.map { |value| value.to_s.strip } || []
      return columns if columns.any? { |value| value.match?(/SKU/i) } || columns.first.to_s.casecmp("ID").zero?
      candidates << columns
    end
    candidates.max_by(&:size) || []
  end

  def normalize_csv(body)
    utf8 = body.to_s.dup.force_encoding("UTF-8")
    utf8 = body.to_s.dup.force_encoding("Windows-1251").encode("UTF-8", invalid: :replace, undef: :replace) unless utf8.valid_encoding?
    utf8.sub("\uFEFF", "")
  end

  def emit_contract_summary(summary)
    sanitized = summary.transform_values do |value|
      value.is_a?(Array) ? value.map(&:to_s).sort : value
    end
    $stdout.puts "OZON_ADS_CONTRACT=#{JSON.generate(sanitized)}"
  end
end
