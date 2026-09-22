module AIDiagnosisEventFilterable
  extend ActiveSupport::Concern

  private

  def load_ai_diagnosis_event_filter(sku_ids: nil)
    @ai_diagnosis_event_tags = latest_active_ai_diagnosis_risk_events(sku_ids: sku_ids)
      .group(:severity, :event_type)
      .order(:severity, :event_type)
      .count("DISTINCT ec_ai_diagnosis.sku_id")
      .map { |(severity, event_type), count| { severity: severity, event_type: event_type, count: count } }
    available_types = @ai_diagnosis_event_tags.pluck(:event_type)
    @ai_diagnosis_event_type = params[:ai_event_type].to_s.presence_in(available_types)
  end

  def load_ai_diagnosis_advice_filter(sku_ids: nil)
    @ai_diagnosis_advice_tags = latest_active_ai_diagnosis_advice_events(sku_ids: sku_ids)
      .group(:event_type)
      .order(:event_type)
      .count("DISTINCT ec_ai_diagnosis.sku_id")
      .map { |event_type, count| { event_type: event_type, count: count } }
    available_types = @ai_diagnosis_advice_tags.pluck(:event_type)
    @ai_diagnosis_advice_type = params[:ai_advice_type].to_s.presence_in(available_types)
  end

  def apply_ai_diagnosis_event_filter_to_skus(scope)
    return scope if @ai_diagnosis_event_type.blank?

    scope.where(id: ai_diagnosis_event_sku_ids)
  end

  def apply_ai_diagnosis_advice_filter_to_skus(scope)
    return scope if @ai_diagnosis_advice_type.blank?

    scope.where(id: ai_diagnosis_advice_sku_ids)
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

  def load_latest_active_ai_diagnosis_risk_event_types_for(skus)
    load_latest_active_ai_diagnosis_risk_events_for(skus)
    @ai_diagnosis_event_types_by_sku_id
  end

  def load_latest_active_ai_diagnosis_risk_events_for(skus)
    sku_ids = Array(skus).map(&:id)
    events = latest_active_ai_diagnosis_events
      .where(ec_ai_diagnosis: { sku_id: sku_ids })
      .where(severity: %w[critical warning])
      .where("ec_ai_diagnosis_events.sub_agent_id IS NOT NULL OR ec_ai_diagnosis_events.scope = ?", "advise")
      .select("ec_ai_diagnosis_events.*", "ec_ai_diagnosis.sku_id AS diagnosis_sku_id")
      .order(:event_type, :position, :id)
      .to_a

    @ai_diagnosis_events_by_sku_id = events.group_by { |event| event.diagnosis_sku_id.to_i }
    @ai_diagnosis_event_types_by_sku_id = @ai_diagnosis_events_by_sku_id.transform_values do |sku_events|
      sku_events.select { |event| event.sub_agent_id.present? }.map(&:event_type).uniq
    end

    @ai_diagnosis_events_by_sku_id
  end

  def ai_diagnosis_event_sku_ids
    latest_active_ai_diagnosis_risk_events
      .where(event_type: @ai_diagnosis_event_type)
      .select("ec_ai_diagnosis.sku_id")
  end

  def ai_diagnosis_advice_sku_ids
    latest_active_ai_diagnosis_advice_events
      .where(event_type: @ai_diagnosis_advice_type)
      .select("ec_ai_diagnosis.sku_id")
  end

  def latest_active_ai_diagnosis_risk_events(sku_ids: nil)
    events = latest_active_ai_diagnosis_events
      .where(severity: %w[critical warning])
      .where.not(sub_agent_id: nil)
    sku_ids ? events.where(ec_ai_diagnosis: { sku_id: sku_ids }) : events
  end

  def latest_active_ai_diagnosis_advice_events(sku_ids: nil)
    events = latest_active_ai_diagnosis_events.where(sub_agent_id: nil, scope: "advise", severity: "critical")
    sku_ids ? events.where(ec_ai_diagnosis: { sku_id: sku_ids }) : events
  end

  def latest_active_ai_diagnosis_events
    Ec::AIDiagnosisEvent
      .joins(:ai_diagnosis)
      .active
      .where(is_latest: true)
      .where(ec_ai_diagnosis: { type: Ec::GeneralDiagnosis.sti_name })
  end
end
