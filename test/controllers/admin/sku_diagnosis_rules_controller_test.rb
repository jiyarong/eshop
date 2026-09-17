require "test_helper"

class Admin::SkuDiagnosisRulesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(5)
    @admin = create_user_with_roles("sku-rules-admin-#{@token}@example.com", "super_admin")
    @viewer = create_user_with_roles("sku-rules-viewer-#{@token}@example.com", "auditor")
    @rule = Ec::SkuDiagnosisRule.create!(
      name: "Rule #{@token}",
      prompt: "## Check inventory\n\n- Verify stock",
      frequency: "weekly"
    )
  end

  teardown do
    Ec::SkuDiagnosisRule.where(id: @rule.id).delete_all
    Ec::SkuDiagnosisRule.where(name: "New #{@token}").delete_all
    UserRole.where(user_id: [@admin.id, @viewer.id]).delete_all
    User.where(id: [@admin.id, @viewer.id]).delete_all
  end

  test "admin can list rules and edit the fixed system agent" do
    sign_in @admin

    get admin_sku_diagnosis_rules_path, headers: { "Accept" => "text/html" }
    assert_response :success
    assert_select "h1", "SKU诊断规则"
    assert_select "a[href=?]", admin_sku_diagnosis_rule_path(@rule), text: @rule.name
    assert_select "a[href=?]", edit_admin_sku_diagnosis_rule_path(@rule)
    assert_select "a[href=?]", edit_admin_agent_path("sku_diagnosis")

    sign_in @admin
    get edit_admin_agent_path("sku_diagnosis"), headers: { "Accept" => "text/html" }
    assert_response :success
    assert_select "input[name='agent[tools][]'][value='save_sku_event']"
    assert_select "input[name='agent[tools][]'][value='erp_ai_request']", count: 0
  end

  test "admin can view a rule with its prompt rendered as markdown" do
    sign_in @admin

    get admin_sku_diagnosis_rule_path(@rule), headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", @rule.name
    assert_select "[data-controller='markdown']" do
      assert_select "pre[data-markdown-target='source']", text: /## Check inventory/
      assert_select "article.gbrain-markdown[data-markdown-target='output'][hidden]"
    end
    assert_select "a[href=?]", edit_admin_sku_diagnosis_rule_path(@rule)
    assert_select ".definition-list", text: /每周/
  end

  test "scheduled agent cannot be started as an interactive conversation" do
    sign_in @admin
    post "/ai/conversations.json", params: { agent_code: "sku_diagnosis", question: "Check SKU" }
    assert_response :unprocessable_entity
    assert_not Conversation.joins(:agent).where(agents: { code: "sku_diagnosis" }, user_id: @admin.id).exists?
  end

  test "admin can create update and delete a rule with selected contexts" do
    sign_in @admin

    get new_admin_sku_diagnosis_rule_path, headers: { "Accept" => "text/html" }
    assert_response :success
    assert_select "input[name='ec_sku_diagnosis_rule[context_keys][]'][checked]", count: Ec::SkuDiagnosisRule::CONTEXT_KEYS.size
    assert_select "label.checkbox-option", text: /Ozon Listing 内容/ do
      assert_select "input#rule_context_ozon_listing_content[value='ozon_listing_content'][checked]"
    end
    assert_select "label.checkbox-option", text: /WB Listing 内容/ do
      assert_select "input#rule_context_wb_listing_content[value='wb_listing_content'][checked]"
    end
    assert_select "textarea[name='ec_sku_diagnosis_rule[allowed_event_types_text]']"
    assert_select "select[name='ec_sku_diagnosis_rule[frequency]'] option[value='manual']", text: "手动"

    sign_in @admin
    post admin_sku_diagnosis_rules_path, headers: { "Accept" => "text/html" }, params: {
      ec_sku_diagnosis_rule: {
        name: "New #{@token}", prompt: "Check profit", frequency: "daily", enabled: "1",
        context_keys: ["base", "profit", "ozon_listing_content"],
        allowed_event_types_text: "库存风险（紧急）\n\n利润 下滑\n库存风险（紧急）\r\n"
      }
    }
    rule = Ec::SkuDiagnosisRule.find_by!(name: "New #{@token}")
    assert_redirected_to admin_sku_diagnosis_rules_path
    assert_equal %w[base profit ozon_listing_content], rule.configuration.fetch("context_keys")
    assert_equal ["库存风险（紧急）", "利润 下滑"], rule.allowed_event_types

    sign_in @admin
    patch admin_sku_diagnosis_rule_path(rule), headers: { "Accept" => "text/html" }, params: {
      ec_sku_diagnosis_rule: {
        name: rule.name, prompt: "Check stock", frequency: "manual", enabled: "0",
        context_keys: ["inventory"], allowed_event_types_text: "inventory_risk"
      }
    }
    assert_redirected_to admin_sku_diagnosis_rules_path
    assert_equal ["inventory"], rule.reload.context_keys
    assert_equal ["inventory_risk"], rule.allowed_event_types
    assert_equal "manual", rule.frequency
    assert_not rule.enabled?

    sign_in @admin
    get edit_admin_sku_diagnosis_rule_path(rule), headers: { "Accept" => "text/html" }
    assert_response :success
    assert_select "textarea[name='ec_sku_diagnosis_rule[allowed_event_types_text]']", text: "inventory_risk"
    assert_select ".ai-toggle-option--status input[name='ec_sku_diagnosis_rule[enabled]']"
    assert_select "input#rule_context_ozon_listing_content[value='ozon_listing_content']"
    assert_select "input#rule_context_wb_listing_content[value='wb_listing_content']"

    sign_in @admin
    delete admin_sku_diagnosis_rule_path(rule), headers: { "Accept" => "text/html" }
    assert_redirected_to admin_sku_diagnosis_rules_path
    assert_not Ec::SkuDiagnosisRule.exists?(rule.id)
  end

  test "unsupported or empty contexts cannot be saved" do
    sign_in @admin

    post admin_sku_diagnosis_rules_path, headers: { "Accept" => "text/html" }, params: {
      ec_sku_diagnosis_rule: { name: "New #{@token}", prompt: "Check", frequency: "daily", context_keys: ["unknown"] }
    }
    assert_response :unprocessable_entity

    sign_in @admin
    patch admin_sku_diagnosis_rule_path(@rule), headers: { "Accept" => "text/html" }, params: {
      ec_sku_diagnosis_rule: { name: @rule.name, prompt: @rule.prompt, frequency: "daily", context_keys: [""] }
    }
    assert_response :unprocessable_entity
    assert_equal Ec::SkuDiagnosisRule::CONTEXT_KEYS, @rule.reload.context_keys
  end

  test "non admin cannot manage rules" do
    sign_in @viewer
    get admin_sku_diagnosis_rules_path, headers: { "Accept" => "text/html" }
    assert_response :forbidden

    sign_in @viewer
    get admin_sku_diagnosis_rule_path(@rule), headers: { "Accept" => "text/html" }
    assert_response :forbidden
  end
end
