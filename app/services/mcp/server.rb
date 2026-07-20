module Mcp
  class Server
    class UnsupportedMethodError < StandardError; end

    GBRAIN_SERVER_NAME = "gbrain".freeze
    GBRAIN_TOOL_SPECS = {
      "get_page" => {
        description: "已知准确 slug 时读取完整知识页面。只用于精确读取；搜索结果出来后，应读取最相关的 3-5 个页面再综合回答。",
        properties: {
          "slug" => {
            type: "string",
            minLength: 1,
            maxLength: 200,
            pattern: "^[a-z0-9][a-z0-9/_-]*$",
            description: "准确页面 slug，例如 category-strategies/ozon-ru-home"
          }
        },
        required: [ "slug" ]
      },
      "list_pages" => {
        description: "按页面类型和一个标签确定性浏览知识。严格品类查询应先用 type=category-strategy 与 category-l1/... 标签获取候选，再用 get_page 读取完整页面；不要用它代替语义检索。",
        properties: {
          "type" => {
            type: "string",
            enum: %w[platform-guide region-profile category-strategy operation-playbook policy case-study concept source note],
            description: "知识页面类型"
          },
          "tag" => {
            type: "string",
            minLength: 1,
            maxLength: 120,
            pattern: "^[a-z0-9][a-z0-9/_-]*$",
            description: "单个标准标签，例如 category-l1/home、platform/ozon、country/ru"
          },
          "limit" => {
            type: "integer",
            minimum: 1,
            maximum: 100,
            default: 50,
            description: "候选数量，默认 50，最大 100"
          }
        },
        required: []
      },
      "search" => {
        description: "具体名称、FBO/FBS、地区名或品类名的快速检索。执行 cheap hybrid 且固定关闭 query expansion；默认适合精准问题。当前政策应设置 recency=strong 和 since（如 90d）。返回的是候选，回答前再用 get_page 读取最相关的 3-5 个完整页面。",
        properties: {
          "query" => {
            type: "string",
            minLength: 2,
            maxLength: 500,
            description: "同时包含平台、国家、地区、品类层级、主题等已知限定词；跨语言时可并列中文、英文或俄文实体名"
          },
          "source_id" => {
            type: "string",
            minLength: 1,
            maxLength: 80,
            pattern: "^[a-z0-9][a-z0-9_-]*$",
            description: "知识源，例如 ozon-ru；需要平台隔离时必须设置"
          },
          "detail" => {
            type: "string",
            enum: %w[low medium high],
            default: "medium",
            description: "候选详情级别，默认 medium"
          },
          "adaptive_return" => {
            type: "boolean",
            default: true,
            description: "精准问题保持 true，让结果集按意图收紧"
          },
          "recency" => {
            type: "string",
            enum: %w[off on strong],
            default: "off",
            description: "事实与策略默认 off；最新政策使用 strong"
          },
          "since" => {
            type: "string",
            maxLength: 32,
            pattern: "^(?:[0-9]{4}-[0-9]{2}(?:-[0-9]{2})?|[1-9][0-9]*[dwy])$",
            description: "effective_date 下界，YYYY-MM-DD、YYYY-MM 或相对时间（如 90d）"
          },
          "until" => {
            type: "string",
            maxLength: 32,
            pattern: "^[0-9]{4}-[0-9]{2}(?:-[0-9]{2})?$",
            description: "effective_date 上界，YYYY-MM-DD 或 YYYY-MM"
          },
          "limit" => {
            type: "integer",
            minimum: 1,
            maximum: 50,
            default: 10,
            description: "候选数量，默认 10，最大 50"
          }
        },
        required: [ "query" ]
      },
      "query" => {
        description: "处理“应该怎么做、为什么、有什么差异”等模糊策略、跨语言或多概念问题。使用 hybrid + expansion + rerank；精准问题设置 adaptive_return=true，宽泛研究不要设置 adaptive_return，并可设置 autocut=false 保留更多候选。当前政策使用 recency=strong、since 和 expand=false。回答前读取最相关的 3-5 个完整页面。",
        properties: {
          "query" => {
            type: "string",
            minLength: 2,
            maxLength: 1000,
            description: "明确写出平台、国家、地区、品类层级、主题、时效要求，并保留关键跨语言实体词"
          },
          "source_id" => {
            type: "string",
            minLength: 1,
            maxLength: 80,
            pattern: "^[a-z0-9][a-z0-9_-]*$",
            description: "知识源，例如 ozon-ru；需要平台隔离时必须设置"
          },
          "detail" => {
            type: "string",
            enum: %w[low medium high],
            default: "medium",
            description: "候选详情级别，默认 medium"
          },
          "expand" => {
            type: "boolean",
            default: true,
            description: "模糊策略与跨语言问题保持 true；当前政策查询设为 false"
          },
          "adaptive_return" => {
            type: "boolean",
            description: "仅在问题答案较具体时设为 true；宽泛研究省略"
          },
          "autocut" => {
            type: "boolean",
            description: "通常省略；宽泛研究需要保留更多候选时设为 false"
          },
          "recency" => {
            type: "string",
            enum: %w[off on strong],
            description: "事实与长期策略使用 off；近期变化使用 on；最新政策使用 strong"
          },
          "since" => {
            type: "string",
            maxLength: 32,
            pattern: "^(?:[0-9]{4}-[0-9]{2}(?:-[0-9]{2})?|[1-9][0-9]*[dwy])$",
            description: "effective_date 下界，YYYY-MM-DD、YYYY-MM 或相对时间（如 90d）"
          },
          "until" => {
            type: "string",
            maxLength: 32,
            pattern: "^[0-9]{4}-[0-9]{2}(?:-[0-9]{2})?$",
            description: "effective_date 上界，YYYY-MM-DD 或 YYYY-MM"
          },
          "limit" => {
            type: "integer",
            minimum: 1,
            maximum: 50,
            default: 10,
            description: "候选数量，默认 10，最大 50"
          }
        },
        required: [ "query" ]
      },
      "traverse_graph" => {
        description: "已知实体 slug 时查询关联知识，例如策略适用地区、证据、替代方案或关联页面。先确认 slug，再进行 1-3 层遍历；返回关联候选后仍需用 get_page 读取相关完整页面。",
        properties: {
          "slug" => {
            type: "string",
            minLength: 1,
            maxLength: 200,
            pattern: "^[a-z0-9][a-z0-9/_-]*$",
            description: "作为遍历起点的准确页面 slug"
          },
          "depth" => {
            type: "integer",
            minimum: 1,
            maximum: 3,
            default: 2,
            description: "遍历深度，默认 2，最大 3"
          },
          "link_type" => {
            type: "string",
            minLength: 1,
            maxLength: 80,
            pattern: "^[a-z0-9][a-z0-9_-]*$",
            description: "可选的关系类型"
          },
          "direction" => {
            type: "string",
            enum: %w[in out both],
            default: "out",
            description: "关系方向，默认 out"
          }
        },
        required: [ "slug" ]
      },
      "think" => {
        description: "需要跨多个页面形成带引用的最终答案并分析冲突与知识缺口时使用。仅用于最终综合，不替代前序检索；包装层不允许保存页面、追加 take 或覆盖模型。输出仍须说明适用范围、复核日期、来源和缺口。",
        properties: {
          "question" => {
            type: "string",
            minLength: 5,
            maxLength: 1500,
            description: "需要综合回答的电商问题，包含已知适用范围和时效要求"
          },
          "anchor" => {
            type: "string",
            minLength: 1,
            maxLength: 200,
            pattern: "^[a-z0-9][a-z0-9/_-]*$",
            description: "可选的核心实体 slug"
          },
          "rounds" => {
            type: "integer",
            minimum: 1,
            maximum: 3,
            default: 1,
            description: "综合轮次，默认 1，最大 3"
          },
          "since" => {
            type: "string",
            maxLength: 10,
            pattern: "^[0-9]{4}-[0-9]{2}(?:-[0-9]{2})?$",
            description: "综合证据的开始日期，YYYY-MM-DD 或 YYYY-MM"
          },
          "until" => {
            type: "string",
            maxLength: 10,
            pattern: "^[0-9]{4}-[0-9]{2}(?:-[0-9]{2})?$",
            description: "综合证据的结束日期，YYYY-MM-DD 或 YYYY-MM"
          }
        },
        required: [ "question" ]
      }
    }.freeze

    KNOWLEDGE_RETRIEVAL_INSTRUCTIONS = <<~PROMPT.squish.freeze
      处理电商知识问题时，先从用户问题提取平台、国家、地区、品类层级、主题和时效要求，再选择工具。
      已知准确 slug 用 gbrain__get_page；明确页面类型或标签浏览用 gbrain__list_pages；具体名称、FBO/FBS、地区名或品类名用 gbrain__search；“应该怎么做、为什么、有什么差异”等模糊策略或跨语言问题用 gbrain__query；已知实体的关联知识用 gbrain__traverse_graph；跨多页最终综合且需要引用、冲突与缺口分析时用 gbrain__think。
      search/query 只能按 source_id 和 effective_date 日期范围过滤，不能按任意 platform、region 或 category frontmatter 字段过滤；这些限定词必须同时写入 query。严格品类查询先调用 gbrain__list_pages，使用 type=category-strategy 和一个 category-l1/... 标签，再读取候选页面。
      搜索或遍历只返回候选。最终回答前读取最相关的 3-5 个完整页面，并在答案中标注适用平台/国家/地区/品类、复核日期、引用来源和仍缺少的信息。不得把候选摘要当作完整证据，不得在证据不足时补造结论。
    PROMPT

    def initialize(current_user:, external_server_registry: ErpAI::Mcp::ServerRegistry.new)
      @current_user = current_user
      @external_server_registry = external_server_registry
    end

    def call(payload)
      case payload["method"]
      when "initialize"
        result(payload["id"], initialize_result)
      when "tools/list"
        result(payload["id"], tools_list_result)
      when "tools/call"
        result(payload["id"], tools_call_result(payload["params"].to_h))
      else
        raise UnsupportedMethodError, "Unsupported MCP method: #{payload['method']}"
      end
    end

    private

    attr_reader :current_user, :external_server_registry

    def initialize_result
      {
        protocolVersion: "2025-06-18",
        serverInfo: {
          name: "eshop_manage",
          version: "1.0.0"
        },
        capabilities: {
          tools: {}
        },
        instructions: KNOWLEDGE_RETRIEVAL_INSTRUCTIONS
      }
    end

    def tools_list_result
      {
        tools: Mcp::ToolRegistry.new(current_user: current_user).definitions + external_tool_definitions
      }
    end

    def tools_call_result(params)
      parsed_external_tool = ErpAI::Mcp::ToolAdapter.parse_model_tool_name(params["name"])
      if gbrain_tool?(parsed_external_tool)
        return gbrain_tool_call_result(parsed_external_tool, params)
      end
      if parsed_external_tool
        return external_tools_call_result(params)
      end

      tool_result = Mcp::ToolExecutor.new(current_user: current_user).call(
        params["name"].to_s,
        params["arguments"].to_h
      )

      {
        content: [
          {
            type: "text",
            text: JSON.generate(tool_result)
          }
        ]
      }
    end

    def external_tool_definitions
      gbrain_tool_definitions + other_external_tool_definitions
    end

    def gbrain_tool_definitions
      return [] unless external_mcp_clients.key?(GBRAIN_SERVER_NAME)

      allowed_tools = external_tool_filters[GBRAIN_SERVER_NAME]

      GBRAIN_TOOL_SPECS.filter_map do |tool_name, spec|
        next if allowed_tools.present? && !allowed_tools.include?(tool_name)

        {
          "name" => ErpAI::Mcp::ToolAdapter.model_tool_name(GBRAIN_SERVER_NAME, tool_name),
          "description" => spec.fetch(:description),
          "inputSchema" => {
            "type" => "object",
            "properties" => spec.fetch(:properties),
            "required" => spec.fetch(:required),
            "additionalProperties" => false
          }
        }
      end
    end

    def other_external_tool_definitions
      external_mcp_clients.except(GBRAIN_SERVER_NAME).flat_map do |server_name, client|
        allowed_tools = external_tool_filters[server_name]

        Array(client.list_tools).filter_map do |tool|
          definition = tool.to_h.deep_dup
          tool_name = (definition["name"] || definition[:name]).to_s
          next if tool_name.blank?
          next if allowed_tools.present? && !allowed_tools.include?(tool_name)

          exposed_name = ErpAI::Mcp::ToolAdapter.model_tool_name(server_name, tool_name)
          definition.key?("name") ? definition.merge("name" => exposed_name) : definition.merge(name: exposed_name)
        end
      rescue StandardError
        next []
      end
    end

    def gbrain_tool?(parsed_tool)
      parsed_tool &&
        parsed_tool.fetch(:server_name) == GBRAIN_SERVER_NAME &&
        GBRAIN_TOOL_SPECS.key?(parsed_tool.fetch(:tool_name))
    end

    def gbrain_tool_call_result(parsed_tool, params)
      tool_name = parsed_tool.fetch(:tool_name)
      arguments = params["arguments"].to_h.slice(*GBRAIN_TOOL_SPECS.fetch(tool_name).fetch(:properties).keys)
      normalize_gbrain_relative_since!(arguments)

      case tool_name
      when "search"
        tool_name = "query"
        arguments = {
          "limit" => 10,
          "detail" => "medium",
          "adaptive_return" => true,
          "recency" => "off"
        }.merge(arguments).merge("expand" => false)
      when "query"
        arguments = { "limit" => 10, "detail" => "medium", "expand" => true }.merge(arguments)
      when "list_pages"
        arguments = { "limit" => 50 }.merge(arguments)
      when "traverse_graph"
        arguments = { "depth" => 2, "direction" => "out" }.merge(arguments)
      when "think"
        arguments = { "rounds" => 1 }.merge(arguments)
      end

      external_tools_call_result(params.merge(
        "name" => ErpAI::Mcp::ToolAdapter.model_tool_name(GBRAIN_SERVER_NAME, tool_name),
        "arguments" => arguments
      ))
    end

    def normalize_gbrain_relative_since!(arguments)
      match = arguments["since"]&.match(/\A([1-9][0-9]*)([dwy])\z/)
      return unless match

      amount = match[1].to_i
      date = case match[2]
      when "d" then Date.current.advance(days: -amount)
      when "w" then Date.current.advance(weeks: -amount)
      when "y" then Date.current.advance(years: -amount)
      end
      arguments["since"] = date.iso8601
    end

    def external_tools_call_result(params)
      result = external_tool_executor.call(
        id: params["name"].to_s,
        name: params["name"].to_s,
        arguments: params["arguments"].to_h
      )
      return result.fetch(:result) if result.key?(:result)

      {
        content: [
          {
            type: "text",
            text: JSON.generate(result.fetch(:error))
          }
        ],
        isError: true
      }
    end

    def external_tool_executor
      @external_tool_executor ||= ErpAI::ToolExecutor.new(
        mcp_clients: external_mcp_clients,
        mcp_tool_filters: external_tool_filters
      )
    end

    def external_mcp_clients
      @external_mcp_clients ||= external_server_registry.clients
    end

    def external_tool_filters
      @external_tool_filters ||= external_server_registry.tool_filters
    end

    def result(id, value)
      {
        jsonrpc: "2.0",
        id: id,
        result: value
      }
    end
  end
end
