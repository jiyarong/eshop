module TableSortable
  extend ActiveSupport::Concern

  included do
    helper_method :table_sort_key, :table_sort_direction
  end

  private

  def load_table_sort(allowed_keys:, default_key: nil, default_direction: "desc")
    requested_key = params[:sort].to_s
    allowed_keys = allowed_keys.map(&:to_s)
    @table_sort_key = if allowed_keys.include?(requested_key)
      requested_key
    elsif allowed_keys.include?(default_key.to_s)
      default_key.to_s
    end
    @table_sort_direction = %w[asc desc].include?(params[:direction].to_s) ? params[:direction].to_s : default_direction
  end

  def table_sort_key
    @table_sort_key
  end

  def table_sort_direction
    @table_sort_direction
  end

  def sort_table_records(records, &value_for)
    present, missing = records.partition { |record| value_for.call(record).present? }
    sorted = present.sort_by { |record| [value_for.call(record), table_sort_tiebreaker(record)] }
    sorted.reverse! if table_sort_direction == "desc"
    sorted + missing.sort_by { |record| table_sort_tiebreaker(record) }
  end

  def table_sort_tiebreaker(record)
    record.respond_to?(:sku_code) ? record.sku_code.to_s : record.to_param.to_s
  end
end
