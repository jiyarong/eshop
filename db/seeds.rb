Role.seed_defaults!
Agent.seed_fixed! if defined?(Agent)
Ec::ToolDefinitionBootstrap.call(User.order(:id).first) if defined?(Ec::ToolDefinitionBootstrap)
