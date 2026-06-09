require "test_helper"
require "yaml"

class KamalAssetsBuildTest < ActiveSupport::TestCase
  test "kamal passes rails master key to docker build" do
    deploy_config = YAML.load_file(Rails.root.join("config/deploy.yml"))

    assert_includes deploy_config.fetch("builder").fetch("secrets"), "RAILS_MASTER_KEY"
  end

  test "docker image builds and verifies production rails assets" do
    dockerfile = Rails.root.join("Dockerfile").read

    assert_includes dockerfile, "nodejs npm"
    assert_includes dockerfile, "npm ci"
    assert_includes dockerfile, "npm run build"
    assert_includes dockerfile, "npm run build:css"
    assert_includes dockerfile, "SKIP_JS_BUILD=1"
    assert_includes dockerfile, "assets:precompile"
    assert_includes dockerfile, "Rails.application.assets.resolver.resolve('application.js')"
    assert_includes dockerfile, "Rails.application.assets.resolver.resolve('mission_control/jobs/bulma.min.css')"
  end
end
