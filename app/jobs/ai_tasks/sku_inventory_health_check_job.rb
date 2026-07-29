module AITasks
  class SkuInventoryHealthCheckJob < ApplicationJob
    queue_as :default

    TIME_ZONE = "Asia/Shanghai".freeze

    def perform
      time_zone = Time.find_zone!(TIME_ZONE)
      now = Time.current.in_time_zone(time_zone)
      skus = Ec::Sku.select(:id, :sku_code).order(:sku_code).to_a
      metrics_by_sku = Ec::InventoryTurnoverMetricsQuery.new(
        sku_codes: skus.map(&:sku_code),
        date_to: now.to_date,
        time_zone: time_zone
      ).call
      checked_sku_ids = Ec::RestockingDiagnosis
        .where(sku_id: skus.map(&:id), created_at: now.all_day)
        .distinct
        .pluck(:sku_id)
        .index_with(true)

      skus.each do |sku|
        next if metrics_by_sku.dig(sku.sku_code, :turnover_days).nil?
        next if checked_sku_ids.key?(sku.id)

        begin
          AITasks::SkuInventoryHealthCheck.run(sku_code: sku.sku_code)
        rescue StandardError => error
          Rails.logger.error("[AITasks::SkuInventoryHealthCheck] #{error.class}: #{error.message}")
        end
      end
    end
  end
end
