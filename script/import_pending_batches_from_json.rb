require "json"
require "securerandom"

class PendingBatchJsonImport
  DEFAULT_JSON_PATH = Rails.root.join("tmp", "pending_import_batches.json")

  def initialize(json_path: DEFAULT_JSON_PATH, now: Time.current)
    @json_path = Pathname(json_path)
    @now = now
  end

  def call
    records = JSON.parse(@json_path.read, symbolize_names: true)

    ApplicationRecord.transaction do
      records.each do |record|
        import_record(record)
      end
    end
  end

  private

  def import_record(record)
    master_sku = find_or_create_master_sku!(record.fetch(:master_sku_code))
    sku = find_or_create_sku!(record.fetch(:sku_code), master_sku)
    upsert_sku_cost_dimensions!(sku.sku_code, record[:package_dimensions_cm])
    create_batch!(sku.sku_code, record)
  end

  def find_or_create_master_sku!(master_sku_code)
    code = normalize_code(master_sku_code)
    Ec::MasterSku.find_or_create_by!(master_sku_code: code) do |master_sku|
      master_sku.is_active = true
      master_sku.product_name = code
    end
  end

  def find_or_create_sku!(sku_code, master_sku)
    code = normalize_code(sku_code)
    sku = Ec::Sku.find_or_initialize_by(sku_code: code)

    if sku.persisted? && sku.master_sku.present? && sku.master_sku != master_sku
      raise "SKU #{code} already belongs to master SKU #{sku.master_sku.master_sku_code}"
    end

    sku.master_sku ||= master_sku
    sku.is_active = true if sku.is_active.nil?
    sku.product_name ||= code
    sku.save! if sku.new_record? || sku.changed?
    sku
  end

  def upsert_sku_cost_dimensions!(sku_code, dimensions)
    return if dimensions.blank?

    sku_cost = Ec::SkuCost.find_or_initialize_by(sku_code: sku_code)
    sku_cost.pkg_length_cm = decimal_or_nil(dimensions[:length_cm])
    sku_cost.pkg_width_cm = decimal_or_nil(dimensions[:width_cm])
    sku_cost.pkg_height_cm = decimal_or_nil(dimensions[:height_cm])
    sku_cost.save! if sku_cost.new_record? || sku_cost.changed?
  end

  def create_batch!(sku_code, record)
    purchased_quantity = quantity_value(record[:purchase_quantity])
    timestamp = @now.strftime("%Y%m%d%H%M%S")
    row_marker = record[:sheet_row].presence || "NA"

    Ec::SkuBatch.create!(
      sku_code: sku_code,
      batch_code: "PENDING-#{sku_code}-R#{row_marker}-#{timestamp}-#{SecureRandom.hex(3).upcase}",
      status: "in_transit",
      batch_type: :normal,
      purchased_quantity: purchased_quantity,
      received_quantity: 0,
      purchase_unit_price_cny: current_purchase_price_for(sku_code),
      memo: "Imported from pending_import_batches.json row #{row_marker}"
    )
  end

  def current_purchase_price_for(sku_code)
    Ec::SkuCost.find_by(sku_code: sku_code)&.purchase_price_cny || 0
  end

  def quantity_value(value)
    Integer(BigDecimal(value.to_s).to_i)
  rescue ArgumentError, TypeError
    0
  end

  def decimal_or_nil(value)
    return nil if value.blank?

    BigDecimal(value.to_s)
  end

  def normalize_code(value)
    value.to_s.strip.upcase
  end
end

if $PROGRAM_NAME == __FILE__
  json_path = ARGV[0].presence || PendingBatchJsonImport::DEFAULT_JSON_PATH
  PendingBatchJsonImport.new(json_path: json_path).call
end
