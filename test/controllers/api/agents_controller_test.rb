require "test_helper"

module Api
  class AgentsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @token = SecureRandom.hex(6)
      @user = User.create!(
        email: "agents-api-#{@token}@example.com",
        password: "password123",
        password_confirmation: "password123"
      )
      @raw_token, = UserAccessToken.generate_for!(@user)
      package = SkillPackage.from_markdown(skill_md)
      @skill = Skill.create!(
        name: package.name,
        description: package.description,
        version: "7",
        skill_md: package.skill_md
      )
      @skill.archive.attach(
        io: StringIO.new(package.archive_data),
        filename: "#{@skill.name}.zip",
        content_type: "application/zip"
      )
      @agent = Agent.create!(
        code: "api_agent_#{@token}",
        name: "API Agent #{@token}",
        description: "API description",
        system_prompt: "API prompt",
        model_id: "deepseek-v4-flash",
        temperature: 0.3,
        thinking_enabled: true,
        recommended_prompts: [ "Question one", "Question two" ],
        skills: [ @skill ],
        tools: [],
        enabled: true
      )
      @agent.avatar.attach(
        io: StringIO.new("avatar"),
        filename: "avatar.png",
        content_type: "image/png"
      )
    end

    teardown do
      @agent.avatar.purge if @agent&.avatar&.attached?
      AgentSkill.where(agent_id: @agent&.id).delete_all
      Agent.where(id: @agent&.id).delete_all
      @skill.archive.purge if @skill&.archive&.attached?
      Skill.where(id: @skill&.id).delete_all
      UserAccessToken.where(user: @user).delete_all
      User.where(id: @user.id).delete_all
    end

    test "returns the requested agents and skills contract" do
      get "/api/agents", headers: { "Authorization" => "Bearer #{@raw_token}" }, as: :json

      assert_response :success
      body = response.parsed_body
      assert_equal %w[agents skills], body.keys.sort

      agent = body.fetch("agents").find { |item| item["name"] == @agent.name }
      assert_equal %w[avatar_url description model name prompt recommended_prompts skills thinking], agent.keys.sort
      assert_equal "API description", agent["description"]
      assert_equal "API prompt", agent["prompt"]
      assert_equal "deepseek-v4-flash", agent["model"]
      assert_equal "enabled", agent["thinking"]
      assert agent["avatar_url"].start_with?("/rails/active_storage/blobs/redirect/")
      assert_includes agent["avatar_url"], "disposition=inline"
      assert_equal [ @skill.name ], agent["skills"]
      assert_equal [ "Question one", "Question two" ], agent["recommended_prompts"]

      skill = body.fetch("skills").find { |item| item["name"] == @skill.name }
      assert_equal %w[description download_url name version], skill.keys.sort
      assert_equal "API skill", skill["description"]
      assert_equal "7", skill["version"]
      assert skill["download_url"].start_with?("/rails/active_storage/blobs/redirect/")
    end

    test "requires a bearer token" do
      get "/api/agents", as: :json

      assert_response :unauthorized
    end

    private

    def skill_md
      <<~MARKDOWN
        ---
        name: api-skill-#{@token}
        description: API skill
        ---

        # Workflow

        Follow the workflow.
      MARKDOWN
    end
  end
end
