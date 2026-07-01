# AI Agent MCP Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a bounded Rails AI agent tool-call loop with support for multiple named remote HTTP MCP servers.

**Architecture:** Add small `ErpAI::Mcp::*` classes for configuration, HTTP JSON-RPC, and tool adaptation; add `ErpAI::ToolExecutor` for namespaced tool dispatch; update `ErpAI::AgentRunner` to loop until final content or max rounds. Keep message persistence on the existing `messages.content` field as compact JSON for tool metadata.

**Tech Stack:** Rails 8, Minitest, ActiveAgent, OpenAI chat provider, Ruby `Net::HTTP`, JSON-RPC over HTTP MCP.

---

### Task 1: MCP Server Configuration and Tool Adaptation

**Files:**
- Create: `app/services/erp_ai/mcp/server_registry.rb`
- Create: `app/services/erp_ai/mcp/tool_adapter.rb`
- Test: `test/services/ai/mcp/server_registry_test.rb`
- Test: `test/services/ai/mcp/tool_adapter_test.rb`

- [ ] **Step 1: Write failing server registry tests**

Add tests proving `config/mcp_servers.yml` can define multiple named servers, rejects duplicate or invalid names, returns no clients when blank, and tracks optional per-server tool allowlists.

- [ ] **Step 2: Run server registry tests and verify RED**

Run: `rbenv exec ruby bin/rails test test/services/ai/mcp/server_registry_test.rb`
Expected: fail with missing `ErpAI::Mcp::ServerRegistry`.

- [ ] **Step 3: Implement minimal server registry**

Implement parsing, name validation, duplicate-name rejection by skipping later duplicates, and client construction via an injectable `client_class`.

- [ ] **Step 4: Write failing tool adapter tests**

Add tests proving MCP tools become `mcp__<server>__<tool>` and preserve metadata and schema.

- [ ] **Step 5: Run tool adapter tests and verify RED**

Run: `rbenv exec ruby bin/rails test test/services/ai/mcp/tool_adapter_test.rb`
Expected: fail with missing `ErpAI::Mcp::ToolAdapter`.

- [ ] **Step 6: Implement minimal tool adapter**

Implement `adapt(server_name:, tools:)` and `parse_model_tool_name(name)`.

- [ ] **Step 7: Run Task 1 tests and verify GREEN**

Run: `rbenv exec ruby bin/rails test test/services/ai/mcp/server_registry_test.rb test/services/ai/mcp/tool_adapter_test.rb`
Expected: pass.

### Task 2: MCP HTTP Client and Tool Executor

**Files:**
- Create: `app/services/erp_ai/mcp/http_client.rb`
- Create: `app/services/erp_ai/tool_executor.rb`
- Test: `test/services/ai/mcp/http_client_test.rb`
- Test: `test/services/ai/tool_executor_test.rb`

- [ ] **Step 1: Write failing HTTP client tests**

Add tests using `WEBrick` or a small TCP test server proving `initialize`, `tools/list`, and `tools/call` send JSON-RPC POSTs with `Accept`, `Content-Type`, `MCP-Protocol-Version`, and optional bearer token.

- [ ] **Step 2: Run HTTP client tests and verify RED**

Run: `rbenv exec ruby bin/rails test test/services/ai/mcp/http_client_test.rb`
Expected: fail with missing `ErpAI::Mcp::HttpClient`.

- [ ] **Step 3: Implement minimal HTTP client**

Use `Net::HTTP`, JSON request bodies, monotonically increasing ids, JSON response parsing, simple SSE `data:` extraction, and structured `McpError` exceptions.

- [ ] **Step 4: Write failing tool executor tests**

Add tests proving `mcp__search__web_search` routes to the `search` client as `web_search`, and unknown tools or servers return structured error hashes.

- [ ] **Step 5: Run tool executor tests and verify RED**

Run: `rbenv exec ruby bin/rails test test/services/ai/tool_executor_test.rb`
Expected: fail with missing `ErpAI::ToolExecutor`.

- [ ] **Step 6: Implement minimal tool executor**

Dispatch only MCP namespaced tools. Return hashes with `tool_call_id`, `name`, and either `result` or `error`.

- [ ] **Step 7: Run Task 2 tests and verify GREEN**

Run: `rbenv exec ruby bin/rails test test/services/ai/mcp/http_client_test.rb test/services/ai/tool_executor_test.rb`
Expected: pass.

### Task 3: Agent Runner Loop

**Files:**
- Modify: `app/services/erp_ai/agent_runner.rb`
- Test: `test/services/ai/agent_runner_test.rb`

- [ ] **Step 1: Write failing runner loop tests**

Add tests proving the runner asks the model, executes MCP tool calls, persists tool messages, then asks again and persists final assistant content.

- [ ] **Step 2: Run runner test and verify RED**

Run: `rbenv exec ruby bin/rails test test/services/ai/agent_runner_test.rb`
Expected: fail because current runner only calls the client once.

- [ ] **Step 3: Implement minimal loop**

Add injectable `server_registry`, `tool_executor`, and `max_tool_rounds`. Merge existing ERP tool definitions with discovered MCP tools. Serialize assistant tool requests and tool results into `Message#content`.

- [ ] **Step 4: Write failing max-round test**

Add a test where the fake client always returns a tool call and assert the runner stores a final assistant limit message.

- [ ] **Step 5: Run max-round test and verify RED**

Run: `rbenv exec ruby bin/rails test test/services/ai/agent_runner_test.rb`
Expected: fail until max-round behavior is implemented.

- [ ] **Step 6: Implement max-round guard**

Stop after the configured number of tool rounds and store a final assistant message.

- [ ] **Step 7: Run Task 3 tests and verify GREEN**

Run: `rbenv exec ruby bin/rails test test/services/ai/agent_runner_test.rb`
Expected: pass.

### Task 4: ActiveAgent Client Contract and Full Verification

**Files:**
- Modify: `app/services/erp_ai/active_agent_client.rb`
- Modify: `app/agents/business_analysis_agent.rb`
- Test: `test/services/ai/active_agent_client_test.rb`
- Test: `test/agents/business_analysis_agent_test.rb`
- Test: `test/controllers/ai/conversations_controller_test.rb`

- [ ] **Step 1: Write failing client contract tests**

Add tests proving client responses always include `tool_calls`, and provider responses with exposed tool calls are normalized.

- [ ] **Step 2: Run client tests and verify RED**

Run: `rbenv exec ruby bin/rails test test/services/ai/active_agent_client_test.rb`
Expected: fail because `tool_calls` is not returned yet.

- [ ] **Step 3: Implement client normalization**

Normalize missing tool calls to `[]`. Extract common provider shapes defensively from `response.message.tool_calls`, `response.tool_calls`, or hash equivalents.

- [ ] **Step 4: Write/adjust agent prompt option tests**

Assert `BusinessAnalysisAgent` passes tool definitions into prompt options when tools are present.

- [ ] **Step 5: Implement tool option pass-through**

Pass `tools:` into ActiveAgent prompt options in the provider-compatible shape used by the existing tests.

- [ ] **Step 6: Run focused verification**

Run: `rbenv exec ruby bin/rails test test/services/ai test/controllers/ai/conversations_controller_test.rb test/agents/business_analysis_agent_test.rb test/models/ai_agent_architecture_test.rb`
Expected: pass.

- [ ] **Step 7: Run git status review**

Run: `git status --short`
Expected: only this feature's service, test, and plan files changed.
