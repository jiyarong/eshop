module RawWb
  class CommissionTariffResolver
    STALE_AFTER_DAYS = 45

    FIELD_BY_DELIVERY_MODE = {
      "fbs" => :kgvp_marketplace,
      "fbo" => :paid_storage_kgvp,
      "fbw" => :paid_storage_kgvp
    }.freeze

    class ResolutionError < StandardError
      attr_reader :code

      def initialize(code)
        @code = code
        super(code.to_s)
      end
    end

    def rate_for(wb_subject_id:, delivery_mode:)
      field = FIELD_BY_DELIVERY_MODE[delivery_mode.to_s]
      raise ResolutionError.new(:unsupported_delivery_mode) unless field

      snapshot = RawWb::CommissionTariffSnapshot.current
      raise ResolutionError.new(:missing_snapshot) unless snapshot

      value = RawWb::CommissionTariff.where(snapshot_id: snapshot.id, wb_subject_id: wb_subject_id).pick(field)
      raise ResolutionError.new(:missing_subject_tariff) if value.nil?

      if snapshot.fetched_at && snapshot.fetched_at < STALE_AFTER_DAYS.days.ago
        Rails.logger.warn("[RawWb::CommissionTariffResolver] snapshot ##{snapshot.id} is stale (fetched_at=#{snapshot.fetched_at})")
      end

      value / BigDecimal(100)
    end

    def rate_for_wb_product(product:, delivery_mode:)
      subject_wb_id = RawWb::Subject.where(id: product.subject_id).pick(:wb_id)
      raise ResolutionError.new(:missing_subject_tariff) unless subject_wb_id

      rate_for(wb_subject_id: subject_wb_id, delivery_mode: delivery_mode)
    end
  end
end
