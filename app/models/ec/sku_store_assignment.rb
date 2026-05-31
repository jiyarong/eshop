module Ec
  class SkuStoreAssignment < ApplicationRecord
    self.table_name = 'ec_sku_store_assignments'

    belongs_to :sku, class_name: 'Ec::Sku', foreign_key: :sku_code, primary_key: :sku_code

    STORE_KEYS = %w[wb1_miral wb2_taxi wb3_zeppto ozon1_nevastal ozon2_nevastal2 ozon_domos ozon_nanokit].freeze
    PLATFORMS  = %w[wb ozon].freeze

    STORE_PLATFORM = {
      'wb1_miral'      => 'wb',
      'wb2_taxi'       => 'wb',
      'wb3_zeppto'     => 'wb',
      'ozon1_nevastal' => 'ozon',
      'ozon2_nevastal2'=> 'ozon',
      'ozon_domos'     => 'ozon',
      'ozon_nanokit'   => 'ozon',
    }.freeze

    STORE_DISPLAY = {
      'wb1_miral'       => 'WB1-МИРОВОЙ',
      'wb2_taxi'        => 'WB2-Такси Линк',
      'wb3_zeppto'      => 'WB3-ЗЕППТО',
      'ozon1_nevastal'  => 'OZON1-NEVASTAL',
      'ozon2_nevastal2' => 'OZON2-Nevastal 2',
      'ozon_domos'      => 'OZON-Domos',
      'ozon_nanokit'    => 'OZON-NanoKit',
    }.freeze

    validates :sku_code,  presence: true
    validates :store_key, inclusion: { in: STORE_KEYS }
    validates :platform,  inclusion: { in: PLATFORMS }
    validates :sku_code,  uniqueness: { scope: :store_key }

    scope :wb,     -> { where(platform: 'wb') }
    scope :ozon,   -> { where(platform: 'ozon') }
    scope :active, -> { where(is_active: true) }

    def store_display_name
      STORE_DISPLAY[store_key]
    end
  end
end
