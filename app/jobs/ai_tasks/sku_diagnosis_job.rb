require "redis"

module AITasks
  class SkuDiagnosisJob < ApplicationJob
    queue_as :default
    limits_concurrency to: 4,
      key: ->(*) { "sku_diagnoses" },
      duration: 1.hour
    retry_on ErpAI::SkuDiagnosisRunner::Failure, wait: 5.minutes, attempts: 3
    retry_on Redis::BaseError, wait: 30.seconds, attempts: 5

    CHECKPOINT_KEY_PREFIX = "eshop_manage:ai_tasks:sku_diagnosis:checkpoint".freeze
    CHECKPOINT_TTL = 35.days

    def perform(as_of_date: nil, sku_code: nil, rule_ids: nil, summary: false, force: false, checkpoint: nil)
      checkpoint = checkpoint_task?(as_of_date:, sku_code:, rule_ids:, summary:, force:) if checkpoint.nil?
      return enqueue_batch(as_of_date: as_of_date, rule_ids: rule_ids, checkpoint:) if sku_code.blank?

      diagnosis_date = as_of_date.presence || current_date
      return if checkpoint && checkpoint_completed?(diagnosis_date, sku_code)

      result = ErpAI::SkuDiagnosisRunner.run(
        as_of_date: as_of_date,
        sku_code: sku_code,
        rule_ids: rule_ids
      )
      mark_checkpoint_completed(diagnosis_date, sku_code) if checkpoint && result.present?
    end

    class << self
      def checkpoint_key(date)
        "#{CHECKPOINT_KEY_PREFIX}:#{date.to_date.iso8601}"
      end

      def checkpoint_redis
        @checkpoint_redis ||= Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"))
      end
    end

    private

    def enqueue_batch(as_of_date:, rule_ids:, checkpoint:)
      diagnosis_date = as_of_date.presence || Time.current.in_time_zone(ErpAI::SkuDiagnosisRunner::TIME_ZONE).to_date
      sku_codes = ErpAI::SkuDiagnosisRunner.batch_sku_codes(as_of_date: diagnosis_date)
      sku_codes = sku_codes.reject { |batch_sku_code| checkpoint_completed?(diagnosis_date, batch_sku_code) } if checkpoint

      sku_codes.each do |batch_sku_code|
        arguments = {
          as_of_date: diagnosis_date,
          sku_code: batch_sku_code,
          rule_ids: rule_ids
        }
        arguments[:checkpoint] = true if checkpoint
        self.class.perform_later(**arguments)
      end
    end

    def checkpoint_task?(as_of_date:, sku_code:, rule_ids:, summary:, force:)
      as_of_date.blank? && sku_code.blank? && rule_ids.blank? && !summary && !force
    end

    def checkpoint_completed?(date, sku_code)
      self.class.checkpoint_redis.sismember(self.class.checkpoint_key(date), sku_code)
    end

    def mark_checkpoint_completed(date, sku_code)
      key = self.class.checkpoint_key(date)
      self.class.checkpoint_redis.sadd(key, sku_code)
      self.class.checkpoint_redis.expire(key, CHECKPOINT_TTL.to_i)
    end

    def current_date
      Time.current.in_time_zone(ErpAI::SkuDiagnosisRunner::TIME_ZONE).to_date
    end
  end
end
