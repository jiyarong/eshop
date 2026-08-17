module AIDiagnosisEventFilterable
  extend ActiveSupport::Concern

  private

  def load_ai_diagnosis_event_filter
    @ai_diagnosis_event_tags = latest_red_ai_diagnosis_events
      .group(:event_type)
      .order(:event_type)
      .count("DISTINCT ec_ai_diagnosis.sku_id")
      .map { |event_type, count| { event_type: event_type, count: count } }
    available_types = @ai_diagnosis_event_tags.pluck(:event_type)
    @ai_diagnosis_event_type = params[:ai_event_type].to_s.presence_in(available_types)
  end

  def apply_ai_diagnosis_event_filter_to_skus(scope)
    return scope if @ai_diagnosis_event_type.blank?

    scope.where(id: ai_diagnosis_event_sku_ids)
  end

  def apply_ai_diagnosis_event_filter_to_sku_records(scope)
    return scope if @ai_diagnosis_event_type.blank?

    scope.where(sku_code: Ec::Sku.where(id: ai_diagnosis_event_sku_ids).select(:sku_code))
  end

  def apply_ai_diagnosis_event_filter_to_master_skus(scope)
    return scope if @ai_diagnosis_event_type.blank?

    scope.where(id: Ec::Sku.where(id: ai_diagnosis_event_sku_ids).select(:master_sku_id))
  end

  def ai_diagnosis_event_filter_active?
    @ai_diagnosis_event_type.present?
  end

  def ai_diagnosis_event_filtered_sku_codes
    @ai_diagnosis_event_filtered_sku_codes ||= Ec::Sku.where(id: ai_diagnosis_event_sku_ids).pluck(:sku_code).to_set
  end

  def load_latest_red_ai_diagnosis_event_types_for(skus)
    load_latest_red_ai_diagnosis_events_for(skus)
    @ai_diagnosis_event_types_by_sku_id
  end

  def load_latest_red_ai_diagnosis_events_for(skus)
    sku_ids = Array(skus).map(&:id)
    events = latest_red_ai_diagnosis_events
      .where(ec_ai_diagnosis: { sku_id: sku_ids })
      .select("ec_ai_diagnosis_events.*", "ec_ai_diagnosis.sku_id AS diagnosis_sku_id")
      .order(:event_type, :position, :id)
      .to_a

    @ai_diagnosis_events_by_sku_id = events.group_by { |event| event.diagnosis_sku_id.to_i }
    @ai_diagnosis_event_types_by_sku_id = @ai_diagnosis_events_by_sku_id.transform_values do |sku_events|
      sku_events.map(&:event_type).uniq
    end

    @ai_diagnosis_events_by_sku_id
  end

  def ai_diagnosis_event_sku_ids
    latest_red_ai_diagnosis_events
      .where(event_type: @ai_diagnosis_event_type)
      .select("ec_ai_diagnosis.sku_id")
  end

  def latest_red_ai_diagnosis_events
    Ec::AIDiagnosisEvent
      .joins(:ai_diagnosis)
      .where(ec_ai_diagnosis: { is_latest: true }, severity: "red")
  end
end
