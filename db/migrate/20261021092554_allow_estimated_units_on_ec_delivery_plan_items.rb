class AllowEstimatedUnitsOnEcDeliveryPlanItems < ActiveRecord::Migration[8.1]
  def change
    change_column_null :ec_delivery_plan_items, :units, true
  end
end
