require "minitest/autorun"
require "yaml"

class KamalQueueConfigTest < Minitest::Test
  def test_kamal_passes_database_pool_configuration_to_containers
    deploy_config = YAML.load_file(File.expand_path("../../config/deploy.yml", __dir__))

    assert_equal 8, deploy_config.fetch("env").fetch("clear").fetch("RAILS_MAX_THREADS")
  end
end
