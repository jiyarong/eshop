require "test_helper"
require "zip"
require "tempfile"

class Admin::SkillsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(6)
    @admin = create_user_with_roles("skill-admin-#{@token}@example.com", "super_admin")
    @created_skill_ids = []
  end

  teardown do
    AgentSkill.where(skill_id: @created_skill_ids).delete_all
    Skill.where(id: @created_skill_ids).find_each do |skill|
      skill.archive.purge if skill.archive.attached?
      skill.destroy!
    end
    UserRole.where(user: @admin).delete_all
    User.where(id: @admin.id).delete_all
  end

  test "creates views and downloads a skill from SKILL.md" do
    sign_in @admin

    assert_difference "Skill.count", 1 do
      post "/admin/skills", params: {
        creation_mode: "markdown",
        skill: { version: "1", skill_md: skill_md("direct-skill-#{@token}") }
      }, headers: { "Accept" => "text/html" }
    end

    skill = Skill.find_by!(name: "direct-skill-#{@token}")
    @created_skill_ids << skill.id
    assert_redirected_to admin_skill_path(skill)
    assert skill.archive.attached?

    sign_in @admin
    get admin_skill_path(skill), headers: { "Accept" => "text/html" }
    assert_response :success
    assert_select "pre", text: /direct-skill-#{@token}/

    sign_in @admin
    get download_admin_skill_path(skill), headers: { "Accept" => "text/html" }
    assert_response :redirect
    assert_includes response.location, "/rails/active_storage/blobs/redirect/"
  end

  test "renders both SKILL.md and ZIP creation modes" do
    sign_in @admin

    get new_admin_skill_path, headers: { "Accept" => "text/html" }
    assert_response :success
    assert_select "textarea[name='skill[skill_md]']"
    assert_select "input[name='skill[archive]']", false

    sign_in @admin
    get new_admin_skill_path(mode: "upload"), headers: { "Accept" => "text/html" }
    assert_response :success
    assert_select "input[name='skill[archive]'][type='file']"
    assert_select "textarea[name='skill[skill_md]']", false
  end

  test "uploads a ZIP package and keeps bundled resources after editing SKILL.md" do
    sign_in @admin

    name = "upload-skill-#{@token}"
    archive = uploaded_file(build_zip(
      "#{name}/SKILL.md" => skill_md(name),
      "#{name}/references/guide.md" => "Guide"
    ))

    post "/admin/skills", params: {
      creation_mode: "upload",
      skill: { version: "2", archive: archive }
    }, headers: { "Accept" => "text/html" }

    skill = Skill.find_by!(name: name)
    @created_skill_ids << skill.id
    assert_redirected_to admin_skill_path(skill)

    updated_md = skill_md(name, description: "Updated skill")
    sign_in @admin
    patch admin_skill_path(skill),
      params: { skill: { version: "3", skill_md: updated_md } },
      headers: { "Accept" => "text/html" }

    assert_redirected_to admin_skill_path(skill)
    skill.reload
    assert_equal "3", skill.version
    assert_equal "Updated skill", skill.description
    files = zip_files(skill.archive.download)
    assert_equal "Guide", files.fetch("#{name}/references/guide.md")
    assert_equal updated_md, files.fetch("#{name}/SKILL.md")
  end

  test "rejects a ZIP whose folder does not match its manifest" do
    sign_in @admin

    archive = uploaded_file(build_zip(
      "wrong-folder/SKILL.md" => skill_md("right-name-#{@token}")
    ))

    assert_no_difference "Skill.count" do
      post "/admin/skills", params: {
        creation_mode: "upload",
        skill: { version: "1", archive: archive }
      }, headers: { "Accept" => "text/html" }
    end

    assert_response :unprocessable_entity
    assert_select ".error-box"
  end

  private

  def skill_md(name, description: "Skill description")
    <<~MARKDOWN
      ---
      name: #{name}
      description: #{description}
      ---

      # Workflow

      Follow these instructions.
    MARKDOWN
  end

  def build_zip(files)
    Zip::OutputStream.write_buffer do |zip|
      files.each do |path, content|
        zip.put_next_entry(path)
        zip.write(content)
      end
    end.string
  end

  def uploaded_file(data)
    tempfile = Tempfile.new([ "skill", ".zip" ])
    tempfile.binmode
    tempfile.write(data)
    tempfile.rewind
    Rack::Test::UploadedFile.new(tempfile.path, "application/zip", true, original_filename: "skill.zip")
  end

  def zip_files(data)
    Zip::File.open_buffer(StringIO.new(data)).each_with_object({}) do |entry, files|
      files[entry.name] = entry.get_input_stream.read unless entry.directory?
    end
  end
end
