module ErpAI
  class DefaultClient
    def complete(_request)
      {
        content: "数据不足：当前系统尚未配置可用的 AI 模型客户端。请配置模型调用后再生成业务分析。",
        usage: {}
      }
    end
  end
end
