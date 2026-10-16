module ErpAI
  # Shared by the production runners and the in-memory evaluation adapters.
  module SkuEvaluationPrompts
    def self.diagnosis(sku_code:, rule_id:, rule_prompt:, event_types:, listing_platforms: [])
      event_type_instruction = if event_types.any?
        "event_type 建议优先使用以下值，也可按诊断结论填写其他具体类型：#{event_types.join(', ')}"
      else
        "event_type 写具体诊断事件类型"
      end
      listing_image_instruction = if listing_platforms.any?
        "每个 Listing product 的图片均按两张一组排列：第一张为主图，第二张为其余产品图合集。"
      end
      <<~PROMPT
        当前 SKU：#{sku_code}
        当前子规则 ID：#{rule_id}
        子规则追加提示词：
        #{rule_prompt}
        #{listing_image_instruction}

        请严格基于下方上下文诊断当前 SKU。必须调用 save_sku_event，sub_agent_id 使用 #{rule_id}，#{event_type_instruction}，message 写诊断结果和依据，simple_context 按当前子规则 Prompt 的要求填写非空的最小证据；severity 使用 info、warning 或 critical 之一。工具返回字段校验错误时，请修正对应字段并再次调用，只有保存成功才算完成。不要处理其他 SKU。
      PROMPT
    end

    def self.planner(sku_code:, period_start:, listings:, historical_context:)
      <<~PROMPT
        当前 SKU：#{sku_code}
        当前计划周期：#{period_start.iso8601} 至 #{(period_start + 6.days).iso8601}
        可用 Listing（scope_id 使用内部 id）：#{listings.to_json}

        下方是该 SKU 本周期各子规则最新的非 info 通用诊断事件。info 事件已排除；warning 和 critical 表示诊断紧迫程度，仅供经营判断参考。旧事件缺少 simple_context 时，使用其已有 message 和 details 作为证据，不得据此补造数据。
        以下是最近周期的历史 Plan / Evaluation Context。历史记录只用于识别已验证、无效、未执行或数据不足的方向，不得机械复制上一周期计划：
        #{historical_context.to_json}
        根据这些事件制定本周期值得执行的运营计划。只使用上方列出的 Listing 内部 id；没有足够依据时不调用 save_sku_plan。
      PROMPT
    end
  end
end
