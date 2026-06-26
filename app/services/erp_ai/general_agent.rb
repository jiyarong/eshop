module ErpAI
  class GeneralAgent
    def initialize(user:, client: DefaultClient.new, server_registry: ErpAI::Mcp::ServerRegistry.new)
      @user = user
      @client = client
      @server_registry = server_registry
    end

    def ask(question)
      AgentRunner.new(
        agent: Agent.ensure_fixed!("general_agent"),
        user: user,
        client: client,
        server_registry: server_registry
      ).ask(question: question)
    end

    private

    attr_reader :user, :client, :server_registry
  end
end
