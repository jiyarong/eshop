module Admin::McpDebugHelper
  def mcp_tool_properties(tool)
    tool&.dig(:inputSchema, :properties).to_h
  end

  def json_tree(value)
    case value
    when Hash
      content_tag(:details, class: "json-node", open: true) do
        concat content_tag(:summary, "{ #{value.size} }")
        concat content_tag(:ul) {
          safe_join(value.map { |key, child| content_tag(:li) { tag.strong(key.to_s) + ": ".html_safe + json_tree(child) } })
        }
      end
    when Array
      content_tag(:details, class: "json-node", open: true) do
        concat content_tag(:summary, "[ #{value.size} ]")
        concat content_tag(:ol) {
          safe_join(value.map { |child| content_tag(:li) { json_tree(child) } })
        }
      end
    else
      content_tag(:code, value.inspect)
    end
  end
end
