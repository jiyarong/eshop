class CreateRawOzonAccrualByDay < ActiveRecord::Migration[8.0]
  def change
    create_table :raw_ozon_accrual_by_day do |t|
      t.references :account, null: false, foreign_key: { to_table: :raw_ozon_seller_accounts }

      # 计费日（/by-day API 按日组织）
      t.date    :accrual_date,      null: false

      # POSTING / ITEM / NON_ITEM
      t.string  :accrued_category,  null: false

      # 费用类型码，0 = SaleRevenue（合成值，非 API 枚举）
      t.integer :type_id,           null: false
      t.string  :type_name

      # 金额：正数=收入，负数=费用（原始符号，不做翻转）
      t.decimal :amount,            precision: 18, scale: 2, null: false
      t.string  :currency_code,     default: 'RUB', null: false

      # SKU（NON_ITEM 及部分 Acquiring 行为 null）
      t.bigint  :ozon_sku_id

      # posting_number / campaign_id / supply_order_number（共用一列，语义由 type_id 决定）
      t.string  :posting_number

      # unit_number：API 原始字段，同一笔订单的 POSTING + ITEM 行共享同一值
      t.string  :unit_number

      t.datetime :synced_at, null: false
    end

    # 复合索引：按账号+日期批量查询（delete-then-insert 的主要查询路径）
    add_index :raw_ozon_accrual_by_day, [:account_id, :accrual_date],
              name: 'idx_ozon_accrual_by_day_account_date'

    # 归集时按 SKU 查
    add_index :raw_ozon_accrual_by_day, [:account_id, :ozon_sku_id],
              name: 'idx_ozon_accrual_by_day_account_sku'

    # 归集时按 posting 查（Acquiring 归属、白俄判定）
    add_index :raw_ozon_accrual_by_day, [:account_id, :posting_number],
              name: 'idx_ozon_accrual_by_day_account_posting'

    # 按费用类型过滤（广告费提取：type_id IN [41,54]）
    add_index :raw_ozon_accrual_by_day, [:account_id, :type_id],
              name: 'idx_ozon_accrual_by_day_account_type'
  end
end