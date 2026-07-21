module Ec
  module AuditConfig
    ATTRIBUTES = {
      "Ec::CostAllocation" => %w[
        allocation_no
        cost_type
        allocation_method
        total_amount_cny
        allocated_on
        status
        memo
      ],
      "Ec::MasterSku" => %w[
        master_sku_code
        product_name
        product_name_ru
        ec_category_id
        is_active
        memo
      ],
      "Ec::PurchaseOrder" => %w[
        order_no
        supplier_id
        ordered_on
        status
        currency
        memo
      ],
      "Ec::Sku" => %w[
        sku_code
        master_sku_id
        product_name
        product_name_ru
        sku_category_id
        color
        spec
        size
        weight_kg
        volume_l
        model
        quality_grade
        features
        owner_name
        is_active
        memo
        deleted_at
      ],
      "Ec::SkuMarketingState" => %w[
        sku_id
        grade
        stage
        effective_at
        ended_at
        changed_by_id
        note
      ],
      "Ec::SkuBatch" => %w[
        sku_code
        batch_code
        status
        purchase_date
        purchased_quantity
        received_quantity
        purchase_unit_price_cny
        expected_arrival_on
        received_on
        memo
      ],
      "Ec::SkuCategory" => %w[
        code
        name
        parent_id
        position
        is_active
        memo
      ],
      "Ec::SkuCost" => %w[
        sku_code
        effective_on
        purchase_price_cny
        freight_to_by_cny
        customs_misc_cny
        customs_duty_rate
        import_vat_rate
        pkg_volume_override_l
        misc_cost_cny
        damage_rate
        memo
      ],
      "Ec::SkuDimension" => %w[
        sku_code
        inner_length_cm
        inner_width_cm
        inner_height_cm
        inner_box_weight_kg
        outer_length_cm
        outer_width_cm
        outer_height_cm
        outer_box_weight_kg
        outer_box_pcs
      ],
      "Ec::SkuPlatformCost" => %w[
        sku_code
        platform
        delivery_mode
        company_type
        target_price_rub
        target_price_rf_rub
        target_price_by_rub
        min_price_rub
        exchange_rate_rub_cny
        logistics_coeff
        wb_logistics_base_rub
        wb_return_rate
        wb_fixed_return_rate
        commission_rate
        acquiring_rate
        ad_spend_rate
        sales_tax_rate
        return_rate
        fbo_delivery_cny
        storage_30d_cny
        ozon_fwd_base_rub
        ozon_fwd_per_liter_rub
        ozon_ret_base_rub
        ozon_ret_per_liter_rub
        ozon_warehouse_op_rub
        ozon_fbs_delivery_rub
      ],
      "Ec::SkuProduct" => %w[
        sku_code
        store_id
        platform
        product_id
        offer_id
        platform_sku_id
        product_name
      ],
      "Ec::Store" => %w[
        platform
        store_name
        company_type
        registration_country
        is_active
        wb_raw_account_id
        ozon_raw_account_id
        ozon_client_id
        ozon_performance_client_id
        memo
      ],
      "Ec::Supplier" => %w[
        name
        contact_name
        phone
        wechat
        address
        is_active
        memo
      ]
    }.freeze

    def self.attributes_for(record_or_class)
      ATTRIBUTES.fetch(record_or_class.name, [])
    end
  end
end
