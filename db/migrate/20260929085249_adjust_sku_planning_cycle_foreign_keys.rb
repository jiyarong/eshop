class AdjustSkuPlanningCycleForeignKeys < ActiveRecord::Migration[8.1]
  def change
    remove_foreign_key :ec_sku_planning_cycles, :ec_skus
    add_foreign_key :ec_sku_planning_cycles, :ec_skus, column: :sku_id, on_delete: :cascade

    remove_foreign_key :ec_sku_planning_cycles, :conversations, column: :planner_conversation_id
    add_foreign_key :ec_sku_planning_cycles, :conversations,
      column: :planner_conversation_id, on_delete: :nullify
  end
end
