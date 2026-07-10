class Sub2UsageDashboard
  Result = Struct.new(:stats, :user_rows, keyword_init: true)

  def self.call(start_date:, end_date:, service: Sub2AIService.new)
    new(start_date:, end_date:, service:).call
  end

  def initialize(start_date:, end_date:, service:)
    @start_date = start_date
    @end_date = end_date
    @service = service
  end

  def call
    access_token = fetch_value(@service.login, "access_token", "token")
    users = User.includes(:sub2_user_api_key).order(:email)
    bindings = users.filter_map(&:sub2_user_api_key)
    usage_rows = usage_by_key_id(access_token, bindings)
    stats = @service.usage_stats(access_token:, start_date: @start_date, end_date: @end_date)
    raise KeyError, "Sub2 usage stats response is invalid" unless stats.is_a?(Hash)

    Result.new(
      stats: stats,
      user_rows: users.map do |user|
        binding = user.sub2_user_api_key
        build_user_row(user, binding, usage_rows[binding&.remote_key_id.to_s] || {})
      end
    )
  rescue KeyError => error
    raise Sub2AIService::Error, error.message
  end

  private

  def usage_by_key_id(access_token, bindings)
    key_ids = bindings.map(&:remote_key_id)
    return {} if key_ids.empty?

    normalize_usage_rows(@service.api_key_usage(access_token:, api_key_ids: key_ids)).index_by do |row|
      fetch_value(row, "api_key_id", "key_id", "id").to_s
    end
  end

  def normalize_usage_rows(data)
    return data if data.is_a?(Array)
    return [] unless data.is_a?(Hash)

    rows = data["api_keys"] || data[:api_keys] || data["items"] || data[:items] || data["data"] || data[:data]
    return rows if rows.is_a?(Array)

    data.filter_map do |key_id, value|
      value.merge("api_key_id" => key_id) if value.is_a?(Hash)
    end
  end

  def build_user_row(user, binding, usage)
    {
      user: user,
      binding: binding,
      requests: metric(usage, "requests", "request_count", "total_requests"),
      input_tokens: metric(usage, "input_tokens", "total_input_tokens"),
      output_tokens: metric(usage, "output_tokens", "total_output_tokens"),
      cache_tokens: metric(usage, "cache_tokens", "total_cache_tokens"),
      cache_creation_tokens: metric(usage, "cache_creation_tokens", "total_cache_creation_tokens"),
      cache_read_tokens: metric(usage, "cache_read_tokens", "total_cache_read_tokens"),
      total_tokens: metric(usage, "tokens", "total_tokens"),
      cost: metric(usage, "cost", "total_cost"),
      actual_cost: metric(usage, "actual_cost", "total_actual_cost"),
      average_duration_ms: metric(usage, "average_duration_ms", "avg_duration_ms")
    }
  end

  def metric(data, *keys)
    keys.each do |key|
      return data[key] if data.key?(key)
      return data[key.to_sym] if data.key?(key.to_sym)
    end
    0
  end

  def fetch_value(data, *keys)
    raise KeyError, "Sub2 response is invalid" unless data.is_a?(Hash)

    keys.each do |key|
      return data[key] if data[key].present?
      return data[key.to_sym] if data[key.to_sym].present?
    end
    raise KeyError, "Sub2 response is missing #{keys.first}"
  end
end
