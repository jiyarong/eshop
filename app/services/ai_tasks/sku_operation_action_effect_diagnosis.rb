module AITasks
  class SkuOperationActionEffectDiagnosis
    AGENT_CODE = "sku_operation_action_tracker".freeze
    DIAGNOSIS_KIND = "operation_action_effect".freeze
    TIME_ZONE = "Asia/Shanghai".freeze
    OBSERVATION_WEEKS = 5
    MAX_LOOKBACK_WEEKS = OBSERVATION_WEEKS * 2
    EFFECTIVENESS_VALUES = %w[positive negative mixed inconclusive].freeze
    CONFIDENCE_VALUES = %w[high medium low].freeze
    EVENT_POLICY_PROMPT = "只返回对经营结果有明显影响、需要观察或需要行动的事件；省略日常小幅波动、低销量噪声、预期滞后和无实质变化的 action；无重要事件时 events 返回空数组。".freeze
    INPUT_STRUCTURE_PROMPT = "field_definitions 用中文说明输入字段含义。action_timeline 已按 operated_at、id 升序排列，diagnosis_target 标识待诊断 action；changes 中的数值变更包含具体前后值，notes 列出实际备注文字。weekly_metrics 中 stores.*.profit_report 来自周利润报表，inventory_snapshots 来自库存快照，sales_funnel 保留销售漏斗数据；所有指标数组与 weeks 数组按索引对齐，null 表示该周缺少对应数据。指标序列独立于 action，必须先判断时间关联和同期干扰，不得将周指标预先归因给单个 action。若此前说明与此冲突，以当前输入结构为准。".freeze
    FIELD_DEFINITIONS = {
      action_timeline: {
        id: "运营 action 的数据库 ID，也是 events.action_id 的取值",
        operation_type: "运营操作类型",
        operated_at: "操作发生时间，使用 Asia/Shanghai 时区",
        weeks_ago: "操作所在自然周距离当前自然周的周数",
        platform: "操作所属电商平台",
        store: "操作所属店铺名称",
        changes: "字段变更摘要；数字变更包含具体前后值",
        notes: "运营备注的具体文字列表",
        diagnosis_target: "是否为本次需要诊断效果的目标 action"
      },
      weekly_metrics: {
        weeks: {
          start: "自然周开始日期（周一）",
          end: "自然周结束日期（周日）",
          weeks_ago: "该自然周距离当前自然周的周数"
        },
        store: {
          id: "系统店铺 ID",
          name: "店铺名称",
          platform: "店铺所属平台",
          currency: "该店铺周利润报表金额字段使用的币种"
        },
        profit_report: {
          report_available: "该周是否成功取得周利润报表数据",
          sales_quantity: "WB 销售件数",
          order_quantity: "Ozon 订单数",
          return_quantity: "退货件数或退货订单数",
          net_sales_quantity: "扣除退货后的净销量",
          gross_sales_amount: "WB 折扣后零售总额，币种见店铺 currency",
          settlement_amount: "WB 平台结算额，币种见店铺 currency",
          sales_revenue: "Ozon 销售收入，币种见店铺 currency",
          commission_cost: "平台佣金费用；正数表示费用，负数表示冲回",
          delivery_cost: "配送或物流费用；正数表示费用，负数表示冲回",
          storage_cost: "仓储费用；正数表示费用，负数表示冲回",
          advertising_cost: "广告费用；正数表示费用，负数表示冲回",
          goods_cost: "净销量对应的货物成本；正数表示成本，负数表示成本冲回",
          pre_tax_profit: "扣除平台费用、广告费和货物成本后的税前利润",
          tax: "税费金额",
          after_tax_profit: "扣除税费后的净利润",
          after_tax_margin_pct: "税后净利润占销售收入的百分比"
        },
        inventory: {
          snapshot_available: "该周是否存在对应库存快照",
          snapshot_date: "该周采用的最新库存快照日期",
          incoming_quantity: "采购批次中尚未转为账面库存的在途数量",
          book_stock: "SKU 账面库存数量",
          platform_inbound_stock: "发往平台仓但尚未入仓的数量",
          platform_stock: "平台仓可售库存数量，包含 FBW/FBO",
          available_stock: "账面库存扣除平台库存及平台在途后的可用数量",
          daily_sales_velocity: "库存快照计算的日均销售速度",
          turnover_days: "按当前库存和销售速度计算的库存周转天数",
          turnover_days_with_procurement: "包含采购在途后的库存周转天数",
          total_quantity: "店铺所有履约类型及在途库存数量合计",
          inbound_quantity: "该店铺发往平台仓的在途数量",
          fbw_quantity: "WB 平台仓履约库存数量",
          fbo_quantity: "Ozon 平台仓履约库存数量",
          fbs_quantity: "商家仓履约库存数量",
          out_of_stock: "平台仓库存是否为零"
        },
        sales_funnel: {
          funnel_coverage_days: "该周有销售漏斗源数据的天数",
          views: "商品浏览次数",
          sessions: "商品访问会话数",
          add_to_cart: "加入购物车次数",
          funnel_orders: "销售漏斗记录的下单件数",
          revenue: "销售漏斗数据源记录的下单金额，不替代周利润报表销售收入",
          buyouts: "签收或买断件数",
          returns: "销售漏斗记录的退货件数",
          cancellations: "销售漏斗记录的取消件数",
          wishlist: "加入心愿单次数",
          stock_wb: "WB 漏斗数据源记录的平台仓库存",
          stock_mp: "WB 漏斗数据源记录的商家仓库存",
          view_to_cart_pct: "浏览到加购转化率（%）",
          cart_to_order_pct: "加购到下单转化率（%）",
          view_to_order_pct: "浏览到下单转化率（%）"
        }
      }
    }.freeze

    def self.run(as_of_date: nil, client: ErpAI::DefaultClient.new, user: nil)
      new(as_of_date: as_of_date, client: client, user: user).run
    end

    def initialize(as_of_date:, client:, user:)
      @time_zone = Time.find_zone!(TIME_ZONE)
      @as_of_date = (as_of_date || Time.current.in_time_zone(@time_zone).to_date).to_date
      @client = client
      @user = user
    end

    def run
      candidate_skus.filter_map do |sku|
        next if diagnosed_for_period?(sku)

        diagnose_sku(sku)
      rescue StandardError => error
        Rails.logger.error(
          "[AITasks::SkuOperationActionEffectDiagnosis] SKU #{sku.sku_code}: #{error.class}: #{error.message}"
        )
        nil
      end
    end

    private

    attr_reader :as_of_date, :client, :time_zone

    def candidate_skus
      Ec::Sku.where(id: target_action_scope.select(:ec_sku_id)).order(:sku_code)
    end

    def target_action_scope
      Ec::OperationAction.where(operated_at: target_action_range)
    end

    def diagnose_sku(sku)
      actions = recent_actions_for(sku)
      target_actions = actions.select { |action| action_week_offset(action).between?(1, OBSERVATION_WEEKS) }
      return if target_actions.empty?

      metrics = metrics_for(sku)
      weekly_metrics = weekly_metric_series(metrics)
      evaluations = target_actions.map { |action| evaluate_action(action, weekly_metrics) }
      target_action_ids = target_actions.map(&:id).to_set
      recent_actions = actions.reject { |action| target_action_ids.include?(action.id) }.map { |action| serialize_action(action) }
      action_timeline = actions.map do |action|
        serialize_action(action).merge(diagnosis_target: target_action_ids.include?(action.id))
      end
      ai_result, conversation = analyze(sku, action_timeline, weekly_metrics)
      persist_diagnosis(sku, ai_result, evaluations, recent_actions, conversation)
    end

    def recent_actions_for(sku)
      sku.operation_actions
        .includes(:sku_product, :store)
        .where(operated_at: analysis_data_range)
        .order(:operated_at, :id)
        .to_a
    end

    def target_action_range
      time_for_date(current_week_start - OBSERVATION_WEEKS.weeks).beginning_of_day..
        time_for_date(analysis_cutoff_date).end_of_day
    end

    def analysis_data_range
      time_for_date(analysis_start_date).beginning_of_day..
        time_for_date(analysis_cutoff_date).end_of_day
    end

    def metrics_for(sku)
      Ec::SkuOperationActionMetricsQuery.new(
        sku: sku,
        from_date: analysis_start_date,
        to_date: analysis_cutoff_date,
        time_zone: time_zone
      ).call
    end

    def evaluate_action(action, weekly_metrics)
      date = action_date(action)
      weeks_ago = action_week_offset(action)
      action_week_start = date.beginning_of_week(:monday)
      platform = action.sku_product.platform
      before = window_metrics(
        weekly_metrics,
        from_date: action_week_start - weeks_ago.weeks,
        to_date: action_week_start - 1.day,
        platform: platform,
        store_id: action.store.id
      )
      after = window_metrics(
        weekly_metrics,
        from_date: action_week_start,
        to_date: analysis_cutoff_date,
        platform: platform,
        store_id: action.store.id
      )

      {
        action: serialize_action(action),
        periods: {
          before: comparison_period(before),
          after: comparison_period(after)
        },
        metrics: metric_comparisons(before.fetch(:metrics), after.fetch(:metrics))
      }
    end

    def window_metrics(weekly_metrics, from_date:, to_date:, platform:, store_id:)
      return empty_window(from_date, to_date) if to_date < from_date

      indices = weekly_metrics.fetch(:weeks).each_index.select do |index|
        week_start = Date.iso8601(weekly_metrics.dig(:weeks, index, :start))
        week_start.between?(from_date, to_date)
      end
      metric_values = {}
      append_window_metrics(
        metric_values,
        weekly_metrics.dig(:stores, store_id.to_s, :profit_report),
        prefix: :profit,
        indices: indices
      )
      append_window_metrics(
        metric_values,
        weekly_metrics.dig(:stores, store_id.to_s, :inventory),
        prefix: :store_inventory,
        indices: indices
      )
      append_window_metrics(
        metric_values,
        weekly_metrics.dig(:inventory_snapshots, :sku),
        prefix: :sku_inventory,
        indices: indices
      )
      append_window_metrics(
        metric_values,
        weekly_metrics.dig(:sales_funnel, platform),
        prefix: :funnel,
        indices: indices
      )
      funnel_coverage = Array(weekly_metrics.dig(:sales_funnel, platform, :funnel_coverage_days))
      funnel_days = indices.sum { |index| funnel_coverage[index].to_i }

      {
        from_date: from_date.iso8601,
        to_date: to_date.iso8601,
        days_count: indices.size * 7,
        weeks_count: indices.size,
        funnel_coverage_days: funnel_days,
        metrics: metric_values
      }
    end

    def append_window_metrics(result, series, prefix:, indices:)
      return unless series

      series.each do |metric, values|
        next unless values.is_a?(Array)
        next if metric.to_s.in?(%w[report_available snapshot_available snapshot_date out_of_stock])

        numeric_values = indices.filter_map { |index| values[index] }.select { |value| value.is_a?(Numeric) }
        next if numeric_values.empty?

        result["#{prefix}_#{metric}_weekly".to_sym] = decimal(numeric_values.sum, numeric_values.size)
      end
    end

    def empty_window(from_date, to_date)
      {
        from_date: from_date.iso8601,
        to_date: to_date.iso8601,
        days_count: 0,
        weeks_count: 0,
        funnel_coverage_days: 0,
        metrics: {}
      }
    end

    def comparison_period(window)
      {
        from: window.fetch(:from_date),
        to: window.fetch(:to_date),
        weeks: window.fetch(:weeks_count),
        coverage_days: window.fetch(:funnel_coverage_days)
      }
    end

    def metric_comparisons(before, after)
      (before.keys | after.keys).each_with_object({}) do |metric, result|
        before_value = before[metric]
        after_value = after[metric]
        next if before_value.nil? || after_value.nil? || before_value == after_value

        result[metric] = {
          before: before_value,
          after: after_value,
          delta_pct: before_value.to_d.zero? ? nil : round_number((after_value - before_value) / before_value.to_d * 100)
        }
      end
    end

    def weekly_metric_series(metrics)
      week_starts = (analysis_start_date..analysis_cutoff_date).step(7).to_a
      weeks = week_starts.map do |week_start|
        {
          start: week_start.iso8601,
          end: (week_start + 6.days).iso8601,
          weeks_ago: ((current_week_start - week_start) / 7).to_i
        }
      end
      stores = metrics.fetch(:stores)
      profit = metrics.fetch(:weekly_profit_by_week_and_store)
      inventory = metrics.fetch(:inventory_snapshots_by_week)
      funnel = metrics.fetch(:funnel_by_day_and_platform)
      platforms = (stores.values.map { |store| store.fetch(:platform) } + funnel.keys.map(&:second)).uniq.sort
      store_series = stores.each_with_object({}) do |(store_id, metadata), result|
        profit_snapshots = week_starts.map { |week_start| profit[[ week_start, store_id ]] }
        inventory_snapshots = week_starts.map do |week_start|
          snapshot = inventory[week_start]
          store_metrics = snapshot&.dig(:stores, store_id)
          store_metrics&.merge(snapshot_date: snapshot.fetch(:snapshot_date))
        end
        result[store_id.to_s] = metadata.merge(
          profit_report: {
            report_available: profit_snapshots.map(&:present?)
          }.merge(transpose_metric_snapshots(profit_snapshots)),
          inventory: {
            snapshot_available: inventory_snapshots.map(&:present?)
          }.merge(transpose_metric_snapshots(inventory_snapshots))
        )
      end

      {
        weeks: weeks,
        stores: store_series,
        inventory_snapshots: {
          sku: {
            snapshot_available: week_starts.map { |week_start| inventory[week_start].present? }
          }.merge(
            transpose_metric_snapshots(
              week_starts.map do |week_start|
                snapshot = inventory[week_start]
                snapshot&.fetch(:sku)&.merge(snapshot_date: snapshot.fetch(:snapshot_date))
              end
            )
          )
        },
        sales_funnel: platforms.index_with do |platform|
          transpose_metric_snapshots(
            week_starts.map { |week_start| weekly_funnel_snapshot(funnel, week_start, platform) }
          )
        end
      }
    end

    def weekly_funnel_snapshot(funnel, week_start, platform)
      dates = (week_start..(week_start + 6.days)).to_a
      funnel_totals = Hash.new(0.to_d)
      coverage_days = 0

      dates.each do |date|
        day_metrics = funnel.fetch([ date, platform ], {})
        coverage_days += 1 if day_metrics.fetch(:source_rows, 0).positive?
        day_metrics.each do |metric, value|
          funnel_totals[metric] += value.to_d unless metric == :source_rows
        end
      end

      metrics = { funnel_coverage_days: coverage_days }
      if coverage_days.positive?
        funnel_totals.each { |metric, total| metrics[metric] = round_number(total) }
        metrics[:view_to_cart_pct] = percent(funnel_totals[:add_to_cart], funnel_totals[:views])
        metrics[:cart_to_order_pct] = percent(funnel_totals[:funnel_orders], funnel_totals[:add_to_cart])
        metrics[:view_to_order_pct] = percent(funnel_totals[:funnel_orders], funnel_totals[:views])
      end
      metrics
    end

    def transpose_metric_snapshots(snapshots)
      metric_names = snapshots.compact.flat_map(&:keys).uniq
      metric_names.index_with do |metric|
        snapshots.map { |snapshot| snapshot&.[](metric) }
      end
    end

    def analyze(sku, action_timeline, weekly_metrics)
      agent = Agent.ensure_fixed!(AGENT_CODE)
      question = {
        task: "结合按时间排列的 action 与逐周指标序列，诊断 diagnosis_target action 的可能效果；不要预先将指标变化归因给某个 action，并把同期 action 作为混杂因素",
        event_policy: EVENT_POLICY_PROMPT,
        as_of_date: as_of_date.iso8601,
        analysis_cutoff_date: analysis_cutoff_date.iso8601,
        sku: sku.sku_code,
        observation_weeks: OBSERVATION_WEEKS,
        max_lookback_weeks: MAX_LOOKBACK_WEEKS,
        week_starts_on: "monday",
        metric_granularity: "natural_week",
        field_definitions: FIELD_DEFINITIONS,
        action_timeline: action_timeline,
        weekly_metrics: weekly_metrics
      }.to_json
      conversation = agent.conversations.create!(
        user: diagnosis_user,
        module_name: "sku_operation_actions",
        business_object_type: "Ec::Sku",
        business_object_id: sku.id.to_s,
        time_range: {
          from: analysis_start_date.iso8601,
          to: analysis_cutoff_date.iso8601
        },
        context: {
          sku_code: sku.sku_code,
          diagnosis_kind: DIAGNOSIS_KIND
        }
      )
      conversation.messages.create!(role: "user", content: question)
      response = client.complete(
        model: agent.model_id,
        temperature: agent.temperature.to_f,
        thinking_enabled: agent.thinking_enabled?,
        system_prompt: [
          agent.system_prompt,
          "当前输入结构：#{INPUT_STRUCTURE_PROMPT}",
          "当前任务额外规则：#{EVENT_POLICY_PROMPT}"
        ].join("\n"),
        context: "",
        messages: [ { role: "user", content: question } ],
        tools: []
      )
      content = response.fetch(:content)
      conversation.messages.create!(
        role: "assistant",
        content: content.is_a?(String) ? content : content.to_json,
        usage: response.fetch(:usage, {})
      )
      [ normalize_ai_result(content), conversation ]
    end

    def normalize_ai_result(content)
      payload = content.is_a?(Hash) ? content.deep_stringify_keys : parse_json_content(content)
      effectiveness = payload["effectiveness"].to_s
      confidence = payload["confidence"].to_s
      raise ArgumentError, "invalid AI effectiveness" unless effectiveness.in?(EFFECTIVENESS_VALUES)
      raise ArgumentError, "invalid AI confidence" unless confidence.in?(CONFIDENCE_VALUES)
      raise ArgumentError, "AI summary is required" if payload["summary"].blank?
      raise ArgumentError, "AI events must be an array" unless payload["events"].is_a?(Array)

      payload
    end

    def parse_json_content(content)
      text = content.to_s
      json = text[/```(?:json)?\s*(.*?)(?:```|\z)/m, 1] || text
      JSON.parse(json.strip)
    end

    def persist_diagnosis(sku, ai_result, evaluations, recent_actions, conversation)
      diagnosis = nil
      sku.with_lock do
        if diagnosed_for_period?(sku)
          conversation.destroy!
          return
        end

        diagnosis = sku.operation_action_diagnoses.create!(
          submitted_by: diagnosis_user,
          analyzed_at: time_for_date(as_of_date).noon,
          data: {
            diagnosis_kind: DIAGNOSIS_KIND,
            observation_date: as_of_date.iso8601,
            analysis_cutoff_date: analysis_cutoff_date.iso8601,
            observation_weeks: OBSERVATION_WEEKS,
            max_lookback_weeks: MAX_LOOKBACK_WEEKS,
            week_starts_on: "monday",
            metric_granularity: "weekly_average",
            summary: ai_result.fetch("summary"),
            effectiveness: ai_result.fetch("effectiveness"),
            confidence: ai_result.fetch("confidence"),
            action_evaluations: evaluations,
            recent_actions: recent_actions
          }
        )
        events = diagnosis_events(ai_result, evaluations, conversation)
        diagnosis.events.create!(events) if events.any?
      end
      diagnosis
    end

    def diagnosis_events(ai_result, evaluations, conversation)
      evaluations_by_action_id = evaluations.index_by { |evaluation| evaluation.dig(:action, :id) }

      ai_result.fetch("events").filter_map.with_index do |event, position|
        next unless event.is_a?(Hash)

        ai_event = event.deep_stringify_keys
        action_id = Integer(ai_event["action_id"], exception: false)
        evaluation = evaluations_by_action_id[action_id]
        next unless evaluation

        action = evaluation.fetch(:action)
        effect = ai_event["effect"].to_s
        effect = "inconclusive" unless effect.in?(EFFECTIVENESS_VALUES)
        {
          conversation: conversation,
          event_type: "operation_action_effect",
          severity: normalized_severity(ai_event["severity"], effect),
          scope: action.fetch(:operation_type),
          message: ai_event["message"].presence || "该 action 暂无足够数据形成可靠结论。",
          details: evaluation.merge(
            ai_effect: effect,
            recommendations: Array(ai_event["recommendations"]).map(&:to_s)
          ),
          position: position
        }
      end
    end

    def normalized_severity(value, effect)
      return value if value.to_s.in?(%w[info warning critical])

      effect == "negative" ? "warning" : "info"
    end

    def diagnosed_for_period?(sku)
      sku.operation_action_diagnoses
        .where("data ->> 'diagnosis_kind' = ?", DIAGNOSIS_KIND)
        .where("data ->> 'analysis_cutoff_date' = ?", analysis_cutoff_date.iso8601)
        .exists?
    end

    def serialize_action(action)
      summary = {
        id: action.id,
        operation_type: action.operation_type,
        operated_at: action.operated_at.in_time_zone(time_zone).iso8601,
        weeks_ago: action_week_offset(action),
        platform: action.sku_product.platform,
        store: action.store.store_name,
        changes: action_change_summary(action)
      }
      notes = action_notes(action)
      summary[:notes] = notes if notes.any?
      summary
    end

    def action_change_summary(action)
      fields = action.diff_result.fetch("fields", {})
      return [ "新增 #{diff_field_label('note')}" ] if action.operation_type == "manual_note"

      fields.flat_map do |field, change|
        summarize_field_change(diff_field_label(field), change.to_h.deep_stringify_keys)
      end
    end

    def summarize_field_change(label, change)
      summaries = []
      added = Array(change["added"])
      removed = Array(change["removed"])

      summaries << summarize_collection_change("新增", label, added) if added.any?
      summaries << summarize_collection_change("移除", label, removed) if removed.any?

      if change.key?("from") || change.key?("to")
        summaries << summarize_value_change(label, change["from"], change["to"])
      elsif change.key?("primary_from") || change.key?("primary_to")
        if change["primary_from"] != change["primary_to"]
          verb = empty_change_value?(change["primary_from"]) ? "新增" : "修改"
          summaries << "#{verb} #{diff_field_label('primary_image')}"
        end
      elsif summaries.empty?
        nested_summaries = change.flat_map do |field, nested_change|
          next [] unless nested_change.respond_to?(:to_h)

          nested_label = "#{label} / #{diff_field_label(field)}"
          summarize_field_change(nested_label, nested_change.to_h.deep_stringify_keys)
        end
        summaries.concat(nested_summaries.presence || [ "修改 #{label}" ])
      end

      summaries.compact.uniq
    end

    def summarize_collection_change(verb, label, values)
      return "#{verb} #{label}：#{values.join('、')}" if values.all? { |value| numeric_change_value?(value) }
      return "新增 #{label}（#{values.size}项）" if verb == "新增"

      "修改 #{label}（移除#{values.size}项）"
    end

    def summarize_value_change(label, from, to)
      return if from == to

      if numeric_change?(from, to)
        return "新增 #{label}：#{to}" if empty_change_value?(from)
        return "移除 #{label}：#{from}" if empty_change_value?(to)

        return "修改 #{label}：#{from} → #{to}"
      end

      verb = empty_change_value?(from) && !empty_change_value?(to) ? "新增" : "修改"
      "#{verb} #{label}"
    end

    def numeric_change?(from, to)
      values = [ from, to ].reject { |value| empty_change_value?(value) }
      values.any? && values.all? { |value| numeric_change_value?(value) }
    end

    def numeric_change_value?(value)
      return true if value.is_a?(Numeric)
      return false unless value.is_a?(String) && value.strip.present?

      BigDecimal(value, exception: false).present?
    end

    def action_notes(action)
      diff = action.diff_result.deep_stringify_keys
      note_change = diff.dig("fields", "note")
      notes = [ diff["note"], *Array(diff["notes"]) ]
      notes << note_change["to"] if note_change.is_a?(Hash)
      notes.flatten.compact.map { |note| note.to_s.strip }.reject(&:blank?).uniq
    end

    def diff_field_label(field)
      I18n.t("erp.operation_actions.diff_fields.#{field}", default: field.to_s)
    end

    def empty_change_value?(value)
      value.nil? || value == "" || value == [] || value == {}
    end

    def diagnosis_user
      @diagnosis_user ||= @user || User.where(active: true)
        .joins(:roles)
        .where(roles: { code: "super_admin" })
        .order(:id)
        .first || User.where(active: true).order(:id).first || raise("No active user available for AI diagnosis")
    end

    def action_date(action)
      action.operated_at.in_time_zone(time_zone).to_date
    end

    def analysis_cutoff_date
      @analysis_cutoff_date ||= current_week_start - 1.day
    end

    def analysis_start_date
      @analysis_start_date ||= current_week_start - MAX_LOOKBACK_WEEKS.weeks
    end

    def current_week_start
      @current_week_start ||= as_of_date.beginning_of_week(:monday)
    end

    def action_week_offset(action)
      ((current_week_start - action_date(action).beginning_of_week(:monday)) / 7).to_i
    end

    def decimal(value, divisor)
      round_number(value.to_d / divisor)
    end

    def percent(numerator, denominator)
      return nil unless denominator.to_d.positive?

      round_number(numerator.to_d / denominator.to_d * 100)
    end

    def round_number(value)
      value.to_d.round(4).to_f
    end

    def time_for_date(date)
      time_zone.local(date.year, date.month, date.day)
    end
  end
end
