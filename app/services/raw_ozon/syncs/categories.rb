module RawOzon
  module Syncs
    module Categories
      # POST /v1/description-category/tree
      def sync_categories
        resp  = @client.post('/v1/description-category/tree', { language: 'ZH_HANS' })
        items = Array(resp['result'])
        rows  = items.flat_map { |c| flatten_category(c) }.uniq { |r| [r[:account_id], r[:category_id]] }
        RawOzon::Category.upsert_all(rows, unique_by: [:account_id, :category_id]) if rows.any?
        rows.size
      end

      private

      def flatten_category(node, parent_id: nil)
        # 类目树有两种节点：category（description_category_id）和 type（type_id）
        id = node['description_category_id'] || node['type_id']
        return [] if id.nil?

        row = {
          account_id:  @account.id,
          category_id: id,
          parent_id:   parent_id,
          title:       node['category_name'] || node['type_name'],
          disabled:    node['disabled'] || false,
          children:    node['children'],
          raw_json:    node,
          synced_at:   Time.current,
        }
        children = Array(node['children']).flat_map { |c| flatten_category(c, parent_id: id) }
        [row] + children
      end
    end
  end
end
