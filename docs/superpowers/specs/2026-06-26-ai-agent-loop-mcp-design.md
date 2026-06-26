# AI Agent Loop and HTTP MCP Design

## Context

The Rails app already has a fixed AI agent architecture:

- `Agent` stores fixed agent definitions, model settings, system prompts, and allowed tool names.
- `Conversation` and `Message` persist user, assistant, and tool messages.
- `ErpAI::AgentRunner` creates one conversation, sends one model request, and stores one assistant response.
- `ErpAI::ActiveAgentClient` delegates to `BusinessAnalysisAgent`, which uses ActiveAgent's OpenAI chat provider.
- `ErpAI::ToolRegistry` currently exposes query-only ERP tool definitions by name, but there is no tool executor and no loop.

The requested feature is to implement an AI Agent loop and connect it to an external generic AI MCP service. First version scope is remote HTTP MCP only. Local stdio MCP servers are out of scope.

## Goals

- Let the assistant perform bounded multi-step reasoning with tool calls.
- Support remote HTTP MCP servers as tool providers.
- Preserve existing conversation persistence and controller API shape.
- Keep the first version small and testable.
- Prevent infinite tool-call loops.

## Non-Goals

- No local stdio MCP process management.
- No new Rails UI for MCP server management.
- No write-capable ERP tools.
- No background job orchestration for long-running agent sessions.
- No broad refactor of the existing AI architecture.

## Configuration

MCP configuration is read from environment variables:

- `ERP_AI_MCP_ENDPOINT`: remote MCP endpoint URL.
- `ERP_AI_MCP_BEARER_TOKEN`: optional bearer token.
- `ERP_AI_MCP_PROTOCOL_VERSION`: defaults to `2025-06-18`.
- `ERP_AI_MAX_TOOL_ROUNDS`: defaults to `4`.

If `ERP_AI_MCP_ENDPOINT` is blank, MCP tools are unavailable and the runner behaves like the current single-response flow, except through the new loop code path.

## Architecture

### `ErpAI::Mcp::HttpClient`

Responsible for MCP JSON-RPC over HTTP:

- Sends `initialize`.
- Sends `tools/list`.
- Sends `tools/call`.
- Uses `POST` requests with `Content-Type: application/json`.
- Sends `Accept: application/json, text/event-stream`.
- Sends `MCP-Protocol-Version`.
- Sends `Authorization: Bearer ...` when a token is configured.

The first version parses JSON responses directly. If a server returns SSE, the client extracts the final JSON-RPC response from `data:` events when possible. Complex MCP server-to-client requests are out of scope.

### `ErpAI::Mcp::ToolAdapter`

Converts MCP tool definitions into model-visible tool definitions:

- Prefixes external MCP tool names as `mcp__external__<tool_name>`.
- Preserves the original MCP name in metadata.
- Keeps MCP input schema when present.
- Avoids collisions with existing ERP tool names.

### `ErpAI::ToolExecutor`

Dispatches requested tool calls:

- Executes `mcp__external__...` names through `ErpAI::Mcp::HttpClient#call_tool`.
- Returns a normalized tool result with tool call id, tool name, and serialized result content.
- Rejects unknown tools with a structured error result instead of raising into the runner.

Existing ERP query tool names remain registered, but they are not executed by this first MCP implementation unless a concrete executor is added later.

### `ErpAI::AgentRunner`

Changes from one model call to a bounded loop:

1. Create conversation and store the user message.
2. Build context and available tool definitions.
3. Ask the model.
4. If the model returns final content with no tool calls, store assistant message and finish.
5. If the model returns tool calls, store the assistant tool-request message when content or tool call metadata is available.
6. Execute each tool call with `ToolExecutor`.
7. Store each result as a `tool` message.
8. Repeat until final content is returned or `ERP_AI_MAX_TOOL_ROUNDS` is reached.

When the max round limit is reached, the runner stores a final assistant message explaining that the tool-call limit was reached and that the user should narrow the question or retry.

## Model Client Contract

`ErpAI::DefaultClient#complete` and `ErpAI::ActiveAgentClient#complete` return:

```ruby
{
  content: "final assistant text or nil",
  tool_calls: [
    {
      id: "call_1",
      name: "mcp__external__tool_name",
      arguments: { "key" => "value" }
    }
  ],
  usage: {}
}
```

`tool_calls` defaults to an empty array. Existing tests that only return `content` continue to work.

The real ActiveAgent adapter extracts tool calls only when the provider response exposes them. Tests use fake clients to verify loop behavior independently from provider response internals.

## Message Persistence

The existing `messages` table has `role`, `content`, and `usage`. To avoid a migration in the first version, tool call metadata is serialized into `content` as compact JSON for assistant tool-request messages and tool result messages.

Examples:

- Assistant tool request: `{"tool_calls":[...]}`
- Tool result: `{"tool_call_id":"call_1","name":"mcp__external__search","result":{...}}`

This keeps the first version surgical. A future migration can add explicit JSONB columns if richer inspection is needed.

## Error Handling

- Missing MCP endpoint means no MCP tools are listed.
- MCP HTTP errors become structured tool error messages.
- Invalid JSON or invalid SSE payloads become structured tool error messages.
- Unknown tool names become structured tool error messages.
- Tool errors are returned to the model in the loop so the model can explain the failure to the user.

## Security

- Only configured MCP endpoints are callable.
- Tool names are namespace-prefixed before they reach the model.
- The runner does not expose MCP tokens to messages.
- This first version does not add write-capable ERP tools.
- The existing controller permission requirement remains unchanged.

## Tests

Add focused tests:

- `ErpAI::Mcp::HttpClient` sends correct JSON-RPC requests and headers for `initialize`, `tools/list`, and `tools/call`.
- `ErpAI::Mcp::ToolAdapter` prefixes MCP tool names and preserves input schema.
- `ErpAI::ToolExecutor` dispatches MCP tools and returns structured errors for unknown tools.
- `ErpAI::AgentRunner` executes model tool calls, persists tool messages, then persists the final assistant answer.
- `ErpAI::AgentRunner` stops at the configured max tool rounds.
- Existing AI controller and ActiveAgent client tests continue to pass.

## Verification

Run:

```bash
rbenv exec ruby bin/rails test test/services/ai test/controllers/ai/conversations_controller_test.rb test/agents/business_analysis_agent_test.rb test/models/ai_agent_architecture_test.rb
```

No frontend build is required because this feature only changes Rails service code and tests.
