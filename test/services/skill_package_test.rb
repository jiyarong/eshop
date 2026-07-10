require "test_helper"
require "zip"

class SkillPackageTest < ActiveSupport::TestCase
  test "builds a normalized skill ZIP from SKILL.md" do
    package = SkillPackage.from_markdown(skill_md("package-skill"))

    assert_equal "package-skill", package.name
    assert_equal "Package skill description", package.description
    assert_equal [ "package-skill/SKILL.md" ], zip_files(package.archive_data).keys
  end

  test "normalizes an uploaded root package and preserves resources when editing" do
    uploaded = build_zip(
      "SKILL.md" => skill_md("uploaded-skill"),
      "scripts/run.sh" => "#!/bin/sh\necho ok\n"
    )

    package = SkillPackage.from_upload(StringIO.new(uploaded))
    updated_md = skill_md("renamed-skill", description: "Updated description")
    updated = SkillPackage.replace_skill_md(package.archive_data, updated_md)
    files = zip_files(updated.archive_data)

    assert_equal "renamed-skill", updated.name
    assert_equal "#!/bin/sh\necho ok\n", files.fetch("renamed-skill/scripts/run.sh")
    assert_equal updated_md, files.fetch("renamed-skill/SKILL.md")
  end

  test "rejects unsafe paths and invalid manifests" do
    unsafe_zip = build_zip(
      "safe-skill/SKILL.md" => skill_md("safe-skill"),
      "safe-skill/../outside.txt" => "unsafe"
    )

    assert_raises(SkillPackage::Error) { SkillPackage.from_upload(StringIO.new(unsafe_zip)) }
    assert_raises(SkillManifest::Error) do
      SkillPackage.from_markdown("---\nname: Invalid_Name\ndescription: Test\n---\nBody")
    end
  end

  private

  def skill_md(name, description: "Package skill description")
    <<~MARKDOWN
      ---
      name: #{name}
      description: #{description}
      ---

      # Instructions

      Follow the requested workflow.
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

  def zip_files(data)
    Zip::File.open_buffer(StringIO.new(data)).each_with_object({}) do |entry, files|
      files[entry.name] = entry.get_input_stream.read unless entry.directory?
    end
  end
end
