# frozen_string_literal: true

module Admin::AIEvalsHelper
  def ai_eval_json(value)
    JSON.pretty_generate(value)
  end

  def ai_eval_status(status)
    content_tag(:span, t("admin.ai_evals.statuses.#{status}"), class: "ai-tag")
  end
end
