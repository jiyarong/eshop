module ErpAI
  class SqlQueriesController < ActionController::API
    MAX_LIMIT = 500
    DEFAULT_LIMIT = 100
    BLOCKED_KEYWORDS = %w[
      alter analyze call copy create delete do drop execute grant insert lock merge refresh
      replace reset revoke set truncate update upsert vacuum
    ].freeze
    SENSITIVE_PATTERNS = [
      /\bapi[_-]?key\b/i,
      /\bapi[_-]?token\b/i,
      /\bclient[_-]?secret\b/i,
      /\bencrypted_password\b/i,
      /\bpassword\b/i,
      /\bsecret\b/i,
      /\btoken_digest\b/i
    ].freeze

    before_action :authenticate_api_key!

    def create
      sql = query_sql
      validation_error = validate_sql(sql)
      return render json: { success: false, error: validation_error }, status: :unprocessable_entity if validation_error

      result = execute_sql(sql)
      rows = result.to_a
      has_more = rows.length > limit
      rows = rows.first(limit)

      render json: {
        success: true,
        columns: result.columns,
        rows: rows,
        pagination: {
          limit: limit,
          offset: offset,
          returned: rows.length,
          has_more: has_more,
          next_offset: has_more ? offset + limit : nil
        }
      }
    rescue ActiveRecord::StatementInvalid => e
      render json: { success: false, error: e.message }, status: :unprocessable_entity
    end

    private

    def authenticate_api_key!
      @current_user = UserApiKey.authenticate(bearer_token)
      return if @current_user&.can?(:view_reports)

      render json: { error: "Unauthorized" }, status: :unauthorized
    end

    def bearer_token
      header = request.headers["Authorization"].to_s
      return unless header.start_with?("Bearer ")

      header.delete_prefix("Bearer ").strip
    end

    def query_sql
      params[:sql].to_s.strip
    end

    def limit
      @limit ||= begin
        value = params[:limit].to_i
        value = DEFAULT_LIMIT if value <= 0
        [value, MAX_LIMIT].min
      end
    end

    def offset
      @offset ||= [params[:offset].to_i, 0].max
    end

    def validate_sql(sql)
      return "sql is required" if sql.blank?
      return "only a single SQL statement is allowed" if sql.include?(";")
      return "only SELECT or WITH queries are allowed" unless sql.match?(/\A(?:select|with)\b/i)
      return "SELECT * is not allowed; request explicit columns" if sql.match?(/\bselect\s+\*/i)

      blocked_keyword = BLOCKED_KEYWORDS.find { |keyword| sql.match?(/\b#{Regexp.escape(keyword)}\b/i) }
      return "#{blocked_keyword.upcase} is not allowed in read-only query SQL" if blocked_keyword

      sensitive_pattern = SENSITIVE_PATTERNS.find { |pattern| sql.match?(pattern) }
      return "querying credential or secret fields is not allowed" if sensitive_pattern

      nil
    end

    def execute_sql(sql)
      ActiveRecord::Base.connection.transaction(joinable: false) do
        set_read_only_transaction
        ActiveRecord::Base.connection.exec_query(paginated_sql(sql), "ErpAI SQL Query")
      end
    end

    def set_read_only_transaction
      ActiveRecord::Base.connection.execute("SET TRANSACTION READ ONLY")
    rescue ActiveRecord::StatementInvalid, ActiveRecord::ActiveRecordError
      nil
    end

    def paginated_sql(sql)
      <<~SQL.squish
        SELECT *
        FROM (#{sql}) erp_ai_query
        LIMIT #{limit + 1}
        OFFSET #{offset}
      SQL
    end
  end
end
