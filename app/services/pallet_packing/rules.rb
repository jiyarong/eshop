module PalletPacking
  module Rules
    AS_OF = "2026-10-14".freeze
    PALLET = { length: 120.0, width: 80.0, height: 14.5 }.freeze
    PROFILES = {
      "ozon_fbo" => { platform: "ozon", height: 220.0, weight: 800.0, gross_weight: false, overhang: 2.0, max_skus: 5, storage_rate: 2.5, coefficient: 1.0 },
      "ozon_fbs" => { platform: "ozon", height: 240.0, weight: 600.0, gross_weight: true, overhang: 2.0, max_skus: 5, storage_rate: 0.0, coefficient: 1.0 },
      "wb_mono" => { platform: "wb", height: 180.0, weight: 500.0, gross_weight: true, overhang: 3.0, max_skus: 3, storage_rate: 25.0, coefficient: 1.7 },
      "wb_piece" => { platform: "wb", height: 180.0, weight: 500.0, gross_weight: true, overhang: 3.0, max_skus: 3, storage_rate: 0.08, coefficient: 1.7 }
    }.freeze

    def self.defaults(profile)
      rule = PROFILES.fetch(profile)
      {
        height: rule[:height], weight: rule[:weight], overhang: 0, tare: 25,
        route_rate: nil, discount: 0, pickup: false, fixed_fee: 0,
        handling_rate: 10, sorting: "composition", storage_days: 0,
        storage_rate: rule[:storage_rate], coefficient: rule[:coefficient]
      }
    end
  end
end
