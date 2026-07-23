module Reports
  class OzonAdsController < ApplicationController
    before_action -> { require_permission!(:view_reports) }
    before_action :load_context

    def overview
      @rows = analytics.overview_rows
      @summary = analytics.summary(@rows)
    end

    def cpc
      @query = params[:q].to_s.strip
      @states = cpc_states
      @rows = analytics.cpc_rows(query: @query, states: @states)
      @summary = analytics.summary(@rows)
    end

    def cpc_detail
      @unit = RawOzon::AdUnit.where(account_id: @account.id, unit_type: "cpc_campaign").find_by!(external_id: params[:id])
      @query = params[:q].to_s.strip
      @rows = analytics.cpc_detail(@unit, query: @query)
      @summary = analytics.summary(@rows)
    end

    def cpo_selected
      @query = params[:q].to_s.strip
      @unit, @rows = analytics.cpo_selected_rows(query: @query)
      @summary = analytics.summary(@rows)
    end

    private

    def load_context
      @stores = Ec::Store.where(platform: "ozon", is_active: true).where.not(ozon_raw_account_id: nil).order(:store_name)
      @store = @stores.find_by(id: params[:store_id]) || @stores.find_by(store_name: "NEVASTAL") || @stores.first
      raise ActiveRecord::RecordNotFound, "No Ozon store configured" unless @store
      @account = @store.raw_ozon_account
      @to_date = report_date(params[:to_date]) || RawOzon::AdDailyStat.where(account_id: @account.id).maximum(:stat_date) || Date.yesterday
      @from_date = report_date(params[:from_date]) || (@to_date - 14)
      @from_date, @to_date = @to_date, @from_date if @from_date > @to_date
    end

    def analytics
      @analytics ||= RawOzon::Ads::AnalyticsQuery.new(
        account: @account, store: @store, from_date: @from_date, to_date: @to_date
      )
    end

    def report_date(value)
      Date.iso8601(value.to_s)
    rescue Date::Error
      nil
    end

    def cpc_states
      return %w[CAMPAIGN_STATE_RUNNING CAMPAIGN_STATE_INACTIVE] unless params.key?(:statuses)

      Array(params[:statuses]).filter_map { |state| state.presence_in(RawOzon::AdUnit::STATES) }.uniq
    end
  end
end
