require "digest"

module RawWb
  module Adv
    class Sync
      CAMPAIGN_BATCH_SIZE = 50
      FULLSTATS_INTERVAL = 20.1
      BUDGET_INTERVAL = 0.26
      EXPENSE_INTERVAL = 1.0
      ALL_APPS_TYPE = -1
      STATUSES_WITH_STATS = [7, 9, 11].freeze
      STATUSES_WITH_BUDGET = [4, 9, 11].freeze

      def self.run(from_date: 8.days.ago.to_date, to_date: Date.yesterday, store_ids: nil)
        stores = Ec::Store.active.where(platform: "wb").where.not(wb_api_token: [nil, ""])
        stores = stores.where(id: store_ids) if store_ids.present?
        raise ArgumentError, "No active WB stores with an API token found" if stores.none?

        stores.each_with_object({}) do |store, results|
          results[store.id] = new(store).run(from_date:, to_date:)
        end
      end

      def initialize(store, client: nil, sleep_seconds: {})
        raise ArgumentError, "Store must be a WB store" unless store.wb?
        raise ArgumentError, "Store has no WB API token" if store.wb_api_token.blank?

        @store = store
        @client = client || RawWb::WbClient.new(store.wb_api_token)
        @sleep_seconds = {
          campaigns: 0.21,
          budgets: BUDGET_INTERVAL,
          stats: FULLSTATS_INTERVAL,
          expenses: EXPENSE_INTERVAL,
        }.merge(sleep_seconds)
      end

      def run(from_date:, to_date:)
        from_date = from_date.to_date
        to_date = to_date.to_date
        raise ArgumentError, "from_date must not be after to_date" if from_date > to_date

        {
          campaigns: run_step(:campaigns) { sync_campaigns },
          budgets: run_step(:budgets) { sync_budgets },
          stats: run_step(:stats) { sync_stats(from_date:, to_date:) },
          expenses: run_step(:expenses) { sync_expenses(from_date:, to_date:) },
        }
      end

      def sync_campaigns
        response = @client.get(:advert, "/adv/v1/promotion/count")
        summaries = Array(response["adverts"]).flat_map do |group|
          Array(group["advert_list"]).filter_map do |item|
            next if item["advertId"].blank?

            {
              advert_id: item["advertId"].to_i,
              campaign_type: group["type"],
              status: group["status"],
              source_updated_at: parse_time(item["changeTime"]),
              raw_payload: item.merge("campaignType" => group["type"], "status" => group["status"]),
            }
          end
        end

        now = Time.current
        RawWb::AdvCampaign.where(store_id: @store.id).update_all(is_current: false, updated_at: now)
        summary_rows = summaries.map do |summary|
          summary.merge(store_id: @store.id, is_current: true, synced_at: now)
        end
        if summary_rows.any?
          RawWb::AdvCampaign.upsert_all(
            summary_rows,
            unique_by: :idx_wb_adv_campaigns_store_advert,
            update_only: %i[campaign_type status source_updated_at is_current raw_payload synced_at]
          )
        end

        details_count = 0
        summaries.map { |row| row[:advert_id] }.each_slice(CAMPAIGN_BATCH_SIZE).with_index do |ids, batch_index|
          details = @client.get(:advert, "/api/advert/v2/adverts", ids: ids.join(","))
          Array(details["adverts"]).each do |payload|
            sync_campaign_detail(payload, now:)
            details_count += 1
          end
          sleep_for(:campaigns) unless batch_index == (summaries.size - 1) / CAMPAIGN_BATCH_SIZE
        end

        { campaigns: summaries.size, details: details_count }
      end

      def sync_budgets
        campaigns = RawWb::AdvCampaign.where(store_id: @store.id, is_current: true, status: STATUSES_WITH_BUDGET)
        observed_at = Time.current

        campaigns.each_with_index do |campaign, index|
          payload = @client.get(:advert, "/adv/v1/budget", id: campaign.advert_id)
          RawWb::AdvBudgetSnapshot.create!(
            campaign:,
            cash: payload["cash"].to_d,
            netting: payload["netting"].to_d,
            total: payload["total"].to_d,
            currency: payload["currency"],
            observed_at:,
            raw_payload: payload
          )
          sleep_for(:budgets) unless index == campaigns.size - 1
        end

        campaigns.size
      end

      def sync_stats(from_date:, to_date:)
        campaigns = RawWb::AdvCampaign.where(
          store_id: @store.id,
          is_current: true,
          status: STATUSES_WITH_STATS
        ).index_by(&:advert_id)
        total = 0

        date_chunks(from_date, to_date).each do |chunk_from, chunk_to|
          campaigns.keys.each_slice(CAMPAIGN_BATCH_SIZE).with_index do |ids, batch_index|
            response = @client.get(
              :advert,
              "/adv/v3/fullstats",
              ids: ids.join(","),
              beginDate: chunk_from.iso8601,
              endDate: chunk_to.iso8601
            )
            Array(response).each do |payload|
              campaign = campaigns[payload["advertId"].to_i]
              next unless campaign

              total += sync_campaign_stats(campaign, payload)
            end
            last_batch = batch_index == (campaigns.size - 1) / CAMPAIGN_BATCH_SIZE
            sleep_for(:stats) unless last_batch && chunk_to == to_date
          end
        end

        total
      end

      def sync_expenses(from_date:, to_date:)
        total = 0
        campaign_ids = RawWb::AdvCampaign.where(store_id: @store.id).pluck(:advert_id, :id).to_h

        date_chunks(from_date, to_date).each_with_index do |(chunk_from, chunk_to), index|
          response = @client.get(:advert, "/adv/v1/upd", from: chunk_from.iso8601, to: chunk_to.iso8601)
          now = Time.current
          rows = Array(response).filter_map do |payload|
            advert_id = payload["advertId"].to_i
            expense_at = parse_time(payload["updTime"])
            next if advert_id.zero? || expense_at.nil?

            {
              store_id: @store.id,
              campaign_id: campaign_ids[advert_id],
              advert_id:,
              expense_at:,
              campaign_name: payload["campName"],
              payment_type: payload["paymentType"],
              upd_num: payload["updNum"],
              amount: payload["updSum"].to_d,
              advert_type: payload["advertType"],
              advert_status: payload["advertStatus"],
              currency: payload["currency"],
              source_fingerprint: expense_fingerprint(payload),
              raw_payload: payload,
              synced_at: now,
            }
          end
          if rows.any?
            RawWb::AdvExpense.upsert_all(
              rows,
              unique_by: :idx_wb_adv_expenses_fingerprint,
              update_only: %i[campaign_id campaign_name payment_type upd_num amount advert_type advert_status currency raw_payload synced_at]
            )
          end
          total += rows.size
          sleep_for(:expenses) unless index == date_chunks(from_date, to_date).size - 1
        end

        total
      end

      private

      def run_step(name)
        yield
      rescue RawWb::WbClient::ApiError, RawWb::WbClient::RetryableError => error
        Rails.logger.warn("[RawWb::Adv::Sync] store=#{@store.id} step=#{name} #{error.class}: #{error.message}")
        { error: error.message }
      rescue => error
        Rails.logger.error("[RawWb::Adv::Sync] store=#{@store.id} step=#{name} #{error.class}: #{error.message}")
        { error: "#{error.class}: #{error.message}" }
      end

      def sync_campaign_detail(payload, now:)
        advert_id = payload["id"].to_i
        campaign = RawWb::AdvCampaign.find_by!(store_id: @store.id, advert_id:)
        settings = payload["settings"] || {}
        timestamps = payload["timestamps"] || {}
        campaign.update!(
          name: settings["name"],
          status: payload["status"],
          payment_type: settings["payment_type"],
          bid_type: payload["bid_type"],
          currency: payload["currency"],
          placements: settings["placements"] || {},
          can_change_nms: payload.dig("restrictions", "can_change_nms"),
          source_created_at: parse_time(timestamps["created"]),
          source_deleted_at: parse_time(timestamps["deleted"]),
          source_started_at: parse_time(timestamps["started"]),
          source_updated_at: parse_time(timestamps["updated"]),
          raw_payload: payload,
          is_current: true,
          synced_at: now
        )

        campaign.products.update_all(is_current: false, updated_at: now)
        product_rows = Array(payload["nm_settings"]).filter_map do |item|
          next if item["nm_id"].blank?

          {
            campaign_id: campaign.id,
            nm_id: item["nm_id"].to_i,
            subject_id: item.dig("subject", "id"),
            subject_name: item.dig("subject", "name"),
            search_bid_kopecks: item.dig("bids_kopecks", "search"),
            recommendation_bid_kopecks: item.dig("bids_kopecks", "recommendations"),
            is_current: true,
            raw_payload: item,
            synced_at: now,
          }
        end
        return if product_rows.empty?

        RawWb::AdvCampaignProduct.upsert_all(
          product_rows,
          unique_by: :idx_wb_adv_campaign_products_unique,
          update_only: %i[subject_id subject_name search_bid_kopecks recommendation_bid_kopecks is_current raw_payload synced_at]
        )
      end

      def sync_campaign_stats(campaign, payload)
        now = Time.current
        currency = payload["currency"] || campaign.currency
        positions = Array(payload["boosterStats"]).to_h do |item|
          [[item["date"].to_s.first(10), item["nm"].to_i], item["avg_position"]]
        end
        campaign_rows = []
        product_rows = []

        Array(payload["days"]).each do |day|
          stat_date = day["date"].to_s.first(10)
          next if stat_date.blank?

          campaign_rows << stat_row(day).merge(
            campaign_id: campaign.id,
            stat_date:,
            currency:,
            raw_payload: day,
            synced_at: now
          )
          product_rows.concat(product_stat_rows(campaign, stat_date, day, positions, currency, now))
        end

        if campaign_rows.any?
          RawWb::AdvCampaignDailyStat.upsert_all(
            campaign_rows,
            unique_by: :idx_wb_adv_campaign_daily_unique,
            update_only: stat_update_columns
          )
        end
        if product_rows.any?
          RawWb::AdvProductDailyStat.upsert_all(
            product_rows,
            unique_by: :idx_wb_adv_product_daily_unique,
            update_only: product_stat_update_columns
          )
        end
        campaign_rows.size
      end

      def product_stat_rows(campaign, stat_date, day, positions, currency, now)
        details = Hash.new { |hash, key| hash[key] = empty_product_aggregate }
        totals = Hash.new { |hash, key| hash[key] = empty_product_aggregate }

        Array(day["apps"]).each do |app|
          app_type = app["appType"].to_i
          Array(app["nms"]).each do |item|
            nm_id = item["nmId"].to_i
            next if nm_id.zero?

            accumulate_product(details[[app_type, nm_id]], item)
            accumulate_product(totals[nm_id], item)
          end
        end

        rows = details.map do |(app_type, nm_id), values|
          product_row(campaign, stat_date, app_type, nm_id, values, currency, now)
        end
        rows.concat totals.map { |nm_id, values|
          product_row(
            campaign,
            stat_date,
            ALL_APPS_TYPE,
            nm_id,
            values,
            currency,
            now,
            avg_position: positions[[stat_date, nm_id]]
          )
        }
        rows
      end

      def product_row(campaign, stat_date, app_type, nm_id, values, currency, now, avg_position: nil)
        calculated = calculated_rates(values)
        {
          campaign_id: campaign.id,
          stat_date:,
          app_type:,
          nm_id:,
          product_name: values[:product_name],
          views: values[:views],
          clicks: values[:clicks],
          add_to_cart: values[:add_to_cart],
          orders: values[:orders],
          ordered_units: values[:ordered_units],
          canceled: values[:canceled],
          spend: values[:spend],
          revenue: values[:revenue],
          ctr: calculated[:ctr],
          cpc: calculated[:cpc],
          cr: calculated[:cr],
          avg_position:,
          currency:,
          raw_payload: { "items" => values[:raw_items] },
          synced_at: now,
        }
      end

      def stat_row(payload)
        {
          views: payload["views"].to_i,
          clicks: payload["clicks"].to_i,
          add_to_cart: payload["atbs"].to_i,
          orders: payload["orders"].to_i,
          ordered_units: payload["shks"].to_i,
          canceled: payload["canceled"].to_i,
          spend: payload["sum"].to_d,
          revenue: payload["sum_price"].to_d,
          ctr: payload["ctr"],
          cpc: payload["cpc"],
          cr: payload["cr"],
        }
      end

      def empty_product_aggregate
        {
          product_name: nil,
          views: 0,
          clicks: 0,
          add_to_cart: 0,
          orders: 0,
          ordered_units: 0,
          canceled: 0,
          spend: 0.to_d,
          revenue: 0.to_d,
          raw_items: [],
        }
      end

      def accumulate_product(target, item)
        target[:product_name] ||= item["name"]
        target[:views] += item["views"].to_i
        target[:clicks] += item["clicks"].to_i
        target[:add_to_cart] += item["atbs"].to_i
        target[:orders] += item["orders"].to_i
        target[:ordered_units] += item["shks"].to_i
        target[:canceled] += item["canceled"].to_i
        target[:spend] += item["sum"].to_d
        target[:revenue] += item["sum_price"].to_d
        target[:raw_items] << item
      end

      def calculated_rates(values)
        {
          ctr: percentage(values[:clicks], values[:views]),
          cpc: ratio(values[:spend], values[:clicks]),
          cr: percentage(values[:orders], values[:clicks]),
        }
      end

      def ratio(numerator, denominator)
        return 0 if denominator.to_d.zero?

        numerator.to_d / denominator.to_d
      end

      def percentage(numerator, denominator)
        ratio(numerator, denominator) * 100
      end

      def date_chunks(from_date, to_date)
        chunks = []
        cursor = from_date
        while cursor <= to_date
          chunk_to = [cursor + 30, to_date].min
          chunks << [cursor, chunk_to]
          cursor = chunk_to + 1
        end
        chunks
      end

      def expense_fingerprint(payload)
        normalized = payload.sort.to_h
        Digest::SHA256.hexdigest(JSON.generate(normalized))
      end

      def parse_time(value)
        Time.zone.parse(value.to_s) if value.present?
      rescue ArgumentError
        nil
      end

      def sleep_for(key)
        seconds = @sleep_seconds.fetch(key, 0).to_f
        sleep(seconds) if seconds.positive?
      end

      def stat_update_columns
        %i[views clicks add_to_cart orders ordered_units canceled spend revenue ctr cpc cr currency raw_payload synced_at]
      end

      def product_stat_update_columns
        %i[product_name views clicks add_to_cart orders ordered_units canceled spend revenue ctr cpc cr avg_position currency raw_payload synced_at]
      end
    end
  end
end
