module AITasks
  class SkuGradeInspector
    AGENT_CODE = "sku_grade_inspector".freeze
    TIME_ZONE = "Asia/Shanghai".freeze
    LOOKBACK_WEEKS = 8
    MAX_ATTEMPTS = 2

    class MissingPersistedResult < StandardError; end

    def self.run(as_of_date: nil, sku_code: nil, client: nil, user: nil)
      new(as_of_date: as_of_date, sku_code: sku_code, client: client, user: user).run
    end

    def initialize(as_of_date:, sku_code:, client:, user:)
      @time_zone = Time.find_zone!(TIME_ZONE)
      @as_of_date = (as_of_date || Time.current.in_time_zone(@time_zone).to_date).to_date
      @sku_code = sku_code.to_s.strip.upcase.presence
      @client = client
      @user = user
    end

    def run
      candidate_skus.filter_map do |sku|
        next if inspected_for_period?(sku)

        inspect_sku(sku)
      rescue StandardError => error
        Rails.logger.error("[AITasks::SkuGradeInspector] SKU #{sku.sku_code}: #{error.class}: #{error.message}")
        nil
      end
    end

    private

    attr_reader :as_of_date, :client, :time_zone

    def candidate_skus
      scope = Ec::Sku.active.order(:sku_code)
      scope = scope.where(sku_code: @sku_code) if @sku_code
      sku_codes = scope.pluck(:sku_code)
      return scope.none if sku_codes.empty? || !Ec::WeeklyRate.exists?(week_start: last_week_start)

      scope.where(sku_code: weekly_profit_sku_codes(sku_codes))
    end

    def weekly_profit_sku_codes(sku_codes)
      report = Ec::WeeklySummaryDeepQuery.run(
        from_date: last_week_start,
        to_date: analysis_cutoff_date,
        sku_codes: sku_codes
      )

      Array(report[:rows] || report["rows"]).filter_map do |row|
        (row[:sku] || row["sku"]).to_s.strip.upcase.presence
      end
    end

    def inspect_sku(sku)
      agent = Agent.ensure_fixed!(AGENT_CODE)
      agent.system_prompt = Agent::SKU_GRADE_INSPECTOR_PROMPT
      runner_options = { agent: agent, user: diagnosis_user }
      runner_options[:client] = client if client
      runner = ErpAI::AgentRunner.new(**runner_options)

      MAX_ATTEMPTS.times do |attempt|
        conversation = runner.ask(
          question: question(sku, retrying: attempt.positive?),
          module_name: "sku_grade_inspections",
          business_object_type: "Ec::Sku",
          business_object_id: sku.id.to_s,
          time_range: {
            from: analysis_start_date.iso8601,
            to: analysis_cutoff_date.iso8601
          }
        )
        diagnosis = diagnosis_for_period(sku)
        if diagnosis&.events&.exists?
          diagnosis.events.where(conversation_id: nil).update_all(
            conversation_id: conversation.id,
            updated_at: Time.current
          )
          return conversation
        end

        Rails.logger.warn(
          "[AITasks::SkuGradeInspector] SKU #{sku.sku_code}: no persisted diagnosis events after attempt #{attempt + 1}"
        )
      end

      raise MissingPersistedResult, "Grade diagnosis and events were not persisted after #{MAX_ATTEMPTS} attempts"
    end

    def question(sku, retrying: false)
      question = <<~QUESTION.squish
        检查 SKU #{sku.sku_code} 的 Grade。检查基准日期为 #{as_of_date.iso8601}，
        只使用 #{analysis_start_date.iso8601} 至 #{analysis_cutoff_date.iso8601} 的最近 8 个完整自然周。
        逐日库存证据通过 GET /ai/skus/inventory_availability 获取，参数为 sku、from_date、to_date。
        严格按系统提示完成所有查询、判断，并将完整结果 POST 到 /ai/diagnosis_results；不要修改 Grade 或 Stage。
      QUESTION
      return question unless retrying

      "#{question} 上一次执行后未检测到包含事件的落库结果；本次必须实际调用写回接口，不能只在最终回答中声称已提交。"
    end

    def inspected_for_period?(sku)
      diagnosis_for_period(sku)&.events&.exists? || false
    end

    def diagnosis_for_period(sku)
      sku.grade_inspects.find_by("data ->> 'analysis_cutoff_date' = ?", analysis_cutoff_date.iso8601)
    end

    def current_week_start
      @current_week_start ||= as_of_date.beginning_of_week(:monday)
    end

    def analysis_start_date
      @analysis_start_date ||= current_week_start - LOOKBACK_WEEKS.weeks
    end

    def analysis_cutoff_date
      @analysis_cutoff_date ||= current_week_start - 1.day
    end

    def last_week_start
      @last_week_start ||= analysis_cutoff_date.beginning_of_week(:monday)
    end

    def diagnosis_user
      @diagnosis_user ||= @user || User.where(active: true)
        .joins(:roles)
        .where(roles: { code: "super_admin" })
        .order(:id)
        .first || User.where(active: true).order(:id).first || raise("No active user available for AI diagnosis")
    end
  end
end
