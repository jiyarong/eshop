class AddConversationToEcAISkuOperationPlans < ActiveRecord::Migration[8.1]
  def change
    add_reference :ec_ai_sku_operation_plans, :conversation, foreign_key: true
    reversible do |direction|
      direction.up do
        select_all(<<~SQL).each do |row|
          SELECT messages.conversation_id, messages.content
          FROM messages
          INNER JOIN conversations ON conversations.id = messages.conversation_id
          WHERE messages.role = 'tool' AND conversations.module_name = 'sku_planner'
        SQL
          payload = JSON.parse(row.fetch("content"))
          next unless payload["name"] == "save_sku_plan" && payload.dig("result", "success")

          plan_id = Integer(payload.dig("result", "plan_id"), exception: false)
          next unless plan_id

          execute <<~SQL
            UPDATE ec_ai_sku_operation_plans
            SET conversation_id = #{Integer(row.fetch("conversation_id"))}
            WHERE id = #{plan_id} AND conversation_id IS NULL
          SQL
        rescue JSON::ParserError, TypeError
          next
        end
      end
    end
  end
end
