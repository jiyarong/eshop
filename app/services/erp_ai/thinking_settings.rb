module ErpAI
  module ThinkingSettings
    MODEL_PROFILES = [
      { pattern: "^deepseek-(?:v4(?:\\.1)?(?:-|$)|flash(?:-|$))", levels: %w[low high max] },
      { pattern: "^gpt-(?:6-(?:astra|sol|luna)|6\\.1-sol)(?:-|$)", levels: %w[low medium high xhigh max], disabled_level: "none" },
      { pattern: "^gpt-5\\.6-(?:sol|terra|luna)(?:-|$)", levels: %w[low medium high xhigh max], disabled_level: "none" },
      { pattern: "^gpt-5\\.[2-5](?!-(?:chat|codex|pro))(?:-|$)", levels: %w[low medium high xhigh], disabled_level: "none" },
      { pattern: "^gpt-5\\.1(?!-(?:chat|codex))(?:-|$)", levels: %w[low medium high], disabled_level: "none" },
      { pattern: "^gpt-5(?:-(?:mini|nano))?(?:-\\d{4}-\\d{2}-\\d{2})?$", levels: %w[minimal low medium high], disabled_level: "minimal" }
    ].freeze

    def self.profile_for(model)
      MODEL_PROFILES.find { |profile| Regexp.new(profile.fetch(:pattern)).match?(model.to_s) }
    end

    def self.levels_for(model)
      profile_for(model)&.fetch(:levels) || []
    end

    def self.deepseek_model?(model)
      model.to_s.start_with?("deepseek")
    end

    def self.gpt_reasoning_model?(model)
      model.to_s.start_with?("gpt-") && profile_for(model).present?
    end

    def self.reasoning_effort(model:, enabled:, level:)
      profile = profile_for(model)
      return unless profile
      raise ArgumentError, "Unsupported thinking level: #{level}" if level.present? && !profile.fetch(:levels).include?(level)

      if deepseek_model?(model)
        level.presence if enabled
      elsif enabled
        level.presence || "medium"
      elsif model.to_s.start_with?("gpt-6-astra", "gpt-6.1-sol")
        "low"
      else
        profile.fetch(:disabled_level)
      end
    end
  end
end
