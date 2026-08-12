module Ec
  class Company < ApplicationRecord
    include Ec::Auditable

    self.table_name = "ec_companies"

    TAGS = %w[supplier customs_broker].freeze
    INVOICE_TYPES = %w[general special].freeze
    CHANNELS = %w[online offline].freeze
    SUPPLIER_GRADES = Ec::SkuMarketingState::GRADES

    belongs_to :developer, class_name: "User", optional: true
    belongs_to :purchaser, class_name: "User", optional: true
    has_many :purchase_orders, class_name: "Ec::PurchaseOrder", foreign_key: :supplier_id
    has_many :sku_batches, class_name: "Ec::SkuBatch", foreign_key: :supplier_id, dependent: :nullify
    has_many :attachment_links, class_name: "Ec::AttachmentLink", as: :attachable, dependent: :destroy
    has_many :attachments, through: :attachment_links, source: :ec_attachment

    validates :name, presence: true, uniqueness: true
    validates :tags, presence: true
    validates :invoice_type, inclusion: { in: INVOICE_TYPES }, allow_blank: true
    validates :channel, inclusion: { in: CHANNELS }, allow_blank: true
    validates :supplier_grade, inclusion: { in: SUPPLIER_GRADES }, allow_blank: true
    validates :online_url, presence: true, if: :online?
    validates :online_url, format: { with: %r{\Ahttps?://}i }, allow_blank: true
    validate :tags_are_supported

    before_validation :normalize_values

    scope :active, -> { where(is_active: true) }
    scope :tagged, ->(tag) { where("? = ANY(ec_companies.tags)", tag.to_s) }

    def supplier?
      tags.include?("supplier")
    end

    def online?
      channel == "online"
    end

    private

    def normalize_values
      self.name = name.to_s.strip
      self.tags = Array(tags).filter_map { |tag| tag.to_s.strip.presence }.uniq
      self.supplier_grade = supplier_grade.to_s.upcase.presence
      self.online_url = nil unless online?
    end

    def tags_are_supported
      return if (Array(tags) - TAGS).empty?

      errors.add(:tags, :invalid)
    end
  end
end
