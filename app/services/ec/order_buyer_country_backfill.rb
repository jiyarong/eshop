module Ec
  # Fills ec_orders.buyer_country (see Ec::BuyerCountry for the signals and their order). One routine
  # for all three uses, and running it again changes nothing that is already settled:
  #   - after an order import, a 3-day window picks up the orders just imported;
  #   - the daily catch-up (config/recurring.yml) re-tries the last 120 days, which is where a late
  #     statistics order, a late cluster or a newly learnt place lands;
  #   - once, without a window, for the history.
  # An order is settled when its country comes from the platform's own signal (WB statistics order,
  # Ozon cluster); until then a stronger source replaces a weaker one, and a different answer from an
  # equal or weaker source is only counted as a conflict.
  class OrderBuyerCountryBackfill
    BATCH = 1_000
    IMPORT_WINDOW_DAYS = 3
    CATCH_UP_WINDOW_DAYS = 120

    def self.run(platform: nil, window_days: nil, dry_run: false, today: Date.current)
      platforms = platform ? [ platform.to_s ] : Ec::BuyerCountry::TOP_SOURCE.keys
      platforms.to_h { |name| [ name, new(platform: name, window_days:, dry_run:, today:).run ] }
    end

    # The import's hook: the orders just imported get their country at once, and a failure here never
    # fails the import (the daily catch-up tries again).
    def self.run_after_import(platform)
      run(platform: platform, window_days: IMPORT_WINDOW_DAYS)
    rescue StandardError => error
      Rails.logger.warn("[OrderBuyerCountryBackfill] #{platform} after import: #{error.class}: #{error.message}")
      nil
    end

    # The daily catch-up: logs what it filled and what is still unknown, so a stalled source shows.
    def self.catch_up
      result = run(window_days: CATCH_UP_WINDOW_DAYS)
      result["wb_clusters_filled"] = fill_wb_clusters(window_days: CATCH_UP_WINDOW_DAYS)
      Rails.logger.info("[OrderBuyerCountryBackfill] catch-up #{result.to_json}")
      result
    end

    # WB fulfilments whose destination cluster is still empty although a statistics order exists (a
    # country the resolver learnt later, such as Kazakhstan). Returns how many it filled.
    def self.fill_wb_clusters(window_days: nil, dry_run: false, today: Date.current)
      scope = Ec::OrderFulfillment.where(platform: "wb", cluster_to: nil).joins(:order)
      scope = scope.where(ec_orders: { ordered_at: (today - window_days).beginning_of_day.. }) if window_days
      filled = 0
      scope.in_batches(of: BATCH) do |batch|
        rows = batch.pluck(:id, "ec_orders.external_order_id")
        stats = RawWb::StatsOrder.where(srid: rows.map(&:last).compact).index_by(&:srid)
        by_cluster = rows.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(id, srid), grouped|
          cluster = stats[srid] && RawWb::OrderClusterResolver.cluster_to(stats[srid])
          grouped[cluster] << id if cluster
        end
        by_cluster.each do |cluster, ids|
          Ec::OrderFulfillment.where(id: ids).update_all(cluster_to: cluster) unless dry_run
          filled += ids.size
        end
      end
      filled
    end

    # Share of the last `days` days' orders that have a country, by platform and status, to see a broken
    # source (a statistics sync that stopped, a cluster table that went stale) the day after.
    def self.coverage(days: 90, today: Date.current)
      scope = Ec::Order.where(ordered_at: (today - days).beginning_of_day..)
      Ec::BuyerCountry::TOP_SOURCE.keys.to_h do |platform|
        rows = scope.where(platform: platform).group(:order_status).pluck(
          :order_status, Arel.sql("COUNT(*)"), Arel.sql("COUNT(buyer_country)"),
          Arel.sql("COUNT(*) FILTER (WHERE buyer_country_source = '#{Ec::BuyerCountry::TOP_SOURCE.fetch(platform)}')")
        )
        [ platform, rows.to_h { |status, total, with_country, platform_signal| [ status, { total:, with_country:, platform_signal: } ] } ]
      end
    end

    def initialize(platform:, window_days:, dry_run:, today:)
      @platform = platform
      @window_days = window_days
      @dry_run = dry_run
      @today = today
      @summary = { checked: 0, written: 0, corrected: 0, conflicts: 0, unresolved: 0, by_source: Hash.new(0), unmapped: Hash.new { |h, k| h[k] = Hash.new(0) } }
    end

    def run
      pending_orders.in_batches(of: BATCH) do |batch|
        orders = batch.pluck(:id, :external_order_id, :buyer_city, :buyer_country, :buyer_country_source)
        signals = platform == "wb" ? wb_signals(orders) : ozon_signals(orders)
        decide(orders, signals)
      end
      summary.merge(by_source: summary[:by_source].to_h, unmapped: summary[:unmapped].transform_values(&:to_h))
    end

    private

    attr_reader :platform, :window_days, :dry_run, :today, :summary

    def pending_orders
      scope = Ec::Order.where(platform: platform)
        .where("buyer_country_source IS NULL OR buyer_country_source <> ?", Ec::BuyerCountry::TOP_SOURCE.fetch(platform))
        .order(:id)
      window_days ? scope.where(ordered_at: (today - window_days).beginning_of_day..) : scope
    end

    def decide(orders, signals)
      writes = Hash.new { |hash, key| hash[key] = [] }
      orders.each do |id, _external, _city, country, source|
        summary[:checked] += 1
        result = signals[id]
        unless result
          summary[:unresolved] += 1
          next
        end

        current_rank = country.present? ? Ec::BuyerCountry.rank(source) : 0
        if Ec::BuyerCountry.rank(result.source) > current_rank
          summary[:corrected] += 1 if country.present? && country != result.country
          summary[:written] += 1
          summary[:by_source][result.source] += 1
          writes[[ result.country, result.source ]] << id
        elsif country.present? && country != result.country
          summary[:conflicts] += 1
        end
      end
      return if dry_run

      writes.each do |(country, source), ids|
        Ec::Order.where(id: ids).update_all(buyer_country: country, buyer_country_source: source)
      end
    end

    # ── WB: the statistics order of the same srid ──────────────────────────────────────────────
    def wb_signals(orders)
      countries = RawWb::StatsOrder.where(srid: orders.map { |_id, external, *| external }.compact)
        .where.not(country_name: [ nil, "" ]).pluck(:srid, :country_name).to_h
      orders.each_with_object({}) do |(id, external, *), signals|
        name = countries[external] or next
        result = Ec::BuyerCountry.wb(name)
        if result then signals[id] = result else summary[:unmapped][:country][name] += 1 end
      end
    end

    # ── Ozon: cluster, then place, then currency ───────────────────────────────────────────────
    def ozon_signals(orders)
      ids = orders.map(&:first)
      fulfillments = Ec::OrderFulfillment.where(order_id: ids, platform: "ozon").pluck(:order_id, :cluster_to, :external_fulfillment_id)
        .group_by(&:first)
      destination_cities = RawOzon::PostingDestination.where(posting_number: fulfillments.values.flatten(1).map(&:last)).pluck(:posting_number, :city).to_h
      currencies = Ec::OrderItem.where(order_id: ids).where.not(buyer_currency_code: [ nil, "" ]).distinct.pluck(:order_id, :buyer_currency_code)
        .group_by(&:first).transform_values { |rows| rows.map(&:last).uniq }
      cluster_countries = RawOzon::WarehouseCluster.distinct.pluck(:cluster_name, :country_name).to_h

      orders.each_with_object({}) do |(id, _external, city, *), signals|
        rows = fulfillments.fetch(id, [])
        order_currency = currencies.fetch(id, []).then { |codes| codes.one? ? codes.first : nil }
        note_unmapped_clusters(rows, cluster_countries)
        result = ozon_cluster_result(rows, cluster_countries) ||
          Ec::BuyerCountry.city([ city, *rows.map { |_, _, posting| destination_cities[posting] } ], currency: order_currency) ||
          Ec::BuyerCountry.currency(order_currency)
        if result
          signals[id] = result
        elsif city.present? && Ec::BuyerCountry.place_countries[Ec::BuyerCountry.normalize_place(city)].nil?
          summary[:unmapped][:place][city] += 1
        end
      end
    end

    # One country for all of the order's postings; postings that disagree say nothing.
    def ozon_cluster_result(rows, cluster_countries)
      results = rows.filter_map do |_, cluster, _|
        cluster.present? ? Ec::BuyerCountry.ozon_cluster(cluster, cluster_countries) : nil
      end
      results.map(&:country).uniq.one? ? results.first : nil
    end

    # A cluster nobody classified is reported even when the place or the currency settled the order,
    # so it gets a line in the config file instead of staying a quiet fallback.
    def note_unmapped_clusters(rows, cluster_countries)
      rows.each do |_, cluster, _|
        summary[:unmapped][:cluster][cluster] += 1 if cluster.present? && Ec::BuyerCountry.ozon_cluster(cluster, cluster_countries).nil?
      end
    end
  end
end
