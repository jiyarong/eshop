# Tool Config Persistence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build shared tool definitions and tool configurations in Rails, wire a tools library UI, and embed the first `WB Pallet Optimizer` tool with database-backed persistence.

**Architecture:** Add `Ec::ToolDefinition` and `Ec::ToolConfiguration` as the persistence layer, split tool browsing and tool configuration actions into dedicated report controllers, and keep the first tool renderer thin by preserving the existing HTML tool DOM and calculation logic while replacing only the persistence adapter and page shell.

**Tech Stack:** Rails 8, Active Record, ERB, Turbo, Minitest, Propshaft/JS assets

---

### Task 1: Add persistence schema and models

**Files:**
- Create: `db/migrate/*_create_ec_tool_definitions.rb`
- Create: `db/migrate/*_create_ec_tool_configurations.rb`
- Create: `app/models/ec/tool_definition.rb`
- Create: `app/models/ec/tool_configuration.rb`
- Test: `test/models/ec/tool_definition_test.rb`
- Test: `test/models/ec/tool_configuration_test.rb`

- [ ] **Step 1: Write the failing model tests**
- [ ] **Step 2: Run model tests to verify they fail**
- [ ] **Step 3: Generate the two migrations with Rails generators**
- [ ] **Step 4: Implement minimal models and associations**
- [ ] **Step 5: Run model tests to verify they pass**

### Task 2: Add routes and controller skeletons

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/reports/tools_controller.rb`
- Create: `app/controllers/reports/tool_configurations_controller.rb`
- Create: `app/services/reports/tool_renderer_resolver.rb`
- Test: `test/controllers/reports/tools_controller_test.rb`

- [ ] **Step 1: Write failing request/controller tests for tools index and latest-version resolution**
- [ ] **Step 2: Run those tests to verify they fail**
- [ ] **Step 3: Add routes and minimal controllers/resolver**
- [ ] **Step 4: Run tests to verify they pass**

### Task 3: Build the tools library and configuration ownership behavior

**Files:**
- Create: `app/views/reports/tools/index.html.erb`
- Create: `app/views/reports/tools/new.html.erb`
- Create: `app/views/reports/tools/show.html.erb`
- Modify: `app/views/layouts/application.html.erb`
- Modify: `config/locales/zh.yml`
- Modify: `config/locales/en.yml`
- Modify: `config/locales/ru.yml`
- Test: `test/controllers/reports/tool_configurations_controller_test.rb`

- [ ] **Step 1: Write failing controller tests for create, owner update, non-owner update forbidden, and action visibility**
- [ ] **Step 2: Run those tests to verify they fail**
- [ ] **Step 3: Implement minimal create/update/show/new/index HTML flows and locale strings**
- [ ] **Step 4: Run targeted tests to verify they pass**

### Task 4: Embed `WB Pallet Optimizer` with DB-backed persistence

**Files:**
- Create: `app/views/reports/tools/renderers/_wb_pallet_optimizer_v1.html.erb`
- Create: `app/assets/stylesheets/wb_pallet_optimizer.css`
- Create: `app/javascript/wb_pallet_optimizer.js`
- Modify: `app/views/reports/tools/show.html.erb`
- Test: `test/controllers/reports/tools_controller_test.rb`

- [ ] **Step 1: Write failing tests that assert the renderer is selected and persisted configuration data is exposed**
- [ ] **Step 2: Run those tests to verify they fail**
- [ ] **Step 3: Implement the renderer partial, bootstrap payload, and JS persistence adapter without changing core calculation logic**
- [ ] **Step 4: Run targeted tests to verify they pass**

### Task 5: Seed the first tool definition and verify navigation

**Files:**
- Modify: `db/seeds.rb` or add a focused seed/bootstrap hook if the repo uses one
- Modify: `test/controllers/reports/tools_controller_test.rb`

- [ ] **Step 1: Write a failing test that `/reports/tools/wb_pallet_optimizer` resolves to the newest active version**
- [ ] **Step 2: Run the test to verify it fails**
- [ ] **Step 3: Add minimal seed/bootstrap support for the first definition**
- [ ] **Step 4: Run the test to verify it passes**

### Task 6: Run focused verification

**Files:**
- Test: `test/models/ec/tool_definition_test.rb`
- Test: `test/models/ec/tool_configuration_test.rb`
- Test: `test/controllers/reports/tools_controller_test.rb`
- Test: `test/controllers/reports/tool_configurations_controller_test.rb`

- [ ] **Step 1: Run the full focused test set**

```bash
SKIP_JS_BUILD=1 bundle exec ruby bin/rails test \
  test/models/ec/tool_definition_test.rb \
  test/models/ec/tool_configuration_test.rb \
  test/controllers/reports/tools_controller_test.rb \
  test/controllers/reports/tool_configurations_controller_test.rb
```

- [ ] **Step 2: Fix any failures and rerun until green**
- [ ] **Step 3: Review diff for scope control**
